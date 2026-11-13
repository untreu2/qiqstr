use std::sync::Arc;
use crate::api;
use crate::sink::{EventSink, StreamSink};

#[derive(Debug, thiserror::Error, uniffi::Error)]
pub enum QiqError {
    #[error("{message}")]
    Failed { message: String },
}

impl From<anyhow::Error> for QiqError {
    fn from(e: anyhow::Error) -> Self { QiqError::Failed { message: format!("{e:#}") } }
}

fn runtime() -> &'static tokio::runtime::Runtime {
    static RT: once_cell::sync::Lazy<tokio::runtime::Runtime> = once_cell::sync::Lazy::new(|| {
        tokio::runtime::Builder::new_multi_thread().enable_all().thread_name("qiqstr-core").build().expect("tokio runtime")
    });
    &RT
}

async fn on_rt<F, T>(fut: F) -> Result<T, QiqError> where F: std::future::Future<Output = anyhow::Result<T>> + Send + 'static, T: Send + 'static {
    runtime().spawn(fut).await.map_err(|e| QiqError::Failed { message: e.to_string() })?.map_err(Into::into)
}

async fn on_rt_plain<F, T>(fut: F) -> Result<T, QiqError> where F: std::future::Future<Output = T> + Send + 'static, T: Send + 'static {
    runtime().spawn(fut).await.map_err(|e| QiqError::Failed { message: e.to_string() })
}

#[derive(uniffi::Record)]
pub struct KeyPair { pub private_key: String, pub public_key: String }

#[derive(uniffi::Record)]
pub struct EmbeddedIds { pub event_ids: Vec<String>, pub addresses: Vec<String> }

#[uniffi::export]
pub fn generate_keypair() -> KeyPair { let (a, b) = api::crypto::generate_keypair(); KeyPair { private_key: a, public_key: b } }

#[uniffi::export]
pub fn extract_embedded_ids_batch_typed(contents: Vec<String>) -> EmbeddedIds { let (a, b) = api::database::extract_embedded_ids_batch_typed(contents); EmbeddedIds { event_ids: a, addresses: b } }

#[uniffi::export]
pub fn cashu_set_account(pubkey_hex: String) -> Result<(), QiqError> { api::cashu::cashu_set_account(pubkey_hex).map_err(Into::into) }

#[uniffi::export]
pub async fn cashu_receive_and_melt(token: String, lightning_target: String) -> Result<String, QiqError> { on_rt(async move { api::cashu::cashu_receive_and_melt(token, lightning_target).await }).await }

#[uniffi::export]
pub async fn cashu_melt_all(lightning_target: String) -> Result<String, QiqError> { on_rt(async move { api::cashu::cashu_melt_all(lightning_target).await }).await }

#[uniffi::export]
pub fn cashu_decode_token(token: String) -> Result<String, QiqError> { api::cashu::cashu_decode_token(token).map_err(Into::into) }

#[uniffi::export]
pub async fn cashu_get_balance() -> Result<String, QiqError> { on_rt(async move { api::cashu::cashu_get_balance().await }).await }

#[uniffi::export]
pub fn get_public_key(private_key_hex: String) -> Result<String, QiqError> { api::crypto::get_public_key(private_key_hex).map_err(Into::into) }

#[uniffi::export]
pub fn sign_event_id(event_id_hex: String, private_key_hex: String) -> Result<String, QiqError> { api::crypto::sign_event_id(event_id_hex, private_key_hex).map_err(Into::into) }

#[uniffi::export]
pub fn verify_event(event_json: String) -> bool { api::crypto::verify_event(event_json) }

#[uniffi::export]
pub async fn verify_note_by_id(event_id_hex: String) -> Result<bool, QiqError> { on_rt(async move { api::crypto::verify_note_by_id(event_id_hex).await }).await }

#[uniffi::export]
pub async fn verify_profile_by_pubkey(pubkey_hex: String) -> Result<bool, QiqError> { on_rt(async move { api::crypto::verify_profile_by_pubkey(pubkey_hex).await }).await }

#[uniffi::export]
pub fn generate_mnemonic() -> Result<String, QiqError> { api::crypto::generate_mnemonic().map_err(Into::into) }

#[uniffi::export]
pub fn validate_mnemonic(mnemonic: String) -> bool { api::crypto::validate_mnemonic(mnemonic) }

#[uniffi::export]
pub fn mnemonic_to_private_key(mnemonic: String) -> Result<String, QiqError> { api::crypto::mnemonic_to_private_key(mnemonic).map_err(Into::into) }

#[uniffi::export]
pub fn generate_aes_key() -> String { api::crypto::generate_aes_key() }

#[uniffi::export]
pub fn generate_aes_nonce() -> String { api::crypto::generate_aes_nonce() }

#[uniffi::export]
pub fn aes_gcm_encrypt(data: Vec<u8>, key_hex: String, nonce_hex: String) -> Result<String, QiqError> { api::crypto::aes_gcm_encrypt(data, key_hex, nonce_hex).map_err(Into::into) }

#[uniffi::export]
pub fn aes_gcm_decrypt(encrypted_base64: String, key_hex: String, nonce_hex: String) -> Result<Vec<u8>, QiqError> { api::crypto::aes_gcm_decrypt(encrypted_base64, key_hex, nonce_hex).map_err(Into::into) }

#[uniffi::export]
pub fn sha256_hash(data: Vec<u8>) -> String { api::crypto::sha256_hash(data) }

#[uniffi::export]
pub fn ncryptsec_encrypt(private_key_hex: String, password: String) -> Result<String, QiqError> { api::crypto::ncryptsec_encrypt(private_key_hex, password).map_err(Into::into) }

#[uniffi::export]
pub fn ncryptsec_decrypt(ncryptsec: String, password: String) -> Result<String, QiqError> { api::crypto::ncryptsec_decrypt(ncryptsec, password).map_err(Into::into) }

