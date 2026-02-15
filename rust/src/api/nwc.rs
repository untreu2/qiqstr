use std::time::Duration;

use anyhow::{anyhow, Result};
use flutter_rust_bridge::frb;
use nostr::nips::nip47::{
    ListTransactionsRequest, NostrWalletConnectURI, PayInvoiceRequest, Request, Response,
};
use nostr::prelude::*;
use nostr_sdk::prelude::*;

#[frb(sync)]
pub fn validate_nwc_uri(uri: String) -> bool {
    NostrWalletConnectURI::parse(&uri).is_ok()
}

#[frb(sync)]
pub fn parse_nwc_uri(uri: String) -> Result<String> {
    let parsed = NostrWalletConnectURI::parse(&uri)
        .map_err(|_| anyhow!("Invalid NWC URI"))?;

    let relays: Vec<String> = parsed
        .relays
        .iter()
        .map(|r: &RelayUrl| r.to_string())
        .collect();

    let result = serde_json::json!({
        "publicKey": parsed.public_key.to_hex(),
        "secret": parsed.secret.to_secret_hex(),
        "relays": relays,
        "lud16": parsed.lud16,
    });

    Ok(result.to_string())
}

pub async fn nwc_pay_invoice(nwc_uri: String, invoice: String) -> Result<String> {
    let uri = NostrWalletConnectURI::parse(&nwc_uri)
        .map_err(|_| anyhow!("Invalid NWC URI"))?;

    let req = Request::pay_invoice(PayInvoiceRequest::new(invoice));
    let event: Event = req.to_event(&uri)
        .map_err(|e| anyhow!("Failed to create NWC request event: {}", e))?;

    let client: Client = Client::default();
    for relay_url in uri.relays.iter() {
        let _ = client.add_relay(relay_url.as_str()).await;
    }
    client.connect().await;

    let filter = Filter::new()
        .author(uri.public_key)
        .kind(Kind::WalletConnectResponse)
        .event(event.id);

    let sub_output = client
        .subscribe(filter, None)
        .await
        .map_err(|e| anyhow!("Failed to subscribe for NWC response: {}", e))?;
    let sub_id = sub_output.val;

    let _ = client
        .send_event(&event)
        .await
        .map_err(|e| anyhow!("Failed to send NWC request: {}", e))?;

    let timeout = Duration::from_secs(60);
    let mut notifications = client.notifications();

    let result = tokio::time::timeout(timeout, async {
        loop {
            match notifications.recv().await {
                Ok(RelayPoolNotification::Event {
                    subscription_id,
                    event: received,
                    ..
                }) => {
                    if subscription_id == sub_id {
                        let response = Response::from_event(&uri, &received)
                            .map_err(|e| anyhow!("Failed to parse NWC response: {}", e))?;

                        if let Some(ref error) = response.error {
                            return Err(anyhow!("{}", error.message));
                        }

                        let pay_result = response
                            .to_pay_invoice()
                            .map_err(|e| anyhow!("Failed to parse pay invoice response: {}", e))?;

                        let result = serde_json::json!({
                            "preimage": pay_result.preimage,
                            "fees_paid": pay_result.fees_paid,
                        });

                        return Ok(result.to_string());
                    }
                }
                Ok(RelayPoolNotification::Shutdown) => {
                    return Err(anyhow!("NWC relay connection closed"));
                }
                Err(tokio::sync::broadcast::error::RecvError::Closed) => {
                    return Err(anyhow!("NWC notification channel closed"));
                }
                Err(tokio::sync::broadcast::error::RecvError::Lagged(_)) => continue,
                _ => continue,
            }
        }
    })
    .await
    .map_err(|_| anyhow!("NWC request timed out (60s)"))?;

    client.disconnect().await;

    result
}

