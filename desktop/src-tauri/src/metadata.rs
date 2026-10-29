use crate::model::{hash, normalized, now, Game};
use regex::Regex;
use serde::{Deserialize, Serialize};
use serde_json::Value;
use std::{
    fs,
    io::{Cursor, Read},
    path::{Path, PathBuf},
    sync::OnceLock,
};
#[derive(Clone, Serialize, Deserialize)]
pub struct Publisher {
    pub id: String,
    pub aliases: Vec<String>,
    pub name: String,
    pub summary: String,
    pub developer: String,
    pub url: String,
    pub source: String,
    pub artwork: String,
    #[serde(default)]
    pub background: String,
    pub genres: Vec<String>,
}
fn publisher_catalog() -> &'static [Publisher] {
    static CATALOG: OnceLock<Vec<Publisher>> = OnceLock::new();
    CATALOG.get_or_init(|| {
        serde_json::from_str(include_str!("../publishers.json"))
            .expect("validated bundled publisher catalog")
    })
}
pub fn publishers() -> Vec<Publisher> {
    publisher_catalog().to_vec()
}
pub fn publisher(name: &str) -> Option<Publisher> {
    let name = normalized(name);
    publisher_catalog()
        .iter()
        .find(|p| p.aliases.iter().any(|a| normalized(a) == name))
        .cloned()
}
#[derive(Clone, Default, Serialize)]
pub struct Details {
    pub name: String,
    pub summary: String,
    pub developer: String,
    pub release_date: String,
    pub artwork: String,
    pub background: String,
    pub url: String,
    pub source: String,
    pub genres: Vec<String>,
    pub steam_id: String,
}
impl Details {
    pub fn partial(&self) -> bool {
        self.summary.is_empty()
            || self.developer.is_empty()
            || self.release_date.is_empty()
            || self.genres.is_empty()
            || self.artwork.is_empty()
            || self.background.is_empty()
    }
    pub fn fill_missing(&mut self, other: &Details) {
        let mut used = false;
        for (value, fallback) in [
            (&mut self.name, &other.name),
            (&mut self.summary, &other.summary),
            (&mut self.developer, &other.developer),
            (&mut self.release_date, &other.release_date),
            (&mut self.artwork, &other.artwork),
            (&mut self.background, &other.background),
            (&mut self.url, &other.url),
        ] {
            if value.is_empty() && !fallback.is_empty() {
                *value = fallback.clone();
                used = true;
            }
        }
        if self.genres.is_empty() && !other.genres.is_empty() {
            self.genres = other.genres.clone();
            used = true;
        }
        if !other.steam_id.is_empty() {
            self.steam_id = other.steam_id.clone();
            used = true;
        }
        if used && !other.source.is_empty() && !self.source.contains(&other.source) {
            self.source = if self.source.is_empty() {
                other.source.clone()
            } else {
                format!("{} + {}", self.source, other.source)
            };
        }
    }
    pub fn apply(&self, game: &mut Game) {
        let mut automatic = game
            .automatic_metadata
            .clone()
            .unwrap_or_else(|| game.metadata_values());
        if !self.name.is_empty()
            && normalized(&game.name)
                == normalized(&crate::launch_plan::display_title(Path::new(
                    &game.launch_target,
                )))
        {
            automatic.insert("name".into(), self.name.clone());
        }
        if !self.summary.is_empty() {
            automatic.insert("summary".into(), self.summary.clone());
        }
        if !self.developer.is_empty() {
            automatic.insert("developer".into(), self.developer.clone());
        }
        if !self.release_date.is_empty() {
            automatic.insert("releaseDate".into(), self.release_date.clone());
        }
        if !self.genres.is_empty() {
            automatic.insert("genres".into(), self.genres.join(", "));
        }
        automatic.insert("source".into(), self.source.clone());
        game.apply_values(&automatic);
        game.apply_values(&game.metadata_overrides.clone().unwrap_or_default());
        game.automatic_metadata = Some(automatic);
        if !self.artwork.is_empty() {
            game.artwork = self.artwork.clone()
        }
        if !self.background.is_empty() {
            game.background_artwork = Some(self.background.clone())
        }
        if !self.url.is_empty() {
            game.store_url = self.url.clone()
        }
        game.refresh_source();
        if self.steam_id.parse::<u64>().is_ok() {
            game.extra.insert(
                "metadataSteamId".into(),
                serde_json::Value::String(self.steam_id.clone()),
            );
        }
        game.metadata_updated = Some(now());
    }
}
pub fn allowed(host: &str) -> bool {
    [
        "steampowered.com",
        "gog.com",
        "epicgames.com",
        "itch.io",
        "roblox.com",
        "playvalorant.com",
        "hoyoverse.com",
        "leagueoflegends.com",
        "minecraft.net",
    ]
    .iter()
    .any(|d| host == *d || host.ends_with(&format!(".{d}")))
        || publisher_catalog().iter().any(|p| {
            reqwest::Url::parse(&p.url)
                .ok()
                .and_then(|url| url.host_str().map(String::from))
                .is_some_and(|domain| host == domain || host.ends_with(&format!(".{domain}")))
        })
}
fn match_key(title: &str) -> String {
    normalized(
        &title
            .replace(['é', 'è', 'ê', 'ë'], "e")
            .replace(['á', 'à', 'â', 'ä'], "a")
            .replace(['ö', 'ô'], "o")
            .replace(['ü', 'û'], "u"),
    )
}
fn steam_match(items: &Value, query: &str) -> Option<u64> {
    let items = items.as_array()?;
    let key = match_key(query);
    if key.is_empty() {
        return None;
    }
    let exact: Vec<_> = items
        .iter()
        .filter(|i| match_key(i["name"].as_str().unwrap_or("")) == key)
        .collect();
    if exact.len() == 1 {
        return exact[0]["id"].as_u64();
    }
    if !exact.is_empty() || key.len() < 8 || query.split_whitespace().count() < 2 {
        return None;
    }
    // A unique subtitle match handles packaged names such as Expedition33.
    // Ambiguous editions/sequels remain manual; never choose the first result.
    let suffix: Vec<_> = items
        .iter()
        .filter(|i| {
            let name = i["name"].as_str().unwrap_or("");
            let words: Vec<_> = name
                .split(|c: char| !c.is_alphanumeric())
                .filter(|s| !s.is_empty())
                .collect();
            (0..words.len()).any(|index| match_key(&words[index..].join(" ")) == key)
        })
        .collect();
    if suffix.len() == 1 {
        suffix[0]["id"].as_u64()
    } else {
        None
    }
}
pub struct Client {
    http: reqwest::blocking::Client,
}
impl Client {
    pub fn new() -> Result<Self, String> {
        Ok(Self {
            http: reqwest::blocking::Client::builder()
                .timeout(std::time::Duration::from_secs(18))
                .user_agent(concat!(
                    "Joynite/",
                    env!("CARGO_PKG_VERSION"),
                    " (+https://github.com/joy-arz/Joynite)"
                ))
                .redirect(reqwest::redirect::Policy::limited(3))
                .build()
                .map_err(|e| e.to_string())?,
        })
    }
    fn request(&self, url: &str, store: bool) -> Result<Vec<u8>, String> {
        if std::env::var("JOYNITE_OFFLINE")
            .or_else(|_| std::env::var("PLAYNITE_OFFLINE"))
            .as_deref()
            == Ok("1")
        {
            return Err("Offline mode: saved metadata remains available".into());
        }
        let parsed = reqwest::Url::parse(url).map_err(|e| e.to_string())?;
        if parsed.scheme() != "https"
            || parsed.host_str().is_none()
            || store && !allowed(parsed.host_str().unwrap_or(""))
        {
            return Err("Unsupported HTTPS provider".into());
        }
        let response = self
            .http
            .get(parsed)
            .send()
            .map_err(|e| e.to_string())?
            .error_for_status()
            .map_err(|e| e.to_string())?;
        if response.url().scheme() != "https"
            || store && !allowed(response.url().host_str().unwrap_or(""))
        {
            return Err("Unsupported provider redirect".into());
        }
        let mut bytes = Vec::new();
        response
            .take(24_000_001)
            .read_to_end(&mut bytes)
            .map_err(|e| e.to_string())?;
        if bytes.len() > 24_000_000 {
            return Err("Provider response exceeds 24 MB".into());
        }
        Ok(bytes)
    }
    pub fn search(&self, name: &str) -> Result<Value, String> {
        let mut url = reqwest::Url::parse("https://store.steampowered.com/api/storesearch/")
            .map_err(|e| e.to_string())?;
        url.query_pairs_mut()
            .extend_pairs([("term", name), ("l", "english"), ("cc", "us")]);
        let data: Value = serde_json::from_slice(&self.request(url.as_str(), true)?)
            .map_err(|e| e.to_string())?;
        Ok(data["items"].clone())
    }
    pub fn steam(&self, id: &str) -> Result<Details, String> {
        if id.parse::<u64>().is_err() {
            return Err("Steam app ID must be numeric".into());
        }
        let data: Value = serde_json::from_slice(&self.request(
            &format!("https://store.steampowered.com/api/appdetails?appids={id}&l=english&cc=us"),
            true,
        )?)
        .map_err(|e| e.to_string())?;
        parse_steam(&data, id)
    }
    pub fn page(&self, url: &str) -> Result<Details, String> {
        let parsed = reqwest::Url::parse(url).map_err(|e| e.to_string())?;
        if parsed.host_str() == Some("store.steampowered.com") {
            let parts: Vec<_> = parsed
                .path_segments()
                .map(|s| s.collect())
                .unwrap_or_default();
            if let Some(index) = parts.iter().position(|p| *p == "app") {
                if let Some(id) = parts.get(index + 1) {
                    return self.steam(id);
                }
            }
        }
        let html = String::from_utf8(self.request(url, true)?).map_err(|e| e.to_string())?;
        parse_html(&html, url)
    }
    fn gog(&self, game: &Game) -> Result<Details, String> {
        let mut url =
            reqwest::Url::parse("https://catalog.gog.com/v1/catalog").map_err(|e| e.to_string())?;
        url.query_pairs_mut().extend_pairs([
            ("query", game.name.as_str()),
            ("limit", "10"),
            ("countryCode", "US"),
            ("locale", "en-US"),
            ("currencyCode", "USD"),
        ]);
        let data: Value = serde_json::from_slice(&self.request(url.as_str(), true)?)
            .map_err(|e| e.to_string())?;
        let matches: Vec<_> = data["products"]
            .as_array()
            .map(|a| {
                a.iter()
                    .filter(|i| {
                        normalized(i["title"].as_str().unwrap_or("")) == normalized(&game.name)
                    })
                    .collect()
            })
            .unwrap_or_default();
        if matches.len() == 1 {
            if let Some(url) = matches[0]["storeLink"].as_str() {
                return self.page(url);
            }
        }
        Err("No unique GOG catalog match".into())
    }
    pub fn automatic(&self, game: &Game) -> Result<Details, String> {
        if let Some(entry) = publisher(&crate::launch_plan::clean_title(&game.name)) {
            let mut data = Details {
                name: entry.name,
                summary: entry.summary,
                developer: entry.developer,
                artwork: entry.artwork,
                background: entry.background,
                url: entry.url,
                source: entry.source,
                genres: entry.genres,
                ..Default::default()
            };
            if data.partial() {
                if let Ok(remote) = self.page(&data.url) {
                    data.fill_missing(&remote);
                }
            }
            return Ok(data);
        }
        if game.store == "Steam" && !game.store_id.is_empty() {
            return self.steam(&game.store_id);
        }
        let mut primary = if !game.store_url.is_empty() {
            self.page(&game.store_url).ok()
        } else {
            None
        };
        if primary.is_none() && game.store == "GOG" {
            primary = self.gog(game).ok();
        }
        if primary.as_ref().is_none_or(Details::partial) {
            let name = primary
                .as_ref()
                .map(|p| p.name.as_str())
                .filter(|n| !n.is_empty())
                .unwrap_or(&game.name);
            let query = crate::launch_plan::clean_title(name);
            if let Ok(items) = self.search(&query) {
                if let Some(id) = steam_match(&items, &query) {
                    if let Ok(fallback) = self.steam(&id.to_string()) {
                        if let Some(primary) = primary.as_mut() {
                            primary.fill_missing(&fallback);
                        } else {
                            primary = Some(fallback);
                        }
                    }
                }
            }
        }
        primary.ok_or_else(|| {
            format!(
                "No unique metadata match for {}. Choose a search result or publisher entry.",
                game.name
            )
        })
    }
    pub fn cache(
        &self,
        remote: &str,
        root: &Path,
        game_id: &str,
        role: &str,
    ) -> Result<String, String> {
        let key = hash(remote) + ".png";
        let folder = root.join("Media").join(hash(game_id));
        let path = folder.join(&key);
        if let Ok((w, h)) = image::image_dimensions(&path) {
            if aspect_fits(w, h, role) {
                return Ok(key);
            }
        }
        let bytes = self.request(remote, false)?;
        let mut reader = image::ImageReader::new(Cursor::new(bytes))
            .with_guessed_format()
            .map_err(|e| e.to_string())?;
        let mut limits = image::Limits::default();
        limits.max_image_width = Some(8192);
        limits.max_image_height = Some(8192);
        limits.max_alloc = Some(128 * 1024 * 1024);
        reader.limits(limits);
        let image = reader.decode().map_err(|e| e.to_string())?;
        if !aspect_fits(image.width(), image.height(), role) {
            return Err(format!("Image does not fit {role} aspect ratio"));
        }
        let size = if role == "portrait" {
            1200
        } else if role == "landscape" {
            1200
        } else {
            1600
        };
        fs::create_dir_all(&folder).map_err(|e| e.to_string())?;
        let temporary = folder.join(format!("{key}.tmp"));
        image
            .thumbnail(size.min(image.width()), size.min(image.height()))
            .save_with_format(&temporary, image::ImageFormat::Png)
            .map_err(|e| e.to_string())?;
        fs::rename(temporary, path).map_err(|e| e.to_string())?;
        Ok(key)
    }
    pub fn artwork(&self, game: &mut Game, root: &Path) {
        let mut id = if game.store == "Steam" {
            game.store_id.clone()
        } else {
            String::new()
        };
        if id.is_empty() {
            id = game
                .extra
                .get("metadataSteamId")
                .and_then(|v| v.as_str())
                .unwrap_or("")
                .into();
        }
        if id.is_empty() {
            if let Ok(url) = reqwest::Url::parse(&game.store_url) {
                if url.host_str() == Some("store.steampowered.com") {
                    let parts: Vec<_> =
                        url.path_segments().map(|s| s.collect()).unwrap_or_default();
                    if let Some(i) = parts.iter().position(|p| *p == "app") {
                        id = parts.get(i + 1).unwrap_or(&"").to_string()
                    }
                }
            }
        }
        if !game.artwork.is_empty() {
            if let Ok(key) = self.cache(&game.artwork, root, &game.id, "landscape") {
                game.cached_landscape = Some(key)
            }
        }
        let mut portraits = vec![];
        if id.parse::<u64>().is_ok() {
            for suffix in ["library_600x900_2x.jpg", "library_600x900.jpg"] {
                portraits.push(format!(
                    "https://cdn.akamai.steamstatic.com/steam/apps/{id}/{suffix}"
                ))
            }
        }
        portraits.sort_by_key(|u| {
            !root
                .join("Media")
                .join(hash(&game.id))
                .join(hash(u) + ".png")
                .exists()
        });
        for url in portraits {
            if let Ok(key) = self.cache(&url, root, &game.id, "portrait") {
                game.cached_artwork = Some(key);
                break;
            }
        }
        if id.is_empty() && !game.artwork.is_empty() {
            if let Ok(key) = self.cache(&game.artwork, root, &game.id, "any") {
                game.cached_artwork = Some(key);
            }
        }
        if game.cached_artwork.is_none() {
            game.cached_artwork = game.cached_landscape.clone();
            if game.cached_artwork.is_none() && !game.artwork.is_empty() {
                game.cached_artwork = self.cache(&game.artwork, root, &game.id, "any").ok();
            }
        }
        if let Some(background) = &game.background_artwork {
            if !background.is_empty() {
                if let Ok(key) = self.cache(background, root, &game.id, "background") {
                    game.cached_background = Some(key)
                }
            }
        }
    }
}
pub fn import_image(path: &Path, root: &Path, game_id: &str) -> Result<String, String> {
    let size = fs::metadata(path).map_err(|e| e.to_string())?.len();
    if size == 0 || size > 24_000_000 {
        return Err("Choose an image smaller than 24 MB".into());
    }
    let bytes = fs::read(path).map_err(|e| e.to_string())?;
    let mut reader = image::ImageReader::new(Cursor::new(&bytes))
        .with_guessed_format()
        .map_err(|e| e.to_string())?;
    let mut limits = image::Limits::default();
    limits.max_image_width = Some(8192);
    limits.max_image_height = Some(8192);
    limits.max_alloc = Some(128 * 1024 * 1024);
    reader.limits(limits);
    let image = reader.decode().map_err(|e| e.to_string())?;
    use sha2::{Digest, Sha256};
    let key = format!("{:x}.png", Sha256::digest(&bytes));
    let folder = root.join("Media").join(hash(game_id));
    fs::create_dir_all(&folder).map_err(|e| e.to_string())?;
    let temporary = folder.join(format!("{key}.tmp"));
    image
        .thumbnail(1600.min(image.width()), 1600.min(image.height()))
        .save_with_format(&temporary, image::ImageFormat::Png)
        .map_err(|e| e.to_string())?;
    fs::rename(temporary, folder.join(&key)).map_err(|e| e.to_string())?;
    Ok(key)
}
pub fn aspect_fits(w: u32, h: u32, role: &str) -> bool {
    if w < 1 || h < 1 {
        return false;
    }
    let ratio = w as f64 / h as f64;
    match role {
        "portrait" => (0.52..=0.85).contains(&ratio),
        "landscape" => (1.3..=2.7).contains(&ratio),
        _ => true,
    }
}
pub fn cache_file(root: &Path, game: &Game, key: &Option<String>) -> Option<PathBuf> {
    let key = key.as_ref()?;
    if key.len() != 68
        || !key.ends_with(".png")
        || !key.as_bytes()[..64].iter().all(|b| b.is_ascii_hexdigit())
    {
        return None;
    }
    let path = root.join("Media").join(hash(&game.id)).join(key);
    path.is_file().then_some(path)
}
pub fn parse_steam(data: &Value, id: &str) -> Result<Details, String> {
    let item = &data[id];
    if item["success"] != true {
        return Err(format!("Steam has no details for {id}"));
    }
    let v = &item["data"];
    Ok(Details {
        steam_id: id.into(),
        name: v["name"].as_str().unwrap_or("").into(),
        summary: plain(v["short_description"].as_str().unwrap_or("")),
        developer: v["developers"]
            .as_array()
            .map(|a| {
                a.iter()
                    .filter_map(Value::as_str)
                    .collect::<Vec<_>>()
                    .join(", ")
            })
            .unwrap_or_default(),
        release_date: v["release_date"]["date"].as_str().unwrap_or("").into(),
        artwork: v["header_image"].as_str().unwrap_or("").into(),
        background: v["screenshots"][0]["path_full"]
            .as_str()
            .or(v["background_raw"].as_str())
            .unwrap_or("")
            .into(),
        url: format!("https://store.steampowered.com/app/{id}/"),
        source: "Steam".into(),
        genres: v["genres"]
            .as_array()
            .map(|a| {
                a.iter()
                    .filter_map(|g| g["description"].as_str().map(String::from))
                    .collect()
            })
            .unwrap_or_default(),
    })
}
pub fn plain(value: &str) -> String {
    static TAG: OnceLock<Regex> = OnceLock::new();
    let mut s = TAG
        .get_or_init(|| Regex::new("<[^>]+>").expect("static regex"))
        .replace_all(value, " ")
        .into_owned();
    for (from, to) in [
        ("&amp;", "&"),
        ("&quot;", "\""),
        ("&#39;", "'"),
        ("&apos;", "'"),
        ("&lt;", "<"),
        ("&gt;", ">"),
        ("&nbsp;", " "),
    ] {
        s = s.replace(from, to)
    }
    s.split_whitespace().collect::<Vec<_>>().join(" ")
}
pub fn parse_html(html: &str, url: &str) -> Result<Details, String> {
    static TAG: OnceLock<Regex> = OnceLock::new();
    static ATTR: OnceLock<Regex> = OnceLock::new();
    let tags = TAG.get_or_init(|| Regex::new(r"(?is)<meta\s+[^>]*>").expect("static regex"));
    let attributes = ATTR.get_or_init(|| {
        Regex::new(r#"(?is)([\w:-]+)\s*=\s*(?:"([^"]*)"|'([^']*)')"#).expect("static regex")
    });
    let mut values = std::collections::HashMap::new();
    for tag in tags.find_iter(html) {
        let attrs: std::collections::HashMap<_, _> = attributes
            .captures_iter(tag.as_str())
            .map(|c| {
                (
                    c[1].to_lowercase(),
                    c.get(2)
                        .or_else(|| c.get(3))
                        .map(|m| m.as_str())
                        .unwrap_or("")
                        .to_owned(),
                )
            })
            .collect();
        if let (Some(key), Some(content)) = (
            attrs.get("property").or_else(|| attrs.get("name")),
            attrs.get("content"),
        ) {
            values.insert(key.to_lowercase(), plain(content));
        }
    }
    let name = values
        .get("og:title")
        .or_else(|| values.get("twitter:title"))
        .cloned()
        .unwrap_or_default();
    let summary = values
        .get("og:description")
        .or_else(|| values.get("description"))
        .cloned()
        .unwrap_or_default();
    if name.is_empty() || summary.is_empty() {
        return Err("This page exposes no game metadata".into());
    }
    let base = reqwest::Url::parse(url).map_err(|e| e.to_string())?;
    let artwork = values
        .get("og:image")
        .or_else(|| values.get("twitter:image"))
        .and_then(|p| base.join(p).ok())
        .filter(|u| u.scheme() == "https")
        .map(|u| u.to_string())
        .unwrap_or_default();
    Ok(Details {
        name,
        summary,
        artwork,
        url: url.into(),
        source: base.host_str().unwrap_or("Publisher").into(),
        ..Default::default()
    })
}
#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn custom_metadata_survives_refresh_reset_and_serialization() {
        let mut game = Game {
            name: "Original".into(),
            launch_target: "/game".into(),
            ..Default::default()
        };
        Details {
            summary: "Automatic".into(),
            developer: "Studio".into(),
            source: "Steam".into(),
            ..Default::default()
        }
        .apply(&mut game);
        game.apply_custom(
            std::collections::BTreeMap::from([
                ("name".into(), "Custom".into()),
                ("summary".into(), "".into()),
                ("launchTarget".into(), "/bad".into()),
            ]),
            false,
        );
        game.custom_artwork = Some("custom.png".into());
        Details {
            summary: "Updated".into(),
            developer: "New studio".into(),
            source: "GOG".into(),
            ..Default::default()
        }
        .apply(&mut game);
        assert_eq!(game.name, "Custom");
        assert_eq!(game.summary, "");
        assert_eq!(game.developer, "New studio");
        assert_eq!(game.launch_target, "/game");
        let mut restored: Game =
            serde_json::from_slice(&serde_json::to_vec(&game).unwrap()).unwrap();
        assert_eq!(restored.metadata_source, "GOG + custom");
        restored.apply_custom(Default::default(), true);
        assert_eq!(restored.name, "Original");
        assert_eq!(restored.summary, "Updated");
        assert!(restored.custom_artwork.is_some());
        restored.custom_artwork = None;
        restored.refresh_source();
        assert_eq!(restored.metadata_source, "GOG");
    }
    #[test]
    fn custom_images_are_copied_and_soft_fill_is_cached() {
        let temp = tempfile::tempdir().unwrap();
        let original = temp.path().join("original.png");
        image::RgbaImage::from_pixel(120, 40, image::Rgba([255, 100, 0, 255]))
            .save(&original)
            .unwrap();
        let key = import_image(&original, temp.path(), "fixture").unwrap();
        std::fs::remove_file(original).unwrap();
        let game = Game {
            id: "fixture".into(),
            ..Default::default()
        };
        let copied = cache_file(temp.path(), &game, &Some(key)).unwrap();
        assert_eq!(image::image_dimensions(&copied).unwrap(), (120, 40));
        let fill = image_fill(&copied).unwrap();
        assert!(fill.is_file());
        let dimensions = image::image_dimensions(&fill).unwrap();
        assert!(dimensions.0 <= 64 && dimensions.1 <= 64);
        assert_eq!(image_fill(&copied).unwrap(), fill);
    }
    #[test]
    fn three_aspect_roles() {
        assert!(aspect_fits(600, 900, "portrait"));
        assert!(!aspect_fits(1920, 1080, "portrait"));
        assert!(aspect_fits(460, 215, "landscape"));
        assert!(!aspect_fits(600, 900, "landscape"));
    }
    #[test]
    fn metadata_keeps_identity() {
        let data = serde_json::json!({"480":{"success":true,"data":{"name":"Fixture","short_description":"A &amp; B","screenshots":[{"path_full":"https://example.com/scene.jpg"}]}}});
        let meta = parse_steam(&data, "480").unwrap();
        let mut game = Game {
            id: "local".into(),
            favorite: true,
            ..Default::default()
        };
        meta.apply(&mut game);
        assert_eq!(game.id, "local");
        assert!(game.favorite);
        assert_eq!(game.summary, "A & B");
        assert!(game.background_artwork.is_some());
    }
    #[test]
    fn square_publisher_artwork_remains_available_offline() {
        let root = tempfile::tempdir().unwrap();
        let mut game = Game {
            id: "publisher-logo".into(),
            artwork: "cached-only-fixture".into(),
            ..Default::default()
        };
        let key = hash(&game.artwork) + ".png";
        let folder = root.path().join("Media").join(hash(&game.id));
        fs::create_dir_all(&folder).unwrap();
        image::RgbaImage::new(128, 128)
            .save(folder.join(&key))
            .unwrap();
        let client = Client::new().unwrap();
        client.artwork(&mut game, root.path());
        assert_eq!(game.cached_artwork, Some(key));
        assert!(cache_file(root.path(), &game, &game.cached_artwork).is_some());
    }
    #[test]
    fn publisher_offline() {
        for name in [
            "Roblox",
            "Valorant",
            "Genshin Impact",
            "EDOPro",
            "YGOPro",
            "YGOPro Percy",
            "YGOPro 2",
            "KoishiPro",
            "YGO Omega",
            "MDPro3",
        ] {
            assert!(!publisher(name).unwrap().summary.is_empty())
        }
        assert!(publisher("Roblox fake").is_none());
        for (name, id) in [
            ("edopro.exe", "edopro"),
            ("Project Ignis", "edopro"),
            ("ygopro_percy.exe", "ygopro-percy"),
            ("ygopro2", "ygopro2"),
            ("Koishi Pro", "koishipro"),
            ("YGO Omega (Mac)", "ygo-omega"),
            ("mdpro3.exe", "mdpro3"),
        ] {
            assert_eq!(publisher(name).unwrap().id, id);
        }
        for name in [
            "EDOPro Installer",
            "YGOPro Soundtrack",
            "YGOPro 2 Server",
            "YGO Omega Server",
            "MDPro30",
            "KoishiPro 2",
        ] {
            assert!(publisher(name).is_none(), "{name}");
        }
        assert!(allowed("projectignis.github.io"));
        assert!(allowed("cli.koishi.pro"));
        assert!(!allowed("projectignis.github.io.evil.example"));
        assert!(!allowed("gog.com.evil.example"));
    }
    #[test]
    fn html_order() {
        let m=parse_html(r#"<meta content="A &amp; B" property="og:title"><meta name='description' content='Description'><meta content='/cover.jpg' property='og:image'>"#,"https://dev.itch.io/game").unwrap();
        assert_eq!(m.name, "A & B");
        assert_eq!(m.artwork, "https://dev.itch.io/cover.jpg");
    }
}

