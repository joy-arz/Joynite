//! Epic's public product CMS and local Legendary catalog metadata.
//! No launcher tokens or account credentials are read.
use crate::{
    metadata::{plain, Details},
    model::{normalized, Game},
};
use serde_json::Value;

pub fn slug(title: &str) -> String {
    title
        .to_lowercase()
        .split(|c: char| !c.is_alphanumeric())
        .filter(|s| !s.is_empty())
        .collect::<Vec<_>>()
        .join("-")
}

pub fn page_slug(url: &reqwest::Url) -> Option<String> {
    if !matches!(
        url.host_str(),
        Some("store.epicgames.com" | "www.epicgames.com" | "epicgames.com")
    ) {
        return None;
    }
    let parts: Vec<_> = url.path_segments()?.collect();
    let index = parts.iter().position(|p| *p == "p" || *p == "product")?;
    let slug = *parts.get(index + 1)?;
    (!slug.is_empty()).then(|| slug.to_owned())
}

fn text(value: &Value) -> String {
    value.as_str().unwrap_or("").to_owned()
}
fn image(images: &Value, roles: &[&str]) -> String {
    for role in roles {
        if let Some(url) = images
            .as_array()
            .and_then(|images| images.iter().find(|i| i["type"] == *role))
            .and_then(|i| i["url"].as_str())
        {
            return url.into();
        }
    }
    String::new()
}

pub fn catalog(value: &Value) -> Result<Details, String> {
    let name = text(&value["title"]);
    if name.is_empty() {
        return Err("Epic catalog item has no title".into());
    }
    Ok(Details {
        name,
        summary: plain(
            value["shortDescription"]
                .as_str()
                .filter(|s| !s.is_empty())
                .or(value["description"].as_str())
                .unwrap_or(""),
        ),
        developer: text(&value["developer"]),
        release_date: text(&value["releaseDate"]),
        portrait: image(
            &value["keyImages"],
            &[
                "DieselGameBoxTall",
                "OfferImageTall",
                "DieselStoreFrontTall",
            ],
        ),
        artwork: image(
            &value["keyImages"],
            &["DieselGameBox", "OfferImageWide", "DieselStoreFrontWide"],
        ),
        background: image(
            &value["keyImages"],
            &["DieselGameBox", "OfferImageWide", "DieselStoreFrontWide"],
        ),
        source: "Epic Games".into(),
        ..Default::default()
    })
}

pub fn product(
    value: &Value,
    requested_slug: &str,
    page: &str,
    game: Option<&Game>,
) -> Result<Details, String> {
    let name = text(&value["productName"]);
    if name.is_empty() {
        return Err("Epic product has no title".into());
    }
    if let Some(game) = game {
        // A generated slug is only a candidate. Never silently pick another game.
        if normalized(&name) != normalized(&game.name)
            || game
                .extra
                .get("epicNamespace")
                .and_then(Value::as_str)
                .is_some_and(|ns| !ns.is_empty() && value["namespace"].as_str() != Some(ns))
        {
            return Err("Epic product identity does not match this installation".into());
        }
    }
    let pages = value["pages"]
        .as_array()
        .ok_or("Epic product has no pages")?;
    // Do not use the first page: it may be DLC or a different edition.
    let matches: Vec<_> = pages.iter().filter(|p| p["_slug"] == page).collect();
    if matches.len() != 1 {
        return Err("No unique Epic product page".into());
    }
    let data = &matches[0]["data"];
    let about = &data["about"];
    let summary = plain(
        about["shortDescription"]
            .as_str()
            .filter(|s| !s.is_empty())
            .or(about["description"].as_str())
            .unwrap_or(""),
    );
    if summary.is_empty() {
        return Err("Epic product page has no description".into());
    }
    let mut url = reqwest::Url::parse("https://store.epicgames.com/en-US/p/").unwrap();
    url.path_segments_mut()
        .unwrap()
        .pop_if_empty()
        .push(requested_slug);
    if page != "home" {
        url.path_segments_mut().unwrap().push(page);
    }
    Ok(Details {
        name,
        summary,
        developer: text(&about["developerAttribution"]),
        release_date: text(&about["releaseDate"]),
        portrait: text(&data["hero"]["portraitBackgroundImageUrl"]),
        artwork: text(&data["hero"]["backgroundImageUrl"]),
        background: text(&data["hero"]["backgroundImageUrl"]),
        url: url.into(),
        source: "Epic Games".into(),
        ..Default::default()
    })
}

pub fn identifiers(namespace: &str, item_id: &str) -> std::collections::BTreeMap<String, Value> {
    [
        ("epicNamespace".into(), Value::String(namespace.into())),
        ("epicCatalogItemId".into(), Value::String(item_id.into())),
    ]
    .into()
}

pub fn attach_local(game: &mut Game, path: &std::path::Path) {
    use std::io::Read;
    let Ok(file) = std::fs::File::open(path) else {
        return;
    };
    let mut bytes = Vec::new();
    if file.take(2_000_001).read_to_end(&mut bytes).is_err() {
        return;
    }
    if bytes.len() > 2_000_000 {
        return;
    }
    let Ok(value) = serde_json::from_slice::<Value>(&bytes) else {
        return;
    };
    let metadata = &value["metadata"];
    if value["app_name"].as_str() != Some(&game.store_id) {
        return;
    }
    game.extra.extend(identifiers(
        metadata["namespace"].as_str().unwrap_or(""),
        metadata["id"].as_str().unwrap_or(""),
    ));
    // Keep only catalog fields needed by Joynite, never account data.
    let fields = [
        "title",
        "description",
        "shortDescription",
        "developer",
        "releaseDate",
        "keyImages",
    ];
    let filtered: serde_json::Map<String, Value> = fields
        .into_iter()
        .filter_map(|key| metadata.get(key).map(|v| (key.into(), v.clone())))
        .collect();
    game.extra
        .insert("epicMetadata".into(), Value::Object(filtered));
}