#[uniffi::export]
pub fn set_active_mute_list(muted_pubkeys: Vec<String>, muted_words: Vec<String>) -> () { api::database::set_active_mute_list(muted_pubkeys, muted_words) }

#[uniffi::export]
pub fn set_known_zappers(zappers_json: String) -> () { api::database::set_known_zappers(zappers_json) }

#[uniffi::export]
pub fn is_event_new_and_track(event_id: String) -> bool { api::database::is_event_new_and_track(event_id) }

#[uniffi::export]
pub async fn db_get_profile(pubkey_hex: String) -> Result<Option<String>, QiqError> { on_rt(async move { api::database::db_get_profile(pubkey_hex).await }).await }

#[uniffi::export]
pub async fn db_get_profiles(pubkeys_hex: Vec<String>) -> Result<String, QiqError> { on_rt(async move { api::database::db_get_profiles(pubkeys_hex).await }).await }

#[uniffi::export]
pub async fn db_has_profile(pubkey_hex: String) -> Result<bool, QiqError> { on_rt(async move { api::database::db_has_profile(pubkey_hex).await }).await }

#[uniffi::export]
pub async fn db_search_profiles(query: String, limit: u32) -> Result<String, QiqError> { on_rt(async move { api::database::db_search_profiles(query, limit).await }).await }

#[uniffi::export]
pub async fn db_get_following_list(pubkey_hex: String) -> Result<Vec<String>, QiqError> { on_rt(async move { api::database::db_get_following_list(pubkey_hex).await }).await }

#[uniffi::export]
pub async fn db_has_following_list(pubkey_hex: String) -> Result<bool, QiqError> { on_rt(async move { api::database::db_has_following_list(pubkey_hex).await }).await }

#[uniffi::export]
pub async fn db_get_mute_list(pubkey_hex: String) -> Result<Vec<String>, QiqError> { on_rt(async move { api::database::db_get_mute_list(pubkey_hex).await }).await }

#[uniffi::export]
pub async fn db_has_mute_list(pubkey_hex: String) -> Result<bool, QiqError> { on_rt(async move { api::database::db_has_mute_list(pubkey_hex).await }).await }

#[uniffi::export]
pub async fn db_save_following_list(pubkey_hex: String, follows_hex: Vec<String>) -> Result<(), QiqError> { on_rt(async move { api::database::db_save_following_list(pubkey_hex, follows_hex).await }).await }

#[uniffi::export]
pub async fn db_delete_following_list(pubkey_hex: String) -> Result<(), QiqError> { on_rt(async move { api::database::db_delete_following_list(pubkey_hex).await }).await }

#[uniffi::export]
pub async fn db_save_mute_list(pubkey_hex: String, muted_hex: Vec<String>) -> Result<(), QiqError> { on_rt(async move { api::database::db_save_mute_list(pubkey_hex, muted_hex).await }).await }

#[uniffi::export]
pub async fn db_delete_mute_list(pubkey_hex: String) -> Result<(), QiqError> { on_rt(async move { api::database::db_delete_mute_list(pubkey_hex).await }).await }

#[uniffi::export]
pub async fn db_get_feed_notes(authors_hex: Vec<String>, limit: u32, muted_pubkeys: Vec<String>, muted_words: Vec<String>) -> Result<String, QiqError> { on_rt(async move { api::database::db_get_feed_notes(authors_hex, limit, muted_pubkeys, muted_words).await }).await }

#[uniffi::export]
pub async fn db_get_profile_notes(pubkey_hex: String, limit: u32, muted_pubkeys: Vec<String>, muted_words: Vec<String>) -> Result<String, QiqError> { on_rt(async move { api::database::db_get_profile_notes(pubkey_hex, limit, muted_pubkeys, muted_words).await }).await }

#[uniffi::export]
pub async fn db_get_hashtag_notes(hashtag: String, limit: u32, muted_pubkeys: Vec<String>, muted_words: Vec<String>) -> Result<String, QiqError> { on_rt(async move { api::database::db_get_hashtag_notes(hashtag, limit, muted_pubkeys, muted_words).await }).await }

#[uniffi::export]
pub async fn db_get_event(event_id: String) -> Result<Option<String>, QiqError> { on_rt(async move { api::database::db_get_event(event_id).await }).await }

#[uniffi::export]
pub async fn db_event_exists(event_id: String) -> Result<bool, QiqError> { on_rt(async move { api::database::db_event_exists(event_id).await }).await }

#[uniffi::export]
pub async fn db_events_exist_batch(event_ids: Vec<String>) -> Result<Vec<bool>, QiqError> { on_rt(async move { api::database::db_events_exist_batch(event_ids).await }).await }

#[uniffi::export]
pub async fn db_save_event(event_json: String) -> Result<bool, QiqError> { on_rt(async move { api::database::db_save_event(event_json).await }).await }

#[uniffi::export]
pub async fn db_save_events(events_json: String) -> Result<u32, QiqError> { on_rt(async move { api::database::db_save_events(events_json).await }).await }

#[uniffi::export]
pub async fn db_delete_events_by_ids(event_ids: Vec<String>) -> Result<u32, QiqError> { on_rt(async move { api::database::db_delete_events_by_ids(event_ids).await }).await }

#[uniffi::export]
pub async fn db_process_deletion_events() -> Result<u32, QiqError> { on_rt(async move { api::database::db_process_deletion_events().await }).await }

#[uniffi::export]
pub async fn db_query_events(filter_json: String, limit: u32) -> Result<String, QiqError> { on_rt(async move { api::database::db_query_events(filter_json, limit).await }).await }

#[uniffi::export]
pub async fn db_get_replies(note_id: String, limit: u32, muted_pubkeys: Vec<String>, muted_words: Vec<String>) -> Result<String, QiqError> { on_rt(async move { api::database::db_get_replies(note_id, limit, muted_pubkeys, muted_words).await }).await }

#[uniffi::export]
pub async fn db_get_notifications(user_pubkey_hex: String, limit: u32, muted_pubkeys: Vec<String>, muted_words: Vec<String>) -> Result<String, QiqError> { on_rt(async move { api::database::db_get_notifications(user_pubkey_hex, limit, muted_pubkeys, muted_words).await }).await }

