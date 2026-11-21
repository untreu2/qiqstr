use std::borrow::Cow;
use std::collections::{HashMap, HashSet};
use std::sync::atomic::{AtomicBool, AtomicU64, AtomicU8, Ordering};
use std::sync::{Arc, Mutex};
use std::time::{Duration, Instant, SystemTime, UNIX_EPOCH};

use anyhow::{anyhow, Result};
use futures::stream::{FuturesUnordered, StreamExt};
use futures::SinkExt;
use nostr::prelude::*;
use serde_json::value::RawValue;
use tokio::sync::mpsc::error::TrySendError;
use tokio::sync::{mpsc, oneshot, RwLock};
use tokio_tungstenite::tungstenite::protocol::WebSocketConfig;
use tokio_tungstenite::tungstenite::Message;

use crate::store::EventStore;

const MAX_WS_MESSAGE_SIZE: usize = 4 * 1024 * 1024;
const MAX_WS_FRAME_SIZE: usize = 2 * 1024 * 1024;
const MAX_FETCH_EVENTS_PER_RELAY: usize = 5_000;
const MAX_AUTH_CHALLENGE_LEN: usize = 512;
const SUBSCRIPTION_BUFFER: usize = if cfg!(test) { 64 } else { 4_096 };

const INITIAL_BACKOFF: Duration = Duration::from_millis(400);
const MAX_BACKOFF: Duration = Duration::from_secs(30);
const STABLE_CONNECTION: Duration = Duration::from_secs(10);
const CONNECT_TIMEOUT: Duration = Duration::from_secs(8);
const KEEPALIVE_INTERVAL: Duration = Duration::from_secs(30);

pub(crate) fn hardened_ws_config() -> WebSocketConfig {
    WebSocketConfig {
        max_message_size: Some(MAX_WS_MESSAGE_SIZE),
        max_frame_size: Some(MAX_WS_FRAME_SIZE),
        ..Default::default()
    }
}

pub const FLAG_READ: u8 = 1 << 0;
pub const FLAG_WRITE: u8 = 1 << 1;
pub const FLAG_DISCOVERY: u8 = 1 << 2;
/// The account chose this relay, so it may learn who is connecting (NIP-42).
pub const FLAG_AUTH: u8 = 1 << 3;

const PRESERVED_FLAGS: u8 = FLAG_DISCOVERY | FLAG_AUTH;

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
    connect_started_ms: AtomicU64,
}

impl RelayStats {
    pub fn latency_ms(&self) -> u64 {
        self.latency_ms.load(Ordering::Relaxed)
    }
}

fn monotonic_ms() -> u64 {
    static START: std::sync::OnceLock<Instant> = std::sync::OnceLock::new();
    START.get_or_init(Instant::now).elapsed().as_millis() as u64
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
    Closed { relay: RelayUrl, message: String },
}

/// What one relay returned for a fetch.
struct FetchReply {
    events: Vec<Event>,
    /// The relay finished the request (EOSE, or every requested id arrived).
    answered: bool,
    /// The events were already checked against their signatures.
    verified: bool,
}

impl FetchReply {
    fn failed() -> Self {
        Self {
            events: Vec::new(),
            answered: false,
            verified: false,
        }
    }
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
        allow_auth: bool,
        resp: oneshot::Sender<FetchReply>,
    },
    CancelFetch {
        sub_id: String,
    },
    Subscribe {
        sub_id: String,
        filter: Filter,
        allow_auth: bool,
        tx: mpsc::Sender<SubNotification>,
    },
    Unsubscribe {
        sub_id: String,
    },
    #[cfg(test)]
    Inspect(oneshot::Sender<Workload>),
}

/// How many fetches, publishes and subscriptions a relay connection is holding.
#[cfg(test)]
#[derive(Debug, PartialEq, Eq)]
struct Workload {
    fetches: usize,
    publishes: usize,
    subscriptions: usize,
}

struct ActiveFetch {
    filter: Filter,
    events: Vec<Event>,
    seen: HashSet<EventId>,
    started: Instant,
    exact_ids: Option<usize>,
    allow_auth: bool,
    auth_retried: bool,
    resp: Option<oneshot::Sender<FetchReply>>,
}

impl ActiveFetch {
    fn new(filter: Filter, allow_auth: bool, resp: oneshot::Sender<FetchReply>) -> Self {
        let exact_ids = filter.ids.as_ref().map(|ids| ids.len()).filter(|&n| n > 0);
        Self {
            filter,
            events: Vec::new(),
            seen: HashSet::new(),
            started: Instant::now(),
            exact_ids,
            allow_auth,
            auth_retried: false,
            resp: Some(resp),
        }
    }

    fn is_abandoned(&self) -> bool {
        self.resp.as_ref().is_none_or(|resp| resp.is_closed())
    }

    fn reply(mut self, answered: bool) {
        if let Some(resp) = self.resp.take() {
            let _ = resp.send(FetchReply {
                events: self.events,
                answered,
                verified: self.exact_ids.is_some(),
            });
        }
    }
}

struct PendingPublish {
    raw_frame: String,
    auth_retried: bool,
    resp: Option<oneshot::Sender<std::result::Result<(), String>>>,
}

impl PendingPublish {
    fn is_abandoned(&self) -> bool {
        self.resp.as_ref().is_none_or(|resp| resp.is_closed())
    }
}

struct ActiveSub {
    filter: Filter,
    tx: mpsc::Sender<SubNotification>,
    allow_auth: bool,
    auth_retried: bool,
}

pub struct RelayConn {
    flags: Arc<AtomicU8>,
    status: Arc<AtomicU8>,
    stats: Arc<RelayStats>,
    cmd_tx: mpsc::UnboundedSender<RelayCmd>,
}

impl RelayConn {
    pub fn flags(&self) -> u8 {
        self.flags.load(Ordering::Relaxed)
    }

