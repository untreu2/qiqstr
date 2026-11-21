use std::collections::{HashMap, HashSet};
use std::sync::atomic::{AtomicBool, AtomicU64, AtomicU8, Ordering};
use std::sync::Arc;
use std::time::{Duration, Instant, SystemTime, UNIX_EPOCH};

use anyhow::{anyhow, Result};
use futures::stream::{FuturesUnordered, StreamExt};
use futures::SinkExt;
use nostr::prelude::*;
use tokio::sync::{mpsc, oneshot, RwLock};
use tokio_tungstenite::tungstenite::Message;

use crate::store::EventStore;

pub const FLAG_READ: u8 = 1 << 0;
pub const FLAG_WRITE: u8 = 1 << 1;
pub const FLAG_DISCOVERY: u8 = 1 << 2;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
#[repr(u8)]
pub enum RelayStatus {
    Initialized = 0,
    Pending = 1,
    Connecting = 2,
    Connected = 3,
    Disconnected = 4,
    Terminated = 5,
    Banned = 6,
    Sleeping = 7,
}

impl RelayStatus {
    pub fn from_u8(v: u8) -> Self {
        match v {
            0 => Self::Initialized,
            1 => Self::Pending,
            2 => Self::Connecting,
            3 => Self::Connected,
            4 => Self::Disconnected,
            5 => Self::Terminated,
            6 => Self::Banned,
            7 => Self::Sleeping,
            _ => Self::Disconnected,
        }
    }

    pub fn as_str(self) -> &'static str {
        match self {
            Self::Initialized => "initialized",
            Self::Pending => "pending",
            Self::Connecting => "connecting",
            Self::Connected => "connected",
            Self::Disconnected => "disconnected",
            Self::Terminated => "terminated",
            Self::Banned => "banned",
            Self::Sleeping => "sleeping",
        }
    }
}

#[derive(Default)]
pub struct RelayStats {
    pub attempts: AtomicU64,
    pub success: AtomicU64,
    pub bytes_sent: AtomicU64,
    pub bytes_received: AtomicU64,
    pub connected_at_secs: AtomicU64,
    pub latency_ms: AtomicU64,
}

impl RelayStats {
    pub fn latency_ms(&self) -> u64 {
        self.latency_ms.load(Ordering::Relaxed)
    }
}

#[derive(Debug, Clone)]
pub struct PublishOutput {
    pub id: EventId,
    pub success: HashSet<RelayUrl>,
    pub failed: HashMap<RelayUrl, String>,
}

#[derive(Debug, Clone)]
pub enum SubNotification {
    Event { event: Box<Event> },
    Eose,
    Closed,
}

enum RelayCmd {
    Connect,
    Disconnect,
    Shutdown(oneshot::Sender<()>),
    SendEvent {
        event: Event,
        resp: oneshot::Sender<std::result::Result<(), String>>,
    },
    Fetch {
        sub_id: String,
        filter: Filter,
        resp: oneshot::Sender<Vec<Event>>,
    },
    CancelFetch {
        sub_id: String,
    },
    Subscribe {
        sub_id: String,
        filter: Filter,
        tx: mpsc::UnboundedSender<SubNotification>,
    },
    Unsubscribe {
        sub_id: String,
    },
}

struct ActiveFetch {
    filter: Filter,
    events: Vec<Event>,
    seen: HashSet<EventId>,
    started: Instant,
    auth_retried: bool,
    resp: Option<oneshot::Sender<Vec<Event>>>,
}

struct PendingPublish {
    raw_frame: String,
    auth_retried: bool,
    resp: Option<oneshot::Sender<std::result::Result<(), String>>>,
}

struct ActiveSub {
    filter: Filter,
    tx: mpsc::UnboundedSender<SubNotification>,
    auth_retried: bool,
}

pub struct RelayConn {
    flags: AtomicU8,
    status: Arc<AtomicU8>,
    stats: Arc<RelayStats>,
    cmd_tx: mpsc::UnboundedSender<RelayCmd>,
}

impl RelayConn {
    pub fn flags(&self) -> u8 {
        self.flags.load(Ordering::Relaxed)
    }

    pub fn set_flags(&self, flags: u8) {
        self.flags.store(flags, Ordering::Relaxed);
    }

    pub fn has_flag(&self, flag: u8) -> bool {
        (self.flags() & flag) == flag
    }

    pub fn add_flag(&self, flag: u8) {
        self.flags.fetch_or(flag, Ordering::Relaxed);
    }

    pub fn remove_flag(&self, flag: u8) {
        self.flags.fetch_and(!flag, Ordering::Relaxed);
    }

    pub fn is_discovery_only(&self) -> bool {
        let f = self.flags();
        (f & FLAG_DISCOVERY) != 0 && (f & FLAG_READ) == 0 && (f & FLAG_WRITE) == 0
    }

    pub fn status(&self) -> RelayStatus {
        RelayStatus::from_u8(self.status.load(Ordering::Relaxed))
    }

    pub fn stats(&self) -> &RelayStats {
        &self.stats
    }

    pub fn connect(&self) {
        let _ = self.cmd_tx.send(RelayCmd::Connect);
    }

    pub fn disconnect(&self) {
        let _ = self.cmd_tx.send(RelayCmd::Disconnect);
    }

    pub async fn shutdown(&self) {
        let (tx, rx) = oneshot::channel();
        if self.cmd_tx.send(RelayCmd::Shutdown(tx)).is_ok() {
            let _ = tokio::time::timeout(Duration::from_secs(2), rx).await;
        }
    }