pub fn image_fill(path: &Path) -> Option<std::path::PathBuf> {
    let target = path.with_file_name(format!("{}.fill.png", path.file_stem()?.to_str()?));
    if target.is_file() {
        return Some(target);
    }
    let source = image::open(path).ok()?.thumbnail(64, 64).to_rgba8();
    let softened = image::imageops::blur(&source, 5.0);
    softened.save(&target).ok()?;
    Some(target)
}

#[cfg(test)]
mod automatic_matching_tests {
    use super::*;
    #[test]
    fn exact_match_wins_and_unique_subtitle_matches_packaged_executable() {
        let items = serde_json::json!([{"id": 1903340, "name": "Clair Obscur: Expedition 33"}]);
        assert_eq!(
            steam_match(
                &items,
                &crate::launch_plan::clean_title("Expedition33-Win64-Shipping")
            ),
            Some(1903340)
        );
        assert_eq!(
            steam_match(&items, "Clair Obscur: Expedition 33"),
            Some(1903340)
        );
        assert_eq!(steam_match(&items, "Expedition 3"), None);
        assert_eq!(
            steam_match(
                &serde_json::json!([{"id": 1, "name": "Game: Expedition 33"}, {"id": 2, "name": "Other: Expedition 33"}]),
                "Expedition 33"
            ),
            None
        );
        assert_eq!(
            steam_match(&serde_json::json!([{"id": 1, "name": "Hades II"}]), "Hades"),
            None
        );
        assert_eq!(
            steam_match(
                &serde_json::json!([{"id": 1, "name": "Pokémon"}]),
                "Pokemon"
            ),
            Some(1)
        );
    }
    #[test]
    fn provider_canonical_title_preserves_user_override_and_launch_identity() {
        let mut game = Game {
            name: "Expedition 33".into(),
            launch_target: "/Games/Expedition33-Win64-Shipping.exe".into(),
            launch_count: 7,
            ..Default::default()
        };
        let details = Details {
            name: "Clair Obscur: Expedition 33".into(),
            summary: "A summary".into(),
            ..Default::default()
        };
        details.apply(&mut game);
        assert_eq!(game.name, "Clair Obscur: Expedition 33");
        assert_eq!(game.launch_count, 7);
        let target = game.launch_target.clone();
        game.metadata_overrides = Some(std::collections::BTreeMap::from([(
            "name".into(),
            "My custom title".into(),
        )]));
        details.apply(&mut game);
        assert_eq!(game.name, "My custom title");
        assert_eq!(game.launch_target, target);
    }
}

