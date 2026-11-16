use std::collections::HashMap;
use std::io::{ErrorKind, Write};
use std::path::{Path, PathBuf};
use std::str::FromStr;
use std::sync::Arc;

use anyhow::{anyhow, Context, Result};
use cdk::cdk_database::WalletDatabase;
use cdk::nuts::{
    CurrencyUnit, MintQuoteState, PaymentMethod, Proof, Proofs, PublicKey, SecretKey,
    SpendingConditions, Token,
};
use cdk::wallet::{ReceiveOptions, SendOptions, Wallet};
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
    *CASHU_ACCOUNT
        .write()
        .map_err(|_| anyhow!("Cashu is unavailable"))? = Some(pubkey);
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
        .map(|path| {
            PathBuf::from(path)
                .parent()
                .unwrap_or_else(|| Path::new("."))
                .to_path_buf()
        })
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

fn normalize_mint_url(mint_url: &str) -> Result<String> {
    let trimmed = mint_url.trim().trim_end_matches('/');
    if !trimmed.starts_with("https://") || trimmed.len() < 12 || trimmed.contains(' ') {
        return Err(anyhow!("Enter a valid https mint address"));
    }
    Ok(trimmed.to_string())
}

async fn wallet_at(mint_url: &str) -> Result<Arc<Wallet>> {
    let url = normalize_mint_url(mint_url)?;
    let store = store().await?;
    let mut guard = store.lock().await;
    guard.wallet_for(&url).await
}

async fn balance_of(wallet: &Wallet) -> Result<u64> {
    wallet
        .total_balance()
        .await
        .map(u64::from)
        .context("Failed to get Cashu balance")
}

async fn fee_reserve(wallet: &Wallet) -> u64 {
    let ppk = wallet
        .get_active_keyset()
        .await
        .map(|keyset| keyset.input_fee_ppk)
        .unwrap_or(0);
    ppk.saturating_mul(64).div_ceil(1000)
}

fn parse_p2pk_pubkey(pubkey_hex: &str) -> Result<PublicKey> {
    let hex = pubkey_hex.trim().to_lowercase();
    let full = match hex.len() {
        64 => format!("02{hex}"),
        66 => hex,
        _ => return Err(anyhow!("Invalid Cashu lock key")),
    };
    PublicKey::from_hex(full).map_err(|_| anyhow!("Invalid Cashu lock key"))
}

/// Looks up a mint and returns JSON `{ "url", "name", "description" }`.
pub async fn cashu_mint_info(mint_url: String) -> Result<String> {
    let url = normalize_mint_url(&mint_url)?;
    let wallet = wallet_at(&url).await?;
    let info = wallet
        .load_mint_info()
        .await
        .map_err(|e| anyhow!("Could not reach the mint: {}", e))?;
    Ok(serde_json::json!({
        "url": url,
        "name": info.name,
        "description": info.description,
    })
    .to_string())
}

/// Works out what must be paid before `amount_sats` can be sent from a mint.
///
/// Returns JSON `{ "needs_payment": bool, "quote_id", "invoice", "pay_sats", "balance_sats" }`.
/// When the wallet already holds enough at that mint, `needs_payment` is false.
pub async fn cashu_fund_quote(mint_url: String, amount_sats: u64) -> Result<String> {
    if amount_sats == 0 {
        return Err(anyhow!("Amount must be greater than zero"));
    }
    let wallet = wallet_at(&mint_url).await?;
    let balance = balance_of(&wallet).await?;
    let needed = amount_sats
        .checked_add(fee_reserve(&wallet).await)
        .ok_or_else(|| anyhow!("Amount is too large"))?;
    if balance >= needed {
        return Ok(serde_json::json!({
            "needs_payment": false,
            "pay_sats": 0,
            "balance_sats": balance,
        })
        .to_string());
    }
    let pay = needed - balance;
    let quote = wallet
        .mint_quote(
            PaymentMethod::BOLT11,
            Some(cdk::Amount::from(pay)),
            None,
            None,
        )
        .await
        .map_err(|e| anyhow!("The mint did not issue an invoice: {}", e))?;
    Ok(serde_json::json!({
        "needs_payment": true,
        "quote_id": quote.id,
        "invoice": quote.request,
        "pay_sats": pay,
        "balance_sats": balance,
    })
    .to_string())
}