pub async fn nwc_get_balance(nwc_uri: String) -> Result<String> {
    let uri = NostrWalletConnectURI::parse(&nwc_uri)
        .map_err(|_| anyhow!("Invalid NWC URI"))?;

    let req = Request::get_balance();
    let event: Event = req.to_event(&uri)
        .map_err(|e| anyhow!("Failed to create NWC request event: {}", e))?;

    let client: Client = Client::default();
    for relay_url in uri.relays.iter() {
        let _ = client.add_relay(relay_url.as_str()).await;
    }
    client.connect().await;

    let filter = Filter::new()
        .author(uri.public_key)
        .kind(Kind::WalletConnectResponse)
        .event(event.id);

    let sub_output = client
        .subscribe(filter, None)
        .await
        .map_err(|e| anyhow!("Failed to subscribe for NWC response: {}", e))?;
    let sub_id = sub_output.val;

    let _ = client
        .send_event(&event)
        .await
        .map_err(|e| anyhow!("Failed to send NWC request: {}", e))?;

    let timeout = Duration::from_secs(30);
    let mut notifications = client.notifications();

    let result = tokio::time::timeout(timeout, async {
        loop {
            match notifications.recv().await {
                Ok(RelayPoolNotification::Event {
                    subscription_id,
                    event: received,
                    ..
                }) => {
                    if subscription_id == sub_id {
                        let response = Response::from_event(&uri, &received)
                            .map_err(|e| anyhow!("Failed to parse NWC response: {}", e))?;

                        if let Some(ref error) = response.error {
                            return Err(anyhow!("{}", error.message));
                        }

                        let balance_result = response
                            .to_get_balance()
                            .map_err(|e| anyhow!("Failed to parse balance response: {}", e))?;

                        let result = serde_json::json!({
                            "balance": balance_result.balance,
                        });

                        return Ok(result.to_string());
                    }
                }
                Ok(RelayPoolNotification::Shutdown) => {
                    return Err(anyhow!("NWC relay connection closed"));
                }
                Err(tokio::sync::broadcast::error::RecvError::Closed) => {
                    return Err(anyhow!("NWC notification channel closed"));
                }
                Err(tokio::sync::broadcast::error::RecvError::Lagged(_)) => continue,
                _ => continue,
            }
        }
    })
    .await
    .map_err(|_| anyhow!("NWC balance request timed out (30s)"))?;

    client.disconnect().await;

    result
}

pub async fn nwc_make_invoice(nwc_uri: String, amount_msats: u64, description: Option<String>) -> Result<String> {
    let uri = NostrWalletConnectURI::parse(&nwc_uri)
        .map_err(|_| anyhow!("Invalid NWC URI"))?;

    let make_req = nostr::nips::nip47::MakeInvoiceRequest {
        amount: amount_msats,
        description,
        description_hash: None,
        expiry: None,
    };

    let req = Request::make_invoice(make_req);
    let event: Event = req.to_event(&uri)
        .map_err(|e| anyhow!("Failed to create NWC request event: {}", e))?;

    let client: Client = Client::default();
    for relay_url in uri.relays.iter() {
        let _ = client.add_relay(relay_url.as_str()).await;
    }
    client.connect().await;

    let filter = Filter::new()
        .author(uri.public_key)
        .kind(Kind::WalletConnectResponse)
        .event(event.id);

    let sub_output = client
        .subscribe(filter, None)
        .await
        .map_err(|e| anyhow!("Failed to subscribe for NWC response: {}", e))?;
    let sub_id = sub_output.val;

    let _ = client
        .send_event(&event)
        .await
        .map_err(|e| anyhow!("Failed to send NWC request: {}", e))?;

    let timeout = Duration::from_secs(30);
    let mut notifications = client.notifications();

    let result = tokio::time::timeout(timeout, async {
        loop {
            match notifications.recv().await {
                Ok(RelayPoolNotification::Event {
                    subscription_id,
                    event: received,
                    ..
                }) => {
                    if subscription_id == sub_id {
                        let response = Response::from_event(&uri, &received)
                            .map_err(|e| anyhow!("Failed to parse NWC response: {}", e))?;

                        if let Some(ref error) = response.error {
                            return Err(anyhow!("{}", error.message));
                        }

                        let invoice_result = response
                            .to_make_invoice()
                            .map_err(|e| anyhow!("Failed to parse make_invoice response: {}", e))?;

                        let result = serde_json::json!({
                            "invoice": invoice_result.invoice,
                            "payment_hash": invoice_result.payment_hash,
                        });

                        return Ok(result.to_string());
                    }
                }
                Ok(RelayPoolNotification::Shutdown) => {
                    return Err(anyhow!("NWC relay connection closed"));
                }
                Err(tokio::sync::broadcast::error::RecvError::Closed) => {
                    return Err(anyhow!("NWC notification channel closed"));
                }
                Err(tokio::sync::broadcast::error::RecvError::Lagged(_)) => continue,
                _ => continue,
            }
        }
    })
    .await
    .map_err(|_| anyhow!("NWC make_invoice request timed out (30s)"))?;

    client.disconnect().await;

    result
}