#[uniffi::export]
pub async fn db_get_interaction_counts(note_id: String) -> Result<String, QiqError> { on_rt(async move { api::database::db_get_interaction_counts(note_id).await }).await }

#[uniffi::export]
pub async fn db_get_batch_interaction_counts(note_ids: Vec<String>) -> Result<String, QiqError> { on_rt(async move { api::database::db_get_batch_interaction_counts(note_ids).await }).await }

#[uniffi::export]
pub async fn db_get_batch_interaction_data(note_ids: Vec<String>, user_pubkey_hex: String) -> Result<String, QiqError> { on_rt(async move { api::database::db_get_batch_interaction_data(note_ids, user_pubkey_hex).await }).await }

#[uniffi::export]
pub async fn db_has_user_reacted(note_id: String, user_pubkey_hex: String) -> Result<bool, QiqError> { on_rt(async move { api::database::db_has_user_reacted(note_id, user_pubkey_hex).await }).await }

#[uniffi::export]
pub async fn db_has_user_reposted(note_id: String, user_pubkey_hex: String) -> Result<bool, QiqError> { on_rt(async move { api::database::db_has_user_reposted(note_id, user_pubkey_hex).await }).await }

#[uniffi::export]
pub async fn db_get_detailed_interactions(note_id: String) -> Result<String, QiqError> { on_rt(async move { api::database::db_get_detailed_interactions(note_id).await }).await }

#[uniffi::export]
pub async fn db_get_articles(limit: u32, muted_pubkeys: Vec<String>, muted_words: Vec<String>) -> Result<String, QiqError> { on_rt(async move { api::database::db_get_articles(limit, muted_pubkeys, muted_words).await }).await }

#[uniffi::export]
pub async fn db_get_articles_by_authors(authors_hex: Vec<String>, limit: u32, muted_pubkeys: Vec<String>, muted_words: Vec<String>) -> Result<String, QiqError> { on_rt(async move { api::database::db_get_articles_by_authors(authors_hex, limit, muted_pubkeys, muted_words).await }).await }

#[uniffi::export]
pub async fn db_find_user_repost_event_id(user_pubkey_hex: String, note_id: String) -> Result<Option<String>, QiqError> { on_rt(async move { api::database::db_find_user_repost_event_id(user_pubkey_hex, note_id).await }).await }

#[uniffi::export]
pub async fn db_get_random_profiles(limit: u32) -> Result<String, QiqError> { on_rt(async move { api::database::db_get_random_profiles(limit).await }).await }

#[uniffi::export]
pub async fn db_save_profile(pubkey_hex: String, profile_json: String) -> Result<(), QiqError> { on_rt(async move { api::database::db_save_profile(pubkey_hex, profile_json).await }).await }

#[uniffi::export]
pub async fn db_save_profiles_batch(profiles_json: String) -> Result<u32, QiqError> { on_rt(async move { api::database::db_save_profiles_batch(profiles_json).await }).await }

#[uniffi::export]
pub async fn db_count_events(filter_json: String) -> Result<u32, QiqError> { on_rt(async move { api::database::db_count_events(filter_json).await }).await }

#[uniffi::export]
pub async fn db_wipe() -> Result<(), QiqError> { on_rt(async move { api::database::db_wipe().await }).await }

#[uniffi::export]
pub async fn db_wipe_directory() -> Result<(), QiqError> { on_rt(async move { api::database::db_wipe_directory().await }).await }

#[uniffi::export]
pub async fn db_search_notes(query: String, limit: u32) -> Result<String, QiqError> { on_rt(async move { api::database::db_search_notes(query, limit).await }).await }

#[uniffi::export]
pub async fn db_get_oldest_events(limit: u32) -> Result<String, QiqError> { on_rt(async move { api::database::db_get_oldest_events(limit).await }).await }

#[uniffi::export]
pub async fn db_cleanup_old_events(days_to_keep: u32) -> Result<u32, QiqError> { on_rt(async move { api::database::db_cleanup_old_events(days_to_keep).await }).await }

#[uniffi::export]
pub async fn db_cleanup_by_kind(kind_num: u16, days_to_keep: u32) -> Result<u32, QiqError> { on_rt(async move { api::database::db_cleanup_by_kind(kind_num, days_to_keep).await }).await }

#[uniffi::export]
pub async fn db_cleanup_foreign_contact_lists(own_pubkey_hex: String) -> Result<u32, QiqError> { on_rt(async move { api::database::db_cleanup_foreign_contact_lists(own_pubkey_hex).await }).await }

#[uniffi::export]
pub async fn db_smart_cleanup(own_pubkey_hex: String, interaction_days: u32, note_days: u32) -> Result<String, QiqError> { on_rt(async move { api::database::db_smart_cleanup(own_pubkey_hex, interaction_days, note_days).await }).await }

#[uniffi::export]
pub async fn db_get_database_stats() -> Result<String, QiqError> { on_rt(async move { api::database::db_get_database_stats().await }).await }

#[uniffi::export]
pub async fn db_get_hydrated_feed_notes(user_pubkey_hex: String, authors_hex: Option<Vec<String>>, limit: u32, muted_pubkeys: Vec<String>, muted_words: Vec<String>, filter_replies: bool, current_user_pubkey_hex: Option<String>) -> Result<String, QiqError> { on_rt(async move { api::database::db_get_hydrated_feed_notes(user_pubkey_hex, authors_hex, limit, muted_pubkeys, muted_words, filter_replies, current_user_pubkey_hex).await }).await }

#[uniffi::export]
pub async fn db_get_hydrated_profile_notes(pubkey_hex: String, limit: u32, muted_pubkeys: Vec<String>, muted_words: Vec<String>, filter_replies: bool, current_user_pubkey_hex: Option<String>, until_timestamp: Option<i64>) -> Result<String, QiqError> { on_rt(async move { api::database::db_get_hydrated_profile_notes(pubkey_hex, limit, muted_pubkeys, muted_words, filter_replies, current_user_pubkey_hex, until_timestamp).await }).await }