    /// Replaces the read and write permissions. A relay keeps its discovery role and the
    /// account's trust, which this can add but not take away.
    pub fn set_flags(&self, flags: u8) {
        let _ = self
            .flags
            .fetch_update(Ordering::Relaxed, Ordering::Relaxed, |current| {
                Some((current & PRESERVED_FLAGS) | flags)
            });
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

    fn receives_pool_subscriptions(&self) -> bool {
        self.has_flag(FLAG_READ) && !self.is_discovery_only()
    }

    /// Opening a connection it started on a moment ago, so it may still answer in time. A relay
    /// that has been trying for longer is not worth holding a request for.
    fn is_joining(&self) -> bool {
        match self.status() {
            RelayStatus::Initialized => true,
            RelayStatus::Connecting => {
                let started = self.stats.connect_started_ms.load(Ordering::Relaxed);
                monotonic_ms().saturating_sub(started) < RECENT_CONNECT_ATTEMPT.as_millis() as u64
            }
            _ => false,
        }
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

/// A relay reachable over TLS on the public internet, as opposed to a local or private host.
pub(crate) fn is_public_secure_relay(url: &RelayUrl) -> bool {
    let text = url.as_str().to_ascii_lowercase();
    let Some(rest) = text.strip_prefix("wss://") else {
        return false;
    };
    let host = rest.split(['/', ':', '?']).next().unwrap_or("");
    if host.is_empty()
        || host == "localhost"
        || host.ends_with(".local")
        || host.ends_with(".onion")
        || host.starts_with('[')
    {
        return false;
    }
    if let Ok(ip) = host.parse::<std::net::Ipv4Addr>() {
        return !(ip.is_private() || ip.is_loopback() || ip.is_link_local() || ip.is_unspecified());
    }
    true
}

fn is_usable_challenge(challenge: &str) -> bool {
    !challenge.is_empty()
        && challenge.len() <= MAX_AUTH_CHALLENGE_LEN
        && !challenge.bytes().any(|b| b.is_ascii_control())
}

fn build_auth_frame(keys: &Keys, challenge: &str, url: &RelayUrl) -> Option<String> {
    if !url.as_str().starts_with("wss://") {
        return None;
    }
    sign_auth_frame(keys, challenge, url)
}

fn sign_auth_frame(keys: &Keys, challenge: &str, url: &RelayUrl) -> Option<String> {
    if !is_usable_challenge(challenge) {
        return None;
    }
    let event = EventBuilder::new(Kind::Authentication, "")
        .tags([
            Tag::custom(TagKind::Custom("relay".into()), vec![url.as_str()]),
            Tag::custom(TagKind::Custom("challenge".into()), vec![challenge]),
        ])
        .sign_with_keys(keys)
        .ok()?;
    Some(format!("[\"AUTH\",{}]", event.as_json()))
}

/// Whether a request names something only its host relay can serve: a relay-hosted group, or the
/// account's own inbox. Answering such a relay's NIP-42 challenge reveals nothing it does not
/// already see in the request.
fn filter_is_relay_scoped(filter: &Filter, account: Option<&PublicKey>) -> bool {
    let group = SingleLetterTag::lowercase(Alphabet::H);
    let inbox = SingleLetterTag::lowercase(Alphabet::P);
    if filter
        .generic_tags
        .get(&group)
        .is_some_and(|ids| !ids.is_empty())
    {
        return true;
    }
    if filter.kinds.as_ref().is_some_and(|kinds| {
        !kinds.is_empty()
            && kinds
                .iter()
                .all(|k| (39_000..=39_009).contains(&k.as_u16()))
    }) {
        return true;
    }
    match (filter.generic_tags.get(&inbox), account) {
        (Some(recipients), Some(me)) => {
            let me = me.to_hex();
            !recipients.is_empty() && recipients.iter().all(|recipient| *recipient == me)
        }
        _ => false,
    }
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

fn raw_str(raw: &RawValue) -> Option<Cow<'_, str>> {
    let text = raw.get();
    let inner = text.strip_prefix('"')?.strip_suffix('"')?;
    if inner.contains('\\') {
        serde_json::from_str::<String>(text).ok().map(Cow::Owned)
    } else {
        Some(Cow::Borrowed(inner))
    }
}

fn jittered(delay: Duration) -> Duration {
    delay.mul_f64(0.75 + rand::random::<f64>() * 0.5)
}

type RelaySocket =
    tokio_tungstenite::WebSocketStream<tokio_tungstenite::MaybeTlsStream<tokio::net::TcpStream>>;

enum ConnectOutcome {
    Connected(Box<RelaySocket>),
    Failed,
    Disconnect,
    Shutdown(oneshot::Sender<()>),
    Orphaned,
}

enum ServeEnd {
    Lost,
    Disconnect,
    Shutdown(oneshot::Sender<()>),
    Orphaned,
}

enum AuthUse {
    Publish,
    Read { allowed: bool },
}

struct RelayActor {
    url: RelayUrl,
    flags: Arc<AtomicU8>,
    status: Arc<AtomicU8>,
    stats: Arc<RelayStats>,
    signer: Arc<RwLock<Option<Keys>>>,
    auto_auth: Arc<AtomicBool>,
    plaintext_auth: Arc<AtomicBool>,
    keepalive: Duration,
    cmd_rx: mpsc::UnboundedReceiver<RelayCmd>,
    fetches: HashMap<String, ActiveFetch>,
    publishes: HashMap<String, PendingPublish>,
    subs: HashMap<String, ActiveSub>,
}

impl RelayActor {
    fn set_status(&self, status: RelayStatus) {
        self.status.store(status as u8, Ordering::Relaxed);
    }

    fn count_sent(&self, frame: &str) {
        self.stats
            .bytes_sent
            .fetch_add(frame.len() as u64, Ordering::Relaxed);
    }

    fn fail_pending(&mut self) {
        for (_, fetch) in self.fetches.drain() {
            fetch.reply(false);
        }
        for (_, mut publish) in self.publishes.drain() {
            if let Some(resp) = publish.resp.take() {
                let _ = resp.send(Err("Relay disconnected".to_string()));
            }
        }
    }

    fn terminate(&mut self, done: Option<oneshot::Sender<()>>) {
        self.set_status(RelayStatus::Terminated);
        self.fail_pending();
        if let Some(done) = done {
            let _ = done.send(());
        }
    }

    /// Handles a request that cannot be served because there is no connection. Subscriptions
    /// are kept so they open as soon as the relay connects.
    fn refuse(&mut self, cmd: RelayCmd, reason: &str) {
        match cmd {
            RelayCmd::SendEvent { resp, .. } => {
                let _ = resp.send(Err(reason.to_string()));
            }
            RelayCmd::Fetch { resp, .. } => {
                let _ = resp.send(FetchReply::failed());
            }
            RelayCmd::CancelFetch { sub_id } => {
                self.fetches.remove(&sub_id);
            }
            RelayCmd::Subscribe {
                sub_id,
                filter,
                allow_auth,
                tx,
            } => self.keep_subscription(sub_id, filter, allow_auth, tx),
            RelayCmd::Unsubscribe { sub_id } => {
                self.subs.remove(&sub_id);
            }
            #[cfg(test)]
            RelayCmd::Inspect(report) => {
                let _ = report.send(self.workload());
            }
            RelayCmd::Connect | RelayCmd::Disconnect | RelayCmd::Shutdown(_) => {}
        }
    }

    #[cfg(test)]
    fn workload(&self) -> Workload {
        Workload {
            fetches: self.fetches.len(),
            publishes: self.publishes.len(),
            subscriptions: self.subs.len(),
        }
    }

    fn keep_subscription(
        &mut self,
        sub_id: String,
        filter: Filter,
        allow_auth: bool,
        tx: mpsc::Sender<SubNotification>,
    ) {
        self.subs.insert(
            sub_id,
            ActiveSub {
                filter,
                tx,
                allow_auth,
                auth_retried: false,
            },
        );
    }

    async fn run(mut self) {
        let mut wanted = false;
        let mut backoff = INITIAL_BACKOFF;
        let mut retry_at: Option<tokio::time::Instant> = None;

        loop {
            if !wanted {
                match self.cmd_rx.recv().await {
                    None => return,
                    Some(RelayCmd::Connect) => {
                        wanted = true;
                        backoff = INITIAL_BACKOFF;
                        retry_at = None;
                    }
                    Some(RelayCmd::Disconnect) => self.set_status(RelayStatus::Disconnected),
                    Some(RelayCmd::Shutdown(done)) => return self.terminate(Some(done)),
                    Some(other) => self.refuse(other, "Relay not connected"),
                }
                continue;
            }

            if let Some(at) = retry_at.take() {
                loop {
                    tokio::select! {
                        _ = tokio::time::sleep_until(at) => break,
                        cmd = self.cmd_rx.recv() => match cmd {
                            None => return,
                            Some(RelayCmd::Connect) => break,
                            Some(RelayCmd::Disconnect) => {
                                wanted = false;
                                self.set_status(RelayStatus::Disconnected);
                                self.fail_pending();
                                break;
                            }
                            Some(RelayCmd::Shutdown(done)) => return self.terminate(Some(done)),
                            Some(other) => self.refuse(other, "Relay reconnecting"),
                        }
                    }
                }
                if !wanted {
                    continue;
                }
            }

            let socket = match self.connect().await {
                ConnectOutcome::Connected(socket) => socket,
                ConnectOutcome::Failed => {
                    self.set_status(RelayStatus::Disconnected);
                    self.fail_pending();
                    retry_at = Some(tokio::time::Instant::now() + jittered(backoff));
                    backoff = (backoff * 2).min(MAX_BACKOFF);
                    continue;
                }
                ConnectOutcome::Disconnect => {
                    wanted = false;
                    self.set_status(RelayStatus::Disconnected);
                    self.fail_pending();
                    continue;
                }
                ConnectOutcome::Shutdown(done) => return self.terminate(Some(done)),
                ConnectOutcome::Orphaned => return,
            };

            let connected_at = Instant::now();
            match self.serve(*socket).await {
                ServeEnd::Lost => {}
                ServeEnd::Disconnect => wanted = false,
                ServeEnd::Shutdown(done) => return self.terminate(Some(done)),
                ServeEnd::Orphaned => return self.terminate(None),
            }

            self.set_status(RelayStatus::Disconnected);
            self.fail_pending();
            if wanted {
                if connected_at.elapsed() >= STABLE_CONNECTION {
                    backoff = INITIAL_BACKOFF;
                }
                retry_at = Some(tokio::time::Instant::now() + jittered(backoff));
                backoff = (backoff * 2).min(MAX_BACKOFF);
            }
        }
    }

    /// Opens the socket while still accepting requests, which wait for the connection.
    async fn connect(&mut self) -> ConnectOutcome {
        self.stats
            .connect_started_ms
            .store(monotonic_ms(), Ordering::Relaxed);
        self.set_status(RelayStatus::Connecting);
        self.stats.attempts.fetch_add(1, Ordering::Relaxed);
        let started = Instant::now();
        let target = self.url.to_string();

        let attempt = tokio_tungstenite::connect_async_with_config(
            target.as_str(),
            Some(hardened_ws_config()),
            true,
        );
        tokio::pin!(attempt);
        let deadline = tokio::time::sleep(CONNECT_TIMEOUT);
        tokio::pin!(deadline);

        loop {
            tokio::select! {
                result = &mut attempt => {
                    let Ok((socket, _)) = result else {
                        return ConnectOutcome::Failed;
                    };
                    let latency = started.elapsed().as_millis().max(1) as u64;
                    self.stats.latency_ms.store(latency, Ordering::Relaxed);
                    self.stats.success.fetch_add(1, Ordering::Relaxed);
                    self.stats.connected_at_secs.store(now_secs(), Ordering::Relaxed);
                    self.set_status(RelayStatus::Connected);
                    return ConnectOutcome::Connected(Box::new(socket));
                }
                _ = &mut deadline => return ConnectOutcome::Failed,
                cmd = self.cmd_rx.recv() => match cmd {
                    None => return ConnectOutcome::Orphaned,
                    Some(RelayCmd::Connect) => {}
                    Some(RelayCmd::Disconnect) => return ConnectOutcome::Disconnect,
                    Some(RelayCmd::Shutdown(done)) => return ConnectOutcome::Shutdown(done),
                    Some(RelayCmd::SendEvent { event, resp }) => {
                        self.publishes.insert(
                            event.id.to_hex(),
                            PendingPublish {
                                raw_frame: build_event_frame(&event),
                                auth_retried: false,
                                resp: Some(resp),
                            },
                        );
                    }
                    Some(RelayCmd::Fetch { sub_id, filter, allow_auth, resp }) => {
                        self.fetches.insert(sub_id, ActiveFetch::new(filter, allow_auth, resp));
                    }
                    Some(other) => self.refuse(other, "Relay reconnecting"),
                }
            }
        }
    }

    /// Sends everything that was waiting for the connection.
    async fn flush_queued(&mut self, socket: &mut RelaySocket) -> bool {
        self.subs.retain(|_, sub| !sub.tx.is_closed());
        self.fetches.retain(|_, fetch| !fetch.is_abandoned());
        self.publishes.retain(|_, publish| !publish.is_abandoned());
        for sub in self.subs.values_mut() {
            sub.auth_retried = false;
        }
        for fetch in self.fetches.values_mut() {
            fetch.auth_retried = false;
        }
        for publish in self.publishes.values_mut() {
            publish.auth_retried = false;
        }

        let mut frames: Vec<String> = Vec::new();
        frames.extend(
            self.subs
                .iter()
                .map(|(id, sub)| build_req_frame(id, &sub.filter)),
        );
        frames.extend(
            self.fetches
                .iter()
                .map(|(id, fetch)| build_req_frame(id, &fetch.filter)),
        );
        frames.extend(self.publishes.values().map(|p| p.raw_frame.clone()));
        for frame in frames {
            self.count_sent(&frame);
            if socket.send(Message::Text(frame)).await.is_err() {
                return false;
            }
        }
        true
    }

    /// Drops requests nobody is waiting for any more, so they are not kept or re-sent forever.
    async fn drop_abandoned(&mut self, socket: &mut RelaySocket) {
        let mut closed: Vec<String> = Vec::new();
        self.fetches.retain(|id, fetch| {
            let keep = !fetch.is_abandoned();
            if !keep {
                closed.push(id.clone());
            }
            keep
        });
        self.subs.retain(|id, sub| {
            let keep = !sub.tx.is_closed();
            if !keep {
                closed.push(id.clone());
            }
            keep
        });
        self.publishes.retain(|_, publish| !publish.is_abandoned());
        for id in closed {
            let frame = build_close_frame(&id);
            self.count_sent(&frame);
            let _ = socket.send(Message::Text(frame)).await;
        }
    }

    async fn serve(&mut self, mut socket: RelaySocket) -> ServeEnd {
        let mut challenge: Option<String> = None;
        let mut ping_sent_at: Option<Instant> = None;
        let mut ping = tokio::time::interval(self.keepalive);
        ping.tick().await;

        if !self.flush_queued(&mut socket).await {
            return ServeEnd::Lost;
        }

        loop {
            tokio::select! {
                frame = socket.next() => match frame {
                    Some(Ok(Message::Text(text))) => {
                        self.stats.bytes_received.fetch_add(text.len() as u64, Ordering::Relaxed);
                        self.on_text(&mut socket, &text, &mut challenge).await;
                    }
                    Some(Ok(Message::Ping(payload))) => {
                        let _ = socket.send(Message::Pong(payload)).await;
                    }
                    Some(Ok(Message::Pong(_))) => {
                        if let Some(sent) = ping_sent_at.take() {
                            let rtt = sent.elapsed().as_millis().max(1) as u64;
                            self.stats.latency_ms.store(rtt, Ordering::Relaxed);
                        }
                    }
                    Some(Ok(Message::Close(_))) | Some(Err(_)) | None => return ServeEnd::Lost,
                    _ => {}
                },
                cmd = self.cmd_rx.recv() => {
                    let Some(cmd) = cmd else {
                        let _ = socket.close(None).await;
                        return ServeEnd::Orphaned;
                    };
                    if let Some(end) = self.on_command(&mut socket, cmd).await {
                        return end;
                    }
                }
                _ = ping.tick() => {
                    if ping_sent_at.is_some() {
                        return ServeEnd::Lost;
                    }
                    self.drop_abandoned(&mut socket).await;
                    ping_sent_at = Some(Instant::now());
                    if socket.send(Message::Ping(Vec::new())).await.is_err() {
                        return ServeEnd::Lost;
                    }
                }
            }
        }
    }

    async fn on_command(&mut self, socket: &mut RelaySocket, cmd: RelayCmd) -> Option<ServeEnd> {
        match cmd {
            RelayCmd::Connect => {}
            RelayCmd::Disconnect => {
                let _ = socket.close(None).await;
                return Some(ServeEnd::Disconnect);
            }
            RelayCmd::Shutdown(done) => {
                let _ = socket.close(None).await;
                return Some(ServeEnd::Shutdown(done));
            }
            RelayCmd::SendEvent { event, resp } => {
                let raw_frame = build_event_frame(&event);
                self.count_sent(&raw_frame);
                if socket.send(Message::Text(raw_frame.clone())).await.is_err() {
                    let _ = resp.send(Err("Failed to send event".to_string()));
                    return Some(ServeEnd::Lost);
                }
                self.publishes.insert(
                    event.id.to_hex(),
                    PendingPublish {
                        raw_frame,
                        auth_retried: false,
                        resp: Some(resp),
                    },
                );
            }
            RelayCmd::Fetch {
                sub_id,
                filter,
                allow_auth,
                resp,
            } => {
                let frame = build_req_frame(&sub_id, &filter);
                self.count_sent(&frame);
                if socket.send(Message::Text(frame)).await.is_err() {
                    let _ = resp.send(FetchReply::failed());
                    return Some(ServeEnd::Lost);
                }
                self.fetches
                    .insert(sub_id, ActiveFetch::new(filter, allow_auth, resp));
            }
            RelayCmd::CancelFetch { sub_id } => {
                if self.fetches.remove(&sub_id).is_some() {
                    self.send_close(socket, &sub_id).await;
                }
            }
            RelayCmd::Subscribe {
                sub_id,
                filter,
                allow_auth,
                tx,
            } => {
                let frame = build_req_frame(&sub_id, &filter);
                self.count_sent(&frame);
                self.keep_subscription(sub_id, filter, allow_auth, tx);
                if socket.send(Message::Text(frame)).await.is_err() {
                    return Some(ServeEnd::Lost);
                }
            }
            RelayCmd::Unsubscribe { sub_id } => {
                if self.subs.remove(&sub_id).is_some() {
                    self.send_close(socket, &sub_id).await;
                }
            }
            #[cfg(test)]
            RelayCmd::Inspect(report) => {
                let _ = report.send(self.workload());
            }
        }
        None
    }

    async fn send_close(&self, socket: &mut RelaySocket, sub_id: &str) {
        let frame = build_close_frame(sub_id);
        self.count_sent(&frame);
        let _ = socket.send(Message::Text(frame)).await;
    }

    async fn on_text(
        &mut self,
        socket: &mut RelaySocket,
        text: &str,
        challenge: &mut Option<String>,
    ) {
        let Ok(parts) = serde_json::from_str::<Vec<&RawValue>>(text) else {
            return;
        };
        let Some(kind) = parts.first().map(|part| part.get()) else {
            return;
        };
        match kind {
            "\"EVENT\"" if parts.len() >= 3 => self.on_event(socket, parts[1], parts[2]).await,
            "\"EOSE\"" if parts.len() >= 2 => self.on_eose(socket, parts[1]).await,
            "\"OK\"" if parts.len() >= 3 => self.on_ok(socket, &parts, challenge.as_deref()).await,
            "\"CLOSED\"" if parts.len() >= 2 => {
                self.on_closed(socket, &parts, challenge.as_deref()).await
            }
            "\"AUTH\"" if parts.len() >= 2 => self.on_challenge(socket, parts[1], challenge).await,
            _ => {}
        }
    }

    async fn on_event(&mut self, socket: &mut RelaySocket, sub: &RawValue, raw_event: &RawValue) {
        let Some(sub_id) = raw_str(sub) else {
            return;
        };
        let sub_id = sub_id.as_ref();

        if let Some(fetch) = self.fetches.get_mut(sub_id) {
            if fetch.events.len() >= MAX_FETCH_EVENTS_PER_RELAY {
                return;
            }
            let Ok(event) = serde_json::from_str::<Event>(raw_event.get()) else {
                return;
            };
            if fetch.seen.contains(&event.id)
                || !fetch.filter.match_event(&event, MatchEventOptions::new())
                || (fetch.exact_ids.is_some() && event.verify().is_err())
            {
                return;
            }
            fetch.seen.insert(event.id);
            fetch.events.push(event);
            if fetch
                .exact_ids
                .is_some_and(|wanted| fetch.events.len() >= wanted)
            {
                self.finish_fetch(socket, sub_id, true).await;
            }
            return;
        }

        let Some(sub) = self.subs.get(sub_id) else {
            return;
        };
        let Ok(event) = serde_json::from_str::<Event>(raw_event.get()) else {
            return;
        };
        if !sub.filter.match_event(&event, MatchEventOptions::new()) || event.verify().is_err() {
            return;
        }
        let notification = SubNotification::Event {
            event: Box::new(event),
        };
        if let Err(TrySendError::Closed(_)) = sub.tx.try_send(notification) {
            self.subs.remove(sub_id);
            self.send_close(socket, sub_id).await;
        }
    }

    async fn finish_fetch(&mut self, socket: &mut RelaySocket, sub_id: &str, answered: bool) {
        let Some(fetch) = self.fetches.remove(sub_id) else {
            return;
        };
        if answered {
            let rtt = fetch.started.elapsed().as_millis().max(1) as u64;
            self.stats.latency_ms.store(rtt, Ordering::Relaxed);
        }
        fetch.reply(answered);
        self.send_close(socket, sub_id).await;
    }

    async fn on_eose(&mut self, socket: &mut RelaySocket, sub: &RawValue) {
        let Some(sub_id) = raw_str(sub) else {
            return;
        };
        if self.fetches.contains_key(sub_id.as_ref()) {
            self.finish_fetch(socket, sub_id.as_ref(), true).await;
        } else if let Some(sub) = self.subs.get(sub_id.as_ref()) {
            let _ = sub.tx.try_send(SubNotification::Eose);
        }
    }

    fn may_authenticate(&self, purpose: AuthUse) -> bool {
        if !self.auto_auth.load(Ordering::Relaxed) {
            return false;
        }
        if (self.flags.load(Ordering::Relaxed) & FLAG_AUTH) != 0 {
            return true;
        }
        let reachable_safely =
            is_public_secure_relay(&self.url) || self.plaintext_auth.load(Ordering::Relaxed);
        match purpose {
            AuthUse::Publish => reachable_safely,
            AuthUse::Read { allowed } => allowed && reachable_safely,
        }
    }

    async fn authenticate(&self, socket: &mut RelaySocket, challenge: &str) -> bool {
        let Some(keys) = self.signer.read().await.clone() else {
            return false;
        };
        let frame = if self.plaintext_auth.load(Ordering::Relaxed) {
            sign_auth_frame(&keys, challenge, &self.url)
        } else {
            build_auth_frame(&keys, challenge, &self.url)
        };
        let Some(frame) = frame else {
            return false;
        };
        self.count_sent(&frame);
        socket.send(Message::Text(frame)).await.is_ok()
    }

    async fn on_challenge(
        &mut self,
        socket: &mut RelaySocket,
        raw: &RawValue,
        challenge: &mut Option<String>,
    ) {
        let Some(value) = raw_str(raw) else {
            return;
        };
        if !is_usable_challenge(&value) {
            return;
        }
        *challenge = Some(value.into_owned());
        let trusted = (self.flags.load(Ordering::Relaxed) & FLAG_AUTH) != 0;
        if trusted && self.auto_auth.load(Ordering::Relaxed) {
            if let Some(challenge) = challenge.as_deref() {
                self.authenticate(socket, challenge).await;
            }
        }
    }

    async fn on_ok(
        &mut self,
        socket: &mut RelaySocket,
        parts: &[&RawValue],
        challenge: Option<&str>,
    ) {
        let Some(event_id) = raw_str(parts[1]) else {
            return;
        };
        let event_id = event_id.as_ref();
        let accepted = parts[2].get() == "true";
        let message = parts
            .get(3)
            .and_then(|raw| raw_str(raw))
            .map(Cow::into_owned)
            .unwrap_or_default();

        let wants_auth = !accepted
            && message.starts_with("auth-required:")
            && self
                .publishes
                .get(event_id)
                .is_some_and(|publish| !publish.auth_retried);
        if wants_auth && self.may_authenticate(AuthUse::Publish) {
            if let Some(challenge) = challenge {
                if self.authenticate(socket, challenge).await {
                    if let Some(publish) = self.publishes.get_mut(event_id) {
                        publish.auth_retried = true;
                        let frame = publish.raw_frame.clone();
                        self.count_sent(&frame);
                        let _ = socket.send(Message::Text(frame)).await;
                        return;
                    }
                }
            }
        }

        let Some(mut publish) = self.publishes.remove(event_id) else {
            return;
        };
        if let Some(resp) = publish.resp.take() {
            let outcome = if accepted {
                Ok(())
            } else if message.is_empty() {
                Err("Rejected by relay".to_string())
            } else {
                Err(message)
            };
            let _ = resp.send(outcome);
        }
    }

    async fn on_closed(
        &mut self,
        socket: &mut RelaySocket,
        parts: &[&RawValue],
        challenge: Option<&str>,
    ) {
        let Some(sub_id) = raw_str(parts[1]) else {
            return;
        };
        let sub_id = sub_id.as_ref();
        let message = parts
            .get(2)
            .and_then(|raw| raw_str(raw))
            .map(Cow::into_owned)
            .unwrap_or_default();

        if message.starts_with("auth-required:") {
            let retry = if let Some(fetch) = self.fetches.get(sub_id) {
                (!fetch.auth_retried).then(|| (fetch.allow_auth, fetch.filter.clone()))
            } else if let Some(sub) = self.subs.get(sub_id) {
                (!sub.auth_retried).then(|| (sub.allow_auth, sub.filter.clone()))
            } else {
                None
            };
            if let (Some((allowed, filter)), Some(challenge)) = (retry, challenge) {
                if self.may_authenticate(AuthUse::Read { allowed })
                    && self.authenticate(socket, challenge).await
                {
                    if let Some(fetch) = self.fetches.get_mut(sub_id) {
                        fetch.auth_retried = true;
                    } else if let Some(sub) = self.subs.get_mut(sub_id) {
                        sub.auth_retried = true;
                    }
                    let frame = build_req_frame(sub_id, &filter);
                    self.count_sent(&frame);
                    let _ = socket.send(Message::Text(frame)).await;
                    return;
                }
            }
        }

        if let Some(fetch) = self.fetches.remove(sub_id) {
            fetch.reply(false);
        } else if let Some(sub) = self.subs.get(sub_id) {
            let _ = sub.tx.try_send(SubNotification::Closed {
                relay: self.url.clone(),
                message,
            });
        }
    }
}

struct RegisteredSub {
    filter: Filter,
    tx: mpsc::Sender<SubNotification>,
    allow_auth: bool,
    pool_wide: bool,
    relays: usize,
}

struct ClientInner {
    db: Arc<EventStore>,
    signer: Arc<RwLock<Option<Keys>>>,
    auto_auth: Arc<AtomicBool>,
    plaintext_auth: Arc<AtomicBool>,
    keepalive_ms: AtomicU64,
    relays: RwLock<HashMap<RelayUrl, Arc<RelayConn>>>,
    subscriptions: Mutex<HashMap<String, RegisteredSub>>,
}

#[derive(Clone)]
pub struct NostrClient {
    inner: Arc<ClientInner>,
}

/// How long a fetch keeps waiting for relays that have not answered yet.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum FetchMode {
    /// Returns once most relays have answered; later answers add little.
    Quick,
    /// Waits for every relay that is still answering, because any one of them may hold the
    /// newest version of what was asked for.
    Thorough,
}

const FETCH_GRACE_AFTER_RESULTS: Duration = Duration::from_millis(1_000);
const FETCH_GRACE_AFTER_MAJORITY: Duration = Duration::from_millis(1_000);
const FETCH_GRACE_AFTER_MAJORITY_WITH_RESULTS: Duration = Duration::from_millis(500);
/// How long a thorough fetch waits after the latest answer for connected relays that are silent.
const THOROUGH_QUIET_PERIOD: Duration = Duration::from_millis(1_500);
/// How long it waits after the latest answer for relays that only just started connecting.
const THOROUGH_JOINING_GRACE: Duration = Duration::from_millis(800);
const RECENT_CONNECT_ATTEMPT: Duration = Duration::from_millis(2_500);

fn is_replaceable_kind(kind: u16) -> bool {
    kind == 0 || kind == 3 || (10_000..20_000).contains(&kind) || (30_000..40_000).contains(&kind)
}

/// A request for one author's replaceable events: relays may hold different versions and only
/// the newest is right, so stopping early risks returning a stale one.
fn is_replaceable_lookup(filter: &Filter) -> bool {
    filter.ids.as_ref().is_none_or(|ids| ids.is_empty())
        && filter.authors.as_ref().is_some_and(|a| a.len() == 1)
        && filter.kinds.as_ref().is_some_and(|kinds| {
            !kinds.is_empty() && kinds.iter().all(|k| is_replaceable_kind(k.as_u16()))
        })
}

impl NostrClient {
    pub fn new(db: Arc<EventStore>, signer: Option<Keys>) -> Self {
        Self {
            inner: Arc::new(ClientInner {
                db,
                signer: Arc::new(RwLock::new(signer)),
                auto_auth: Arc::new(AtomicBool::new(false)),
                plaintext_auth: Arc::new(AtomicBool::new(false)),
                keepalive_ms: AtomicU64::new(KEEPALIVE_INTERVAL.as_millis() as u64),
                relays: RwLock::new(HashMap::new()),
                subscriptions: Mutex::new(HashMap::new()),
            }),
        }
    }

    pub fn in_memory(signer: Option<Keys>) -> Self {
        let db = Arc::new(EventStore::open_in_memory().expect("in-memory sqlite"));
        Self::new(db, signer)
    }

    /// Lets relays that require it learn the account's public key (NIP-42). Relays marked with
    /// [`FLAG_AUTH`] are answered as soon as they ask. Any other relay is answered only when it
    /// refuses a publish, a relay-hosted group request, or a read of the account's own inbox,
    /// and only if it is a public relay reached over TLS.
    pub fn automatic_authentication(&self, enabled: bool) {
        self.inner.auto_auth.store(enabled, Ordering::Relaxed);
    }

    #[cfg(test)]
    fn allow_plaintext_authentication(&self) {
        self.inner.plaintext_auth.store(true, Ordering::Relaxed);
    }

    #[cfg(test)]
    fn set_keepalive(&self, interval: Duration) {
        self.inner
            .keepalive_ms
            .store(interval.as_millis() as u64, Ordering::Relaxed);
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

    fn registered_subscriptions(
        &self,
    ) -> std::sync::MutexGuard<'_, HashMap<String, RegisteredSub>> {
        self.inner
            .subscriptions
            .lock()
            .unwrap_or_else(|poisoned| poisoned.into_inner())
    }

    /// Opens the pool's live subscriptions on a relay that joined after they were made.
    fn replay_subscriptions(&self, conn: &RelayConn) {
        let mut subscriptions = self.registered_subscriptions();
        subscriptions.retain(|_, sub| !sub.tx.is_closed());
        for (sub_id, sub) in subscriptions.iter_mut().filter(|(_, sub)| sub.pool_wide) {
            let sent = conn.cmd_tx.send(RelayCmd::Subscribe {
                sub_id: sub_id.clone(),
                filter: sub.filter.clone(),
                allow_auth: sub.allow_auth,
                tx: sub.tx.clone(),
            });
            if sent.is_ok() {
                sub.relays += 1;
            }
        }
    }

    /// How many relays a live subscription has been sent to, counting relays that joined the
    /// pool after it was opened.
    pub fn subscription_relay_count(&self, sub_id: &str) -> usize {
        self.registered_subscriptions()
            .get(sub_id)
            .map_or(0, |sub| sub.relays)
    }

    pub async fn add_relay_with_flags(&self, url: &str, flags: u8) -> Result<bool> {
        let relay_url = RelayUrl::parse(url)?;
        let mut relays = self.inner.relays.write().await;
        if let Some(existing) = relays.get(&relay_url) {
            let was_subscribed = existing.receives_pool_subscriptions();
            existing.set_flags(flags);
            if !was_subscribed && existing.receives_pool_subscriptions() {
                self.replay_subscriptions(existing);
            }
            return Ok(true);
        }
        let flags = Arc::new(AtomicU8::new(flags));
        let status = Arc::new(AtomicU8::new(RelayStatus::Initialized as u8));
        let stats = Arc::new(RelayStats::default());
        let (cmd_tx, cmd_rx) = mpsc::unbounded_channel();
        let actor = RelayActor {
            url: relay_url.clone(),
            flags: flags.clone(),
            status: status.clone(),
            stats: stats.clone(),
            signer: self.inner.signer.clone(),
            auto_auth: self.inner.auto_auth.clone(),
            plaintext_auth: self.inner.plaintext_auth.clone(),
            keepalive: Duration::from_millis(self.inner.keepalive_ms.load(Ordering::Relaxed)),
            cmd_rx,
            fetches: HashMap::new(),
            publishes: HashMap::new(),
            subs: HashMap::new(),
        };
        tokio::spawn(actor.run());
        let conn = Arc::new(RelayConn {
            flags,
            status,
            stats,
            cmd_tx,
        });
        if conn.receives_pool_subscriptions() {
            self.replay_subscriptions(&conn);
        }
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
        self.unset_signer().await;
        self.registered_subscriptions().clear();
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
        self.fetch_from_conns(conns, filter, timeout, save_to_db, FetchMode::Quick)
            .await
    }

    async fn readable_relays(&self, only_connected_if_enough: bool) -> Vec<Arc<RelayConn>> {
        let relays = self.inner.relays.read().await;
        let mut connected: Vec<Arc<RelayConn>> = Vec::new();
        let mut usable: Vec<Arc<RelayConn>> = Vec::new();
        for conn in relays.values() {
            if !conn.has_flag(FLAG_READ) {
                continue;
            }
            let status = conn.status();
            if status == RelayStatus::Connected {
                connected.push(conn.clone());
            }
            if !matches!(status, RelayStatus::Banned | RelayStatus::Terminated) {
                usable.push(conn.clone());
            }
        }
        if only_connected_if_enough && connected.len() >= 2 {
            connected
        } else {
            usable
        }
    }

    /// Fetches from the pool's read relays. A request for one author's replaceable events waits
    /// for every relay still answering; anything else returns once most relays have answered.
    pub async fn fetch(
        &self,
        filter: Filter,
        timeout: Duration,
        save_to_db: bool,
    ) -> Result<Vec<Event>> {
        if is_replaceable_lookup(&filter) {
            self.thorough_fetch(filter, timeout, save_to_db).await
        } else {
            self.quick_fetch(filter, timeout, save_to_db).await
        }
    }

    /// Fetches from the connected read relays and returns once most of them have answered.
    pub async fn quick_fetch(
        &self,
        filter: Filter,
        timeout: Duration,
        save_to_db: bool,
    ) -> Result<Vec<Event>> {
        let conns = self.readable_relays(true).await;
        self.fetch_from_conns(conns, filter, timeout, save_to_db, FetchMode::Quick)
            .await
    }

    /// Fetches from every read relay, including ones still connecting, and waits until all of
    /// them have answered or have gone quiet.
    pub async fn thorough_fetch(
        &self,
        filter: Filter,
        timeout: Duration,
        save_to_db: bool,
    ) -> Result<Vec<Event>> {
        let conns = self.readable_relays(false).await;
        self.fetch_from_conns(conns, filter, timeout, save_to_db, FetchMode::Thorough)
            .await
    }

    async fn fetch_from_conns(
        &self,
        conns: Vec<Arc<RelayConn>>,
        filter: Filter,
        timeout: Duration,
        save_to_db: bool,
        mode: FetchMode,
    ) -> Result<Vec<Event>> {
        if conns.is_empty() {
            return Ok(Vec::new());
        }
        let expected_ids = filter.ids.as_ref().map(|ids| ids.len()).filter(|&n| n > 0);
        let single_id_lookup =
            expected_ids == Some(1) || (expected_ids.is_some() && filter.limit == Some(1));
        let account = self
            .inner
            .signer
            .read()
            .await
            .as_ref()
            .map(Keys::public_key);
        let allow_auth = filter_is_relay_scoped(&filter, account.as_ref());

        let mut outstanding: Vec<Option<(Arc<RelayConn>, String)>> =
            Vec::with_capacity(conns.len());
        let mut pending: FuturesUnordered<_> = FuturesUnordered::new();
        for conn in conns {
            let sub_id = next_sub_id("f");
            let (tx, rx) = oneshot::channel();
            if conn
                .cmd_tx
                .send(RelayCmd::Fetch {
                    sub_id: sub_id.clone(),
                    filter: filter.clone(),
                    allow_auth,
                    resp: tx,
                })
                .is_ok()
            {
                let index = outstanding.len();
                outstanding.push(Some((conn, sub_id)));
                pending.push(
                    async move { (index, rx.await.unwrap_or_else(|_| FetchReply::failed())) },
                );
            }
        }

        let deadline = tokio::time::Instant::now() + timeout;
        let mut verified: HashMap<EventId, Event> = HashMap::new();
        let mut candidates: HashMap<EventId, Vec<Event>> = HashMap::new();
        let mut answered = 0usize;
        let mut first_results: Option<tokio::time::Instant> = None;
        let mut majority: Option<tokio::time::Instant> = None;
        let mut last_answer: Option<tokio::time::Instant> = None;

        loop {
            let mut wake = deadline;
            match mode {
                FetchMode::Quick => {
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
                }
                FetchMode::Thorough => {
                    if let Some(at) = last_answer {
                        let waiting_on = || outstanding.iter().flatten().map(|(conn, _)| conn);
                        let patience = if waiting_on().any(|c| c.status() == RelayStatus::Connected)
                        {
                            THOROUGH_QUIET_PERIOD
                        } else if waiting_on().any(|c| c.is_joining()) {
                            THOROUGH_JOINING_GRACE
                        } else {
                            Duration::ZERO
                        };
                        wake = wake.min(at + patience);
                    }
                }
            }
            if wake <= tokio::time::Instant::now() {
                break;
            }

            tokio::select! {
                next = pending.next() => {
                    let Some((index, reply)) = next else {
                        break;
                    };
                    outstanding[index] = None;
                    let now = tokio::time::Instant::now();
                    if reply.answered {
                        answered += 1;
                        last_answer = Some(now);
                    }
                    if !reply.events.is_empty() && first_results.is_none() {
                        first_results = Some(now);
                    }
                    for event in reply.events {
                        if reply.verified {
                            verified.entry(event.id).or_insert(event);
                        } else {
                            let copies = candidates.entry(event.id).or_default();
                            if !copies.contains(&event) {
                                copies.push(event);
                            }
                        }
                    }
                    if single_id_lookup && !verified.is_empty() {
                        break;
                    }
                    if expected_ids.is_some_and(|wanted| verified.len() >= wanted) {
                        break;
                    }
                    if majority.is_none() && answered > 0 {
                        let waiting_on_connected = outstanding
                            .iter()
                            .flatten()
                            .filter(|(conn, _)| conn.status() == RelayStatus::Connected)
                            .count();
                        if answered >= waiting_on_connected {
                            majority = Some(now);
                        }
                    }
                }
                _ = tokio::time::sleep_until(wake) => {}
            }
        }

        for (conn, sub_id) in outstanding.into_iter().flatten() {
            let _ = conn.cmd_tx.send(RelayCmd::CancelFetch { sub_id });
        }

        if verified.is_empty() && candidates.is_empty() {
            return Ok(Vec::new());
        }

        // An id we already hold names an event we verified before, so our copy is returned and
        // the relay's is never trusted on the strength of its id. Everything else is verified
        // before copies are merged, so a forged copy cannot stand in for a genuine one.
        candidates.retain(|id, _| !verified.contains_key(id));
        let candidate_ids: Vec<EventId> = candidates.keys().copied().collect();
        let stored = self
            .inner
            .db
            .events_by_ids(&candidate_ids)
            .unwrap_or_default();
        for event in &stored {
            candidates.remove(&event.id);
        }
        let to_verify: Vec<Event> = candidates.into_values().flatten().collect();
        let checked: Vec<Event> = if to_verify.len() >= 16 {
            tokio::task::spawn_blocking(move || verify_events_parallel(to_verify))
                .await
                .unwrap_or_default()
        } else {
            to_verify
                .into_iter()
                .filter(|event| event.verify().is_ok())
                .collect()
        };
        for event in checked {
            verified.entry(event.id).or_insert(event);
        }

        let mut all: Vec<Event> = verified.into_values().collect();
        if save_to_db && !all.is_empty() {
            let _ = self.inner.db.save_events(&all);
        }
        all.extend(
            stored
                .into_iter()
                .filter(|event| filter.match_event(event, MatchEventOptions::new())),
        );
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

    /// Opens a live subscription and returns its id, its notifications, and how many relays it
    /// was sent to. Without `targets` it covers the pool's read relays, including any added
    /// while it is open.
    pub async fn subscribe_on(
        &self,
        filter: Filter,
        targets: Option<&[RelayUrl]>,
    ) -> Result<(String, mpsc::Receiver<SubNotification>, usize)> {
        let sub_id = next_sub_id("sub");
        let (tx, rx) = mpsc::channel(SUBSCRIPTION_BUFFER);
        let account = self
            .inner
            .signer
            .read()
            .await
            .as_ref()
            .map(Keys::public_key);
        let allow_auth = filter_is_relay_scoped(&filter, account.as_ref());
        let relays = self.inner.relays.read().await;
        let mut count = 0usize;
        for (url, conn) in relays.iter() {
            let include = match targets {
                Some(list) => list.contains(url),
                None => conn.receives_pool_subscriptions(),
            };
            if include
                && conn
                    .cmd_tx
                    .send(RelayCmd::Subscribe {
                        sub_id: sub_id.clone(),
                        filter: filter.clone(),
                        allow_auth,
                        tx: tx.clone(),
                    })
                    .is_ok()
            {
                count += 1;
            }
        }
        let mut subscriptions = self.registered_subscriptions();
        subscriptions.retain(|_, sub| !sub.tx.is_closed());
        subscriptions.insert(
            sub_id.clone(),
            RegisteredSub {
                filter,
                tx,
                allow_auth,
                pool_wide: targets.is_none(),
                relays: count,
            },
        );
        drop(subscriptions);
        Ok((sub_id, rx, count))
    }

    pub async fn unsubscribe(&self, sub_id: &str) {
        self.registered_subscriptions().remove(sub_id);
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

/// A scripted relay for tests.
#[cfg(test)]
pub(crate) mod test_relay {
    use std::sync::atomic::{AtomicUsize, Ordering};
    use std::sync::Arc;
    use std::time::Duration;

    use futures::{SinkExt, StreamExt};
    use nostr::prelude::*;
    use tokio::net::TcpListener;
    use tokio_tungstenite::accept_async;
    use tokio_tungstenite::tungstenite::Message;

    #[derive(Clone, Default)]
    pub(crate) struct Script {
        pub(crate) events: Vec<serde_json::Value>,
        pub(crate) live: Vec<serde_json::Value>,
        pub(crate) delay: Duration,
        pub(crate) silent: bool,
        pub(crate) close_on_connect: bool,
        pub(crate) challenge: Option<&'static str>,
        pub(crate) require_auth: bool,
        pub(crate) refuse_requests: Option<&'static str>,
        pub(crate) drop_first_connection_after_answering: bool,
        pub(crate) never_acknowledge_publishes: bool,
    }

    pub(crate) struct MockRelay {
        pub(crate) url: String,
        pub(crate) connections: Arc<AtomicUsize>,
        pub(crate) requests: Arc<AtomicUsize>,
        pub(crate) answered: Arc<AtomicUsize>,
        pub(crate) authentications: Arc<AtomicUsize>,
        pub(crate) publishes: Arc<AtomicUsize>,
    }

    impl MockRelay {
        pub(crate) fn relay_url(&self) -> RelayUrl {
            RelayUrl::parse(&self.url).unwrap()
        }
    }

    pub(crate) fn json(event: &Event) -> serde_json::Value {
        serde_json::from_str(&event.as_json()).unwrap()
    }

    fn frame(value: serde_json::Value) -> Message {
        Message::Text(value.to_string())
    }

    pub(crate) async fn mock_relay(script: Script) -> MockRelay {
        let listener = TcpListener::bind("127.0.0.1:0").await.unwrap();
        let relay = MockRelay {
            url: format!("ws://{}", listener.local_addr().unwrap()),
            connections: Arc::new(AtomicUsize::new(0)),
            requests: Arc::new(AtomicUsize::new(0)),
            answered: Arc::new(AtomicUsize::new(0)),
            authentications: Arc::new(AtomicUsize::new(0)),
            publishes: Arc::new(AtomicUsize::new(0)),
        };
        let connections = relay.connections.clone();
        let requests = relay.requests.clone();
        let answered = relay.answered.clone();
        let authentications = relay.authentications.clone();
        let publishes = relay.publishes.clone();
        tokio::spawn(async move {
            while let Ok((stream, _)) = listener.accept().await {
                let script = script.clone();
                let connections = connections.clone();
                let requests = requests.clone();
                let answered = answered.clone();
                let authentications = authentications.clone();
                let publishes = publishes.clone();
                tokio::spawn(async move {
                    let Ok(mut ws) = accept_async(stream).await else {
                        return;
                    };
                    let connection = connections.fetch_add(1, Ordering::SeqCst);
                    if script.close_on_connect {
                        let _ = ws.close(None).await;
                        return;
                    }
                    if let Some(challenge) = script.challenge {
                        let _ = ws.send(frame(serde_json::json!(["AUTH", challenge]))).await;
                    }
                    let mut authenticated = false;
                    while let Some(Ok(message)) = ws.next().await {
                        let Message::Text(text) = message else {
                            continue;
                        };
                        let Ok(value) = serde_json::from_str::<serde_json::Value>(&text) else {
                            continue;
                        };
                        match value[0].as_str() {
                            Some("REQ") => {
                                requests.fetch_add(1, Ordering::SeqCst);
                                let sub = value[1].clone();
                                if script.silent {
                                    continue;
                                }
                                if let Some(reason) = script.refuse_requests {
                                    let _ = ws
                                        .send(frame(serde_json::json!(["CLOSED", sub, reason])))
                                        .await;
                                    continue;
                                }
                                if script.require_auth && !authenticated {
                                    let _ = ws
                                        .send(frame(serde_json::json!([
                                            "CLOSED",
                                            sub,
                                            "auth-required: sign in first"
                                        ])))
                                        .await;
                                    continue;
                                }
                                tokio::time::sleep(script.delay).await;
                                for event in &script.events {
                                    let _ = ws
                                        .send(frame(serde_json::json!(["EVENT", sub, event])))
                                        .await;
                                }
                                let _ = ws.send(frame(serde_json::json!(["EOSE", sub]))).await;
                                answered.fetch_add(1, Ordering::SeqCst);
                                for event in &script.live {
                                    let _ = ws
                                        .send(frame(serde_json::json!(["EVENT", sub, event])))
                                        .await;
                                }
                                if script.drop_first_connection_after_answering && connection == 0 {
                                    let _ = ws.close(None).await;
                                    return;
                                }
                            }
                            Some("AUTH") => {
                                let valid = Event::from_json(value[1].to_string()).is_ok_and(|e| {
                                    e.kind == Kind::Authentication && e.verify().is_ok()
                                });
                                if valid {
                                    authenticated = true;
                                    authentications.fetch_add(1, Ordering::SeqCst);
                                }
                                let _ = ws
                                    .send(frame(serde_json::json!([
                                        "OK",
                                        value[1]["id"],
                                        valid,
                                        ""
                                    ])))
                                    .await;
                            }
                            Some("EVENT") => {
                                publishes.fetch_add(1, Ordering::SeqCst);
                                if script.never_acknowledge_publishes {
                                    continue;
                                }
                                let accepted = !script.require_auth || authenticated;
                                let reason = if accepted {
                                    ""
                                } else {
                                    "auth-required: sign in first"
                                };
                                let _ = ws
                                    .send(frame(serde_json::json!([
                                        "OK",
                                        value[1]["id"],
                                        accepted,
                                        reason
                                    ])))
                                    .await;
                            }
                            _ => {}
                        }
                    }
                });
            }
        });
        relay
    }

    pub(crate) async fn relay_with(events: &[&Event], delay: Duration) -> MockRelay {
        mock_relay(Script {
            events: events.iter().map(|event| json(event)).collect(),
            delay,
            ..Script::default()
        })
        .await
    }

    pub(crate) async fn unreachable_relay() -> String {
        let listener = TcpListener::bind("127.0.0.1:0").await.unwrap();
        format!("ws://{}", listener.local_addr().unwrap())
    }
}

#[cfg(test)]
mod tests {
    use super::test_relay::*;
    use super::*;
    use tokio::net::TcpListener;

    async fn connected_client(signer: Option<Keys>, urls: &[&str]) -> NostrClient {
        let client = NostrClient::in_memory(signer);
        for url in urls {
            client.add_relay(url).await.unwrap();
        }
        client.connect().await;
        client
            .wait_for_ready(Duration::from_secs(3), urls.len())
            .await;
        client
    }

    async fn workload(client: &NostrClient, url: &RelayUrl) -> Workload {
        let relays = client.relays().await;
        let (tx, rx) = oneshot::channel();
        relays[url].cmd_tx.send(RelayCmd::Inspect(tx)).ok().unwrap();
        rx.await.unwrap()
    }

    async fn eventually(mut condition: impl FnMut() -> bool, within: Duration) -> bool {
        let deadline = Instant::now() + within;
        while Instant::now() < deadline {
            if condition() {
                return true;
            }
            tokio::time::sleep(Duration::from_millis(20)).await;
        }
        condition()
    }

    fn note(keys: &Keys, content: &str) -> Event {
        EventBuilder::text_note(content)
            .sign_with_keys(keys)
            .unwrap()
    }

    #[test]
    fn nip42_auth_refuses_plaintext_ws_and_invalid_challenges() {
        let keys = Keys::generate();
        let ws_url = RelayUrl::parse("ws://relay.example.com").unwrap();
        let wss_url = RelayUrl::parse("wss://relay.example.com").unwrap();

        assert!(build_auth_frame(&keys, "valid-challenge", &ws_url).is_none());
        assert!(build_auth_frame(&keys, "", &wss_url).is_none());
        assert!(
            build_auth_frame(&keys, &"a".repeat(MAX_AUTH_CHALLENGE_LEN + 1), &wss_url).is_none()
        );
        assert!(build_auth_frame(&keys, "bad\nchallenge", &wss_url).is_none());

        let ok = build_auth_frame(&keys, "valid-challenge-123", &wss_url);
        assert!(ok.is_some());
    }

    #[test]
    fn relay_frames_are_read_without_copying_plain_strings() {
        let raw: Box<RawValue> = serde_json::from_str(r#""f_12""#).unwrap();
        assert!(matches!(raw_str(&raw), Some(Cow::Borrowed("f_12"))));
        let escaped: Box<RawValue> = serde_json::from_str(r#""say \"hi\"\n""#).unwrap();
        assert_eq!(raw_str(&escaped).unwrap(), "say \"hi\"\n");
        let number: Box<RawValue> = serde_json::from_str("12").unwrap();
        assert!(raw_str(&number).is_none());
    }

    #[test]
    fn only_requests_bound_to_their_relay_may_reveal_the_account() {
        let me = Keys::generate().public_key();
        let other = Keys::generate().public_key();
        let group = SingleLetterTag::lowercase(Alphabet::H);

        assert!(filter_is_relay_scoped(
            &Filter::new().kind(Kind::from(9)).custom_tag(group, "room"),
            None
        ));
        assert!(filter_is_relay_scoped(
            &Filter::new().kinds([Kind::from(39000), Kind::from(39002)]),
            None
        ));
        assert!(filter_is_relay_scoped(
            &Filter::new().kind(Kind::GiftWrap).pubkey(me),
            Some(&me)
        ));
        assert!(!filter_is_relay_scoped(
            &Filter::new().kind(Kind::GiftWrap).pubkey(me),
            None
        ));
        assert!(!filter_is_relay_scoped(
            &Filter::new().kind(Kind::GiftWrap).pubkeys([me, other]),
            Some(&me)
        ));
        assert!(!filter_is_relay_scoped(
            &Filter::new()
                .kind(Kind::from(1018))
                .event(EventId::all_zeros()),
            Some(&me)
        ));
        assert!(!filter_is_relay_scoped(
            &Filter::new().kinds([Kind::from(39000), Kind::TextNote]),
            Some(&me)
        ));

        for (url, public) in [
            ("wss://relay.example.com", true),
            ("wss://relay.example.com:7447/path", true),
            ("ws://relay.example.com", false),
            ("wss://localhost", false),
            ("wss://printer.local", false),
            ("wss://hidden.onion", false),
            ("wss://192.168.1.10", false),
            ("wss://10.0.0.5:8080", false),
            ("wss://127.0.0.1", false),
            ("wss://8.8.8.8", true),
        ] {
            assert_eq!(
                is_public_secure_relay(&RelayUrl::parse(url).unwrap()),
                public,
                "{url}"
            );
        }
    }

    #[test]
    fn only_one_authors_replaceable_events_need_every_relay() {
        let author = Keys::generate().public_key();
        let other = Keys::generate().public_key();
        for kind in [0u16, 3, 10000, 10002, 30023, 39999] {
            assert!(
                is_replaceable_lookup(&Filter::new().kind(Kind::from(kind)).author(author)),
                "{kind}"
            );
        }
        assert!(is_replaceable_lookup(
            &Filter::new()
                .kinds([Kind::ContactList, Kind::MuteList])
                .author(author)
                .limit(1)
        ));
        assert!(!is_replaceable_lookup(
            &Filter::new().kind(Kind::TextNote).author(author)
        ));
        assert!(!is_replaceable_lookup(
            &Filter::new()
                .kinds([Kind::Metadata, Kind::TextNote])
                .author(author)
        ));
        assert!(!is_replaceable_lookup(
            &Filter::new().kind(Kind::Metadata).authors([author, other])
        ));
        assert!(!is_replaceable_lookup(&Filter::new().kind(Kind::Metadata)));
        assert!(!is_replaceable_lookup(
            &Filter::new()
                .kind(Kind::Metadata)
                .author(author)
                .id(EventId::all_zeros())
        ));
    }

    #[tokio::test]
    async fn shutdown_clears_signer() {
        let client = NostrClient::in_memory(Some(Keys::generate()));
        assert!(client.signer().await.is_ok());
        client.shutdown().await;
        assert!(client.signer().await.is_err());
    }

    #[tokio::test]
    async fn forged_event_does_not_censor_honest_relay_on_exact_id_fetch() {
        let keys = Keys::generate();
        let real_note = note(&keys, "authentic note");
        let mut forged = json(&real_note);
        forged["content"] = serde_json::json!("forged tampered content");

        let bad = mock_relay(Script {
            events: vec![forged],
            ..Script::default()
        })
        .await;
        let good = relay_with(&[&real_note], Duration::from_millis(40)).await;
        let client = connected_client(None, &[&bad.url, &good.url]).await;

        let fetched = client
            .fetch(
                Filter::new().id(real_note.id).limit(1),
                Duration::from_secs(3),
                true,
            )
            .await
            .unwrap();
        assert_eq!(fetched, vec![real_note]);

        client.shutdown().await;
    }

    #[tokio::test]
    async fn a_relay_cannot_pass_off_its_own_copy_of_an_event_we_already_hold() {
        let keys = Keys::generate();
        let attacker = Keys::generate().public_key();
        let stored = EventBuilder::new(Kind::ContactList, "")
            .tag(Tag::public_key(Keys::generate().public_key()))
            .custom_created_at(Timestamp::from(1_700_000_000))
            .sign_with_keys(&keys)
            .unwrap();
        let mut newer_looking = json(&stored);
        newer_looking["created_at"] = serde_json::json!(1_900_000_000u64);
        newer_looking["tags"] = serde_json::json!([["p", attacker.to_hex()]]);
        let other_note = note(&keys, "a stored note");
        let mut rewritten_note = json(&other_note);
        rewritten_note["content"] = serde_json::json!("words the author never wrote");

        let relay = mock_relay(Script {
            events: vec![newer_looking, rewritten_note],
            ..Script::default()
        })
        .await;
        let client = connected_client(None, &[&relay.url]).await;
        client
            .database()
            .save_events(&[stored.clone(), other_note.clone()])
            .unwrap();

        for save_to_db in [true, false] {
            let lists = client
                .fetch(
                    Filter::new()
                        .author(keys.public_key())
                        .kind(Kind::ContactList)
                        .limit(1),
                    Duration::from_secs(3),
                    save_to_db,
                )
                .await
                .unwrap();
            assert_eq!(lists, vec![stored.clone()]);

            let notes = client
                .fetch(
                    Filter::new().author(keys.public_key()).kind(Kind::TextNote),
                    Duration::from_secs(3),
                    save_to_db,
                )
                .await
                .unwrap();
            assert_eq!(notes, vec![other_note.clone()]);
        }
        assert_eq!(
            client.database().event_by_id(&stored.id).unwrap(),
            Some(stored)
        );

        client.shutdown().await;
    }

    #[tokio::test]
    async fn a_forged_copy_cannot_hide_the_genuine_event_another_relay_has() {
        let keys = Keys::generate();
        let genuine = note(&keys, "authentic");
        let mut reused_signature = json(&genuine);
        reused_signature["content"] = serde_json::json!("forged");
        let mut invented_signature = json(&genuine);
        invented_signature["sig"] = serde_json::json!("00".repeat(64));

        for forged in [reused_signature, invented_signature] {
            let bad = mock_relay(Script {
                events: vec![forged],
                ..Script::default()
            })
            .await;
            let good = relay_with(&[&genuine], Duration::from_millis(60)).await;
            let client = connected_client(None, &[&bad.url, &good.url]).await;

            let fetched = client
                .fetch(
                    Filter::new()
                        .author(keys.public_key())
                        .kind(Kind::TextNote)
                        .limit(10),
                    Duration::from_secs(3),
                    true,
                )
                .await
                .unwrap();
            assert_eq!(fetched, vec![genuine.clone()]);
            assert_eq!(
                client.database().event_by_id(&genuine.id).unwrap(),
                Some(genuine.clone())
            );
            client.shutdown().await;
        }
    }

    #[tokio::test]
    async fn relays_that_fail_do_not_end_a_fetch_before_healthy_ones_answer() {
        let keys = Keys::generate();
        let event = note(&keys, "slow but valid");
        let slow = relay_with(&[&event], Duration::from_millis(400)).await;
        let dead_one = unreachable_relay().await;
        let dead_two = unreachable_relay().await;
        let client = connected_client(None, &[&slow.url, &dead_one, &dead_two]).await;
        tokio::time::sleep(Duration::from_millis(250)).await;

        let started = Instant::now();
        let fetched = client
            .fetch(
                Filter::new().author(keys.public_key()).limit(10),
                Duration::from_secs(5),
                false,
            )
            .await
            .unwrap();
        assert_eq!(fetched, vec![event]);
        assert!(started.elapsed() >= Duration::from_millis(350));
        assert!(started.elapsed() < Duration::from_secs(3));

        client.shutdown().await;
    }

    #[tokio::test]
    async fn empty_answers_from_fast_relays_leave_time_for_a_slower_one() {
        let keys = Keys::generate();
        let event = note(&keys, "only on the slower relay");
        let empty_one = relay_with(&[], Duration::ZERO).await;
        let empty_two = relay_with(&[], Duration::ZERO).await;
        let slower = relay_with(&[&event], Duration::from_millis(600)).await;
        let client = connected_client(None, &[&empty_one.url, &empty_two.url, &slower.url]).await;

        let started = Instant::now();
        let fetched = client
            .fetch(
                Filter::new().author(keys.public_key()).kind(Kind::TextNote),
                Duration::from_secs(5),
                false,
            )
            .await
            .unwrap();
        assert_eq!(fetched, vec![event]);
        assert!(started.elapsed() < Duration::from_secs(2));

        client.shutdown().await;
    }

    #[tokio::test]
    async fn a_replaceable_lookup_waits_for_the_relay_holding_the_newest_version() {
        let keys = Keys::generate();
        let old = EventBuilder::new(Kind::ContactList, "")
            .custom_created_at(Timestamp::from(1_000))
            .sign_with_keys(&keys)
            .unwrap();
        let new = EventBuilder::new(Kind::ContactList, "")
            .tag(Tag::public_key(Keys::generate().public_key()))
            .custom_created_at(Timestamp::from(2_000))
            .sign_with_keys(&keys)
            .unwrap();
        let fast = relay_with(&[&old], Duration::ZERO).await;
        let slow = relay_with(&[&new], Duration::from_millis(900)).await;
        let client = connected_client(None, &[&fast.url, &slow.url]).await;

        let started = Instant::now();
        let fetched = client
            .fetch(
                Filter::new()
                    .author(keys.public_key())
                    .kind(Kind::ContactList)
                    .limit(1),
                Duration::from_secs(6),
                true,
            )
            .await
            .unwrap();
        assert_eq!(fetched.first(), Some(&new));
        assert!(started.elapsed() < Duration::from_secs(3));
        assert_eq!(
            client
                .database()
                .query(
                    &Filter::new()
                        .author(keys.public_key())
                        .kind(Kind::ContactList)
                )
                .unwrap(),
            vec![new]
        );

        client.shutdown().await;
    }

    #[tokio::test]
    async fn a_replaceable_lookup_includes_relays_that_are_still_connecting() {
        let keys = Keys::generate();
        let newest = EventBuilder::new(Kind::MuteList, "")
            .custom_created_at(Timestamp::from(5_000))
            .sign_with_keys(&keys)
            .unwrap();
        let first = relay_with(&[], Duration::ZERO).await;
        let second = relay_with(&[], Duration::ZERO).await;
        let late = relay_with(&[&newest], Duration::ZERO).await;
        let client = connected_client(None, &[&first.url, &second.url]).await;
        client.add_relay(&late.url).await.unwrap();
        client.connect().await;

        let fetched = client
            .fetch(
                Filter::new().author(keys.public_key()).kind(Kind::MuteList),
                Duration::from_secs(5),
                false,
            )
            .await
            .unwrap();
        assert_eq!(fetched, vec![newest]);

        client.shutdown().await;
    }

    #[tokio::test]
    async fn a_relay_stuck_connecting_does_not_hold_a_replaceable_lookup() {
        let keys = Keys::generate();
        let profile = EventBuilder::new(Kind::Metadata, r#"{"name":"me"}"#)
            .sign_with_keys(&keys)
            .unwrap();
        let fast = relay_with(&[&profile], Duration::ZERO).await;
        let stuck = TcpListener::bind("127.0.0.1:0").await.unwrap();
        let stuck_url = format!("ws://{}", stuck.local_addr().unwrap());
        let held = tokio::spawn(async move {
            let mut sockets = Vec::new();
            while let Ok((socket, _)) = stuck.accept().await {
                sockets.push(socket);
            }
        });
        let client = connected_client(None, &[&fast.url, &stuck_url]).await;
        let lookup = || {
            client.fetch(
                Filter::new()
                    .author(keys.public_key())
                    .kind(Kind::Metadata)
                    .limit(1),
                Duration::from_secs(10),
                false,
            )
        };

        let started = Instant::now();
        assert_eq!(lookup().await.unwrap(), vec![profile.clone()]);
        assert!(started.elapsed() < THOROUGH_QUIET_PERIOD);

        tokio::time::sleep(RECENT_CONNECT_ATTEMPT).await;
        let relays = client.relays().await;
        let stuck_relay = &relays[&RelayUrl::parse(&stuck_url).unwrap()];
        assert_eq!(stuck_relay.status(), RelayStatus::Connecting);
        assert!(!stuck_relay.is_joining());
        let started = Instant::now();
        assert_eq!(lookup().await.unwrap(), vec![profile]);
        assert!(
            started.elapsed() < Duration::from_millis(400),
            "waited {:?} for a relay that has been connecting for seconds",
            started.elapsed()
        );

        held.abort();
        client.shutdown().await;
    }

    #[tokio::test]
    async fn a_silent_relay_does_not_hold_a_replaceable_lookup_until_its_timeout() {
        let keys = Keys::generate();
        let profile = EventBuilder::new(Kind::Metadata, r#"{"name":"me"}"#)
            .sign_with_keys(&keys)
            .unwrap();
        let fast = relay_with(&[&profile], Duration::ZERO).await;
        let silent = mock_relay(Script {
            silent: true,
            ..Script::default()
        })
        .await;
        let client = connected_client(None, &[&fast.url, &silent.url]).await;

        let started = Instant::now();
        let fetched = client
            .fetch(
                Filter::new()
                    .author(keys.public_key())
                    .kind(Kind::Metadata)
                    .limit(1),
                Duration::from_secs(10),
                false,
            )
            .await
            .unwrap();
        assert_eq!(fetched, vec![profile]);
        assert!(started.elapsed() >= THOROUGH_QUIET_PERIOD - Duration::from_millis(200));
        assert!(started.elapsed() < Duration::from_secs(4));

        client.shutdown().await;
    }

    #[tokio::test]
    async fn a_relay_added_later_joins_the_live_subscriptions() {
        let keys = Keys::generate();
        let live_event = note(&keys, "seen only by the relay that joined later");
        let first = relay_with(&[], Duration::ZERO).await;
        let late = mock_relay(Script {
            live: vec![json(&live_event)],
            ..Script::default()
        })
        .await;
        let discovery = relay_with(&[], Duration::ZERO).await;
        let client = connected_client(None, &[&first.url]).await;

        let (sub_id, mut notifications, sent_to) = client
            .subscribe_on(Filter::new().kind(Kind::TextNote), None)
            .await
            .unwrap();
        assert_eq!(sent_to, 1);
        let (_, mut targeted, _) = client
            .subscribe_on(
                Filter::new().kind(Kind::TextNote),
                Some(&[first.relay_url()]),
            )
            .await
            .unwrap();

        client.add_discovery_relay(&discovery.url).await.unwrap();
        client.add_relay(&late.url).await.unwrap();
        client.connect().await;

        let received = tokio::time::timeout(Duration::from_secs(3), async {
            loop {
                match notifications.recv().await {
                    Some(SubNotification::Event { event }) => return Some(*event),
                    Some(_) => {}
                    None => return None,
                }
            }
        })
        .await
        .expect("the late relay never received the subscription");
        assert_eq!(received, Some(live_event));
        assert_eq!(late.requests.load(Ordering::SeqCst), 1);
        assert_eq!(client.subscription_relay_count(&sub_id), 2);
        assert_eq!(discovery.requests.load(Ordering::SeqCst), 0);
        assert!(!matches!(
            targeted.try_recv(),
            Ok(SubNotification::Event { .. })
        ));

        client.unsubscribe(&sub_id).await;
        assert_eq!(client.subscription_relay_count(&sub_id), 0);
        let another = relay_with(&[], Duration::ZERO).await;
        client.add_relay(&another.url).await.unwrap();
        client.connect().await;
        client.wait_for_ready(Duration::from_secs(2), 4).await;
        tokio::time::sleep(Duration::from_millis(150)).await;
        assert_eq!(another.requests.load(Ordering::SeqCst), 0);

        client.shutdown().await;
    }

    #[tokio::test]
    async fn changing_a_relays_permissions_keeps_its_other_roles() {
        let client = NostrClient::in_memory(None);
        client
            .add_discovery_relay("wss://relay.example.com")
            .await
            .unwrap();
        client
            .add_relay_with_flags("wss://relay.example.com", FLAG_READ | FLAG_AUTH)
            .await
            .unwrap();
        client
            .add_relay_with_flags("wss://relay.example.com", FLAG_WRITE)
            .await
            .unwrap();
        let relays = client.relays().await;
        let relay = relays.values().next().unwrap();
        assert!(relay.has_flag(FLAG_DISCOVERY));
        assert!(relay.has_flag(FLAG_AUTH));
        assert!(relay.has_flag(FLAG_WRITE));
        assert!(!relay.has_flag(FLAG_READ));
        client.shutdown().await;
    }

    #[tokio::test]
    async fn a_relay_that_keeps_closing_is_retried_with_growing_delays() {
        let flapping = mock_relay(Script {
            close_on_connect: true,
            ..Script::default()
        })
        .await;
        let client = NostrClient::in_memory(None);
        client.add_relay(&flapping.url).await.unwrap();
        client.connect().await;
        tokio::time::sleep(Duration::from_millis(3_200)).await;
        let attempts = flapping.connections.load(Ordering::SeqCst);
        assert!(
            (2..=5).contains(&attempts),
            "{attempts} connections in 3.2 s"
        );
        client.shutdown().await;
    }

    #[tokio::test]
    async fn a_trusted_relay_is_authenticated_as_soon_as_it_asks() {
        let relay = mock_relay(Script {
            challenge: Some("challenge-on-connect"),
            ..Script::default()
        })
        .await;
        let client = NostrClient::in_memory(Some(Keys::generate()));
        client.automatic_authentication(true);
        client.allow_plaintext_authentication();
        client
            .add_relay_with_flags(&relay.url, FLAG_READ | FLAG_WRITE | FLAG_AUTH)
            .await
            .unwrap();
        client.connect().await;
        assert!(
            eventually(
                || relay.authentications.load(Ordering::SeqCst) == 1,
                Duration::from_secs(3)
            )
            .await
        );

        let untrusted = mock_relay(Script {
            challenge: Some("challenge-on-connect"),
            ..Script::default()
        })
        .await;
        client.add_relay(&untrusted.url).await.unwrap();
        client.connect().await;
        client.wait_for_ready(Duration::from_secs(3), 2).await;
        tokio::time::sleep(Duration::from_millis(200)).await;
        assert_eq!(untrusted.authentications.load(Ordering::SeqCst), 0);

        client.shutdown().await;
    }

    #[tokio::test]
    async fn an_untrusted_relay_cannot_demand_the_account_for_an_ordinary_read() {
        let keys = Keys::generate();
        let response = EventBuilder::new(Kind::from(1018), "vote")
            .sign_with_keys(&Keys::generate())
            .unwrap();
        let hint_relay = mock_relay(Script {
            events: vec![json(&response)],
            challenge: Some("who-are-you"),
            require_auth: true,
            ..Script::default()
        })
        .await;
        let client = NostrClient::in_memory(Some(keys.clone()));
        client.automatic_authentication(true);
        client.allow_plaintext_authentication();
        client.add_relay(&hint_relay.url).await.unwrap();
        client.connect().await;
        client.wait_for_ready(Duration::from_secs(3), 1).await;

        let started = Instant::now();
        let fetched = client
            .thorough_fetch(
                Filter::new().kind(Kind::from(1018)),
                Duration::from_secs(6),
                false,
            )
            .await
            .unwrap();
        assert!(fetched.is_empty());
        assert!(started.elapsed() < Duration::from_secs(2));
        assert_eq!(hint_relay.authentications.load(Ordering::SeqCst), 0);

        let strict = NostrClient::in_memory(Some(keys));
        strict.automatic_authentication(true);
        strict.add_relay(&hint_relay.url).await.unwrap();
        strict.connect().await;
        strict.wait_for_ready(Duration::from_secs(3), 1).await;
        let group = SingleLetterTag::lowercase(Alphabet::H);
        let fetched = strict
            .thorough_fetch(
                Filter::new()
                    .kind(Kind::from(1018))
                    .custom_tag(group, "room"),
                Duration::from_secs(6),
                false,
            )
            .await
            .unwrap();
        assert!(fetched.is_empty());
        assert_eq!(hint_relay.authentications.load(Ordering::SeqCst), 0);

        client.shutdown().await;
        strict.shutdown().await;
    }

    #[tokio::test]
    async fn group_requests_and_publishes_authenticate_when_the_relay_requires_it() {
        let keys = Keys::generate();
        let group = SingleLetterTag::lowercase(Alphabet::H);
        let message = EventBuilder::new(Kind::from(9), "hello group")
            .tag(Tag::custom(TagKind::SingleLetter(group), ["room"]))
            .sign_with_keys(&Keys::generate())
            .unwrap();
        let group_relay = mock_relay(Script {
            events: vec![json(&message)],
            challenge: Some("members-only"),
            require_auth: true,
            ..Script::default()
        })
        .await;
        let client = NostrClient::in_memory(Some(keys.clone()));
        client.automatic_authentication(true);
        client.allow_plaintext_authentication();
        client.add_relay(&group_relay.url).await.unwrap();
        client.connect().await;
        client.wait_for_ready(Duration::from_secs(3), 1).await;

        let fetched = client
            .thorough_fetch(
                Filter::new().kind(Kind::from(9)).custom_tag(group, "room"),
                Duration::from_secs(5),
                false,
            )
            .await
            .unwrap();
        assert_eq!(fetched, vec![message]);
        assert_eq!(group_relay.authentications.load(Ordering::SeqCst), 1);

        let publishing_relay = mock_relay(Script {
            challenge: Some("writers-only"),
            require_auth: true,
            ..Script::default()
        })
        .await;
        client.add_relay(&publishing_relay.url).await.unwrap();
        client.connect().await;
        client.wait_for_ready(Duration::from_secs(3), 2).await;
        let mine = note(&keys, "published after authenticating");
        let output = client
            .publish_event(&mine, Some(&[publishing_relay.relay_url()]))
            .await
            .unwrap();
        assert!(output.success.contains(&publishing_relay.relay_url()));
        assert_eq!(publishing_relay.authentications.load(Ordering::SeqCst), 1);
        assert_eq!(publishing_relay.publishes.load(Ordering::SeqCst), 2);

        let reader = NostrClient::in_memory(None);
        reader.automatic_authentication(true);
        reader.allow_plaintext_authentication();
        reader.add_relay(&group_relay.url).await.unwrap();
        reader.connect().await;
        reader.wait_for_ready(Duration::from_secs(3), 1).await;
        let unsigned = reader
            .thorough_fetch(
                Filter::new().kind(Kind::from(9)).custom_tag(group, "room"),
                Duration::from_secs(5),
                false,
            )
            .await
            .unwrap();
        assert!(unsigned.is_empty());

        client.shutdown().await;
        reader.shutdown().await;
    }

    #[tokio::test]
    async fn a_subscription_authenticates_again_after_the_relay_reconnects() {
        let group = SingleLetterTag::lowercase(Alphabet::H);
        let relay = mock_relay(Script {
            challenge: Some("members-only"),
            require_auth: true,
            drop_first_connection_after_answering: true,
            ..Script::default()
        })
        .await;
        let client = NostrClient::in_memory(Some(Keys::generate()));
        client.automatic_authentication(true);
        client.allow_plaintext_authentication();
        client.add_relay(&relay.url).await.unwrap();
        client.connect().await;

        let (_sub_id, mut notifications, _) = client
            .subscribe_on(
                Filter::new().kind(Kind::from(9)).custom_tag(group, "room"),
                None,
            )
            .await
            .unwrap();

        assert!(
            eventually(
                || relay.answered.load(Ordering::SeqCst) == 2,
                Duration::from_secs(5)
            )
            .await,
            "the subscription was not reopened after the reconnect: {} answered, {} authentications",
            relay.answered.load(Ordering::SeqCst),
            relay.authentications.load(Ordering::SeqCst)
        );
        assert_eq!(relay.connections.load(Ordering::SeqCst), 2);
        assert_eq!(relay.authentications.load(Ordering::SeqCst), 2);
        let mut closed = 0;
        while let Ok(notification) = notifications.try_recv() {
            if matches!(notification, SubNotification::Closed { .. }) {
                closed += 1;
            }
        }
        assert_eq!(closed, 0);

        client.shutdown().await;
    }

    #[tokio::test]
    async fn a_refused_subscription_tells_its_consumer_which_relay_closed_it() {
        let relay = mock_relay(Script {
            challenge: Some("members-only"),
            require_auth: true,
            ..Script::default()
        })
        .await;
        let client = connected_client(None, &[&relay.url]).await;
        let (_sub_id, mut notifications, _) = client
            .subscribe_on(Filter::new().kind(Kind::TextNote), None)
            .await
            .unwrap();
        let notification = tokio::time::timeout(Duration::from_secs(3), notifications.recv())
            .await
            .unwrap();
        match notification {
            Some(SubNotification::Closed {
                relay: url,
                message,
            }) => {
                assert_eq!(url, relay.relay_url());
                assert!(message.starts_with("auth-required:"));
            }
            other => panic!("expected a closed notification, got {other:?}"),
        }
        client.shutdown().await;
    }

    #[tokio::test]
    async fn a_consumer_that_falls_behind_cannot_grow_a_subscription_without_bound() {
        let keys = Keys::generate();
        let flood: Vec<serde_json::Value> = (0..SUBSCRIPTION_BUFFER * 3)
            .map(|i| json(&note(&keys, &format!("flood {i}"))))
            .collect();
        let after = note(&keys, "still served after the flood");
        let relay = mock_relay(Script {
            events: vec![json(&after)],
            live: flood,
            ..Script::default()
        })
        .await;
        let client = connected_client(None, &[&relay.url]).await;

        let (_sub_id, mut notifications, _) = client
            .subscribe_on(Filter::new().kind(Kind::TextNote), None)
            .await
            .unwrap();
        tokio::time::sleep(Duration::from_millis(600)).await;

        let fetched = client
            .fetch(Filter::new().id(after.id), Duration::from_secs(3), false)
            .await
            .unwrap();
        assert_eq!(fetched, vec![after]);

        let mut buffered = 0;
        while notifications.try_recv().is_ok() {
            buffered += 1;
        }
        assert_eq!(buffered, SUBSCRIPTION_BUFFER);

        client.shutdown().await;
    }

    #[tokio::test]
    async fn requests_nobody_waits_for_are_dropped_from_the_connection() {
        let relay = mock_relay(Script {
            silent: true,
            never_acknowledge_publishes: true,
            ..Script::default()
        })
        .await;
        let client = NostrClient::in_memory(None);
        client.set_keepalive(Duration::from_millis(400));
        client.add_relay(&relay.url).await.unwrap();
        client.connect().await;
        client.wait_for_ready(Duration::from_secs(3), 1).await;
        let url = relay.relay_url();

        let event = note(&Keys::generate(), "never acknowledged");
        let relays = client.relays().await;
        let sent = relays[&url]
            .send_event(event, Duration::from_millis(40))
            .await;
        assert_eq!(sent, Err("Event dispatch timed out".to_string()));

        let abandoned_fetch = tokio::time::timeout(
            Duration::from_millis(40),
            client.thorough_fetch(
                Filter::new().kind(Kind::TextNote),
                Duration::from_secs(30),
                false,
            ),
        )
        .await;
        assert!(abandoned_fetch.is_err());

        let (_sub_id, notifications, _) = client
            .subscribe_on(Filter::new().kind(Kind::TextNote), None)
            .await
            .unwrap();
        assert_eq!(
            workload(&client, &url).await,
            Workload {
                fetches: 1,
                publishes: 1,
                subscriptions: 1
            }
        );
        drop(notifications);

        tokio::time::sleep(Duration::from_millis(700)).await;
        assert_eq!(
            workload(&client, &url).await,
            Workload {
                fetches: 0,
                publishes: 0,
                subscriptions: 0
            }
        );
        assert_eq!(relays[&url].status(), RelayStatus::Connected);

        client.shutdown().await;
    }
}