/// Mints the ecash for a paid funding quote.
///
/// Returns JSON `{ "minted_sats": u64 }`. Fails while the invoice is unpaid.
pub async fn cashu_fund_complete(mint_url: String, quote_id: String) -> Result<String> {
    let wallet = wallet_at(&mint_url).await?;
    let quote = wallet
        .check_mint_quote(&quote_id)
        .await
        .map_err(|e| anyhow!("Could not check the invoice: {}", e))?;
    let minted = match quote.state {
        MintQuoteState::Unpaid => return Err(anyhow!("The invoice has not been paid yet")),
        MintQuoteState::Issued => 0,
        _ => {
            let proofs = wallet
                .mint(&quote_id, cdk::amount::SplitTarget::default(), None)
                .await
                .map_err(|e| anyhow!("Minting failed: {}", e))?;
            proofs.iter().map(|proof| u64::from(proof.amount)).sum()
        }
    };
    Ok(serde_json::json!({ "minted_sats": minted }).to_string())
}

/// Takes `amount_sats` out of the wallet as a token, optionally locked to a key (NUT-11).
///
/// Returns JSON `{ "token": String, "proofs": [String], "mint_url", "amount_sats", "fee_sats" }`.
pub async fn cashu_create_token(
    mint_url: String,
    amount_sats: u64,
    p2pk_pubkey_hex: Option<String>,
) -> Result<String> {
    if amount_sats == 0 {
        return Err(anyhow!("Amount must be greater than zero"));
    }
    let url = normalize_mint_url(&mint_url)?;
    let wallet = wallet_at(&url).await?;
    let conditions = match p2pk_pubkey_hex
        .as_deref()
        .filter(|key| !key.trim().is_empty())
    {
        Some(key) => Some(SpendingConditions::new_p2pk(parse_p2pk_pubkey(key)?, None)),
        None => None,
    };
    let options = SendOptions {
        conditions,
        include_fee: true,
        ..Default::default()
    };
    let prepared = wallet
        .prepare_send(cdk::Amount::from(amount_sats), options)
        .await
        .map_err(|e| anyhow!("Not enough ecash at this mint: {}", e))?;
    let fee = u64::from(prepared.fee());
    let token = prepared
        .confirm(None)
        .await
        .map_err(|e| anyhow!("Could not create the token: {}", e))?;
    let keysets = wallet
        .load_mint_keysets()
        .await
        .context("Failed to load mint keysets")?;
    let proofs = token
        .proofs(&keysets)
        .map_err(|e| anyhow!("Could not read the token: {}", e))?;
    let encoded: Vec<String> = proofs
        .iter()
        .map(serde_json::to_string)
        .collect::<std::result::Result<_, _>>()?;
    Ok(serde_json::json!({
        "token": token.to_string(),
        "proofs": encoded,
        "mint_url": url,
        "amount_sats": amount_sats,
        "fee_sats": fee,
    })
    .to_string())
}