#[uniffi::export]
pub async fn db_get_hydrated_hashtag_notes(hashtag: String, limit: u32, muted_pubkeys: Vec<String>, muted_words: Vec<String>, current_user_pubkey_hex: Option<String>) -> Result<String, QiqError> { on_rt(async move { api::database::db_get_hydrated_hashtag_notes(hashtag, limit, muted_pubkeys, muted_words, current_user_pubkey_hex).await }).await }

#[uniffi::export]
pub async fn db_get_hydrated_notes_by_ids(event_ids: Vec<String>, muted_pubkeys: Vec<String>, muted_words: Vec<String>, current_user_pubkey_hex: Option<String>) -> Result<String, QiqError> { on_rt(async move { api::database::db_get_hydrated_notes_by_ids(event_ids, muted_pubkeys, muted_words, current_user_pubkey_hex).await }).await }

#[uniffi::export]
pub async fn db_get_hydrated_profile_replies(pubkey_hex: String, limit: u32, muted_pubkeys: Vec<String>, muted_words: Vec<String>, current_user_pubkey_hex: Option<String>, until_timestamp: Option<i64>) -> Result<String, QiqError> { on_rt(async move { api::database::db_get_hydrated_profile_replies(pubkey_hex, limit, muted_pubkeys, muted_words, current_user_pubkey_hex, until_timestamp).await }).await }

#[uniffi::export]
pub async fn db_get_hydrated_replies(note_id: String, limit: u32, muted_pubkeys: Vec<String>, muted_words: Vec<String>, current_user_pubkey_hex: Option<String>) -> Result<String, QiqError> { on_rt(async move { api::database::db_get_hydrated_replies(note_id, limit, muted_pubkeys, muted_words, current_user_pubkey_hex).await }).await }

#[uniffi::export]
pub async fn db_get_hydrated_note(event_id: String, current_user_pubkey_hex: Option<String>) -> Result<Option<String>, QiqError> { on_rt(async move { api::database::db_get_hydrated_note(event_id, current_user_pubkey_hex).await }).await }

#[uniffi::export]
pub async fn db_get_hydrated_notifications(user_pubkey_hex: String, limit: u32, muted_pubkeys: Vec<String>, muted_words: Vec<String>) -> Result<String, QiqError> { on_rt(async move { api::database::db_get_hydrated_notifications(user_pubkey_hex, limit, muted_pubkeys, muted_words).await }).await }

#[uniffi::export]
pub async fn db_get_hydrated_notifications_before(user_pubkey_hex: String, before_timestamp: u64, limit: u32, muted_pubkeys: Vec<String>, muted_words: Vec<String>) -> Result<String, QiqError> { on_rt(async move { api::database::db_get_hydrated_notifications_before(user_pubkey_hex, before_timestamp, limit, muted_pubkeys, muted_words).await }).await }

#[uniffi::export]
pub async fn db_get_oldest_notification_timestamp(user_pubkey_hex: String) -> Result<Option<u64>, QiqError> { on_rt(async move { api::database::db_get_oldest_notification_timestamp(user_pubkey_hex).await }).await }

#[uniffi::export]
pub async fn db_get_hydrated_articles(authors_hex: Option<Vec<String>>, limit: u32, muted_pubkeys: Vec<String>, muted_words: Vec<String>) -> Result<String, QiqError> { on_rt(async move { api::database::db_get_hydrated_articles(authors_hex, limit, muted_pubkeys, muted_words).await }).await }

#[uniffi::export]
pub async fn db_get_hydrated_article(event_id: String) -> Result<Option<String>, QiqError> { on_rt(async move { api::database::db_get_hydrated_article(event_id).await }).await }

#[uniffi::export]
pub async fn db_get_hydrated_article_by_naddr(pubkey_hex: String, d_tag: String) -> Result<Option<String>, QiqError> { on_rt(async move { api::database::db_get_hydrated_article_by_naddr(pubkey_hex, d_tag).await }).await }

#[uniffi::export]
pub fn parse_note_content(content: String) -> String { api::database::parse_note_content(content) }

#[uniffi::export]
pub fn extract_embedded_ids_batch(contents: Vec<String>) -> String { api::database::extract_embedded_ids_batch(contents) }

#[uniffi::export]
pub async fn db_get_hydrated_reaction_notes(pubkey_hex: String, limit: u32, muted_pubkeys: Vec<String>, muted_words: Vec<String>, current_user_pubkey_hex: Option<String>) -> Result<String, QiqError> { on_rt(async move { api::database::db_get_hydrated_reaction_notes(pubkey_hex, limit, muted_pubkeys, muted_words, current_user_pubkey_hex).await }).await }

#[uniffi::export]
pub async fn db_calculate_follow_score(current_user_hex: String, target_hex: String) -> Result<String, QiqError> { on_rt(async move { api::database::db_calculate_follow_score(current_user_hex, target_hex).await }).await }

#[uniffi::export]
pub async fn db_get_follow_sets(authors_hex: Vec<String>, limit: u32, hidden_d_tags: Vec<String>) -> Result<String, QiqError> { on_rt(async move { api::database::db_get_follow_sets(authors_hex, limit, hidden_d_tags).await }).await }

#[uniffi::export]
pub async fn db_get_hydrated_feed_notes_sorted(user_pubkey_hex: String, authors_hex: Option<Vec<String>>, limit: u32, filter_replies: bool, current_user_pubkey_hex: Option<String>, sort_mode: String) -> Result<String, QiqError> { on_rt(async move { api::database::db_get_hydrated_feed_notes_sorted(user_pubkey_hex, authors_hex, limit, filter_replies, current_user_pubkey_hex, sort_mode).await }).await }