    pub async fn send_event(
        &self,
        event: Event,
        timeout: Duration,
    ) -> std::result::Result<(), String> {
        let (tx, rx) = oneshot::channel();
        self.cmd_tx
            .send(RelayCmd::SendEvent { event, resp: tx })
            .map_err(|_| "Relay task closed".to_string())?;
        match tokio::time::timeout(timeout, rx).await {
            Ok(Ok(res)) => res,
            Ok(Err(_)) => Err("Relay disconnected".to_string()),
            Err(_) => Err("Event dispatch timed out".to_string()),
        }
    }
}

static SUB_COUNTER: AtomicU64 = AtomicU64::new(1);

fn next_sub_id(prefix: &str) -> String {
    let n = SUB_COUNTER.fetch_add(1, Ordering::Relaxed);
    format!("{prefix}_{n}")
}

fn now_secs() -> u64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|d| d.as_secs())
        .unwrap_or(0)
}

fn build_auth_frame(keys: &Keys, challenge: &str, url: &RelayUrl) -> Option<String> {
    let event = EventBuilder::new(Kind::Authentication, "")
        .tags([
            Tag::custom(TagKind::Custom("relay".into()), vec![url.as_str()]),
            Tag::custom(TagKind::Custom("challenge".into()), vec![challenge]),
        ])
        .sign_with_keys(keys)
        .ok()?;
    Some(format!("[\"AUTH\",{}]", event.as_json()))
}

fn build_req_frame(sub_id: &str, filter: &Filter) -> String {
    format!(
        "[\"REQ\",{},{}]",
        serde_json::json!(sub_id),
        filter.as_json()
    )
}

fn build_close_frame(sub_id: &str) -> String {
    format!("[\"CLOSE\",{}]", serde_json::json!(sub_id))
}

fn build_event_frame(event: &Event) -> String {
    format!("[\"EVENT\",{}]", event.as_json())
}

