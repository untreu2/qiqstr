use std::collections::HashMap;
use std::path::PathBuf;
use std::str::FromStr;
use std::sync::Arc;

use anyhow::{anyhow, Result};
use cdk::nuts::{CurrencyUnit, PaymentMethod, Token};
use cdk::wallet::{ReceiveOptions, Wallet};
use cdk_sqlite::wallet::WalletSqliteDatabase;
use flutter_rust_bridge::frb;
use rand::RngCore;
use tokio::sync::{Mutex, OnceCell};

use crate::api::relay::db_path_state;

static WALLET_STORE: OnceCell<Mutex<WalletStore>> = OnceCell::const_new();

struct WalletStore {
    db_path: PathBuf,
    wallets: HashMap<String, Arc<Wallet>>,
    seed: [u8; 64],
}

impl WalletStore {
    fn new(db_path: PathBuf) -> Self {
        let seed = Self::load_or_create_seed(&db_path);
        Self { db_path, wallets: HashMap::new(), seed }
    }

    fn seed_path(db_path: &PathBuf) -> PathBuf {
        db_path
            .parent()
            .unwrap_or_else(|| std::path::Path::new("."))
            .join("cashu_seed.bin")
    }

    fn load_or_create_seed(db_path: &PathBuf) -> [u8; 64] {
        let path = Self::seed_path(db_path);
        if let Ok(bytes) = std::fs::read(&path) {
            if bytes.len() == 64 {
                let mut seed = [0u8; 64];
                seed.copy_from_slice(&bytes);
                return seed;
            }
        }
        let mut seed = [0u8; 64];
        rand::thread_rng().fill_bytes(&mut seed);
        let _ = std::fs::write(&path, &seed);
        seed
    }

    async fn wallet_for(&mut self, mint_url: &str) -> Result<Arc<Wallet>> {
        if let Some(w) = self.wallets.get(mint_url) {
            return Ok(w.clone());
        }

        let db = WalletSqliteDatabase::new(self.db_path.clone())
            .await
            .map_err(|e| anyhow!("Failed to open cashu db: {}", e))?;

        let wallet = Wallet::new(
            mint_url,
            CurrencyUnit::Sat,
            Arc::new(db),
            self.seed,
            None,
        )
        .map_err(|e| anyhow!("Failed to create wallet: {}", e))?;

        wallet
            .recover_incomplete_sagas()
            .await
            .map_err(|e| anyhow!("Saga recovery failed: {}", e))?;

        let wallet = Arc::new(wallet);
        self.wallets.insert(mint_url.to_string(), wallet.clone());
        Ok(wallet)
    }
}

async fn store() -> Result<&'static Mutex<WalletStore>> {
    WALLET_STORE
        .get_or_try_init(|| async {
            let db_path = {
                let lock = db_path_state().read().await;
                lock.as_ref()
                    .map(|p| {
                        PathBuf::from(p)
                            .parent()
                            .unwrap_or_else(|| std::path::Path::new("."))
                            .join("cashu_wallet.sqlite")
                    })
                    .unwrap_or_else(|| {
                        let home = std::env::var("HOME").unwrap_or_else(|_| ".".into());
                        PathBuf::from(home).join(".cashu_wallet.sqlite")
                    })
            };
            Ok::<_, anyhow::Error>(Mutex::new(WalletStore::new(db_path)))
        })
        .await
}

/// Receives a Cashu token and melts it to the given Lightning target.
/// Fee-aware: starts with fee offset of 1 sat, increments by 1, max 5 attempts.
///
/// Returns JSON `{ "amount_sats": u64 }`
pub async fn cashu_receive_and_melt(
    token: String,
    lightning_target: String,
) -> Result<String> {
    let token_str = token.trim();
    let parsed =
        Token::from_str(token_str).map_err(|e| anyhow!("Invalid token: {}", e))?;

    let mint_url = parsed
        .mint_url()
        .map_err(|e| anyhow!("Could not extract mint URL: {}", e))?
        .to_string();

    let store = store().await?;
    let mut guard = store.lock().await;
    let wallet = guard.wallet_for(&mint_url).await?;
    drop(guard);

    let _received_amount = wallet
        .receive(token_str, ReceiveOptions::default())
        .await
        .map_err(|e| anyhow!("Failed to receive token: {}", e))?;

    let total_balance = wallet
        .total_balance()
        .await
        .map(u64::from)
        .map_err(|e| anyhow!("Failed to get balance: {}", e))?;

    let melted = melt_with_retry(&wallet, lightning_target.trim(), total_balance).await?;

    Ok(serde_json::json!({ "amount_sats": melted }).to_string())
}