/// Claims key-locked proofs (a nutzap) and, when a Lightning target is given, melts them to it.
///
/// Returns JSON `{ "received_sats": u64, "melted_sats": u64 }`.
pub async fn cashu_redeem_proofs(
    mint_url: String,
    proofs_json: Vec<String>,
    p2pk_private_key_hex: String,
    lightning_target: String,
) -> Result<String> {
    if proofs_json.is_empty() {
        return Err(anyhow!("No proofs to redeem"));
    }
    let proofs: Proofs = proofs_json
        .iter()
        .map(|raw| serde_json::from_str::<Proof>(raw))
        .collect::<std::result::Result<_, _>>()
        .map_err(|_| anyhow!("Invalid Cashu proof"))?;
    let key = SecretKey::from_hex(p2pk_private_key_hex.trim())
        .map_err(|_| anyhow!("Invalid Cashu unlock key"))?;
    let wallet = wallet_at(&mint_url).await?;
    let options = ReceiveOptions {
        p2pk_signing_keys: vec![key],
        ..Default::default()
    };
    let received = wallet
        .receive_proofs(proofs, options, None, None)
        .await
        .map(u64::from)
        .map_err(|e| anyhow!("Failed to redeem: {}", e))?;
    let target = lightning_target.trim();
    let mut melted = 0u64;
    if !target.is_empty() {
        let balance = balance_of(&wallet).await?;
        if let Ok(amount) = melt_with_retry(&wallet, target, balance).await {
            melted = amount;
        }
    }
    Ok(serde_json::json!({ "received_sats": received, "melted_sats": melted }).to_string())
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
    fn lock_keys_accept_nostr_and_compressed_forms() {
        let key = SecretKey::generate().public_key();
        let compressed = key.to_hex();
        let x_only = key.x_only_public_key().to_string();
        assert_eq!(
            parse_p2pk_pubkey(&x_only).unwrap().to_hex(),
            format!("02{x_only}")
        );
        assert_eq!(parse_p2pk_pubkey(&compressed).unwrap().to_hex(), compressed);
        assert!(parse_p2pk_pubkey("abcd").is_err());
    }

    #[test]
    fn mint_addresses_must_be_https() {
        assert_eq!(
            normalize_mint_url(" https://mint.example.com/ ").unwrap(),
            "https://mint.example.com"
        );
        assert!(normalize_mint_url("http://mint.example.com").is_err());
        assert!(normalize_mint_url("mint.example.com").is_err());
    }

    #[tokio::test]
    #[ignore = "uses the public test mint at testnut.cashu.space"]
    async fn locked_token_round_trip_on_the_test_mint() {
        let directory = TestDirectory::new();
        *db_path_state().write().await = Some(
            directory
                .0
                .join("nostr-lmdb")
                .to_string_lossy()
                .into_owned(),
        );
        let mint = "https://testnut.cashu.space".to_string();
        let sender = "a".repeat(64);
        let receiver = "b".repeat(64);

        cashu_set_account(sender.clone()).unwrap();
        let quote: serde_json::Value =
            serde_json::from_str(&cashu_fund_quote(mint.clone(), 64).await.unwrap()).unwrap();
        assert_eq!(quote["needs_payment"], true);
        let quote_id = quote["quote_id"].as_str().unwrap().to_string();
        let mut funded = false;
        for _ in 0..20 {
            if cashu_fund_complete(mint.clone(), quote_id.clone())
                .await
                .is_ok()
            {
                funded = true;
                break;
            }
            tokio::time::sleep(std::time::Duration::from_secs(1)).await;
        }
        assert!(funded, "the test mint did not settle the invoice");
        let again: serde_json::Value =
            serde_json::from_str(&cashu_fund_quote(mint.clone(), 21).await.unwrap()).unwrap();
        assert_eq!(again["needs_payment"], false);

        let key = SecretKey::generate();
        let lock = key.public_key().x_only_public_key().to_string();
        let created: serde_json::Value = serde_json::from_str(
            &cashu_create_token(mint.clone(), 21, Some(lock.clone()))
                .await
                .unwrap(),
        )
        .unwrap();
        let proofs: Vec<String> = created["proofs"]
            .as_array()
            .unwrap()
            .iter()
            .map(|proof| proof.as_str().unwrap().to_string())
            .collect();
        assert!(!proofs.is_empty());

        cashu_set_account(receiver).unwrap();
        let wrong = SecretKey::generate().to_secret_hex();
        assert!(
            cashu_redeem_proofs(mint.clone(), proofs.clone(), wrong, String::new())
                .await
                .is_err()
        );
        let redeemed: serde_json::Value = serde_json::from_str(
            &cashu_redeem_proofs(mint.clone(), proofs, key.to_secret_hex(), String::new())
                .await
                .unwrap(),
        )
        .unwrap();
        assert!(redeemed["received_sats"].as_u64().unwrap() >= 20);

        cashu_set_account(sender).unwrap();
        let plain: serde_json::Value =
            serde_json::from_str(&cashu_create_token(mint.clone(), 10, None).await.unwrap())
                .unwrap();
        let decoded: serde_json::Value = serde_json::from_str(
            &cashu_decode_token(plain["token"].as_str().unwrap().to_string()).unwrap(),
        )
        .unwrap();
        assert!(decoded["amount_sats"].as_u64().unwrap() >= 10);
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