async fn run_relay_actor(
    url: RelayUrl,
    status: Arc<AtomicU8>,
    stats: Arc<RelayStats>,
    signer: Arc<RwLock<Option<Keys>>>,
    auto_auth: Arc<AtomicBool>,
    mut cmd_rx: mpsc::UnboundedReceiver<RelayCmd>,
) {
    let mut desired_connected = false;
    let mut active_fetches: HashMap<String, ActiveFetch> = HashMap::new();
    let mut pending_publishes: HashMap<String, PendingPublish> = HashMap::new();
    let mut active_subs: HashMap<String, ActiveSub> = HashMap::new();
    let mut backoff = Duration::from_millis(400);
    let mut next_connect_at: Option<tokio::time::Instant> = None;

    let fail_pending_ops =
        |fetches: &mut HashMap<String, ActiveFetch>,
         publishes: &mut HashMap<String, PendingPublish>| {
            for (_, mut f) in fetches.drain() {
                if let Some(resp) = f.resp.take() {
                    let _ = resp.send(f.events);
                }
            }
            for (_, mut p) in publishes.drain() {
                if let Some(resp) = p.resp.take() {
                    let _ = resp.send(Err("Relay disconnected".to_string()));
                }
            }
        };

    loop {
        if !desired_connected {
            let Some(cmd) = cmd_rx.recv().await else {
                break;
            };
            match cmd {
                RelayCmd::Connect => {
                    desired_connected = true;
                    backoff = Duration::from_millis(400);
                    next_connect_at = None;
                }
                RelayCmd::Disconnect => {
                    status.store(RelayStatus::Disconnected as u8, Ordering::Relaxed);
                }
                RelayCmd::Shutdown(done) => {
                    status.store(RelayStatus::Terminated as u8, Ordering::Relaxed);
                    fail_pending_ops(&mut active_fetches, &mut pending_publishes);
                    let _ = done.send(());
                    return;
                }
                RelayCmd::SendEvent { resp, .. } => {
                    let _ = resp.send(Err("Relay not connected".to_string()));
                }
                RelayCmd::Fetch { resp, .. } => {
                    let _ = resp.send(Vec::new());
                }
                RelayCmd::CancelFetch { .. } => {}
                RelayCmd::Subscribe { sub_id, filter, tx } => {
                    active_subs.insert(
                        sub_id,
                        ActiveSub {
                            filter,
                            tx,
                            auth_retried: false,
                        },
                    );
                }
                RelayCmd::Unsubscribe { sub_id } => {
                    active_subs.remove(&sub_id);
                }
            }
            continue;
        }

        // Wait for reconnect backoff if scheduled, while remaining responsive to commands
        if let Some(at) = next_connect_at.take() {
            loop {
                tokio::select! {
                    _ = tokio::time::sleep_until(at) => break,
                    cmd = cmd_rx.recv() => match cmd {
                        None => return,
                        Some(RelayCmd::Connect) => break,
                        Some(RelayCmd::Disconnect) => {
                            desired_connected = false;
                            status.store(RelayStatus::Disconnected as u8, Ordering::Relaxed);
                            fail_pending_ops(&mut active_fetches, &mut pending_publishes);
                            break;
                        }
                        Some(RelayCmd::Shutdown(done)) => {
                            status.store(RelayStatus::Terminated as u8, Ordering::Relaxed);
                            fail_pending_ops(&mut active_fetches, &mut pending_publishes);
                            let _ = done.send(());
                            return;
                        }
                        Some(RelayCmd::SendEvent { resp, .. }) => {
                            let _ = resp.send(Err("Relay reconnecting".to_string()));
                        }
                        Some(RelayCmd::Fetch { resp, .. }) => {
                            let _ = resp.send(Vec::new());
                        }
                        Some(RelayCmd::CancelFetch { sub_id }) => {
                            active_fetches.remove(&sub_id);
                        }
                        Some(RelayCmd::Subscribe { sub_id, filter, tx }) => {
                            active_subs.insert(sub_id, ActiveSub { filter, tx, auth_retried: false });
                        }
                        Some(RelayCmd::Unsubscribe { sub_id }) => {
                            active_subs.remove(&sub_id);
                        }
                    }
                }
            }
            if !desired_connected {
                continue;
            }
        }

        // Attempt WebSocket connection with TCP_NODELAY enabled
        status.store(RelayStatus::Connecting as u8, Ordering::Relaxed);
        stats.attempts.fetch_add(1, Ordering::Relaxed);
        let connect_start = Instant::now();

        let connect_fut = tokio_tungstenite::connect_async_with_config(url.as_str(), None, true);
        tokio::pin!(connect_fut);

        let connect_timeout = tokio::time::sleep(Duration::from_secs(8));
        tokio::pin!(connect_timeout);

        let mut ws_opt = None;
        let mut shutdown_done: Option<oneshot::Sender<()>> = None;

        loop {
            tokio::select! {
                res = &mut connect_fut => {
                    if let Ok((stream, _)) = res {
                        ws_opt = Some(stream);
                    }
                    break;
                }
                _ = &mut connect_timeout => {
                    break;
                }
                cmd = cmd_rx.recv() => match cmd {
                    None => return,
                    Some(RelayCmd::Connect) => {}
                    Some(RelayCmd::Disconnect) => {
                        desired_connected = false;
                        break;
                    }
                    Some(RelayCmd::Shutdown(done)) => {
                        desired_connected = false;
                        shutdown_done = Some(done);
                        break;
                    }
                    Some(RelayCmd::SendEvent { event, resp }) => {
                        let raw_frame = build_event_frame(&event);
                        pending_publishes.insert(
                            event.id.to_hex(),
                            PendingPublish {
                                raw_frame,
                                auth_retried: false,
                                resp: Some(resp),
                            },
                        );
                    }
                    Some(RelayCmd::Fetch { sub_id, filter, resp }) => {
                        active_fetches.insert(
                            sub_id,
                            ActiveFetch {
                                filter,
                                events: Vec::new(),
                                seen: HashSet::new(),
                                started: Instant::now(),
                                auth_retried: false,
                                resp: Some(resp),
                            },
                        );
                    }
                    Some(RelayCmd::CancelFetch { sub_id }) => {
                        active_fetches.remove(&sub_id);
                    }
                    Some(RelayCmd::Subscribe { sub_id, filter, tx }) => {
                        active_subs.insert(sub_id, ActiveSub { filter, tx, auth_retried: false });
                    }
                    Some(RelayCmd::Unsubscribe { sub_id }) => {
                        active_subs.remove(&sub_id);
                    }
                }
            }
        }

        if let Some(done) = shutdown_done {
            status.store(RelayStatus::Terminated as u8, Ordering::Relaxed);
            fail_pending_ops(&mut active_fetches, &mut pending_publishes);
            let _ = done.send(());
            return;
        }
        if !desired_connected {
            status.store(RelayStatus::Disconnected as u8, Ordering::Relaxed);
            fail_pending_ops(&mut active_fetches, &mut pending_publishes);
            continue;
        }

        let Some(mut ws) = ws_opt else {
            status.store(RelayStatus::Disconnected as u8, Ordering::Relaxed);
            fail_pending_ops(&mut active_fetches, &mut pending_publishes);
            next_connect_at = Some(tokio::time::Instant::now() + backoff);
            backoff = (backoff * 2).min(Duration::from_secs(30));
            continue;
        };

        // Connected!
        let connect_ms = connect_start.elapsed().as_millis().max(1) as u64;
        stats.latency_ms.store(connect_ms, Ordering::Relaxed);
        stats.success.fetch_add(1, Ordering::Relaxed);
        stats.connected_at_secs.store(now_secs(), Ordering::Relaxed);
        status.store(RelayStatus::Connected as u8, Ordering::Relaxed);
        backoff = Duration::from_millis(400);

        let mut last_challenge: Option<String> = None;
        let mut last_ping_sent: Option<Instant> = None;
        let mut ping_interval = tokio::time::interval(Duration::from_secs(30));
        ping_interval.tick().await; // consume immediate tick

        // Flush queued subscriptions, fetches, and publishes immediately
        let mut send_failed = false;
        active_subs.retain(|_, sub| !sub.tx.is_closed());
        for (sub_id, sub) in &active_subs {
            let frame = build_req_frame(sub_id, &sub.filter);
            stats
                .bytes_sent
                .fetch_add(frame.len() as u64, Ordering::Relaxed);
            if ws.send(Message::Text(frame)).await.is_err() {
                send_failed = true;
                break;
            }
        }
        if !send_failed {
            active_fetches.retain(|_, f| f.resp.as_ref().is_some_and(|r| !r.is_closed()));
            for (sub_id, f) in &active_fetches {
                let frame = build_req_frame(sub_id, &f.filter);
                stats
                    .bytes_sent
                    .fetch_add(frame.len() as u64, Ordering::Relaxed);
                if ws.send(Message::Text(frame)).await.is_err() {
                    send_failed = true;
                    break;
                }
            }
        }
        if !send_failed {
            for p in pending_publishes.values() {
                stats
                    .bytes_sent
                    .fetch_add(p.raw_frame.len() as u64, Ordering::Relaxed);
                if ws.send(Message::Text(p.raw_frame.clone())).await.is_err() {
                    send_failed = true;
                    break;
                }
            }
        }

        if !send_failed {
            loop {
                tokio::select! {
                    frame = ws.next() => {
                        match frame {
                            Some(Ok(Message::Text(text))) => {
                                stats.bytes_received.fetch_add(text.len() as u64, Ordering::Relaxed);
                                let Ok(val) = serde_json::from_str::<serde_json::Value>(&text) else {
                                    continue;
                                };
                                let Some(arr) = val.as_array() else {
                                    continue;
                                };
                                let Some(msg_type) = arr.first().and_then(|v| v.as_str()) else {
                                    continue;
                                };
                                match msg_type {
                                    "EVENT" if arr.len() >= 3 => {
                                        let Some(sub_id) = arr[1].as_str() else { continue };
                                        let in_fetch = active_fetches.contains_key(sub_id);
                                        let in_sub = active_subs.contains_key(sub_id);
                                        if !in_fetch && !in_sub {
                                            continue;
                                        }
                                        let Ok(event) = serde_json::from_value::<Event>(arr[2].clone()) else {
                                            continue;
                                        };
                                        if in_fetch {
                                            let mut complete_now = false;
                                            if let Some(f) = active_fetches.get_mut(sub_id) {
                                                if f.filter.match_event(&event, MatchEventOptions::new()) && f.seen.insert(event.id) {
                                                    f.events.push(event);
                                                    let exact_ids = f.filter.ids.as_ref().map(|s| s.len()).filter(|&n| n > 0);
                                                    if exact_ids == Some(1)
                                                        || (exact_ids.is_some() && Some(f.events.len()) >= exact_ids)
                                                    {
                                                        complete_now = true;
                                                    }
                                                }
                                            }
                                            if complete_now {
                                                if let Some(mut f) = active_fetches.remove(sub_id) {
                                                    let rtt = f.started.elapsed().as_millis().max(1) as u64;
                                                    stats.latency_ms.store(rtt, Ordering::Relaxed);
                                                    if let Some(resp) = f.resp.take() {
                                                        let _ = resp.send(f.events);
                                                    }
                                                    let close = build_close_frame(sub_id);
                                                    stats.bytes_sent.fetch_add(close.len() as u64, Ordering::Relaxed);
                                                    let _ = ws.send(Message::Text(close)).await;
                                                }
                                            }
                                        } else if in_sub && event.verify().is_ok() {
                                            let mut dead = false;
                                            if let Some(sub) = active_subs.get(sub_id) {
                                                if sub
                                                    .filter
                                                    .match_event(&event, MatchEventOptions::new())
                                                    && sub
                                                        .tx
                                                        .send(SubNotification::Event {
                                                            event: Box::new(event),
                                                        })
                                                        .is_err()
                                                {
                                                    dead = true;
                                                }
                                            }
                                            if dead {
                                                active_subs.remove(sub_id);
                                                let close = build_close_frame(sub_id);
                                                let _ = ws.send(Message::Text(close)).await;
                                            }
                                        }
                                    }
                                    "EOSE" if arr.len() >= 2 => {
                                        let Some(sub_id) = arr[1].as_str() else { continue };
                                        if let Some(mut f) = active_fetches.remove(sub_id) {
                                            let rtt = f.started.elapsed().as_millis().max(1) as u64;
                                            stats.latency_ms.store(rtt, Ordering::Relaxed);
                                            if let Some(resp) = f.resp.take() {
                                                let _ = resp.send(f.events);
                                            }
                                            let close = build_close_frame(sub_id);
                                            stats.bytes_sent.fetch_add(close.len() as u64, Ordering::Relaxed);
                                            let _ = ws.send(Message::Text(close)).await;
                                        } else if let Some(sub) = active_subs.get(sub_id) {
                                            let _ = sub.tx.send(SubNotification::Eose);
                                        }
                                    }
                                    "OK" if arr.len() >= 3 => {
                                        let Some(eid) = arr[1].as_str() else { continue };
                                        let accepted = arr[2].as_bool().unwrap_or(false);
                                        let message = arr.get(3).and_then(|v| v.as_str()).unwrap_or("").to_string();
                                        if !accepted
                                            && message.starts_with("auth-required:")
                                            && last_challenge.is_some()
                                            && auto_auth.load(Ordering::Relaxed)
                                        {
                                            let should_retry = pending_publishes
                                                .get(eid)
                                                .is_some_and(|p| !p.auth_retried);
                                            if should_retry {
                                                let keys_opt = signer.read().await.clone();
                                                if let (Some(keys), Some(ch)) = (keys_opt, last_challenge.as_deref()) {
                                                    if let Some(auth_frame) = build_auth_frame(&keys, ch, &url) {
                                                        stats.bytes_sent.fetch_add(auth_frame.len() as u64, Ordering::Relaxed);
                                                        if ws.send(Message::Text(auth_frame)).await.is_ok() {
                                                            if let Some(p) = pending_publishes.get_mut(eid) {
                                                                p.auth_retried = true;
                                                                stats.bytes_sent.fetch_add(p.raw_frame.len() as u64, Ordering::Relaxed);
                                                                let _ = ws.send(Message::Text(p.raw_frame.clone())).await;
                                                                continue;
                                                            }
                                                        }
                                                    }
                                                }
                                            }
                                        }
                                        if let Some(mut p) = pending_publishes.remove(eid) {
                                            if let Some(resp) = p.resp.take() {
                                                let res = if accepted {
                                                    Ok(())
                                                } else {
                                                    Err(if message.is_empty() {
                                                        "Rejected by relay".to_string()
                                                    } else {
                                                        message
                                                    })
                                                };
                                                let _ = resp.send(res);
                                            }
                                        }
                                    }
                                    "CLOSED" if arr.len() >= 2 => {
                                        let Some(sub_id) = arr[1].as_str() else { continue };
                                        let message = arr.get(2).and_then(|v| v.as_str()).unwrap_or("").to_string();
                                        if message.starts_with("auth-required:")
                                            && last_challenge.is_some()
                                            && auto_auth.load(Ordering::Relaxed)
                                        {
                                            let keys_opt = signer.read().await.clone();
                                            if let (Some(keys), Some(ch)) = (keys_opt, last_challenge.as_deref()) {
                                                if let Some(f) = active_fetches.get_mut(sub_id) {
                                                    if !f.auth_retried {
                                                        if let Some(auth_frame) = build_auth_frame(&keys, ch, &url) {
                                                            f.auth_retried = true;
                                                            let req = build_req_frame(sub_id, &f.filter);
                                                            let _ = ws.send(Message::Text(auth_frame)).await;
                                                            let _ = ws.send(Message::Text(req)).await;
                                                            continue;
                                                        }
                                                    }
                                                } else if let Some(sub) = active_subs.get_mut(sub_id) {
                                                    if !sub.auth_retried {
                                                        if let Some(auth_frame) = build_auth_frame(&keys, ch, &url) {
                                                            sub.auth_retried = true;
                                                            let req = build_req_frame(sub_id, &sub.filter);
                                                            let _ = ws.send(Message::Text(auth_frame)).await;
                                                            let _ = ws.send(Message::Text(req)).await;
                                                            continue;
                                                        }
                                                    }
                                                }
                                            }
                                        }
                                        if let Some(mut f) = active_fetches.remove(sub_id) {
                                            if let Some(resp) = f.resp.take() {
                                                let _ = resp.send(f.events);
                                            }
                                        } else if let Some(sub) = active_subs.get(sub_id) {
                                            let _ = sub.tx.send(SubNotification::Closed);
                                        }
                                    }
                                    "AUTH" if arr.len() >= 2 => {
                                        if let Some(challenge) = arr[1].as_str() {
                                            last_challenge = Some(challenge.to_string());
                                            if auto_auth.load(Ordering::Relaxed) {
                                                if let Some(keys) = signer.read().await.clone() {
                                                    if let Some(auth_frame) = build_auth_frame(&keys, challenge, &url) {
                                                        stats.bytes_sent.fetch_add(auth_frame.len() as u64, Ordering::Relaxed);
                                                        let _ = ws.send(Message::Text(auth_frame)).await;
                                                    }
                                                }
                                            }
                                        }
                                    }
                                    _ => {}
                                }
                            }
                            Some(Ok(Message::Ping(payload))) => {
                                let _ = ws.send(Message::Pong(payload)).await;
                            }
                            Some(Ok(Message::Pong(_))) => {
                                if let Some(sent) = last_ping_sent.take() {
                                    let rtt = sent.elapsed().as_millis().max(1) as u64;
                                    stats.latency_ms.store(rtt, Ordering::Relaxed);
                                }
                            }
                            Some(Ok(Message::Close(_))) | Some(Err(_)) | None => {
                                break;
                            }
                            _ => {}
                        }
                    }
                    cmd = cmd_rx.recv() => {
                        match cmd {
                            None => {
                                let _ = ws.close(None).await;
                                status.store(RelayStatus::Terminated as u8, Ordering::Relaxed);
                                fail_pending_ops(&mut active_fetches, &mut pending_publishes);
                                return;
                            }
                            Some(RelayCmd::Connect) => {}
                            Some(RelayCmd::Disconnect) => {
                                desired_connected = false;
                                let _ = ws.close(None).await;
                                break;
                            }
                            Some(RelayCmd::Shutdown(done)) => {
                                let _ = ws.close(None).await;
                                status.store(RelayStatus::Terminated as u8, Ordering::Relaxed);
                                fail_pending_ops(&mut active_fetches, &mut pending_publishes);
                                let _ = done.send(());
                                return;
                            }
                            Some(RelayCmd::SendEvent { event, resp }) => {
                                let raw_frame = build_event_frame(&event);
                                stats.bytes_sent.fetch_add(raw_frame.len() as u64, Ordering::Relaxed);
                                if ws.send(Message::Text(raw_frame.clone())).await.is_err() {
                                    let _ = resp.send(Err("Failed to send event".to_string()));
                                    break;
                                }
                                pending_publishes.insert(
                                    event.id.to_hex(),
                                    PendingPublish {
                                        raw_frame,
                                        auth_retried: false,
                                        resp: Some(resp),
                                    },
                                );
                            }
                            Some(RelayCmd::Fetch { sub_id, filter, resp }) => {
                                let frame = build_req_frame(&sub_id, &filter);
                                stats.bytes_sent.fetch_add(frame.len() as u64, Ordering::Relaxed);
                                if ws.send(Message::Text(frame)).await.is_err() {
                                    let _ = resp.send(Vec::new());
                                    break;
                                }
                                active_fetches.insert(
                                    sub_id,
                                    ActiveFetch {
                                        filter,
                                        events: Vec::new(),
                                        seen: HashSet::new(),
                                        started: Instant::now(),
                                        auth_retried: false,
                                        resp: Some(resp),
                                    },
                                );
                            }
                            Some(RelayCmd::CancelFetch { sub_id }) => {
                                if active_fetches.remove(&sub_id).is_some() {
                                    let close = build_close_frame(&sub_id);
                                    stats.bytes_sent.fetch_add(close.len() as u64, Ordering::Relaxed);
                                    let _ = ws.send(Message::Text(close)).await;
                                }
                            }
                            Some(RelayCmd::Subscribe { sub_id, filter, tx }) => {
                                let frame = build_req_frame(&sub_id, &filter);
                                stats.bytes_sent.fetch_add(frame.len() as u64, Ordering::Relaxed);
                                active_subs.insert(sub_id, ActiveSub { filter, tx, auth_retried: false });
                                if ws.send(Message::Text(frame)).await.is_err() {
                                    break;
                                }
                            }
                            Some(RelayCmd::Unsubscribe { sub_id }) => {
                                if active_subs.remove(&sub_id).is_some() {
                                    let close = build_close_frame(&sub_id);
                                    stats.bytes_sent.fetch_add(close.len() as u64, Ordering::Relaxed);
                                    let _ = ws.send(Message::Text(close)).await;
                                }
                            }
                        }
                    }
                    _ = ping_interval.tick() => {
                        if last_ping_sent.is_some() {
                            // Previous ping never got a pong — dead half-open socket
                            break;
                        }
                        last_ping_sent = Some(Instant::now());
                        if ws.send(Message::Ping(Vec::new())).await.is_err() {
                            break;
                        }
                    }
                }
            }
        }

        // Disconnected from loop
        status.store(RelayStatus::Disconnected as u8, Ordering::Relaxed);
        fail_pending_ops(&mut active_fetches, &mut pending_publishes);
        if desired_connected {
            next_connect_at = Some(tokio::time::Instant::now() + backoff);
            backoff = (backoff * 2).min(Duration::from_secs(30));
        }
    }
}

