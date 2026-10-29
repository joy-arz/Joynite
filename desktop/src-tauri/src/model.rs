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
    pub metadata_overrides: Option<BTreeMap<String, String>>,
    pub automatic_metadata: Option<BTreeMap<String, String>>,
    pub custom_artwork: Option<String>,
    pub custom_landscape: Option<String>,
    pub custom_background: Option<String>,
    pub hidden: Option<bool>,
    pub pending_uninstall: Option<bool>,
    pub store_url: String,
    pub metadata_source: String,
    pub metadata_updated: Option<f64>,
    pub favorite: bool,
    pub launch_count: u32,
    pub last_played: Option<f64>,
    pub added_at: f64,
    #[serde(flatten)]
    pub extra: BTreeMap<String, serde_json::Value>,
}
impl Game {
    pub fn record_launch(&mut self) {
        self.launch_count = self.launch_count.saturating_add(1);
        self.last_played = Some(now());
    }
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
            metadata_overrides: None,
            automatic_metadata: None,
            custom_artwork: None,
            custom_landscape: None,
            custom_background: None,
            hidden: None,
            pending_uninstall: None,
            store_url: String::new(),
            metadata_source: String::new(),
            metadata_updated: None,
            favorite: false,
            launch_count: 0,
            last_played: None,
            added_at: now(),
            extra: BTreeMap::new(),
        }
    }
}
impl Game {
    pub fn metadata_values(&self) -> BTreeMap<String, String> {
        BTreeMap::from([
            ("name".into(), self.name.clone()),
            ("summary".into(), self.summary.clone()),
            ("developer".into(), self.developer.clone()),
            ("releaseDate".into(), self.release_date.clone()),
            ("genres".into(), self.genres.join(", ")),
            ("source".into(), self.metadata_source.clone()),
        ])
    }
    pub fn apply_values(&mut self, values: &BTreeMap<String, String>) {
        if let Some(value) = values.get("name") {
            self.name = value.clone()
        }
        if let Some(value) = values.get("summary") {
            self.summary = value.clone()
        }
        if let Some(value) = values.get("developer") {
            self.developer = value.clone()
        }
        if let Some(value) = values.get("releaseDate") {
            self.release_date = value.clone()
        }
        if let Some(value) = values.get("genres") {
            self.genres = value
                .split(',')
                .map(str::trim)
                .filter(|s| !s.is_empty())
                .map(String::from)
                .collect()
        }
    }
    pub fn refresh_source(&mut self) {
        let base = self
            .automatic_metadata
            .as_ref()
            .and_then(|m| m.get("source"))
            .cloned()
            .unwrap_or_default();
        let custom = self
            .metadata_overrides
            .as_ref()
            .is_some_and(|m| !m.is_empty())
            || self.custom_artwork.is_some()
            || self.custom_landscape.is_some()
            || self.custom_background.is_some();
        self.metadata_source = if custom {
            if base.is_empty() {
                "Custom".into()
            } else {
                format!("{base} + custom")
            }
        } else {
            base
        };
    }
    pub fn apply_custom(&mut self, changes: BTreeMap<String, String>, reset: bool) {
        let automatic = self
            .automatic_metadata
            .clone()
            .unwrap_or_else(|| self.metadata_values());
        let mut overrides = if reset {
            BTreeMap::new()
        } else {
            self.metadata_overrides.clone().unwrap_or_default()
        };
        for (key, value) in changes {
            if ["name", "summary", "developer", "releaseDate", "genres"].contains(&key.as_str()) {
                overrides.insert(key, value);
            }
        }
        self.apply_values(&automatic);
        self.apply_values(&overrides);
        self.automatic_metadata = Some(automatic);
        self.metadata_overrides = Some(overrides);
        self.refresh_source();
        self.metadata_updated = Some(now());
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

pub fn is_launcher_id(id: &str) -> bool {
    let id = id.to_ascii_lowercase();
    id.starts_with("io.github.joy-arz.joynite") || id.starts_with("io.github.joy-arz.playnite")
}
#[cfg(test)]
mod local_launch_tests {
    use super::*;
    #[test]
    fn counts_only_explicit_joynite_launches_and_migrates_legacy_records() {
        let mut game: Game =
            serde_json::from_str(r#"{"id":"legacy","name":"Legacy","lastPlayed":900000000}"#)
                .unwrap();
        assert_eq!(game.launch_count, 0);
        game.record_launch();
        assert_eq!(game.launch_count, 1);
        game.launch_count = u32::MAX;
        game.record_launch();
        assert_eq!(game.launch_count, u32::MAX);
        let restored: Game = serde_json::from_slice(&serde_json::to_vec(&game).unwrap()).unwrap();
        assert_eq!(restored.launch_count, u32::MAX);
    }
}