#[uniffi::export]
pub async fn db_get_hydrated_thread_structure(root_note_id: String, current_user_pubkey_hex: Option<String>, limit: u32) -> Result<String, QiqError> { on_rt(async move { api::database::db_get_hydrated_thread_structure(root_note_id, current_user_pubkey_hex, limit).await }).await }

#[uniffi::export]
pub fn extract_pubkeys_from_events(events_json: String) -> Result<Vec<String>, QiqError> { api::database::extract_pubkeys_from_events(events_json).map_err(Into::into) }

#[uniffi::export]
pub fn filter_reply_event_ids(events_json: String) -> Result<Vec<String>, QiqError> { api::database::filter_reply_event_ids(events_json).map_err(Into::into) }

#[uniffi::export]
pub fn extract_repost_original_ids(events_json: String) -> Result<Vec<String>, QiqError> { api::database::extract_repost_original_ids(events_json).map_err(Into::into) }

#[uniffi::export]
pub async fn queue_missing_repost_originals(since_timestamp: i64) -> Result<Vec<String>, QiqError> { on_rt(async move { api::database::queue_missing_repost_originals(since_timestamp).await }).await }

#[uniffi::export]
pub async fn db_get_mute_list_content(pubkey_hex: String) -> Result<Option<String>, QiqError> { on_rt(async move { api::database::db_get_mute_list_content(pubkey_hex).await }).await }

#[uniffi::export]
pub async fn db_save_following_list_from_event(event_json: String, self_pubkey_hex: String) -> Result<(), QiqError> { on_rt(async move { api::database::db_save_following_list_from_event(event_json, self_pubkey_hex).await }).await }

#[uniffi::export]
pub async fn db_get_notifications_missing_profiles(user_pubkey_hex: String, limit: u32) -> Result<Vec<String>, QiqError> { on_rt(async move { api::database::db_get_notifications_missing_profiles(user_pubkey_hex, limit).await }).await }

#[uniffi::export]
pub fn create_signed_event(kind: u16, content: String, tags: Vec<Vec<String>>, private_key_hex: String) -> Result<String, QiqError> { api::events::create_signed_event(kind, content, tags, private_key_hex).map_err(Into::into) }

#[uniffi::export]
pub fn zap_receipt_summary(event_json: String) -> Result<String, QiqError> { api::events::zap_receipt_summary(event_json).map_err(Into::into) }

#[uniffi::export]
pub fn create_note_event(content: String, tags: Vec<Vec<String>>, private_key_hex: String) -> Result<String, QiqError> { api::events::create_note_event(content, tags, private_key_hex).map_err(Into::into) }

#[uniffi::export]
pub fn create_reaction_event(target_event_id: String, target_author: String, content: String, private_key_hex: String, relay_url: String, target_kind: u16) -> Result<String, QiqError> { api::events::create_reaction_event(target_event_id, target_author, content, private_key_hex, relay_url, target_kind).map_err(Into::into) }

#[uniffi::export]
pub fn create_reply_event(content: String, tags: Vec<Vec<String>>, private_key_hex: String) -> Result<String, QiqError> { api::events::create_reply_event(content, tags, private_key_hex).map_err(Into::into) }

#[uniffi::export]
pub fn create_repost_event(note_id: String, note_author: String, content: String, private_key_hex: String, relay_url: String) -> Result<String, QiqError> { api::events::create_repost_event(note_id, note_author, content, private_key_hex, relay_url).map_err(Into::into) }

#[uniffi::export]
pub fn create_deletion_event(event_ids: Vec<String>, reason: String, private_key_hex: String) -> Result<String, QiqError> { api::events::create_deletion_event(event_ids, reason, private_key_hex).map_err(Into::into) }

#[uniffi::export]
pub fn create_profile_event(profile_json: String, private_key_hex: String) -> Result<String, QiqError> { api::events::create_profile_event(profile_json, private_key_hex).map_err(Into::into) }

#[uniffi::export]
pub fn create_follow_event(following_pubkeys: Vec<String>, private_key_hex: String) -> Result<String, QiqError> { api::events::create_follow_event(following_pubkeys, private_key_hex).map_err(Into::into) }

#[uniffi::export]
pub fn create_mute_event(muted_pubkeys: Vec<String>, private_key_hex: String) -> Result<String, QiqError> { api::events::create_mute_event(muted_pubkeys, private_key_hex).map_err(Into::into) }

#[uniffi::export]
pub fn create_zap_request_event(tags: Vec<Vec<String>>, content: String, private_key_hex: String) -> Result<String, QiqError> { api::events::create_zap_request_event(tags, content, private_key_hex).map_err(Into::into) }

#[uniffi::export]
pub fn create_quote_event(content: String, quoted_event_id: String, quoted_event_pubkey: Option<String>, relay_url: String, private_key_hex: String, additional_tags: Vec<Vec<String>>) -> Result<String, QiqError> { api::events::create_quote_event(content, quoted_event_id, quoted_event_pubkey, relay_url, private_key_hex, additional_tags).map_err(Into::into) }

#[uniffi::export]
pub fn create_blossom_auth_event(content: String, sha256_hash: String, expiration: i64, private_key_hex: String) -> Result<String, QiqError> { api::events::create_blossom_auth_event(content, sha256_hash, expiration, private_key_hex).map_err(Into::into) }

#[uniffi::export]
pub fn create_relay_list_event(relay_urls: Vec<String>, private_key_hex: String) -> Result<String, QiqError> { api::events::create_relay_list_event(relay_urls, private_key_hex).map_err(Into::into) }

#[uniffi::export]
pub fn create_relay_list_event_with_markers(relay_configs: Vec<String>, private_key_hex: String) -> Result<String, QiqError> { api::events::create_relay_list_event_with_markers(relay_configs, private_key_hex).map_err(Into::into) }

#[uniffi::export]
pub fn marmot_open(data_dir: String, private_key_hex: String) -> Result<String, QiqError> { api::marmot::marmot_open(data_dir, private_key_hex).map_err(Into::into) }

#[uniffi::export]
pub fn marmot_close() -> () { api::marmot::marmot_close() }