struct ClientInner {
    db: Arc<EventStore>,
    signer: Arc<RwLock<Option<Keys>>>,
    auto_auth: Arc<AtomicBool>,
    relays: RwLock<HashMap<RelayUrl, Arc<RelayConn>>>,
}

#[derive(Clone)]
pub struct NostrClient {
    inner: Arc<ClientInner>,
}

const FETCH_GRACE_AFTER_RESULTS: Duration = Duration::from_millis(600);
const FETCH_GRACE_AFTER_MAJORITY: Duration = Duration::from_millis(250);
const FETCH_GRACE_AFTER_MAJORITY_WITH_RESULTS: Duration = Duration::from_millis(180);

impl NostrClient {
    pub fn new(db: Arc<EventStore>, signer: Option<Keys>) -> Self {
        Self {
            inner: Arc::new(ClientInner {
                db,
                signer: Arc::new(RwLock::new(signer)),
                auto_auth: Arc::new(AtomicBool::new(false)),
                relays: RwLock::new(HashMap::new()),
            }),
        }
    }

    pub fn in_memory(signer: Option<Keys>) -> Self {
        let db = Arc::new(EventStore::open_in_memory().expect("in-memory sqlite"));
        Self::new(db, signer)
    }

    pub fn automatic_authentication(&self, enabled: bool) {
        self.inner.auto_auth.store(enabled, Ordering::Relaxed);
    }