pub async fn nwc_list_transactions(nwc_uri: String, limit: Option<u64>, offset: Option<u64>) -> Result<String> {
    let uri = NostrWalletConnectURI::parse(&nwc_uri)
        .map_err(|_| anyhow!("Invalid NWC URI"))?;

    let params = ListTransactionsRequest {
        from: None,
        until: None,
        limit,
        offset,
        unpaid: Some(false),
        transaction_type: None,
    };

    let req = Request::list_transactions(params);
    let event: Event = req.to_event(&uri)
        .map_err(|e| anyhow!("Failed to create NWC request event: {}", e))?;

    let client: Client = Client::default();
    for relay_url in uri.relays.iter() {
        let _ = client.add_relay(relay_url.as_str()).await;
    }
    client.connect().await;

    let filter = Filter::new()
        .author(uri.public_key)
        .kind(Kind::WalletConnectResponse)
        .event(event.id);

    let sub_output = client
        .subscribe(filter, None)
        .await
        .map_err(|e| anyhow!("Failed to subscribe for NWC response: {}", e))?;
    let sub_id = sub_output.val;

    let _ = client
        .send_event(&event)
        .await
        .map_err(|e| anyhow!("Failed to send NWC request: {}", e))?;

    let timeout = Duration::from_secs(30);
    let mut notifications = client.notifications();

    let result = tokio::time::timeout(timeout, async {
        loop {
            match notifications.recv().await {
                Ok(RelayPoolNotification::Event {
                    subscription_id,
                    event: received,
                    ..
                }) => {
                    if subscription_id == sub_id {
                        let response = Response::from_event(&uri, &received)
                            .map_err(|e| anyhow!("Failed to parse NWC response: {}", e))?;

                        if let Some(ref error) = response.error {
                            return Err(anyhow!("{}", error.message));
                        }

                        let txs = response
                            .to_list_transactions()
                            .map_err(|e| anyhow!("Failed to parse list_transactions response: {}", e))?;

                        let transactions: Vec<serde_json::Value> = txs.iter().map(|tx| {
                            let tx_type = tx.transaction_type.as_ref().map(|t| format!("{:?}", t).to_lowercase());
                            let is_incoming = tx_type.as_deref() == Some("incoming");

                            serde_json::json!({
                                "type": tx_type,
                                "isIncoming": is_incoming,
                                "amount": tx.amount / 1000,
                                "fees_paid": tx.fees_paid / 1000,
                                "description": tx.description,
                                "invoice": tx.invoice,
                                "created_at": tx.created_at.as_secs(),
                            })
                        }).collect();

                        let result = serde_json::json!({
                            "transactions": transactions,
                        });

                        return Ok(result.to_string());
                    }
                }
                Ok(RelayPoolNotification::Shutdown) => {
                    return Err(anyhow!("NWC relay connection closed"));
                }
                Err(tokio::sync::broadcast::error::RecvError::Closed) => {
                    return Err(anyhow!("NWC notification channel closed"));
                }
                Err(tokio::sync::broadcast::error::RecvError::Lagged(_)) => continue,
                _ => continue,
            }
        }
    })
    .await
    .map_err(|_| anyhow!("NWC list_transactions request timed out (30s)"))?;

    client.disconnect().await;

    result
}
