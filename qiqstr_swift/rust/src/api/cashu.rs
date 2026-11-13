use std::collections::HashMap;
use std::io::{ErrorKind, Write};
use std::path::{Path, PathBuf};
use std::str::FromStr;
use std::sync::Arc;

use anyhow::{anyhow, Context, Result};
use cdk::cdk_database::WalletDatabase;
use cdk::nuts::{CurrencyUnit, PaymentMethod, Token};
use cdk::wallet::{ReceiveOptions, Wallet};
use cdk_sqlite::wallet::WalletSqliteDatabase;
use rand::RngCore;
use tokio::sync::Mutex;

use crate::api::relay::db_path_state;

static WALLET_STORE: Mutex<Option<(PathBuf, Arc<Mutex<WalletStore>>)>> = Mutex::const_new(None);

struct WalletStore {
    database: Arc<WalletSqliteDatabase>,
    wallets: HashMap<String, Arc<Wallet>>,
    seed: [u8; 64],
}

impl WalletStore {
    async fn new(db_path: PathBuf) -> Result<Self> {
        let seed = Self::load_or_create_seed(&db_path)?;
        let database = Arc::new(
            WalletSqliteDatabase::new(db_path)
                .await
                .context("Failed to open Cashu database")?,
        );
        let mut store = Self {
            database,
            wallets: HashMap::new(),
            seed,
        };
        for mint in store.database.get_mints().await?.into_keys() {
            store.insert_wallet(&mint.to_string())?;
        }
        Ok(store)
    }

    fn seed_path(db_path: &Path) -> PathBuf {
        db_path
            .parent()
            .unwrap_or_else(|| Path::new("."))
            .join("cashu_seed.bin")
    }

    fn load_or_create_seed(db_path: &Path) -> Result<[u8; 64]> {
        let path = Self::seed_path(db_path);
        match std::fs::read(&path) {
            Ok(bytes) => {
                return bytes.try_into().map_err(|_| {
                    anyhow!(
                        "Cashu seed is corrupt; restore the original seed before using the wallet"
                    )
                })
            }
            Err(error) if error.kind() == ErrorKind::NotFound => {}
            Err(error) => return Err(error).context("Failed to read Cashu seed"),
        }
        if db_path.try_exists()? {
            return Err(anyhow!(
                "Cashu seed is missing for an existing wallet; restore the original seed"
            ));
        }
        let mut seed = [0u8; 64];
        rand::thread_rng().fill_bytes(&mut seed);
        let mut options = std::fs::OpenOptions::new();
        options.write(true).create_new(true);
        #[cfg(unix)]
        {
            use std::os::unix::fs::OpenOptionsExt;
            options.mode(0o600);
        }
        let mut file = options.open(&path).context("Failed to create Cashu seed")?;
        if let Err(error) = file.write_all(&seed).and_then(|_| file.sync_all()) {
            let _ = std::fs::remove_file(&path);
            return Err(error).context("Failed to persist Cashu seed");
        }
        Ok(seed)
    }

    fn insert_wallet(&mut self, mint_url: &str) -> Result<Arc<Wallet>> {
        let wallet = Arc::new(
            Wallet::new(
                mint_url,
                CurrencyUnit::Sat,
                self.database.clone(),
                self.seed,
                None,
            )
            .context("Failed to create Cashu wallet")?,
        );
        self.wallets.insert(mint_url.to_string(), wallet.clone());
        Ok(wallet)
    }

    async fn wallet_for(&mut self, mint_url: &str) -> Result<Arc<Wallet>> {
        let wallet = match self.wallets.get(mint_url) {
            Some(wallet) => wallet.clone(),
            None => {
                self.database.add_mint(mint_url.parse()?, None).await?;
                self.insert_wallet(mint_url)?
            }
        };
        wallet
            .recover_incomplete_sagas()
            .await
            .context("Cashu recovery failed")?;
        Ok(wallet)
    }
}

static CASHU_ACCOUNT: std::sync::RwLock<Option<String>> = std::sync::RwLock::new(None);

pub fn cashu_set_account(pubkey_hex: String) -> Result<()> {
    let pubkey = pubkey_hex.trim().to_lowercase();
    if pubkey.len() != 64 || !pubkey.chars().all(|c| c.is_ascii_hexdigit()) {
        return Err(anyhow!("Invalid account for Cashu"));
    }
    *CASHU_ACCOUNT.write().map_err(|_| anyhow!("Cashu is unavailable"))? = Some(pubkey);
    Ok(())
}

const LEGACY_FILES: [&str; 4] = [
    "cashu_wallet.sqlite",
    "cashu_wallet.sqlite-wal",
    "cashu_wallet.sqlite-shm",
    "cashu_seed.bin",
];