    pub fn database(&self) -> &Arc<EventStore> {
        &self.inner.db
    }

    pub async fn signer(&self) -> Result<Keys> {
        self.inner
            .signer
            .read()
            .await
            .clone()
            .ok_or_else(|| anyhow!("No signer configured"))
    }

    pub async fn set_signer(&self, keys: Keys) {
        *self.inner.signer.write().await = Some(keys);
    }

    pub async fn unset_signer(&self) {
        *self.inner.signer.write().await = None;
    }

    pub async fn sign_event_builder(&self, builder: EventBuilder) -> Result<Event> {
        let keys = self.signer().await?;
        Ok(builder.sign_with_keys(&keys)?)
    }

    pub async fn add_relay_with_flags(&self, url: &str, flags: u8) -> Result<bool> {
        let relay_url = RelayUrl::parse(url)?;
        let mut relays = self.inner.relays.write().await;
        if let Some(existing) = relays.get(&relay_url) {
            existing.set_flags(flags);
            return Ok(true);
        }
        let status = Arc::new(AtomicU8::new(RelayStatus::Initialized as u8));
        let stats = Arc::new(RelayStats::default());
        let (cmd_tx, cmd_rx) = mpsc::unbounded_channel();
        tokio::spawn(run_relay_actor(
            relay_url.clone(),
            status.clone(),
            stats.clone(),
            self.inner.signer.clone(),
            self.inner.auto_auth.clone(),
            cmd_rx,
        ));
        let conn = Arc::new(RelayConn {
            flags: AtomicU8::new(flags),
            status,
            stats,
            cmd_tx,
        });
        relays.insert(relay_url, conn);
        Ok(true)
    }