#[uniffi::export]
pub fn marmot_key_package_event(relays: Vec<String>) -> Result<String, QiqError> { api::marmot::marmot_key_package_event(relays).map_err(Into::into) }

#[uniffi::export]
pub fn marmot_key_package_relays_event(relays: Vec<String>) -> Result<String, QiqError> { api::marmot::marmot_key_package_relays_event(relays).map_err(Into::into) }

#[uniffi::export]
pub fn marmot_pick_key_package(events_json: String, pubkey_hex: String) -> Result<Option<String>, QiqError> { api::marmot::marmot_pick_key_package(events_json, pubkey_hex).map_err(Into::into) }

#[uniffi::export]
pub fn marmot_create_chat(peer_key_package_json: String, relays: Vec<String>) -> Result<String, QiqError> { api::marmot::marmot_create_chat(peer_key_package_json, relays).map_err(Into::into) }

#[uniffi::export]
pub fn marmot_send_message(group_id_hex: String, kind: u16, content: String, tags_json: String) -> Result<String, QiqError> { api::marmot::marmot_send_message(group_id_hex, kind, content, tags_json).map_err(Into::into) }

#[uniffi::export]
pub fn marmot_process_event(event_json: String) -> Result<String, QiqError> { api::marmot::marmot_process_event(event_json).map_err(Into::into) }

#[uniffi::export]
pub fn marmot_groups() -> Result<String, QiqError> { api::marmot::marmot_groups().map_err(Into::into) }

#[uniffi::export]
pub fn marmot_messages(group_id_hex: String, limit: u32) -> Result<String, QiqError> { api::marmot::marmot_messages(group_id_hex, limit).map_err(Into::into) }

#[uniffi::export]
pub fn marmot_messages_page(group_id_hex: String, limit: u32, offset: u32) -> Result<String, QiqError> { api::marmot::marmot_messages_page(group_id_hex, limit, offset).map_err(Into::into) }

#[uniffi::export]
pub fn marmot_groups_needing_self_update(threshold_secs: u64) -> Result<Vec<String>, QiqError> { api::marmot::marmot_groups_needing_self_update(threshold_secs).map_err(Into::into) }

#[uniffi::export]
pub fn marmot_self_update(group_id_hex: String) -> Result<String, QiqError> { api::marmot::marmot_self_update(group_id_hex).map_err(Into::into) }

#[uniffi::export]
pub fn marmot_merge_pending_commit(group_id_hex: String) -> Result<(), QiqError> { api::marmot::marmot_merge_pending_commit(group_id_hex).map_err(Into::into) }

#[uniffi::export]
pub fn marmot_clear_pending_commit(group_id_hex: String) -> Result<(), QiqError> { api::marmot::marmot_clear_pending_commit(group_id_hex).map_err(Into::into) }

#[uniffi::export]
pub fn marmot_encrypt_media(group_id_hex: String, data: Vec<u8>, mime_type: String, filename: String, output_path: String) -> Result<String, QiqError> { api::marmot::marmot_encrypt_media(group_id_hex, data, mime_type, filename, output_path).map_err(Into::into) }

#[uniffi::export]
pub fn marmot_decrypt_media(group_id_hex: String, imeta: Vec<String>, data: Vec<u8>) -> Result<Vec<u8>, QiqError> { api::marmot::marmot_decrypt_media(group_id_hex, imeta, data).map_err(Into::into) }

#[uniffi::export]
pub fn nip19_decode(bech32_str: String) -> Result<String, QiqError> { api::nip19::nip19_decode(bech32_str).map_err(Into::into) }

#[uniffi::export]
pub fn nip19_decode_tlv(bech32_str: String) -> Result<String, QiqError> { api::nip19::nip19_decode_tlv(bech32_str).map_err(Into::into) }

#[uniffi::export]
pub fn nip19_encode_pubkey(pubkey_hex: String) -> Result<String, QiqError> { api::nip19::nip19_encode_pubkey(pubkey_hex).map_err(Into::into) }

#[uniffi::export]
pub fn nip19_encode_privkey(privkey_hex: String) -> Result<String, QiqError> { api::nip19::nip19_encode_privkey(privkey_hex).map_err(Into::into) }

#[uniffi::export]
pub fn nip19_encode_note(event_id_hex: String) -> Result<String, QiqError> { api::nip19::nip19_encode_note(event_id_hex).map_err(Into::into) }

#[uniffi::export]
pub fn encode_basic_bech32(hex_str: String, prefix: String) -> Result<String, QiqError> { api::nip19::encode_basic_bech32(hex_str, prefix).map_err(Into::into) }

#[uniffi::export]
pub fn nip19_encode_naddr(kind: u16, pubkey_hex: String, identifier: String) -> Result<String, QiqError> { api::nip19::nip19_encode_naddr(kind, pubkey_hex, identifier).map_err(Into::into) }

#[uniffi::export]
pub fn nip19_encode_nevent(event_id_hex: String, author_hex: Option<String>) -> Result<String, QiqError> { api::nip19::nip19_encode_nevent(event_id_hex, author_hex).map_err(Into::into) }

#[uniffi::export]
pub fn nip19_encode_nprofile(pubkey_hex: String) -> Result<String, QiqError> { api::nip19::nip19_encode_nprofile(pubkey_hex).map_err(Into::into) }

#[uniffi::export]
pub fn nip44_encrypt(content: String, sender_sk_hex: String, receiver_pk_hex: String) -> Result<String, QiqError> { api::nip44::nip44_encrypt(content, sender_sk_hex, receiver_pk_hex).map_err(Into::into) }

#[uniffi::export]
pub fn nip44_decrypt(payload: String, receiver_sk_hex: String, sender_pk_hex: String) -> Result<String, QiqError> { api::nip44::nip44_decrypt(payload, receiver_sk_hex, sender_pk_hex).map_err(Into::into) }

