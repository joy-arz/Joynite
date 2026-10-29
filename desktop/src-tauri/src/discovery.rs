use crate::{
    model::{hash, CompatibilityLaunch, Game},
    vdf,
};
use serde::Serialize;
use std::{
    collections::{BTreeMap, HashSet},
    fs,
    path::{Path, PathBuf},
};
#[derive(Default, Serialize)]
pub struct Scan {
    pub games: Vec<Game>,
    pub warnings: Vec<String>,
}
fn entries(path: &Path) -> Vec<PathBuf> {
    fs::read_dir(path)
        .map(|x| {
            x.filter_map(Result::ok)
                .take(2048)
                .map(|x| x.path())
                .collect()
        })
        .unwrap_or_default()
}
pub fn steam_game(manifest: &Path) -> Result<Option<Game>, String> {
    let data = vdf::parse(&fs::read_to_string(manifest).map_err(|e| e.to_string())?)?;
    let state = vdf::object(&data, "AppState").ok_or("Missing AppState")?;
    let id = vdf::text(state, "appid")
        .filter(|s| s.parse::<u64>().is_ok())
        .ok_or("Invalid app ID")?;
    let name = vdf::text(state, "name").ok_or("Missing game title")?;
    let install = vdf::text(state, "installdir").ok_or("Missing installation directory")?;
    if install == ".." || install == "." || install.contains('/') || install.contains('\\') {
        return Err("Invalid installation directory".into());
    }
    let flags = vdf::text(state, "StateFlags")
        .unwrap_or("0")
        .parse::<u32>()
        .unwrap_or(0);
    let path = manifest
        .parent()
        .ok_or("Invalid manifest path")?
        .join("common")
        .join(install);
    if flags & 4 == 0 || !path.exists() {
        return Ok(None);
    }
    Ok(Some(Game {
        id: format!("steam:{id}"),
        name: name.into(),
        store: "Steam".into(),
        launch_kind: "store".into(),
        launch_target: format!("steam://rungameid/{id}"),
        install_path: path.to_string_lossy().into(),
        store_id: id.into(),
        store_url: format!("https://store.steampowered.com/app/{id}/"),
        ..Default::default()
    }))
}
pub fn windows_path(value: &str, prefix: &Path) -> Option<PathBuf> {
    let clean = value.replace('\\', "/");
    let parts: Vec<_> = clean.split('/').filter(|s| !s.is_empty()).collect();
    if parts.is_empty()
        || parts.iter().any(|s| *s == ".." || *s == ".")
        || parts[0].len() != 2
        || !parts[0].ends_with(':')
    {
        return None;
    }
    let mut root = if parts[0].eq_ignore_ascii_case("c:") {
        prefix.join("drive_c")
    } else {
        fs::canonicalize(prefix.join("dosdevices").join(parts[0].to_lowercase())).ok()?
    };
    for p in &parts[1..] {
        root.push(p)
    }
    Some(root)
}
fn steam_libraries(base: &Path, prefix: Option<&Path>) -> Vec<PathBuf> {
    let mut paths = vec![base.to_owned()];
    if let Ok(data) = fs::read_to_string(base.join("libraryfolders.vdf"))
        .and_then(|s| vdf::parse(&s).map_err(std::io::Error::other))
    {
        if let Some(libraries) = vdf::object(&data, "libraryfolders") {
            for val in libraries.values() {
                if let vdf::Value::Object(obj) = val {
                    if let Some(path) = vdf::text(obj, "path") {
                        if let Some(mapped) =
                            prefix.and_then(|p| windows_path(path, p)).or_else(|| {
                                if Path::new(path).is_absolute() {
                                    Some(PathBuf::from(path))
                                } else {
                                    None
                                }
                            })
                        {
                            paths.push(mapped.join("steamapps"))
                        }
                    }
                }
            }
        }
    }
    paths.sort();
    paths.dedup();
    paths
}
fn scan_steam(base: &Path, prefix: Option<(&Path, Option<&Path>, &str)>, out: &mut Scan) {
    for library in steam_libraries(base, prefix.map(|p| p.0)) {
        for file in entries(&library).into_iter().filter(|p| {
            p.extension().is_some_and(|e| e == "acf")
                && p.file_name()
                    .is_some_and(|n| n.to_string_lossy().starts_with("appmanifest_"))
        }) {
            match steam_game(&file) {
                Ok(Some(mut game)) => {
                    if let Some((root, wrapper, label)) = prefix {
                        let steam = base.parent().unwrap_or(base);
                        let exe = steam.join("steam.exe");
                        let mut candidates = vec![];
                        if let Some(app) = wrapper {
                            candidates.extend([
                                app.join("Contents/SharedSupport/wine/bin/wine"),
                                app.join("Contents/Frameworks/wswine.bundle/bin/wine64"),
                            ])
                        }
                        if label == "CrossOver" {
                            candidates.push(PathBuf::from("/Applications/CrossOver.app/Contents/SharedSupport/CrossOver/bin/wine"));
                            candidates.push(PathBuf::from("/opt/cxoffice/bin/wine"))
                        }
                        if wrapper.is_none() && label != "CrossOver" {
                            candidates.extend([
                                PathBuf::from("/opt/homebrew/bin/wine"),
                                PathBuf::from("/usr/local/bin/wine"),
                                PathBuf::from("/usr/bin/wine"),
                            ]);
                        }
                        let runtime = candidates
                            .into_iter()
                            .find(|p| p.is_file())
                            .unwrap_or_default();
                        let mut environment =
                            BTreeMap::from([("WINEPREFIX".into(), root.to_string_lossy().into())]);
                        if label == "CrossOver" {
                            environment.insert(
                                "CX_BOTTLE".into(),
                                root.file_name()
                                    .unwrap_or_default()
                                    .to_string_lossy()
                                    .into(),
                            );
                        }
                        if let Some(app) = wrapper {
                            environment.insert(
                                "DYLD_FALLBACK_LIBRARY_PATH".into(),
                                app.join("Contents/SharedSupport/wine/lib")
                                    .to_string_lossy()
                                    .into(),
                            );
                            if let Ok(info) =
                                plist::Value::from_file(app.join("Contents/Info.plist"))
                            {
                                if let Some(dict) = info.as_dictionary() {
                                    for key in [
                                        "WINEESYNC",
                                        "WINEMSYNC",
                                        "WINEDEBUG",
                                        "DXVK",
                                        "D3DMETAL",
                                        "WINEDLLOVERRIDES",
                                    ] {
                                        if let Some(value) = dict.get(key) {
                                            if let Some(text) = value.as_string() {
                                                environment.insert(key.into(), text.into());
                                            } else if let Some(number) = value.as_signed_integer() {
                                                environment.insert(key.into(), number.to_string());
                                            }
                                        }
                                    }
                                }
                            }
                        }
                        if label == "CrossOver" && cfg!(target_os = "macos") {
                            let x11 = PathBuf::from(
                                "/Applications/CrossOver.app/Contents/SharedSupport/X11",
                            );
                            environment.insert(
                                "DYLD_FALLBACK_LIBRARY_PATH".into(),
                                format!(
                                    "{}:{}/lib:/lib:/usr/lib:/usr/X11/lib",
                                    x11.join("lib").display(),
                                    dirs::home_dir().unwrap_or_default().display()
                                ),
                            );
                            environment.insert(
                                "FONTCONFIG_PATH".into(),
                                x11.join("etc/fonts").to_string_lossy().into(),
                            );
                            environment
                                .insert("FONTCONFIG_ROOT".into(), x11.to_string_lossy().into());
                            environment.insert(
                                "FONT_ENCODINGS_DIRECTORY".into(),
                                x11.join("lib/X11/fonts/encodings/encodings.dir")
                                    .to_string_lossy()
                                    .into(),
                            );
                            environment.insert("VERSIONER_PERL_PREFER_32_BIT".into(), "yes".into());
                        }
                        game.id = format!(
                            "wine-steam:{}:{}",
                            &hash(&root.to_string_lossy())[..16],
                            game.store_id
                        );
                        game.launch_kind = "compatibility".into();
                        game.launch_target = exe.to_string_lossy().into();
                        game.compatibility = Some(CompatibilityLaunch {
                            executable: runtime.to_string_lossy().into(),
                            arguments: vec![
                                exe.to_string_lossy().into(),
                                "-applaunch".into(),
                                game.store_id.clone(),
                            ],
                            environment,
                            working_directory: steam.to_string_lossy().into(),
                            label: label.into(),
                        });
                        if runtime.as_os_str().is_empty() {
                            out.warnings.push(format!(
                                "{}: prefix found, Wine runtime not found",
                                game.name
                            ))
                        }
                    }
                    out.games.push(game)
                }
                Ok(None) => {}
                Err(e) => out.warnings.push(format!("{}: {e}", file.display())),
            }
        }
    }
}
fn app_game(path: &Path) -> Option<Game> {
    let info = plist::Value::from_file(path.join("Contents/Info.plist")).ok()?;
    let dict = info.as_dictionary()?;
    let id = dict
        .get("CFBundleIdentifier")
        .and_then(|x| x.as_string())
        .unwrap_or("");
    if crate::model::is_launcher_id(id) {
        return None;
    }
    let name = dict
        .get("CFBundleDisplayName")
        .and_then(|x| x.as_string())
        .map(String::from)
        .unwrap_or_else(|| {
            path.file_stem()
                .unwrap_or_default()
                .to_string_lossy()
                .replace('_', " ")
        });
    Some(Game {
        id: format!("app:{}", path.display()),
        name,
        launch_target: path.to_string_lossy().into(),
        install_path: path.to_string_lossy().into(),
        ..Default::default()
    })
}
fn scan_apps(
    root: &Path,
    depth: usize,
    all: bool,
    out: &mut Scan,
    prefixes: &mut Vec<(PathBuf, Option<PathBuf>, String)>,
) {
    if depth > 4 {
        return;
    }
    for path in entries(root) {
        if path.is_symlink() {
            continue;
        }
        if path.extension().is_some_and(|e| e == "app") {
            let wrapper = ["Contents/SharedSupport/prefix", "Contents/Resources"]
                .into_iter()
                .map(|p| path.join(p))
                .find(|p| p.join("drive_c").is_dir());
            if let Some(prefix) = &wrapper {
                prefixes.push((
                    prefix.clone(),
                    Some(path.clone()),
                    "Sikarugir / Wineskin".into(),
                ))
            }
            let name = path
                .file_stem()
                .unwrap_or_default()
                .to_string_lossy()
                .to_lowercase();
            let category = plist::Value::from_file(path.join("Contents/Info.plist"))
                .ok()
                .and_then(|v| {
                    v.as_dictionary()
                        .and_then(|d| d.get("LSApplicationCategoryType"))
                        .and_then(|v| v.as_string())
                        .map(String::from)
                })
                .unwrap_or_default();
            if all
                || wrapper.is_some()
                || category.contains("games")
                || crate::metadata::publisher(&name).is_some()
                || [
                    "roblox",
                    "minecraft",
                    "mindustry",
                    "loop_hero",
                    "hades",
                    "inscryption",
                    "league of legends",
                    "genshin impact",
                ]
                .contains(&name.as_str())
            {
                if let Some(game) = app_game(&path) {
                    out.games.push(game)
                }
            }
        } else if path.is_dir() && all {
            scan_apps(&path, depth + 1, all, out, prefixes)
        }
    }
}
fn desktop_game(path: &Path) -> Option<Game> {
    let content = fs::read_to_string(path).ok()?;
    let name = content.lines().find_map(|l| l.strip_prefix("Name="))?;
    if !content
        .lines()
        .any(|l| l.starts_with("Categories=") && l.contains("Game"))
    {
        return None;
    }
    Some(Game {
        id: format!("desktop:{}", path.display()),
        name: name.into(),
        launch_kind: "desktop".into(),
        launch_target: path.to_string_lossy().into(),
        install_path: path.to_string_lossy().into(),
        ..Default::default()
    })
}
pub fn scan(home: &Path, folders: &[String]) -> Scan {
    let mut out = Scan::default();
    let mut prefixes = vec![(home.join(".wine"), None, "Wine".into())];
    let mut steam = vec![
        home.join("Library/Application Support/Steam/steamapps"),
        home.join(".local/share/Steam/steamapps"),
        home.join(".steam/steam/steamapps"),
        home.join(".var/app/com.valvesoftware.Steam/.local/share/Steam/steamapps"),
    ];
    #[cfg(windows)]
    {
        if let Ok(program) = std::env::var("ProgramFiles(x86)") {
            steam.push(PathBuf::from(program).join("Steam/steamapps"))
        }
        if let Ok(output) = std::process::Command::new("reg.exe")
            .args(["query", r"HKCU\Software\Valve\Steam", "/v", "SteamPath"])
            .output()
        {
            let text = String::from_utf8_lossy(&output.stdout);
            if let Some(path) = text
                .lines()
                .find_map(|s| s.split_once("REG_SZ").map(|p| p.1.trim()))
            {
                steam.push(PathBuf::from(path).join("steamapps"))
            }
        }
    }
    for base in steam.drain(..) {
        scan_steam(&base, None, &mut out)
    }
    for root in [
        home.join("Library/Application Support/CrossOver/Bottles"),
        home.join("Library/Containers/com.isaacmarovitz.Whisky/Bottles"),
        home.join("Library/Containers/com.isaacmarovitz.Whisky/Data/Bottles"),
        home.join(".local/share/bottles/bottles"),
        home.join(".cxoffice"),
    ] {
        for child in entries(&root) {
            let label =
                if root.to_string_lossy().contains("CrossOver") || root.ends_with(".cxoffice") {
                    "CrossOver"
                } else {
                    "Wine"
                };
            prefixes.push((child, None, label.into()))
        }
    }
    let mut roots = vec![
        home.join("Games"),
        home.join("GOG Games"),
        home.join("Applications/Sikarugir"),
        home.join("Applications/Wineskin"),
        home.join("Library/Application Support/itch/apps"),
        PathBuf::from("/Applications/Games"),
    ];
    roots.extend(folders.iter().map(PathBuf::from));
    for root in &roots {
        if root.join("drive_c").is_dir() {
            prefixes.push((root.clone(), None, "Wine".into()))
        }
        scan_apps(root, 0, true, &mut out, &mut prefixes);
        for path in entries(root) {
            if path.extension().is_some_and(|e| {
                e.eq_ignore_ascii_case("exe") || e.eq_ignore_ascii_case("lnk") || e == "AppImage"
            }) {
                out.games.push(Game {
                    id: format!("file:{}", path.display()),
                    name: crate::launch_plan::display_title(&path),
                    launch_kind: "executable".into(),
                    launch_target: path.to_string_lossy().into(),
                    install_path: path.to_string_lossy().into(),
                    ..Default::default()
                })
            }
        }
    }
    scan_apps(
        Path::new("/Applications"),
        0,
        false,
        &mut out,
        &mut prefixes,
    );
    scan_apps(
        &home.join("Applications"),
        0,
        false,
        &mut out,
        &mut prefixes,
    );
    for root in [
        home.join(".local/share/applications"),
        PathBuf::from("/usr/share/applications"),
    ] {
        for path in entries(&root) {
            if let Some(game) = desktop_game(&path) {
                out.games.push(game)
            }
        }
    }
    let mut seen = HashSet::new();
    for (prefix, wrapper, label) in prefixes {
        if !seen.insert(prefix.clone()) {
            continue;
        }
        for folder in ["Program Files (x86)/Steam", "Program Files/Steam", "Steam"] {
            let steam = prefix.join("drive_c").join(folder);
            if steam.join("steam.exe").is_file() {
                scan_steam(
                    &steam.join("steamapps"),
                    Some((&prefix, wrapper.as_deref(), &label)),
                    &mut out,
                )
            }
        }
    }
    scan_clients(home, &mut out);
    let mut seen = HashSet::new();
    out.games.retain(|g| seen.insert(g.id.clone()));
    out.games.sort_by_key(|g| g.name.to_lowercase());
    out
}
fn scan_clients(home: &Path, out: &mut Scan) {
    let data = if cfg!(target_os = "macos") {
        home.join("Library/Application Support")
    } else if cfg!(windows) {
        dirs::data_dir().unwrap_or_else(|| home.to_owned())
    } else {
        home.join(".config")
    };
    let epic = if cfg!(windows) {
        PathBuf::from(std::env::var("PROGRAMDATA").unwrap_or_else(|_| "C:\\ProgramData".into()))
            .join("Epic/EpicGamesLauncher/Data/Manifests")
    } else {
        data.join("Epic/EpicGamesLauncher/Data/Manifests")
    };
    for file in entries(&epic) {
        let Ok(v) = fs::read(&file).and_then(|b| {
            serde_json::from_slice::<serde_json::Value>(&b).map_err(std::io::Error::other)
        }) else {
            continue;
        };
        let Some(path) = v["InstallLocation"].as_str() else {
            continue;
        };
        let Some(id) = v["AppName"].as_str() else {
            continue;
        };
        if !Path::new(path).exists() || v["bIsIncompleteInstall"].as_bool() == Some(true) {
            continue;
        }
        let launch = [
            v["CatalogNamespace"].as_str().unwrap_or(""),
            v["CatalogItemId"].as_str().unwrap_or(""),
            id,
        ]
        .join(":");
        out.games.push(Game {
            id: format!("epic:{id}"),
            name: v["DisplayName"].as_str().unwrap_or(id).into(),
            store: "Epic".into(),
            launch_kind: "store".into(),
            launch_target: format!(
                "com.epicgames.launcher://apps/{}?action=launch&silent=true",
                launch
                    .replace('&', "%26")
                    .replace('?', "%3F")
                    .replace('#', "%23")
            ),
            install_path: path.into(),
            store_id: id.into(),
            ..Default::default()
        })
    }
    for (relative, store, runner) in [
        (
            "legendaryConfig/legendary/installed.json",
            "Epic",
            "legendary",
        ),
        ("gog_store/installed.json", "GOG", "gog"),
    ] {
        let file = data.join("heroic").join(relative);
        let Ok(v) = fs::read(file).and_then(|b| {
            serde_json::from_slice::<serde_json::Value>(&b).map_err(std::io::Error::other)
        }) else {
            continue;
        };
        let entries: Vec<(String, serde_json::Value)> =
            if let Some(array) = v["installed"].as_array() {
                array
                    .iter()
                    .map(|v| (v["appName"].as_str().unwrap_or("").into(), v.clone()))
                    .collect()
            } else {
                v.as_object()
                    .map(|m| m.iter().map(|(k, v)| (k.clone(), v.clone())).collect())
                    .unwrap_or_default()
            };
        for (key, item) in entries {
            let id = item["app_name"]
                .as_str()
                .or(item["appName"].as_str())
                .unwrap_or(&key);
            if id.is_empty() {
                continue;
            }
            let path = item["install_path"]
                .as_str()
                .or(item["installPath"].as_str())
                .unwrap_or("");
            let name = item["title"]
                .as_str()
                .or(item["name"].as_str())
                .unwrap_or(id);
            out.games.push(Game {
                id: format!("heroic:{store}:{id}"),
                name: name.into(),
                store: store.into(),
                launch_kind: "store".into(),
                launch_target: format!(
                    "heroic://launch/{runner}/{}",
                    id.replace('/', "%2F")
                        .replace('?', "%3F")
                        .replace('#', "%23")
                ),
                install_path: path.into(),
                store_id: id.into(),
                ..Default::default()
            })
        }
    }
}
#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn installation_bits_and_paths() {
        let temp = tempfile::tempdir().unwrap();
        let base = temp.path().join("steamapps");
        fs::create_dir_all(base.join("common/Test")).unwrap();
        let file = base.join("appmanifest_480.acf");
        fs::write(
            &file,
            r#""AppState"{"appid""480""name""Test""installdir""Test""StateFlags""6"}"#,
        )
        .unwrap();
        assert_eq!(
            steam_game(&file).unwrap().unwrap().launch_target,
            "steam://rungameid/480"
        );
        fs::write(
            &file,
            r#""AppState"{"appid""480""name""Test""installdir""../Test""StateFlags""4"}"#,
        )
        .unwrap();
        assert!(steam_game(&file).is_err())
    }
    #[test]
    fn windows_paths_reject_traversal() {
        let root = Path::new("/prefix");
        assert_eq!(
            windows_path(r"C:\Program Files (x86)\Steam", root),
            Some(root.join("drive_c/Program Files (x86)/Steam"))
        );
        assert!(windows_path(r"C:\..\Users", root).is_none())
    }
    #[test]
    fn prefix_specific_steam() {
        let t = tempfile::tempdir().unwrap();
        let prefix = t.path().join(".wine");
        let base = prefix.join("drive_c/Program Files (x86)/Steam");
        fs::create_dir_all(base.join("steamapps/common/Fixture")).unwrap();
        fs::write(base.join("steam.exe"), b"fixture").unwrap();
        fs::write(
            base.join("steamapps/appmanifest_480.acf"),
            r#""AppState"{"appid""480""name""Fixture""installdir""Fixture""StateFlags""4"}"#,
        )
        .unwrap();
        let result = scan(t.path(), &[]);
        let game = result
            .games
            .iter()
            .find(|g| g.id.starts_with("wine-steam:"))
            .unwrap();
        assert_eq!(
            game.compatibility.as_ref().unwrap().environment["WINEPREFIX"],
            prefix.to_string_lossy()
        );
        assert_eq!(
            game.compatibility.as_ref().unwrap().arguments[1],
            "-applaunch"
        )
    }
}