    pub async fn add_relay(&self, url: &str) -> Result<bool> {
        self.add_relay_with_flags(url, FLAG_READ | FLAG_WRITE).await
    }

    pub async fn add_discovery_relay(&self, url: &str) -> Result<bool> {
        let relay_url = RelayUrl::parse(url)?;
        let relays = self.inner.relays.read().await;
        if let Some(existing) = relays.get(&relay_url) {
            existing.add_flag(FLAG_DISCOVERY);
            return Ok(true);
        }
        drop(relays);
        self.add_relay_with_flags(url, FLAG_DISCOVERY).await
    }

    pub async fn remove_relay(&self, url: &RelayUrl) -> Result<()> {
        let removed = self.inner.relays.write().await.remove(url);
        if let Some(conn) = removed {
            conn.shutdown().await;
        }
        Ok(())
    }

    pub async fn relays(&self) -> HashMap<RelayUrl, Arc<RelayConn>> {
        self.inner.relays.read().await.clone()
    }

    pub async fn connect(&self) {
        let relays = self.inner.relays.read().await;
        for conn in relays.values() {
            conn.connect();
        }
    }

    pub async fn disconnect(&self) {
        let relays = self.inner.relays.read().await;
        for conn in relays.values() {
            conn.disconnect();
        }
    }

    pub async fn shutdown(&self) {
        let relays: Vec<Arc<RelayConn>> = {
            let mut map = self.inner.relays.write().await;
            map.drain().map(|(_, v)| v).collect()
        };
        let futs = relays
            .into_iter()
            .map(|c| async move { c.shutdown().await });
        futures::future::join_all(futs).await;
    }

