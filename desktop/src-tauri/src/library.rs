use crate::{
    discovery,
    metadata::{self, Client},
    model::{hash, Game, Library},
};
use serde::Serialize;
use std::{
    fs,
    io::Write,
    path::{Path, PathBuf},
    process::{Command, Stdio},
    sync::{
        atomic::{AtomicBool, Ordering},
        Mutex,
    },
};
pub struct Store {
    pub library: Library,
    pub root: PathBuf,
    pub error: Option<String>,
    pub notices: Vec<String>,
    pub revision: u64,
}
pub struct AppState {
    pub store: Mutex<Store>,
    pub cancel: AtomicBool,
}
#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
pub struct Images {
    pub portrait_fill: Option<String>,
    pub landscape_fill: Option<String>,
    pub background_fill: Option<String>,
    pub portrait: Option<String>,
    pub landscape: Option<String>,
    pub background: Option<String>,
}
#[derive(Serialize)]
pub struct UiGame {
    #[serde(flatten)]
    pub game: Game,
    pub images: Images,
}
#[derive(Serialize)]
pub struct Snapshot {
    pub games: Vec<UiGame>,
    pub folders: Vec<String>,
    pub notices: Vec<String>,
    pub error: Option<String>,
    pub platform: String,
    pub revision: u64,
}
impl Store {
    pub fn open() -> Self {
        let root = std::env::var("PLAYNITE_DATA_DIRECTORY")
            .map(PathBuf::from)
            .unwrap_or_else(|_| {
                dirs::data_dir()
                    .unwrap_or_else(|| PathBuf::from("."))
                    .join("PlayniteCarousel")
            });
        let mut error = None;
        let mut library = Library::default();
        if let Err(e) = fs::create_dir_all(&root) {
            error = Some(format!("Cannot create library directory: {e}"))
        }
        let file = root.join("library.json");
        if !file.exists() && std::env::var_os("PLAYNITE_DATA_DIRECTORY").is_none() {
            if let Some(home) = dirs::home_dir() {
                let native = home.join("Library/Application Support/PlayniteMac");
                if native.join("library.json").is_file() {
                    if let Err(e) = copy_tree(&native.join("Media"), &root.join("Media"))
                        .and_then(|_| fs::copy(native.join("library.json"), &file).map(|_| ()))
                    {
                        error = Some(format!("Native-library migration failed: {e}"))
                    }
                }
            }
        }
        if file.exists() {
            match fs::read(&file)
                .and_then(|b| serde_json::from_slice::<Library>(&b).map_err(std::io::Error::other))
            {
                Ok(data) if data.version == 1 => library = data,
                Ok(_) => {
                    error = Some("Unsupported library version; original file preserved".into())
                }
                Err(e) => {
                    error = Some(format!(
                    "Library is read-only after a load failure. Restore library.json.backup. {e}"
                ))
                }
            }
        }
        Self {
            library,
            root,
            error,
            notices: vec![],
            revision: 1,
        }
    }
    pub fn ensure_writable(&self) -> Result<(), String> {
        if let Some(error) = &self.error {
            return Err(error.clone());
        }
        Ok(())
    }
    pub fn save(&mut self) -> Result<(), String> {
        if let Some(error) = &self.error {
            return Err(error.clone());
        }
        save_library(&self.root, &self.library)?;
        self.revision += 1;
        Ok(())
    }
    pub fn snapshot(&self) -> Snapshot {
        let games = self
            .library
            .games
            .iter()
            .map(|game| {
                let file = |key: &Option<String>| {
                    metadata::cache_file(&self.root, game, key)
                        .map(|p| p.to_string_lossy().into_owned())
                };
                let mut images = Images {
                    portrait_fill: None,
                    landscape_fill: None,
                    background_fill: None,
                    portrait: file(&game.custom_artwork).or_else(|| file(&game.cached_artwork)),
                    landscape: file(&game.custom_landscape)
                        .or_else(|| file(&game.cached_landscape))
                        .or_else(|| file(&game.custom_artwork))
                        .or_else(|| file(&game.cached_artwork)),
                    background: file(&game.custom_background)
                        .or_else(|| file(&game.cached_background))
                        .or_else(|| file(&game.custom_landscape))
                        .or_else(|| file(&game.cached_landscape))
                        .or_else(|| file(&game.custom_artwork))
                        .or_else(|| file(&game.cached_artwork)),
                };
                images.portrait_fill = images
                    .portrait
                    .as_ref()
                    .and_then(|s| metadata::image_fill(Path::new(s)))
                    .map(|p| p.to_string_lossy().into_owned());
                images.landscape_fill = images
                    .landscape
                    .as_ref()
                    .and_then(|s| metadata::image_fill(Path::new(s)))
                    .map(|p| p.to_string_lossy().into_owned());
                images.background_fill = images
                    .background
                    .as_ref()
                    .and_then(|s| metadata::image_fill(Path::new(s)))
                    .map(|p| p.to_string_lossy().into_owned());
                UiGame {
                    game: game.clone(),
                    images,
                }
            })
            .collect();
        Snapshot {
            games,
            folders: self.library.folders.clone(),
            notices: self.notices.clone(),
            error: self.error.clone(),
            platform: std::env::consts::OS.into(),
            revision: self.revision,
        }
    }
    pub fn game(&self, id: &str) -> Result<Game, String> {
        self.library
            .games
            .iter()
            .find(|g| g.id == id)
            .cloned()
            .ok_or("Game no longer exists".into())
    }
    pub fn scan(&mut self) -> Result<(), String> {
        self.ensure_writable()?;
        let home = dirs::home_dir().ok_or("Home directory is unavailable")?;
        let result = discovery::scan(&home, &self.library.folders);
        self.notices = result.warnings;
        for found in result.games {
            if let Some(current) = self.library.games.iter_mut().find(|g| g.id == found.id) {
                current.launch_target = found.launch_target;
                current.install_path = found.install_path;
                current.compatibility = found.compatibility
            } else if !self.library.games.iter().any(|g| {
                !g.install_path.is_empty()
                    && g.install_path == found.install_path
                    && g.launch_kind == found.launch_kind
            }) {
                self.library.games.push(found)
            }
        }
        let removed: Vec<_> = self
            .library
            .games
            .iter()
            .filter(|g| confirmed_missing(g))
            .map(|g| g.id.clone())
            .collect();
        for id in removed {
            self.library.games.retain(|g| g.id != id);
            let folder = self.root.join("Media").join(hash(&id));
            if folder.exists() {
                if let Err(e) = fs::remove_dir_all(folder) {
                    self.notices.push(format!("Cache cleanup: {e}"))
                }
            }
        }
        self.save()
    }
}
fn copy_tree(source: &Path, target: &Path) -> std::io::Result<()> {
    if !source.exists() {
        return Ok(());
    }
    fs::create_dir_all(target)?;
    for entry in fs::read_dir(source)? {
        let entry = entry?;
        let kind = entry.file_type()?;
        if kind.is_symlink() {
            continue;
        }
        if kind.is_dir() {
            copy_tree(&entry.path(), &target.join(entry.file_name()))?
        } else if kind.is_file() {
            fs::copy(entry.path(), target.join(entry.file_name()))?;
        }
    }
    Ok(())
}
pub fn save_library(root: &Path, library: &Library) -> Result<(), String> {
    fs::create_dir_all(root).map_err(|e| e.to_string())?;
    let file = root.join("library.json");
    let temp = root.join(format!("library.{}.tmp", std::process::id()));
    let bytes = serde_json::to_vec_pretty(library).map_err(|e| e.to_string())?;
    if file.exists() {
        fs::copy(&file, root.join("library.json.backup")).map_err(|e| e.to_string())?;
    }
    let mut output = fs::File::create(&temp).map_err(|e| e.to_string())?;
    output
        .write_all(&bytes)
        .and_then(|_| output.sync_all())
        .map_err(|e| e.to_string())?;
    drop(output);
    fs::rename(temp, file).map_err(|e| e.to_string())
}
pub fn confirmed_missing(game: &Game) -> bool {
    if game.pending_uninstall != Some(true) || game.install_path.is_empty() {
        return false;
    }
    let path = Path::new(&game.install_path);
    if path.exists() {
        return false;
    }
    if let Ok(relative) = path.strip_prefix("/Volumes") {
        if let Some(name) = relative.components().next() {
            if !Path::new("/Volumes").join(name.as_os_str()).exists() {
                return false;
            }
        }
    }
    path.parent().is_some_and(Path::exists)
}
fn spawn_reaped(command: &mut Command) -> Result<(), String> {
    command.stdin(Stdio::null());
    let mut child = command.spawn().map_err(|e| e.to_string())?;
    std::thread::spawn(move || {
        let _ = child.wait();
    });
    Ok(())
}
pub fn open_uri(url: &str) -> Result<(), String> {
    let parsed = reqwest::Url::parse(url).map_err(|e| e.to_string())?;
    if ![
        "steam",
        "heroic",
        "com.epicgames.launcher",
        "https",
        "ms-settings",
        "appstream",
    ]
    .contains(&parsed.scheme())
    {
        return Err("Unsupported launch protocol".into());
    }
    #[cfg(target_os = "macos")]
    let mut cmd = {
        let mut c = Command::new("/usr/bin/open");
        c.arg(url);
        c
    };
    #[cfg(target_os = "windows")]
    let mut cmd = {
        let mut c = Command::new("rundll32.exe");
        c.args(["url.dll,FileProtocolHandler", url]);
        c
    };
    #[cfg(target_os = "linux")]
    let mut cmd = {
        let mut c = Command::new("xdg-open");
        c.arg(url);
        c
    };
    spawn_reaped(&mut cmd)?;
    Ok(())
}
fn compatibility(game: &Game, uninstall: bool, root: &Path) -> Result<(), String> {
    let plan = game
        .compatibility
        .as_ref()
        .ok_or("No compatibility launch plan")?;
    let executable = Path::new(&plan.executable);
    if !["wine", "wine64", "wine64-preloader"].contains(
        &executable
            .file_name()
            .unwrap_or_default()
            .to_string_lossy()
            .as_ref(),
    ) || !executable.is_file()
    {
        return Err(
            "The existing Wine runtime is unavailable; rescan after connecting its disk".into(),
        );
    }
    let prefix = plan
        .environment
        .get("WINEPREFIX")
        .ok_or("Wine prefix is missing")?;
    if !Path::new(prefix).join("drive_c").is_dir() {
        return Err("Wine prefix is unavailable".into());
    }
    let steam = plan
        .arguments
        .first()
        .filter(|p| p.to_lowercase().ends_with("steam.exe") && Path::new(p).is_file())
        .ok_or("Steam executable is missing")?;
    let mut command = Command::new(executable);
    if uninstall {
        if game.store_id.parse::<u64>().is_err() {
            return Err("Invalid Steam app ID".into());
        }
        command.args([steam, &format!("steam://uninstall/{}", game.store_id)]);
    } else {
        command.args(&plan.arguments);
    }
    for (key, value) in &plan.environment {
        if [
            "WINEPREFIX",
            "CX_BOTTLE",
            "DYLD_FALLBACK_LIBRARY_PATH",
            "WINEESYNC",
            "WINEMSYNC",
            "WINEDEBUG",
            "DXVK",
            "D3DMETAL",
            "WINEDLLOVERRIDES",
            "FONTCONFIG_PATH",
            "FONTCONFIG_ROOT",
            "FONT_ENCODINGS_DIRECTORY",
            "VERSIONER_PERL_PREFER_32_BIT",
        ]
        .contains(&key.as_str())
        {
            command.env(key, value);
        }
    }
    let logs = root.join("Logs");
    fs::create_dir_all(&logs).map_err(|e| e.to_string())?;
    let log = fs::File::create(logs.join(hash(&game.id) + ".log")).map_err(|e| e.to_string())?;
    let error_log = log.try_clone().map_err(|e| e.to_string())?;
    command
        .current_dir(&plan.working_directory)
        .stdin(Stdio::null())
        .stdout(log)
        .stderr(error_log);
    spawn_reaped(&mut command)?;
    Ok(())
}
pub fn launch(game: &Game, root: &Path) -> Result<(), String> {
    if game.launch_kind == "store" {
        return open_uri(&game.launch_target);
    }
    if game.launch_kind == "compatibility" {
        return compatibility(game, false, root);
    }
    let path = Path::new(&game.launch_target);
    if !path.exists() {
        return Err("Game path is missing. Reconnect its disk or add its new location.".into());
    }
    let mut command = if path.extension().is_some_and(|e| e == "app") {
        #[cfg(target_os = "macos")]
        {
            let mut c = Command::new("/usr/bin/open");
            c.arg(path);
            c
        }
        #[cfg(not(target_os = "macos"))]
        {
            return Err("Mac application bundles require macOS".into());
        }
    } else if game.launch_kind == "desktop" {
        #[cfg(target_os = "linux")]
        {
            let mut c = Command::new("gio");
            c.arg("launch").arg(path);
            c
        }
        #[cfg(not(target_os = "linux"))]
        {
            return Err("Desktop entries require Linux".into());
        }
    } else {
        if path
            .extension()
            .is_some_and(|e| ["bat", "cmd", "ps1", "sh"].iter().any(|x| e == *x))
        {
            return Err("Shell scripts are not supported as direct game launch targets".into());
        }
        Command::new(path)
    };
    spawn_reaped(&mut command)?;
    Ok(())
}
#[derive(Serialize)]
pub struct UninstallPlan {
    pub title: String,
    pub message: String,
    pub method: String,
}
pub fn uninstall_plan(game: &Game) -> Result<UninstallPlan, String> {
    if game.launch_kind == "compatibility" {
        return Ok(UninstallPlan{title:format!("Uninstall {} in Wine Steam?",game.name),message:"Steam inside the original prefix opens its uninstall dialog. Metadata stays until removal is confirmed.".into(),method:"compatibility".into()});
    }
    if game.launch_kind == "store" {
        let client = if game.launch_target.starts_with("heroic:") {
            "Heroic"
        } else {
            &game.store
        };
        return Ok(UninstallPlan{title:format!("Uninstall {}?",game.name),message:format!("Open {client} and complete its uninstall flow. Metadata stays until removal is confirmed."),method:"client".into()});
    }
    let path = Path::new(&game.launch_target);
    if cfg!(windows) || game.launch_kind == "desktop" {
        return Ok(UninstallPlan{title:format!("Manage {} in the system uninstaller",game.name),message:"Use the original installer or system package manager to remove this game. Playnite does not remove a lone executable and leave the installation behind.".into(),method:"system".into()});
    }
    if path.is_symlink()
        || game.install_path != game.launch_target
        || !path.exists()
        || path.starts_with("/System")
        || path.starts_with("/Library")
        || path.to_string_lossy().contains(".app/")
        || path
            .file_stem()
            .unwrap_or_default()
            .to_string_lossy()
            .to_lowercase()
            .starts_with("playnite")
    {
        return Err("Only the game's existing standalone app can be moved to Trash; system apps, links and Playnite are protected".into());
    }
    if !path
        .extension()
        .is_some_and(|e| e == "app" || e == "AppImage")
    {
        return Err("Uninstall this game through its original package manager".into());
    }
    Ok(UninstallPlan{title:format!("Move {} to Trash?",game.name),message:format!("Move {} to Trash, including data inside its bundle. External saves stay in place. Metadata is removed only after success. Quit the game first.",path.display()),method:"trash".into()})
}
pub fn uninstall(store: &mut Store, id: &str) -> Result<(), String> {
    if let Some(error) = &store.error {
        return Err(error.clone());
    }
    let game = store.game(id)?;
    let plan = uninstall_plan(&game)?;
    if plan.method == "trash" {
        trash::delete(&game.launch_target).map_err(|e| e.to_string())?;
        if Path::new(&game.launch_target).exists() {
            return Err("Application is still present; metadata retained".into());
        }
        store.library.games.retain(|g| g.id != id);
        store.save()?;
        let folder = store.root.join("Media").join(hash(id));
        if folder.exists() {
            fs::remove_dir_all(folder).map_err(|e| e.to_string())?
        }
    } else {
        if plan.method == "compatibility" {
            compatibility(&game, true, &store.root)?
        } else if game.store == "Steam" && game.store_id.parse::<u64>().is_ok() {
            open_uri(&format!("steam://uninstall/{}", game.store_id))?
        } else if game.launch_target.starts_with("heroic:") {
            open_uri("heroic://")?
        } else if game.store == "Epic" {
            open_uri("com.epicgames.launcher://")?
        } else if cfg!(windows) {
            open_uri("ms-settings:appsfeatures")?
        } else {
            let parent = Path::new(&game.install_path)
                .parent()
                .ok_or("Missing installation folder")?;
            let mut command = Command::new("xdg-open");
            command.arg(parent);
            spawn_reaped(&mut command)?;
        }
        if let Some(current) = store.library.games.iter_mut().find(|g| g.id == id) {
            current.pending_uninstall = Some(true)
        }
        store.save()?;
    }
    Ok(())
}
pub fn enrich(state: &AppState, id: &str, source: Option<&str>) -> Result<(), String> {
    let (original, root) = {
        let store = state.store.lock().map_err(|e| e.to_string())?;
        if store.error.is_some() {
            return Err("Library is read-only".into());
        }
        (store.game(id)?, store.root.clone())
    };
    let client = Client::new()?;
    let details = if let Some(source) = source {
        if let Some(publisher) = metadata::publishers().into_iter().find(|p| p.id == source) {
            metadata::Details {
                name: publisher.name,
                summary: publisher.summary,
                developer: publisher.developer,
                artwork: publisher.artwork,
                url: publisher.url,
                source: publisher.source,
                genres: publisher.genres,
                ..Default::default()
            }
        } else {
            client.page(source)?
        }
    } else {
        client.automatic(&original)?
    };
    let mut updated = original.clone();
    details.apply(&mut updated);
    client.artwork(&mut updated, &root);
    let mut store = state.store.lock().map_err(|e| e.to_string())?;
    if let Some(current) = store.library.games.iter_mut().find(|g| g.id == id) {
        if current.metadata_updated != original.metadata_updated {
            return Ok(());
        }
        details.apply(current);
        current.cached_artwork = updated.cached_artwork;
        current.cached_landscape = updated.cached_landscape;
        current.cached_background = updated.cached_background;
        store.save()?;
    } else {
        let _ = fs::remove_dir_all(root.join("Media").join(hash(id)));
    }
    Ok(())
}
impl AppState {
    pub fn snapshot(&self) -> Result<Snapshot, String> {
        Ok(self.store.lock().map_err(|e| e.to_string())?.snapshot())
    }
    pub fn hydrate(&self, all: bool, notify: impl Fn(Snapshot)) -> Result<(), String> {
        self.cancel.store(false, Ordering::Relaxed);
        let ids: Vec<_> = {
            let store = self.store.lock().map_err(|e| e.to_string())?;
            store
                .library
                .games
                .iter()
                .filter(|g| all || g.metadata_updated.is_none())
                .map(|g| g.id.clone())
                .collect()
        };
        for id in ids {
            if self.cancel.load(Ordering::Relaxed) {
                break;
            }
            if let Err(error) = enrich(self, &id, None) {
                let mut store = self.store.lock().map_err(|e| e.to_string())?;
                store.notices.push(error)
            }
            if let Ok(snapshot) = self.snapshot() {
                notify(snapshot)
            }
            std::thread::sleep(std::time::Duration::from_millis(250))
        }
        let pending = {
            let store = self.store.lock().map_err(|e| e.to_string())?;
            store.library.games.clone()
        };
        let client = Client::new()?;
        for original in pending {
            if self.cancel.load(Ordering::Relaxed) {
                break;
            }
            let root = self.store.lock().map_err(|e| e.to_string())?.root.clone();
            let mut game = original.clone();
            client.artwork(&mut game, &root);
            let mut store = self.store.lock().map_err(|e| e.to_string())?;
            if let Some(current) = store.library.games.iter_mut().find(|g| g.id == game.id) {
                if current.artwork == original.artwork {
                    let changed = current.cached_artwork != game.cached_artwork
                        || current.cached_landscape != game.cached_landscape
                        || current.cached_background != game.cached_background;
                    current.cached_artwork = game.cached_artwork;
                    current.cached_landscape = game.cached_landscape;
                    current.cached_background = game.cached_background;
                    if changed {
                        store.save()?;
                        drop(store);
                        if let Ok(snapshot) = self.snapshot() {
                            notify(snapshot)
                        }
                    }
                }
            }
        }
        Ok(())
    }
}
#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn atomic_backup_and_unknown_fields() {
        let t = tempfile::tempdir().unwrap();
        let mut library = Library::default();
        let game: Game =
            serde_json::from_str(r#"{"id":"fixture","name":"Fixture","futureField":42}"#).unwrap();
        library.games.push(game);
        save_library(t.path(), &library).unwrap();
        save_library(t.path(), &Library::default()).unwrap();
        let backup: Library =
            serde_json::from_slice(&fs::read(t.path().join("library.json.backup")).unwrap())
                .unwrap();
        assert_eq!(backup.games[0].extra["futureField"], 42);
    }
    #[test]
    fn no_cleanup_for_disconnected_volume() {
        let g = Game {
            install_path: "/Volumes/Disconnected-Playnite-Test/Games/A.app".into(),
            pending_uninstall: Some(true),
            ..Default::default()
        };
        assert!(!confirmed_missing(&g));
    }
    #[test]
    fn corrupt_load_is_not_replaced() {
        let t = tempfile::tempdir().unwrap();
        fs::write(t.path().join("library.json"), "broken").unwrap();
        let raw = fs::read(t.path().join("library.json")).unwrap();
        assert!(serde_json::from_slice::<Library>(&raw).is_err());
        assert_eq!(fs::read(t.path().join("library.json")).unwrap(), b"broken");
    }
}