pub fn merge_discovery(current: &mut Game, found: &Game) {
    if found.store != "Epic" {
        return;
    }
    for key in ["epicNamespace", "epicCatalogItemId", "epicMetadata"] {
        if let Some(value) = found.extra.get(key).filter(|v| v.as_str() != Some("")) {
            current.extra.insert(key.into(), value.clone());
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    fn fixture() -> Value {
        json!({"productName":"Fixture", "namespace":"sandbox", "pages":[
            {"_slug":"dlc", "data":{"about":{"shortDescription":"Wrong DLC"}}},
            {"_slug":"home", "data":{
                "about":{"shortDescription":"A &amp; B", "developerAttribution":"Studio"},
                "hero":{"portraitBackgroundImageUrl":"https://cdn.example/tall.png",
                    "backgroundImageUrl":"https://cdn.example/wide.png"}}}]})
    }

    #[test]
    fn product_uses_home_and_checks_identity() {
        let mut game = Game {
            name: "Fixture".into(),
            extra: identifiers("sandbox", "item"),
            ..Default::default()
        };
        let details = product(&fixture(), "fixture", "home", Some(&game)).unwrap();
        assert_eq!(details.summary, "A & B");
        assert_eq!(details.developer, "Studio");
        assert_eq!(details.portrait, "https://cdn.example/tall.png");
        assert_eq!(details.url, "https://store.epicgames.com/en-US/p/fixture");
        game.extra = identifiers("other-sandbox", "item");
        assert!(product(&fixture(), "fixture", "home", Some(&game)).is_err());
        game.extra.clear();
        game.name = "Fixture II".into();
        assert!(product(&fixture(), "fixture", "home", Some(&game)).is_err());
        assert!(product(&fixture(), "fixture", "missing-edition", None).is_err());
        let mut duplicate = fixture();
        duplicate["pages"]
            .as_array_mut()
            .unwrap()
            .push(fixture()["pages"][1].clone());
        assert!(product(&duplicate, "fixture", "home", None).is_err());
    }

    #[test]
    fn epic_page_urls_reject_lookalike_hosts() {
        for url in [
            "https://store.epicgames.com/en-US/p/hades",
            "https://www.epicgames.com/store/en-US/product/hades/home",
        ] {
            assert_eq!(
                page_slug(&reqwest::Url::parse(url).unwrap()).as_deref(),
                Some("hades")
            );
        }
        assert!(page_slug(
            &reqwest::Url::parse("https://store.epicgames.com.evil.test/p/hades").unwrap()
        )
        .is_none());
        assert_eq!(slug("Rocket League"), "rocket-league");
    }

    #[test]
    fn catalog_keeps_separate_artwork_roles_and_custom_values() {
        let details = catalog(&json!({"title":"Fixture", "description":"Description", "developer":"Studio", "keyImages":[
            {"type":"DieselGameBoxLogo","url":"logo"},
            {"type":"DieselGameBox","url":"wide"},
            {"type":"DieselGameBoxTall","url":"tall"}]})).unwrap();
        assert_eq!(details.artwork, "wide");
        assert_eq!(details.portrait, "tall");
        let mut game = Game {
            store: "Epic".into(),
            store_id: "artifact".into(),
            launch_target: "original".into(),
            metadata_overrides: Some([("summary".into(), "My description".into())].into()),
            ..Default::default()
        };
        details.apply(&mut game);
        assert_eq!(game.summary, "My description");
        assert_eq!(game.store_id, "artifact");
        assert_eq!(game.launch_target, "original");
        assert_eq!(game.extra["automaticPortrait"], "tall");
        let roundtrip: Game = serde_json::from_slice(&serde_json::to_vec(&game).unwrap()).unwrap();
        assert_eq!(roundtrip.extra["automaticPortrait"], "tall");
    }

    #[test]
    fn local_metadata_and_rescan_upgrade_existing_games() {
        let dir = tempfile::tempdir().unwrap();
        let path = dir.path().join("artifact.json");
        std::fs::write(&path, json!({"app_name":"artifact", "token":"never copy", "metadata":{
            "id":"item", "namespace":"sandbox", "title":"Fixture", "description":"Cached", "secret":"never copy"}}).to_string()).unwrap();
        let mut found = Game {
            store: "Epic".into(),
            store_id: "artifact".into(),
            ..Default::default()
        };
        attach_local(&mut found, &path);
        assert!(found.extra["epicMetadata"].get("secret").is_none());
        assert!(found.extra.get("token").is_none());
        let mut current = Game {
            favorite: true,
            launch_count: 12,
            ..Default::default()
        };
        merge_discovery(&mut current, &found);
        assert_eq!(current.extra["epicNamespace"], "sandbox");
        assert_eq!(
            catalog(&current.extra["epicMetadata"]).unwrap().summary,
            "Cached"
        );
        assert!(current.favorite);
        assert_eq!(current.launch_count, 12);
        found.store_id = "another-artifact".into();
        found.extra.clear();
        attach_local(&mut found, &path);
        assert!(found.extra.is_empty());
    }
}