fn account_wallet_path(base: &Path, pubkey: &str) -> Result<PathBuf> {
    let dir = base.join("cashu").join(pubkey);
    std::fs::create_dir_all(&dir).context("Failed to create Cashu storage")?;
    let target = dir.join("cashu_wallet.sqlite");
    if !target.try_exists()? && !dir.join("cashu_seed.bin").try_exists()? {
        for name in LEGACY_FILES {
            let legacy = base.join(name);
            if legacy.try_exists()? {
                std::fs::rename(&legacy, dir.join(name)).context("Failed to move Cashu storage")?;
            }
        }
    }
    Ok(target)
}

async fn store() -> Result<Arc<Mutex<WalletStore>>> {
    let base = db_path_state()
        .read()
        .await
        .as_ref()
        .map(|path| PathBuf::from(path).parent().unwrap_or_else(|| Path::new(".")).to_path_buf())
        .ok_or_else(|| anyhow!("Initialize persistent app storage before using Cashu"))?;
    let account = CASHU_ACCOUNT
        .read()
        .map_err(|_| anyhow!("Cashu is unavailable"))?
        .clone()
        .ok_or_else(|| anyhow!("Sign in before using Cashu"))?;
    let mut guard = WALLET_STORE.lock().await;
    let db_path = account_wallet_path(&base, &account)?;
    if let Some((current_path, store)) = guard.as_ref() {
        if current_path == &db_path {
            return Ok(store.clone());
        }
    }
    let store = Arc::new(Mutex::new(WalletStore::new(db_path.clone()).await?));
    *guard = Some((db_path, store.clone()));
    Ok(store)
}

fn parse_sat_token(token: &str) -> Result<Token> {
    let parsed = Token::from_str(token.trim()).context("Invalid token")?;
    if parsed.unit().unwrap_or(CurrencyUnit::Sat) != CurrencyUnit::Sat {
        return Err(anyhow!("Only sat-denominated Cashu tokens are supported"));
    }
    parsed.value().context("Invalid token amount")?;
    Ok(parsed)
}

/// Receives a Cashu token and melts it to the given Lightning target.
///
/// Returns JSON `{ "amount_sats": u64 }`
pub async fn cashu_receive_and_melt(token: String, lightning_target: String) -> Result<String> {
    let token_str = token.trim();
    let parsed = parse_sat_token(token_str)?;

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
        if let Err(error) = wallet.recover_incomplete_sagas().await {
            last_error = Some(format!("{}: recovery failed: {}", mint_url, error));
            continue;
        }
        let balance = u64::from(
            wallet
                .total_balance()
                .await
                .context("Failed to get Cashu balance")?,
        );
        if balance == 0 {
            continue;
        }

        match melt_with_retry(wallet, ln, balance).await {
            Ok(melted) => {
                total_melted = total_melted
                    .checked_add(melted)
                    .ok_or_else(|| anyhow!("Total Cashu amount overflow"))?;
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
        "error": last_error,
    })
    .to_string())
}

