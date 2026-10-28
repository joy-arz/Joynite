use serde::{Deserialize, Serialize};
use std::collections::BTreeMap;

pub fn now() -> f64 {
    std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .unwrap_or_default()
        .as_secs_f64()
        - 978_307_200.0
}
#[derive(Clone, Debug, Default, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", default)]
pub struct CompatibilityLaunch {
    pub executable: String,
    pub arguments: Vec<String>,
    pub environment: BTreeMap<String, String>,
    pub working_directory: String,
    pub label: String,
}
#[derive(Clone, Debug, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", default)]
pub struct Game {
    pub id: String,
    pub name: String,
    pub store: String,
    pub launch_kind: String,
    pub launch_target: String,
    pub install_path: String,
    pub store_id: String,
    pub summary: String,
    pub developer: String,
    pub genres: Vec<String>,
    pub release_date: String,
    pub artwork: String,
    pub background_artwork: Option<String>,
    pub cached_artwork: Option<String>,
    pub cached_landscape: Option<String>,
    pub cached_background: Option<String>,
    pub compatibility: Option<CompatibilityLaunch>,
    pub hidden: Option<bool>,
    pub pending_uninstall: Option<bool>,
    pub store_url: String,
    pub metadata_source: String,
    pub metadata_updated: Option<f64>,
    pub favorite: bool,
    pub last_played: Option<f64>,
    pub added_at: f64,
    #[serde(flatten)]
    pub extra: BTreeMap<String, serde_json::Value>,
}
impl Default for Game {
    fn default() -> Self {
        Self {
            id: String::new(),
            name: String::new(),
            store: "Mac".into(),
            launch_kind: "application".into(),
            launch_target: String::new(),
            install_path: String::new(),
            store_id: String::new(),
            summary: String::new(),
            developer: String::new(),
            genres: vec![],
            release_date: String::new(),
            artwork: String::new(),
            background_artwork: None,
            cached_artwork: None,
            cached_landscape: None,
            cached_background: None,
            compatibility: None,
            hidden: None,
            pending_uninstall: None,
            store_url: String::new(),
            metadata_source: String::new(),
            metadata_updated: None,
            favorite: false,
            last_played: None,
            added_at: now(),
            extra: BTreeMap::new(),
        }
    }
}
#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct Library {
    pub version: u32,
    pub games: Vec<Game>,
    pub folders: Vec<String>,
}
impl Default for Library {
    fn default() -> Self {
        Self {
            version: 1,
            games: vec![],
            folders: vec![],
        }
    }
}
pub fn normalized(value: &str) -> String {
    value
        .chars()
        .filter(|c| c.is_alphanumeric())
        .flat_map(char::to_lowercase)
        .collect()
}
pub fn hash(value: &str) -> String {
    use sha2::{Digest, Sha256};
    format!("{:x}", Sha256::digest(value.as_bytes()))
}
