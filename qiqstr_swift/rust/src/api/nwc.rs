use std::time::Duration;

use anyhow::{anyhow, Result};
use nostr::nips::nip47::{
    ListTransactionsRequest, LookupInvoiceRequest, NostrWalletConnectURI, PayInvoiceRequest,
    Request, Response, TransactionState,
};
use nostr::prelude::*;
use nostr_sdk::prelude::*;

pub fn validate_nwc_uri(uri: String) -> bool {
    NostrWalletConnectURI::parse(&uri).is_ok_and(|parsed| parsed.public_key.xonly().is_ok())
}

pub fn parse_nwc_uri(uri: String) -> Result<String> {
    let parsed = NostrWalletConnectURI::parse(&uri).map_err(|_| anyhow!("Invalid NWC URI"))?;

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

async fn request_wallet(nwc_uri: &str, request: Request, timeout: Duration) -> Result<Response> {
    let uri = NostrWalletConnectURI::parse(nwc_uri).map_err(|_| anyhow!("Invalid NWC URI"))?;
    let event = request
        .to_event(&uri)
        .map_err(|e| anyhow!("Failed to create NWC request: {}", e))?;
    let filter = Filter::new()
        .author(uri.public_key)
        .kind(Kind::WalletConnectResponse)
        .event(event.id);
    let client = Client::default();
    let result = tokio::time::timeout(timeout, async {
        for relay in &uri.relays {
            client.add_relay(relay.as_str()).await?;
        }
        client.connect().await;
        client.wait_for_connection(Duration::from_secs(10)).await;
        let mut notifications = client.notifications();
        let subscription = client.subscribe(filter.clone(), None).await?;
        let published = client.send_event(&event).await?;
        if published.success.is_empty() {
            return Err(anyhow!("No relay accepted the wallet request"));
        }
        loop {
            match notifications.recv().await {
                Ok(RelayPoolNotification::Event {
                    subscription_id,
                    event: received,
                    ..
                }) if subscription_id == subscription.val
                    && filter.match_event(&received, MatchEventOptions::default()) =>
                {
                    received.verify()?;
                    let response = Response::from_event(&uri, &received)
                        .map_err(|e| anyhow!("Failed to parse NWC response: {}", e))?;
                    if let Some(error) = &response.error {
                        return Err(anyhow!("{}", error.message));
                    }
                    return Ok(response);
                }
                Ok(RelayPoolNotification::Shutdown) => {
                    return Err(anyhow!("NWC relay connection closed"))
                }
                Err(tokio::sync::broadcast::error::RecvError::Closed) => {
                    return Err(anyhow!("NWC notification channel closed"))
                }
                _ => {}
            }
        }
    })
    .await
    .map_err(|_| anyhow!("NWC request timed out ({}s)", timeout.as_secs()));
    client.shutdown().await;
    result?
}

pub async fn nwc_pay_invoice(nwc_uri: String, invoice: String) -> Result<String> {
    let response = request_wallet(
        &nwc_uri,
        Request::pay_invoice(PayInvoiceRequest::new(invoice)),
        Duration::from_secs(60),
    )
    .await?;
    let result = response.to_pay_invoice()?;
    Ok(
        serde_json::json!({ "preimage": result.preimage, "fees_paid": result.fees_paid })
            .to_string(),
    )
}

pub async fn nwc_lookup_invoice(nwc_uri: String, invoice: String) -> Result<String> {
    let request = LookupInvoiceRequest {
        payment_hash: None,
        invoice: Some(invoice),
    };
    let response = request_wallet(
        &nwc_uri,
        Request::lookup_invoice(request),
        Duration::from_secs(20),
    )
    .await?;
    let result = response.to_lookup_invoice()?;
    let state = match result.state {
        Some(TransactionState::Settled) => "settled",
        Some(TransactionState::Failed) => "failed",
        Some(TransactionState::Expired) => "expired",
        Some(TransactionState::Pending) => "pending",
        None if result.settled_at.is_some() || result.preimage.as_deref().is_some_and(|p| !p.is_empty()) => "settled",
        None => "pending",
    };
    Ok(serde_json::json!({
        "state": state,
        "preimage": result.preimage,
        "payment_hash": result.payment_hash,
        "fees_paid": result.fees_paid,
    })
    .to_string())
}

pub async fn nwc_get_balance(nwc_uri: String) -> Result<String> {
    let response =
        request_wallet(&nwc_uri, Request::get_balance(), Duration::from_secs(30)).await?;
    Ok(serde_json::json!({ "balance": response.to_get_balance()?.balance }).to_string())
}

pub async fn nwc_make_invoice(
    nwc_uri: String,
    amount_msats: u64,
    description: Option<String>,
) -> Result<String> {
    if amount_msats == 0 {
        return Err(anyhow!("Invoice amount must be greater than zero"));
    }
    let request = nostr::nips::nip47::MakeInvoiceRequest {
        amount: amount_msats,
        description,
        description_hash: None,
        expiry: None,
    };
    let response = request_wallet(
        &nwc_uri,
        Request::make_invoice(request),
        Duration::from_secs(30),
    )
    .await?;
    let result = response.to_make_invoice()?;
    Ok(
        serde_json::json!({ "invoice": result.invoice, "payment_hash": result.payment_hash })
            .to_string(),
    )
}

pub async fn nwc_list_transactions(
    nwc_uri: String,
    limit: Option<u64>,
    offset: Option<u64>,
) -> Result<String> {
    let request = ListTransactionsRequest {
        from: None,
        until: None,
        limit,
        offset,
        unpaid: Some(false),
        transaction_type: None,
    };
    let response = request_wallet(
        &nwc_uri,
        Request::list_transactions(request),
        Duration::from_secs(30),
    )
    .await?;
    let transactions: Vec<serde_json::Value> = response
        .to_list_transactions()?
        .iter()
        .map(|tx| {
            let transaction_type = tx
                .transaction_type
                .as_ref()
                .map(|value| format!("{:?}", value).to_lowercase());
            serde_json::json!({
                "isIncoming": transaction_type.as_deref() == Some("incoming"),
                "type": transaction_type,
                "amount": tx.amount / 1000,
                "fees_paid": tx.fees_paid / 1000,
                "description": tx.description,
                "invoice": tx.invoice,
                "payment_hash": tx.payment_hash,
                "created_at": tx.created_at.as_secs(),
            })
        })
        .collect();
    Ok(serde_json::json!({ "transactions": transactions }).to_string())
}

#[cfg(test)]
mod tests {
    use super::*;
    use futures::{SinkExt, StreamExt};
    use tokio::net::TcpListener;
    use tokio_tungstenite::{accept_async, tungstenite::Message};

    #[test]
    fn rejects_wallet_keys_that_are_not_curve_points() {
        let secret = Keys::generate().secret_key().to_secret_hex();
        let valid = format!("nostr+walletconnect://{}?relay=wss%3A%2F%2Frelay.example.com&secret={secret}", Keys::generate().public_key().to_hex());
        let invalid = format!("nostr+walletconnect://{}?relay=wss%3A%2F%2Frelay.example.com&secret={secret}", "ff".repeat(32));
        assert!(validate_nwc_uri(valid));
        assert!(!validate_nwc_uri(invalid));
    }

    #[tokio::test]
    async fn timeout_closes_the_wallet_connection_even_without_publish_acknowledgement() {
        let listener = TcpListener::bind("127.0.0.1:0").await.unwrap();
        let address = listener.local_addr().unwrap();
        let wallet = Keys::generate();
        let app = Keys::generate();
        let uri = format!(
            "nostr+walletconnect://{}?relay=ws://{}&secret={}",
            wallet.public_key().to_hex(),
            address,
            app.secret_key().to_secret_hex()
        );
        let server = tokio::spawn(async move {
            let (stream, _) = listener.accept().await.unwrap();
            let mut socket = accept_async(stream).await.unwrap();
            while let Some(Ok(message)) = socket.next().await {
                if message.is_close() {
                    break;
                }
            }
        });
        let result = request_wallet(&uri, Request::get_balance(), Duration::from_millis(300)).await;
        assert!(result.unwrap_err().to_string().contains("timed out"));
        tokio::time::timeout(Duration::from_secs(2), server)
            .await
            .expect("wallet connection leaked after timeout")
            .unwrap();
    }

    #[tokio::test]
    async fn receives_wallet_response_before_publish_acknowledgement() {
        let listener = TcpListener::bind("127.0.0.1:0").await.unwrap();
        let address = listener.local_addr().unwrap();
        let wallet = Keys::generate();
        let app = Keys::generate();
        let uri = format!(
            "nostr+walletconnect://{}?relay=ws://{}&secret={}",
            wallet.public_key().to_hex(),
            address,
            app.secret_key().to_secret_hex()
        );
        let server = tokio::spawn(async move {
            let (stream, _) = listener.accept().await.unwrap();
            let mut socket = accept_async(stream).await.unwrap();
            let mut subscription = String::new();
            while let Some(Ok(message)) = socket.next().await {
                let Message::Text(text) = message else {
                    continue;
                };
                let message: serde_json::Value = serde_json::from_str(&text).unwrap();
                match message[0].as_str() {
                    Some("REQ") => subscription = message[1].as_str().unwrap().to_string(),
                    Some("EVENT") => {
                        assert!(
                            !subscription.is_empty(),
                            "request published before response subscription"
                        );
                        let request = Event::from_json(message[1].to_string()).unwrap();
                        request.verify().unwrap();
                        let payload = serde_json::json!({
                            "result_type": "get_balance",
                            "result": {"balance": 123000}
                        });
                        let encrypted = nostr::nips::nip04::encrypt(
                            wallet.secret_key(),
                            &request.pubkey,
                            payload.to_string(),
                        )
                        .unwrap();
                        let response = EventBuilder::new(Kind::WalletConnectResponse, encrypted)
                            .tags([Tag::event(request.id), Tag::public_key(request.pubkey)])
                            .sign_with_keys(&wallet)
                            .unwrap();
                        let response: serde_json::Value =
                            serde_json::from_str(&response.as_json()).unwrap();
                        socket
                            .send(Message::Text(
                                serde_json::json!(["EVENT", subscription, response]).to_string(),
                            ))
                            .await
                            .unwrap();
                        tokio::time::sleep(Duration::from_millis(100)).await;
                        socket
                            .send(Message::Text(
                                serde_json::json!(["OK", request.id.to_hex(), true, ""])
                                    .to_string(),
                            ))
                            .await
                            .unwrap();
                    }
                    _ => {}
                }
            }
        });
        let result = tokio::time::timeout(Duration::from_secs(5), nwc_get_balance(uri)).await;
        server.abort();
        let balance: serde_json::Value =
            serde_json::from_str(&result.expect("wallet response was lost").unwrap()).unwrap();
        assert_eq!(balance["balance"], 123000);
    }
}