    pub async fn wait_for_ready(&self, timeout: Duration, prefer_count: usize) -> u32 {
        let deadline = tokio::time::Instant::now() + timeout;
        let mut first_connected_at: Option<tokio::time::Instant> = None;

        loop {
            let (total, connected) = {
                let relays = self.inner.relays.read().await;
                let mut total = 0usize;
                let mut connected = 0usize;
                for conn in relays.values() {
                    if conn.is_discovery_only() {
                        continue;
                    }
                    total += 1;
                    if conn.status() == RelayStatus::Connected {
                        connected += 1;
                    }
                }
                (total, connected)
            };

            if total == 0 || connected >= total || connected >= prefer_count {
                return connected as u32;
            }
            let now = tokio::time::Instant::now();
            if connected > 0 {
                let first = *first_connected_at.get_or_insert(now);
                if now.duration_since(first) >= Duration::from_millis(150) {
                    return connected as u32;
                }
            }
            if now >= deadline {
                return connected as u32;
            }
            let next_tick = (now + Duration::from_millis(15)).min(deadline);
            tokio::time::sleep_until(next_tick).await;
        }
    }

    pub async fn fetch_events_from(
        &self,
        urls: &[RelayUrl],
        filter: Filter,
        timeout: Duration,
        save_to_db: bool,
    ) -> Result<Vec<Event>> {
        let conns: Vec<Arc<RelayConn>> = {
            let relays = self.inner.relays.read().await;
            urls.iter().filter_map(|u| relays.get(u).cloned()).collect()
        };
        if conns.is_empty() {
            return Ok(Vec::new());
        }
        self.fetch_from_conns(conns, filter, timeout, save_to_db)
            .await
    }

    pub async fn quick_fetch(
        &self,
        filter: Filter,
        timeout: Duration,
        save_to_db: bool,
    ) -> Result<Vec<Event>> {
        let conns = {
            let relays = self.inner.relays.read().await;
            let mut connected: Vec<Arc<RelayConn>> = Vec::new();
            let mut all_read: Vec<Arc<RelayConn>> = Vec::new();
            for conn in relays.values() {
                if !conn.has_flag(FLAG_READ) {
                    continue;
                }
                let st = conn.status();
                if st == RelayStatus::Connected {
                    connected.push(conn.clone());
                }
                if !matches!(st, RelayStatus::Banned | RelayStatus::Terminated) {
                    all_read.push(conn.clone());
                }
            }
            let mut chosen = if connected.len() >= 2 {
                connected
            } else if !all_read.is_empty() {
                all_read
            } else {
                connected
            };
            // Prefer lowest-latency relays first
            chosen.sort_by_key(|c| {
                let l = c.stats().latency_ms();
                if l == 0 {
                    u64::MAX
                } else {
                    l
                }
            });
            chosen
        };

        if conns.is_empty() {
            return Ok(Vec::new());
        }

        self.fetch_from_conns(conns, filter, timeout, save_to_db)
            .await
    }

    async fn fetch_from_conns(
        &self,
        conns: Vec<Arc<RelayConn>>,
        filter: Filter,
        timeout: Duration,
        save_to_db: bool,
    ) -> Result<Vec<Event>> {
        let expected_ids = filter.ids.as_ref().map(|ids| ids.len()).filter(|&n| n > 0);
        let single_id_lookup =
            expected_ids == Some(1) || (expected_ids.is_some() && filter.limit == Some(1));

        let total = conns.len();
        let mut active_sub_ids: Vec<(Arc<RelayConn>, String)> = Vec::with_capacity(total);
        let mut pending: FuturesUnordered<_> = FuturesUnordered::new();

        for conn in conns {
            let sub_id = next_sub_id("f");
            let (tx, rx) = oneshot::channel();
            if conn
                .cmd_tx
                .send(RelayCmd::Fetch {
                    sub_id: sub_id.clone(),
                    filter: filter.clone(),
                    resp: tx,
                })
                .is_ok()
            {
                active_sub_ids.push((conn, sub_id));
                pending.push(async move { rx.await.unwrap_or_default() });
            }
        }

        let deadline = tokio::time::Instant::now() + timeout;
        let mut unique: HashMap<EventId, Event> = HashMap::new();
        let mut finished = 0usize;
        let mut first_results: Option<tokio::time::Instant> = None;
        let mut majority: Option<tokio::time::Instant> = None;

        loop {
            let mut wake = deadline;
            if let Some(at) = first_results {
                wake = wake.min(at + FETCH_GRACE_AFTER_RESULTS);
            }
            if let Some(at) = majority {
                let grace = if first_results.is_some() {
                    FETCH_GRACE_AFTER_MAJORITY_WITH_RESULTS
                } else {
                    FETCH_GRACE_AFTER_MAJORITY
                };
                wake = wake.min(at + grace);
            }

            tokio::select! {
                next = pending.next() => match next {
                    Some(batch) => {
                        finished += 1;
                        let now = tokio::time::Instant::now();
                        if !batch.is_empty() && first_results.is_none() {
                            first_results = Some(now);
                        }
                        for ev in batch {
                            unique.entry(ev.id).or_insert(ev);
                        }
                        if single_id_lookup && !unique.is_empty() {
                            break;
                        }
                        if let Some(target_count) = expected_ids {
                            if unique.len() >= target_count {
                                break;
                            }
                        }
                        if majority.is_none() && finished * 2 >= total {
                            majority = Some(now);
                        }
                    }
                    None => break,
                },
                _ = tokio::time::sleep_until(wake) => break,
            }
        }

        // Cancel any still-running fetches on straggler relays immediately
        if finished < total {
            for (conn, sub_id) in active_sub_ids {
                let _ = conn.cmd_tx.send(RelayCmd::CancelFetch { sub_id });
            }
        }

        if unique.is_empty() {
            return Ok(Vec::new());
        }

        let candidates: Vec<Event> = unique.into_values().collect();

        // Skip re-verifying events already persisted in our verified local store!
        let existing_ids = if save_to_db {
            let cand_ids: Vec<EventId> = candidates.iter().map(|e| e.id).collect();
            self.inner.db.existing_ids(&cand_ids).unwrap_or_default()
        } else {
            HashSet::new()
        };

        let mut already_verified: Vec<Event> = Vec::new();
        let mut to_verify: Vec<Event> = Vec::new();
        for ev in candidates {
            if existing_ids.contains(&ev.id) {
                already_verified.push(ev);
            } else {
                to_verify.push(ev);
            }
        }

        let newly_verified: Vec<Event> = if to_verify.len() >= 16 {
            tokio::task::spawn_blocking(move || verify_events_parallel(to_verify))
                .await
                .unwrap_or_default()
        } else {
            to_verify
                .into_iter()
                .filter(|e| e.verify().is_ok())
                .collect()
        };

        if save_to_db && !newly_verified.is_empty() {
            let _ = self.inner.db.save_events(&newly_verified);
        }

        let mut all = already_verified;
        all.extend(newly_verified);
        all.sort_by(|a, b| {
            b.created_at
                .cmp(&a.created_at)
                .then_with(|| a.id.cmp(&b.id))
        });
        Ok(all)
    }