/// Melts all proofs in the wallet to the given Lightning target.
///
/// Returns JSON `{ "total_sats": u64, "mints": [ { "mint_url": String, "sats": u64 } ] }`
pub async fn cashu_melt_all(lightning_target: String) -> Result<String> {
    let store = store().await?;
    let guard = store.lock().await;
    let wallets: Vec<(String, Arc<Wallet>)> = guard
        .wallets
        .iter()
        .map(|(k, v)| (k.clone(), v.clone()))
        .collect();
    drop(guard);

    if wallets.is_empty() {
        return Err(anyhow!("No Cashu wallets found. Receive a token first."));
    }

    let ln = lightning_target.trim();
    let mut total_melted: u64 = 0;
    let mut mints = Vec::new();
    let mut last_error: Option<String> = None;

    for (mint_url, wallet) in &wallets {
        let balance = wallet.total_balance().await.map(u64::from).unwrap_or(0);
        if balance == 0 {
            continue;
        }

        match melt_with_retry(wallet, ln, balance).await {
            Ok(melted) => {
                total_melted += melted;
                mints.push(serde_json::json!({ "mint_url": mint_url, "sats": melted }));
            }
            Err(e) => {
                last_error = Some(format!("{}: {}", mint_url, e));
            }
        }
    }

    if total_melted == 0 {
        return Err(anyhow!(
            "{}",
            last_error.unwrap_or_else(|| "Nothing to melt".into())
        ));
    }

    Ok(serde_json::json!({
        "total_sats": total_melted,
        "mints": mints,
    })
    .to_string())
}

/// Fee-aware melt with retry.
/// 1. Try send_sats = available_sats - 1 (minimum fee offset).
/// 2. On InsufficientFunds, increment fee by 1 and retry.
/// Max 5 attempts (fee offsets: 1, 2, 3, 4, 5).
async fn melt_with_retry(
    wallet: &Wallet,
    ln_target: &str,
    available_sats: u64,
) -> Result<u64> {
    if available_sats == 0 {
        return Err(anyhow!("Balance is zero"));
    }

    for extra_fee in 1u64..=5 {
        let send_sats = match available_sats.checked_sub(extra_fee) {
            Some(s) if s > 0 => s,
            _ => return Err(anyhow!("Amount too small to cover fees")),
        };

        let amount_msat = cdk::Amount::from(send_sats * 1000);

        let quote = match get_quote(wallet, ln_target, amount_msat).await {
            Ok(q) => q,
            Err(e) => {
                let msg = e.to_string().to_lowercase();
                if msg.contains("insufficient")
                    || msg.contains("amount")
                    || msg.contains("too small")
                {
                    continue;
                }
                return Err(e);
            }
        };

        match wallet.prepare_melt(&quote.id, HashMap::new()).await {
            Ok(prepared) => {
                prepared
                    .confirm()
                    .await
                    .map_err(|e| anyhow!("Melt confirm failed: {}", e))?;
                return Ok(send_sats);
            }
            Err(e) => {
                let msg = e.to_string().to_lowercase();
                if msg.contains("insufficient") || msg.contains("not enough") {
                    continue;
                }
                return Err(anyhow!("prepare_melt failed: {}", e));
            }
        }
    }

    Err(anyhow!("Failed after 5 attempts: insufficient funds"))
}

async fn get_quote(
    wallet: &Wallet,
    ln_target: &str,
    amount_msat: cdk::Amount,
) -> Result<cdk::wallet::MeltQuote> {
    if ln_target.contains('@') {
        wallet
            .melt_lightning_address_quote(ln_target, amount_msat)
            .await
            .map_err(|e| anyhow!("{}", e))
    } else {
        wallet
            .melt_quote(PaymentMethod::BOLT11, ln_target.to_string(), None, None)
            .await
            .map_err(|e| anyhow!("{}", e))
    }
}

/// Decodes a Cashu token: returns mint URL and amount.
///
/// Returns JSON `{ "mint_url": String, "amount_sats": u64 }`
#[frb(sync)]
pub fn cashu_decode_token(token: String) -> Result<String> {
    let parsed =
        Token::from_str(token.trim()).map_err(|e| anyhow!("Invalid token: {}", e))?;

    let mint_url = parsed
        .mint_url()
        .map_err(|e| anyhow!("Could not extract mint URL: {}", e))?
        .to_string();

    let amount_sats = parsed.value().map(u64::from).unwrap_or(0);

    Ok(serde_json::json!({
        "mint_url": mint_url,
        "amount_sats": amount_sats,
    })
    .to_string())
}

/// Returns the total Cashu balance across all wallets.
///
/// Returns JSON `{ "total_sats": u64, "mints": [ { "mint_url": String, "sats": u64 } ] }`
pub async fn cashu_get_balance() -> Result<String> {
    let store = store().await?;
    let guard = store.lock().await;
    let wallets: Vec<(String, Arc<Wallet>)> = guard
        .wallets
        .iter()
        .map(|(k, v)| (k.clone(), v.clone()))
        .collect();
    drop(guard);

    let mut total: u64 = 0;
    let mut mints = Vec::new();

    for (mint_url, wallet) in wallets {
        let balance = wallet.total_balance().await.map(u64::from).unwrap_or(0);
        total += balance;
        mints.push(serde_json::json!({ "mint_url": mint_url, "sats": balance }));
    }

    Ok(serde_json::json!({ "total_sats": total, "mints": mints }).to_string())
}