#[cfg(test)]
mod live_automatic_tests {
    use super::*;
    #[test]
    #[ignore = "contacts live official metadata providers"]
    fn packaged_windows_titles_find_automatic_metadata() {
        let client = Client::new().unwrap();
        let game = Game {
            name: "Expedition33-Win64-Shipping".into(),
            ..Default::default()
        };
        let details = client.automatic(&game).unwrap();
        assert_eq!(details.name, "Clair Obscur: Expedition 33");
        assert!(!details.summary.is_empty());
        assert!(details.url.contains("1903340"));
        let game = Game {
            name: "VALORANT-Win64-Shipping".into(),
            ..Default::default()
        };
        let details = client.automatic(&game).unwrap();
        assert_eq!(details.name, "VALORANT");
        assert_eq!(details.developer, "Riot Games");
    }
}

pub fn needs_metadata(game: &Game) -> bool {
    let Some(updated) = game.metadata_updated else {
        return true;
    };
    let incomplete = game.summary.is_empty()
        || game.developer.is_empty()
        || game.genres.is_empty()
        || game.artwork.is_empty()
        || (publisher(&game.name).is_none() && game.release_date.is_empty());
    incomplete && (updated > now() || now() - updated >= 86400.0)
}

#[cfg(test)]
mod fallback_tests {
    use super::*;
    #[test]
    fn secondary_provider_fills_only_missing_fields_and_keeps_overrides() {
        let mut primary = Details {
            name: "Store title".into(),
            summary: "Store summary".into(),
            url: "https://www.gog.com/game/example".into(),
            source: "GOG".into(),
            ..Default::default()
        };
        primary.fill_missing(&Details {
            name: "Steam title".into(),
            summary: "Other summary".into(),
            developer: "Developer".into(),
            release_date: "2020-01-01".into(),
            genres: vec!["RPG".into()],
            artwork: "https://example.com/cover.png".into(),
            steam_id: "42".into(),
            source: "Steam".into(),
            ..Default::default()
        });
        assert_eq!(primary.summary, "Store summary");
        assert_eq!(primary.url, "https://www.gog.com/game/example");
        assert_eq!(primary.developer, "Developer");
        assert_eq!(primary.source, "GOG + Steam");
        let mut game = Game {
            store: "GOG".into(),
            store_id: "123".into(),
            launch_count: 8,
            metadata_overrides: Some(std::collections::BTreeMap::from([(
                "summary".into(),
                "Custom".into(),
            )])),
            ..Default::default()
        };
        primary.apply(&mut game);
        assert_eq!(game.summary, "Custom");
        assert_eq!(game.store_id, "123");
        assert_eq!(game.extra["metadataSteamId"], "42");
        assert_eq!(game.launch_count, 8);
    }
    #[test]
    fn partial_metadata_retries_after_cooldown_without_fetching_every_start() {
        let mut game = Game::default();
        assert!(needs_metadata(&game));
        game.metadata_updated = Some(now());
        assert!(!needs_metadata(&game));
        game.metadata_updated = Some(now() - 86401.0);
        assert!(needs_metadata(&game));
    }
}