#[uniffi::export]
pub fn nip04_decrypt(payload: String, receiver_sk_hex: String, sender_pk_hex: String) -> Result<String, QiqError> { api::nip44::nip04_decrypt(payload, receiver_sk_hex, sender_pk_hex).map_err(Into::into) }

#[uniffi::export]
pub fn validate_nwc_uri(uri: String) -> bool { api::nwc::validate_nwc_uri(uri) }

#[uniffi::export]
pub fn parse_nwc_uri(uri: String) -> Result<String, QiqError> { api::nwc::parse_nwc_uri(uri).map_err(Into::into) }

#[uniffi::export]
pub async fn nwc_pay_invoice(nwc_uri: String, invoice: String) -> Result<String, QiqError> { on_rt(async move { api::nwc::nwc_pay_invoice(nwc_uri, invoice).await }).await }

#[uniffi::export]
pub async fn nwc_lookup_invoice(nwc_uri: String, invoice: String) -> Result<String, QiqError> { on_rt(async move { api::nwc::nwc_lookup_invoice(nwc_uri, invoice).await }).await }

#[uniffi::export]
pub async fn nwc_get_balance(nwc_uri: String) -> Result<String, QiqError> { on_rt(async move { api::nwc::nwc_get_balance(nwc_uri).await }).await }

#[uniffi::export]
pub async fn nwc_make_invoice(nwc_uri: String, amount_msats: u64, description: Option<String>) -> Result<String, QiqError> { on_rt(async move { api::nwc::nwc_make_invoice(nwc_uri, amount_msats, description).await }).await }

#[uniffi::export]
pub async fn nwc_list_transactions(nwc_uri: String, limit: Option<u64>, offset: Option<u64>) -> Result<String, QiqError> { on_rt(async move { api::nwc::nwc_list_transactions(nwc_uri, limit, offset).await }).await }

#[uniffi::export]
pub async fn init_client(relay_urls: Vec<String>, private_key_hex: Option<String>, db_path: Option<String>, discovery_relays: Vec<String>) -> Result<(), QiqError> { on_rt(async move { api::relay::init_client(relay_urls, private_key_hex, db_path, discovery_relays).await }).await }

#[uniffi::export]
pub async fn connect_relays() -> Result<(), QiqError> { on_rt(async move { api::relay::connect_relays().await }).await }

#[uniffi::export]
pub async fn wait_for_ready(timeout_secs: u32) -> Result<u32, QiqError> { on_rt(async move { api::relay::wait_for_ready(timeout_secs).await }).await }

#[uniffi::export]
pub async fn disconnect_relays() -> Result<(), QiqError> { on_rt(async move { api::relay::disconnect_relays().await }).await }

#[uniffi::export]
pub async fn shutdown_client() -> Result<(), QiqError> { on_rt(async move { api::relay::shutdown_client().await }).await }

#[uniffi::export]
pub async fn update_signer(private_key_hex: String) -> Result<(), QiqError> { on_rt(async move { api::relay::update_signer(private_key_hex).await }).await }

#[uniffi::export]
pub async fn is_client_initialized() -> Result<bool, QiqError> { on_rt_plain(async move { api::relay::is_client_initialized().await }).await }

#[uniffi::export]
pub async fn add_relay(url: String) -> Result<bool, QiqError> { on_rt(async move { api::relay::add_relay(url).await }).await }

#[uniffi::export]
pub async fn add_relay_with_flags(url: String, read: bool, write: bool) -> Result<bool, QiqError> { on_rt(async move { api::relay::add_relay_with_flags(url, read, write).await }).await }

#[uniffi::export]
pub async fn remove_relay(url: String) -> Result<(), QiqError> { on_rt(async move { api::relay::remove_relay(url).await }).await }

#[uniffi::export]
pub async fn get_relay_list() -> Result<Vec<String>, QiqError> { on_rt(async move { api::relay::get_relay_list().await }).await }

#[uniffi::export]
pub async fn get_connected_relay_count() -> Result<u32, QiqError> { on_rt(async move { api::relay::get_connected_relay_count().await }).await }

#[uniffi::export]
pub async fn get_relay_status() -> Result<String, QiqError> { on_rt(async move { api::relay::get_relay_status().await }).await }

#[uniffi::export]
pub async fn stream_relay_status(sink: Arc<dyn EventSink>) -> Result<(), QiqError> { on_rt(async move { api::relay::stream_relay_status(StreamSink::new(sink)).await }).await }

#[uniffi::export]
pub async fn discover_and_connect_outbox_relays(pubkeys_hex: Vec<String>, max_outbox_relays: u32, min_relay_frequency: u32) -> Result<String, QiqError> { on_rt(async move { api::relay::discover_and_connect_outbox_relays(pubkeys_hex, max_outbox_relays as usize, min_relay_frequency as usize).await }).await }

#[uniffi::export]
pub async fn sync_events(filter_json: String) -> Result<String, QiqError> { on_rt(async move { api::relay::sync_events(filter_json).await }).await }

#[uniffi::export]
pub async fn fetch_events(filter_json: String, timeout_secs: u32) -> Result<String, QiqError> { on_rt(async move { api::relay::fetch_events(filter_json, timeout_secs).await }).await }

#[uniffi::export]
pub async fn fetch_counts_from_relays(note_ids: Vec<String>, user_pubkey_hex: Option<String>) -> Result<String, QiqError> { on_rt(async move { api::relay::fetch_counts_from_relays(note_ids, user_pubkey_hex).await }).await }

#[uniffi::export]
pub async fn stream_interaction_counts(note_ids: Vec<String>, user_pubkey_hex: Option<String>, sink: Arc<dyn EventSink>) -> Result<(), QiqError> { on_rt(async move { api::relay::stream_interaction_counts(note_ids, user_pubkey_hex, StreamSink::new(sink)).await }).await }

#[uniffi::export]
pub async fn fetch_event_by_id(event_id: String, timeout_secs: u32) -> Result<Option<String>, QiqError> { on_rt(async move { api::relay::fetch_event_by_id(event_id, timeout_secs).await }).await }