async fn melt_with_retry(wallet: &Wallet, ln_target: &str, available_sats: u64) -> Result<u64> {
    if available_sats == 0 {
        return Err(anyhow!("Balance is zero"));
    }

    let mut extra_fee = 1u64;
    for _ in 0..5 {
        let send_sats = match available_sats.checked_sub(extra_fee) {
            Some(s) if s > 0 => s,
            _ => return Err(anyhow!("Amount too small to cover fees")),
        };

        let amount_msat = cdk::Amount::from(
            send_sats
                .checked_mul(1000)
                .ok_or_else(|| anyhow!("Amount is too large"))?,
        );

        let quote = match get_quote(wallet, ln_target, amount_msat).await {
            Ok(q) => q,
            Err(e) => {
                let msg = e.to_string().to_lowercase();
                if msg.contains("insufficient")
                    || msg.contains("amount")
                    || msg.contains("too small")
                {
                    extra_fee += 1;
                    continue;
                }
                return Err(e);
            }
        };

        match wallet.prepare_melt(&quote.id, HashMap::new()).await {
            Ok(prepared) => {
                let finalized = prepared.confirm().await.context("Melt confirm failed")?;
                return Ok(u64::from(finalized.amount()));
            }
            Err(e) => {
                let msg = e.to_string().to_lowercase();
                if msg.contains("insufficient") || msg.contains("not enough") {
                    if !ln_target.contains('@') {
                        return Err(anyhow!("Insufficient funds for the invoice and its fees"));
                    }
                    extra_fee = extra_fee
                        .saturating_add(1)
                        .max(u64::from(quote.fee_reserve));
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
pub fn cashu_decode_token(token: String) -> Result<String> {
    let parsed = parse_sat_token(&token)?;

    let mint_url = parsed
        .mint_url()
        .map_err(|e| anyhow!("Could not extract mint URL: {}", e))?
        .to_string();

    let amount_sats = u64::from(parsed.value()?);

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
        let balance = u64::from(
            wallet
                .total_balance()
                .await
                .context("Failed to get Cashu balance")?,
        );
        total = total
            .checked_add(balance)
            .ok_or_else(|| anyhow!("Total Cashu balance overflow"))?;
        mints.push(serde_json::json!({ "mint_url": mint_url, "sats": balance }));
    }

    Ok(serde_json::json!({ "total_sats": total, "mints": mints }).to_string())
}

#[cfg(test)]
mod tests {
    use super::*;

    struct TestDirectory(PathBuf);

    impl TestDirectory {
        fn new() -> Self {
            let path = std::env::temp_dir().join(format!("qiqstr-cashu-{}", rand::random::<u64>()));
            std::fs::create_dir(&path).unwrap();
            Self(path)
        }

        fn database(&self) -> PathBuf {
            self.0.join("cashu_wallet.sqlite")
        }
    }

    impl Drop for TestDirectory {
        fn drop(&mut self) {
            let _ = std::fs::remove_dir_all(&self.0);
        }
    }

    #[test]
    fn legacy_wallet_moves_to_the_first_account_only() {
        let directory = TestDirectory::new();
        std::fs::write(directory.0.join("cashu_wallet.sqlite"), b"db").unwrap();
        std::fs::write(directory.0.join("cashu_seed.bin"), [7u8; 64]).unwrap();
        let first = "a".repeat(64);
        let second = "b".repeat(64);
        let path = account_wallet_path(&directory.0, &first).unwrap();
        assert_eq!(std::fs::read(&path).unwrap(), b"db");
        assert!(path.parent().unwrap().join("cashu_seed.bin").exists());
        assert!(!directory.0.join("cashu_wallet.sqlite").exists());
        let other = account_wallet_path(&directory.0, &second).unwrap();
        assert!(!other.exists());
        assert_ne!(path.parent(), other.parent());
    }

    #[test]
    fn seed_survives_reopening() {
        let directory = TestDirectory::new();
        let first = WalletStore::load_or_create_seed(&directory.database()).unwrap();
        assert_eq!(
            WalletStore::load_or_create_seed(&directory.database()).unwrap(),
            first
        );
        #[cfg(unix)]
        {
            use std::os::unix::fs::PermissionsExt;
            let metadata =
                std::fs::metadata(WalletStore::seed_path(&directory.database())).unwrap();
            assert_eq!(metadata.permissions().mode() & 0o777, 0o600);
        }
    }

    #[test]
    fn corrupt_seed_is_preserved_and_rejected() {
        let directory = TestDirectory::new();
        let seed = WalletStore::seed_path(&directory.database());
        std::fs::write(&seed, [1, 2, 3]).unwrap();
        assert!(WalletStore::load_or_create_seed(&directory.database()).is_err());
        assert_eq!(std::fs::read(seed).unwrap(), [1, 2, 3]);
    }

    #[test]
    fn missing_seed_for_existing_wallet_is_rejected() {
        let directory = TestDirectory::new();
        std::fs::write(directory.database(), []).unwrap();
        assert!(WalletStore::load_or_create_seed(&directory.database()).is_err());
        assert!(!WalletStore::seed_path(&directory.database()).exists());
    }

    #[test]
    fn seed_storage_failure_is_not_ignored() {
        let directory = TestDirectory::new();
        assert!(
            WalletStore::load_or_create_seed(&directory.0.join("missing/wallet.sqlite")).is_err()
        );
    }

    #[tokio::test]
    async fn persisted_mints_are_loaded_without_network_after_restart() {
        let directory = TestDirectory::new();
        let store = WalletStore::new(directory.database()).await.unwrap();
        store
            .database
            .add_mint("https://mint.example".parse().unwrap(), None)
            .await
            .unwrap();
        drop(store);
        let reopened = WalletStore::new(directory.database()).await.unwrap();
        assert!(reopened.wallets.contains_key("https://mint.example"));
        assert_eq!(
            u64::from(
                reopened.wallets["https://mint.example"]
                    .total_balance()
                    .await
                    .unwrap()
            ),
            0
        );
    }

    #[test]
    fn tokens_in_other_units_are_rejected() {
        let token = Token::new(
            "https://mint.example".parse().unwrap(),
            vec![],
            None,
            CurrencyUnit::Msat,
        );
        assert!(parse_sat_token(&token.to_string()).is_err());
    }
}