    pub async fn publish_event(
        &self,
        event: &Event,
        targets: Option<&[RelayUrl]>,
    ) -> Result<PublishOutput> {
        event.verify()?;
        let relays = self.relays().await;
        if let Some(targets) = targets {
            if targets.iter().any(|url| !relays.contains_key(url)) {
                return Err(anyhow!("Publication target is not a configured relay"));
            }
        }
        let selected: Vec<(RelayUrl, Arc<RelayConn>)> = relays
            .into_iter()
            .filter(|(url, conn)| {
                targets.map_or_else(
                    || conn.has_flag(FLAG_WRITE),
                    |targets| targets.contains(url),
                )
            })
            .collect();
        if selected.is_empty() {
            return Err(anyhow!("No publication relays configured"));
        }

        let mut pending: FuturesUnordered<_> = selected
            .into_iter()
            .map(|(url, conn)| {
                let ev = event.clone();
                async move {
                    let res = conn.send_event(ev, Duration::from_secs(12)).await;
                    (url, res)
                }
            })
            .collect();

        let mut output = PublishOutput {
            id: event.id,
            success: HashSet::new(),
            failed: HashMap::new(),
        };
        let mut deadline: Option<tokio::time::Instant> = None;

        loop {
            let next = match deadline {
                Some(at) => match tokio::time::timeout_at(at, pending.next()).await {
                    Ok(n) => n,
                    Err(_) => break,
                },
                None => pending.next().await,
            };
            let Some((url, result)) = next else { break };
            match result {
                Ok(()) => {
                    output.success.insert(url);
                    if deadline.is_none() {
                        deadline = Some(tokio::time::Instant::now() + Duration::from_millis(1500));
                    }
                }
                Err(err) => {
                    output.failed.insert(url, err);
                }
            }
        }

        if !pending.is_empty() {
            tokio::spawn(async move { while pending.next().await.is_some() {} });
        }

        if !output.success.is_empty() {
            self.inner.db.save_event(event)?;
        }

        Ok(output)
    }

    pub async fn subscribe_on(
        &self,
        filter: Filter,
        targets: Option<&[RelayUrl]>,
    ) -> Result<(String, mpsc::UnboundedReceiver<SubNotification>, usize)> {
        let sub_id = next_sub_id("sub");
        let (tx, rx) = mpsc::unbounded_channel();
        let relays = self.inner.relays.read().await;
        let mut count = 0usize;
        for (url, conn) in relays.iter() {
            let include = match targets {
                Some(list) => list.contains(url),
                None => conn.has_flag(FLAG_READ) && !conn.is_discovery_only(),
            };
            if include
                && conn
                    .cmd_tx
                    .send(RelayCmd::Subscribe {
                        sub_id: sub_id.clone(),
                        filter: filter.clone(),
                        tx: tx.clone(),
                    })
                    .is_ok()
            {
                count += 1;
            }
        }
        Ok((sub_id, rx, count))
    }

    pub async fn unsubscribe(&self, sub_id: &str) {
        let relays = self.inner.relays.read().await;
        for conn in relays.values() {
            let _ = conn.cmd_tx.send(RelayCmd::Unsubscribe {
                sub_id: sub_id.to_string(),
            });
        }
    }
}

pub fn verify_events_parallel(mut events: Vec<Event>) -> Vec<Event> {
    if events.len() < 16 {
        return events.into_iter().filter(|e| e.verify().is_ok()).collect();
    }
    let threads = std::thread::available_parallelism()
        .map(|n| n.get())
        .unwrap_or(2)
        .min(4);
    let chunk_size = events.len().div_ceil(threads).max(1);
    let mut results: Vec<Vec<Event>> = Vec::with_capacity(threads);
    std::thread::scope(|s| {
        let mut handles = Vec::new();
        while !events.is_empty() {
            let take = chunk_size.min(events.len());
            let chunk: Vec<Event> = events.drain(..take).collect();
            handles.push(s.spawn(move || {
                chunk
                    .into_iter()
                    .filter(|e| e.verify().is_ok())
                    .collect::<Vec<_>>()
            }));
        }
        for h in handles {
            if let Ok(part) = h.join() {
                results.push(part);
            }
        }
    });
    results.into_iter().flatten().collect()
}