#[uniffi::export]
pub async fn fetch_events_by_ids(event_ids: Vec<String>, timeout_secs: u32) -> Result<String, QiqError> { on_rt(async move { api::relay::fetch_events_by_ids(event_ids, timeout_secs).await }).await }

#[uniffi::export]
pub async fn fetch_events_multi_filter(filters_json: String, timeout_secs: u32) -> Result<String, QiqError> { on_rt(async move { api::relay::fetch_events_multi_filter(filters_json, timeout_secs).await }).await }

#[uniffi::export]
pub async fn send_event(event_json: String) -> Result<String, QiqError> { on_rt(async move { api::relay::send_event(event_json).await }).await }

#[uniffi::export]
pub async fn send_event_to(event_json: String, relay_urls: Vec<String>) -> Result<String, QiqError> { on_rt(async move { api::relay::send_event_to(event_json, relay_urls).await }).await }

#[uniffi::export]
pub async fn broadcast_events(events_json: String, relay_urls: Option<Vec<String>>) -> Result<String, QiqError> { on_rt(async move { api::relay::broadcast_events(events_json, relay_urls).await }).await }

#[uniffi::export]
pub async fn stream_broadcast_events(events_json: String, relay_urls: Option<Vec<String>>, sink: Arc<dyn EventSink>) -> Result<(), QiqError> { on_rt(async move { api::relay::stream_broadcast_events(events_json, relay_urls, StreamSink::new(sink)).await }).await }

#[uniffi::export]
pub async fn request_to_vanish(relay_urls: Vec<String>, reason: String) -> Result<String, QiqError> { on_rt(async move { api::relay::request_to_vanish(relay_urls, reason).await }).await }

#[uniffi::export]
pub async fn delete_events(event_ids: Vec<String>, reason: String) -> Result<String, QiqError> { on_rt(async move { api::relay::delete_events(event_ids, reason).await }).await }

#[uniffi::export]
pub async fn fetch_all_events_for_author(author_hex: String, sink: Arc<dyn EventSink>) -> Result<(), QiqError> { on_rt(async move { api::relay::fetch_all_events_for_author(author_hex, StreamSink::new(sink)).await }).await }

#[uniffi::export]
pub async fn fetch_profile_events(author_hex: String, kinds_str: String, since_timestamp: i64, sink: Arc<dyn EventSink>) -> Result<(), QiqError> { on_rt(async move { api::relay::fetch_profile_events(author_hex, kinds_str, since_timestamp, StreamSink::new(sink)).await }).await }

#[uniffi::export]
pub async fn subscribe_to_events(filter_json: String, sink: Arc<dyn EventSink>) -> Result<(), QiqError> { on_rt(async move { api::relay::subscribe_to_events(filter_json, StreamSink::new(sink)).await }).await }

#[uniffi::export]
pub async fn resolve_thread_root(note_id: String) -> Result<String, QiqError> { on_rt(async move { api::relay::resolve_thread_root(note_id).await }).await }

#[uniffi::export]
pub async fn sync_replies_recursive(note_id: String, max_depth: u32) -> Result<u32, QiqError> { on_rt(async move { api::relay::sync_replies_recursive(note_id, max_depth).await }).await }

#[uniffi::export]
pub async fn build_thread_structure(root_note_json: String, replies_json: String) -> Result<String, QiqError> { on_rt(async move { api::relay::build_thread_structure(root_note_json, replies_json).await }).await }

#[uniffi::export]
pub async fn fetch_thread_ancestors(event_ids: Vec<String>) -> Result<u32, QiqError> { on_rt(async move { api::relay::fetch_thread_ancestors(event_ids).await }).await }

#[uniffi::export]
pub async fn fetch_missing_references(event_ids: Vec<String>) -> Result<u32, QiqError> { on_rt(async move { api::relay::fetch_missing_references(event_ids).await }).await }

#[uniffi::export]
pub async fn merge_and_sort_notes(existing_json: String, incoming_json: String) -> Result<String, QiqError> { on_rt(async move { api::relay::merge_and_sort_notes(existing_json, incoming_json).await }).await }

#[uniffi::export]
pub async fn fetch_full_thread_local(note_id: String, current_user_pubkey_hex: Option<String>, muted_pubkeys: Vec<String>, muted_words: Vec<String>) -> Result<Option<String>, QiqError> { on_rt(async move { api::relay::fetch_full_thread_local(note_id, current_user_pubkey_hex, muted_pubkeys, muted_words).await }).await }

#[uniffi::export]
pub async fn fetch_full_thread(note_id: String, current_user_pubkey_hex: Option<String>, muted_pubkeys: Vec<String>, muted_words: Vec<String>) -> Result<String, QiqError> { on_rt(async move { api::relay::fetch_full_thread(note_id, current_user_pubkey_hex, muted_pubkeys, muted_words).await }).await }

#[uniffi::export]
pub async fn get_database_size_mb() -> Result<u64, QiqError> { on_rt(async move { api::relay::get_database_size_mb().await }).await }

#[uniffi::export]
pub async fn fetch_missing_profiles_for_events(events_json: String) -> Result<u32, QiqError> { on_rt(async move { api::relay::fetch_missing_profiles_for_events(events_json).await }).await }

#[uniffi::export]
pub async fn fetch_repost_originals(repost_event_ids_json: String) -> Result<u32, QiqError> { on_rt(async move { api::relay::fetch_repost_originals(repost_event_ids_json).await }).await }

#[uniffi::export]
pub async fn fetch_follower_counts(pubkey_hexes: Vec<String>) -> Result<String, QiqError> { on_rt(async move { api::relay::fetch_follower_counts(pubkey_hexes).await }).await }

#[uniffi::export]
pub async fn fetch_events_from_relays(filter_json: String, relay_urls: Vec<String>, timeout_secs: u32) -> Result<String, QiqError> { on_rt(async move { api::relay::fetch_events_from_relays(filter_json, relay_urls, timeout_secs).await }).await }
