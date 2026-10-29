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
    pub backup: crate::backup::Control,
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
        let root = std::env::var("JOYNITE_DATA_DIRECTORY")
            .or_else(|_| std::env::var("PLAYNITE_DATA_DIRECTORY"))
            .map(PathBuf::from)
            .unwrap_or_else(|_| {
                dirs::data_dir()
                    .unwrap_or_else(|| PathBuf::from("."))
                    .join("JoyniteDesktop")
            });
        let mut error = None;
        let mut library = Library::default();
        if let Err(e) = fs::create_dir_all(&root) {
            error = Some(format!("Cannot create library directory: {e}"))
        }
        let file = root.join("library.json");
        if std::env::var_os("JOYNITE_DATA_DIRECTORY").is_none()
            && std::env::var_os("PLAYNITE_DATA_DIRECTORY").is_none()
        {
            let mut candidates = vec![];
            if let Some(base) = dirs::data_dir() {
                candidates.push(base.join("PlayniteCarousel"));
            }
            if cfg!(target_os = "macos") {
                if let Some(home) = dirs::home_dir() {
                    candidates.push(home.join("Library/Application Support/Joynite"));
                    candidates.push(home.join("Library/Application Support/PlayniteMac"));
                }
            }
            if let Err(e) = migrate_library(&root, &candidates) {
                error = Some(format!(
                    "Library migration failed; previous files remain intact: {e}"
                ));
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
    pub fn view_game(&self, game: &Game) -> UiGame {
        let file = |key: &Option<String>| {
            metadata::cache_file(&self.root, game, key).map(|p| p.to_string_lossy().into_owned())
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
    }
    pub fn snapshot(&self) -> Snapshot {
        let games = self
            .library
            .games
            .iter()
            .map(|game| self.view_game(game))
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
    pub fn set_launch_action(
        &mut self,
        id: &str,
        action: Option<crate::model::LaunchAction>,
    ) -> Result<(), String> {
        self.ensure_writable()?;
        if let Some(action) = &action {
            crate::launch_plan::validate_action(action)?;
        }
        let mut next = self.library.clone();
        next.games
            .iter_mut()
            .find(|g| g.id == id)
            .ok_or("Game no longer exists")?
            .launch_action = action;
        save_library(&self.root, &next)?;
        self.library = next;
        self.revision += 1;
        Ok(())
    }
    pub fn record_launch(&mut self, id: &str) -> Result<(), String> {
        self.ensure_writable()?;
        let mut next = self.library.clone();
        next.games
            .iter_mut()
            .find(|g| g.id == id)
            .ok_or("Game no longer exists")?
            .record_launch();
        save_library(&self.root, &next)?;
        self.library = next;
        self.revision += 1;
        Ok(())
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
            if let Some(current) = self.library.games.iter_mut().find(|g| {
                g.id == found.id
                    || (found.store == "GOG"
                        && ["Mac", "Local", "GOG"].contains(&g.store.as_str())
                        && if cfg!(windows) {
                            g.launch_target.eq_ignore_ascii_case(&found.launch_target)
                        } else {
                            g.launch_target == found.launch_target
                        })
            }) {
                if found.store == "GOG" {
                    current.store = found.store.clone();
                    current.store_id = found.store_id.clone();
                }
                current.launch_target = found.launch_target;
                current.install_path = found.install_path;
                current.compatibility = found.compatibility;
                if let Some(action) = found.extra.get("defaultLaunchAction") {
                    current
                        .extra
                        .insert("defaultLaunchAction".into(), action.clone());
                }
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
fn migrate_library(root: &Path, sources: &[PathBuf]) -> std::io::Result<()> {
    if root.join("library.json").exists() {
        return Ok(());
    }
    let Some(source) = sources.iter().find(|s| s.join("library.json").is_file()) else {
        return Ok(());
    };
    fs::create_dir_all(root)?;
    copy_tree(&source.join("Media"), &root.join("Media"))?;
    if source.join("library.json.backup").is_file() {
        fs::copy(
            source.join("library.json.backup"),
            root.join("library.json.backup"),
        )?;
    }
    let temporary = root.join("library.migration.tmp");
    fs::copy(source.join("library.json"), &temporary)?;
    fs::rename(temporary, root.join("library.json"))?;
    Ok(())
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
pub fn validate_uri(url: &str) -> Result<(), String> {
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
    Ok(())
}
pub fn open_uri(url: &str) -> Result<(), String> {
    validate_uri(url)?;
    #[cfg(target_os = "macos")]
    let mut cmd = {
        let mut c = Command::new("/usr/bin/open");
        c.arg(url);
        c
    };
    #[cfg(target_os = "windows")]
    return crate::windows_launch::open(std::ffi::OsStr::new(url), "", None);
    #[cfg(target_os = "linux")]
    let mut cmd = {
        let mut c = Command::new("xdg-open");
        c.arg(url);
        c
    };
    #[cfg(not(windows))]
    {
        spawn_reaped(&mut cmd)?;
        Ok(())
    }
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
    spawn_tracked(&mut command, root, &game.id)?;
    Ok(())
}
fn diagnostic(
    root: &Path,
    id: &str,
    state: &str,
    detail: &str,
    pid: Option<u32>,
    exit_code: Option<i32>,
    elapsed: Option<f64>,
) {
    let logs = root.join("Logs");
    if fs::create_dir_all(&logs).is_err() {
        return;
    }
    let path = logs.join(hash(id) + ".launch.json");
    if state == "exited" {
        if let Ok(bytes) = fs::read(&path) {
            if let Ok(report) = serde_json::from_slice::<serde_json::Value>(&bytes) {
                if report["processID"].as_u64() != pid.map(u64::from) {
                    return;
                }
            }
        }
    }
    let temporary = logs.join(hash(id) + ".launch.tmp");
    let value = serde_json::json!({"state":state,"detail":detail,"processID":pid,"exitCode":exit_code,"elapsedSeconds":elapsed,"timestamp":crate::model::now()});
    if let Ok(bytes) = serde_json::to_vec(&value) {
        if fs::write(&temporary, bytes).is_ok() {
            let _ = fs::rename(temporary, path);
        }
    }
}
fn spawn_tracked(command: &mut Command, root: &Path, id: &str) -> Result<(), String> {
    command.stdin(Stdio::null());
    let mut child = command.spawn().map_err(|e| e.to_string())?;
    let pid = child.id();
    diagnostic(
        root,
        id,
        "accepted",
        "Joynite started the process. Game-menu arrival is not verified.",
        Some(pid),
        None,
        None,
    );
    let root = root.to_path_buf();
    let id = id.to_owned();
    let start = std::time::Instant::now();
    std::thread::spawn(move || {
        if let Ok(status) = child.wait() {
            diagnostic(
                &root,
                &id,
                "exited",
                if start.elapsed().as_secs() < 5 {
                    "Process exited early. This may be a launcher handoff; inspect the runtime/client for errors."
                } else {
                    "Process exited. Game-menu arrival was not verified."
                },
                Some(pid),
                status.code(),
                Some(start.elapsed().as_secs_f64()),
            );
        }
    });
    Ok(())
}
pub fn record_failed_launch(game: &Game, root: &Path, error: &str) {
    diagnostic(root, &game.id, "failed", error, None, None, None);
}
pub fn launch(game: &Game, root: &Path) -> Result<(), String> {
    if let Some(action) = &game.launch_action {
        return launch_action(game, action, root);
    }
    if let Some(action) = game.extra.get("defaultLaunchAction") {
        let action: crate::model::LaunchAction = serde_json::from_value(action.clone())
            .map_err(|e| format!("Invalid installed-game action: {e}"))?;
        return launch_action(game, &action, root);
    }
    if game.launch_kind == "store" {
        open_uri(&game.launch_target)?;
        diagnostic(root,&game.id,"accepted","A store launch request was handed to the operating system. Complete client prompts; game-menu arrival is not verified.",None,None,None);
        return Ok(());
    }
    if game.launch_kind == "compatibility" {
        return compatibility(game, false, root);
    }
    let path = Path::new(&game.launch_target);
    if !path.exists() {
        return Err("Game path is missing. Reconnect its disk or add its new location.".into());
    }
    #[cfg(windows)]
    {
        if !path.is_file()
            || !path
                .extension()
                .is_some_and(|e| e.eq_ignore_ascii_case("exe") || e.eq_ignore_ascii_case("lnk"))
        {
            return Err("Choose a Windows game executable or its working .lnk shortcut".into());
        }
        let data = PathBuf::from(
            std::env::var("PROGRAMDATA").unwrap_or_else(|_| r"C:\ProgramData".into()),
        );
        let plan = crate::launch_plan::riot_target(path, &data)?;
        let (target, arguments) = plan
            .as_ref()
            .map(|(p, a)| (p.as_path(), a.as_str()))
            .unwrap_or((path, ""));
        crate::windows_launch::open(target.as_os_str(), arguments, target.parent())?;
        diagnostic(root, &game.id, "accepted", "Windows shell accepted the launch. Client prompts and game-menu arrival remain unverified.", None, None, None);
        return Ok(());
    }
    #[cfg(not(windows))]
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
        return launch_desktop(path, root, &game.id);
    } else {
        if path
            .extension()
            .is_some_and(|e| ["bat", "cmd", "ps1", "sh"].iter().any(|x| e == *x))
        {
            return Err("Shell scripts are not supported as direct game launch targets".into());
        }
        Command::new(path)
    };
    #[cfg(not(windows))]
    {
        if let Some(parent) = path.parent() {
            command.current_dir(parent);
        }
        spawn_tracked(&mut command, root, &game.id)?;
        Ok(())
    }
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
        return Ok(UninstallPlan{title:format!("Manage {} in the system uninstaller",game.name),message:"Use the original installer or system package manager to remove this game. Joynite does not remove a lone executable and leave the installation behind.".into(),method:"system".into()});
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
            .starts_with("joynite")
        || path
            .file_stem()
            .unwrap_or_default()
            .to_string_lossy()
            .to_lowercase()
            .starts_with("playnite")
    {
        return Err("Only the game's existing standalone app can be moved to Trash; system apps, links and Joynite are protected".into());
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
                background: publisher.background,
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
    if source.is_some() && details.steam_id.is_empty() {
        updated.extra.remove("metadataSteamId");
    }
    details.apply(&mut updated);
    client.artwork(&mut updated, &root);
    let mut store = state.store.lock().map_err(|e| e.to_string())?;
    if let Some(current) = store.library.games.iter_mut().find(|g| g.id == id) {
        if current.metadata_updated != original.metadata_updated {
            return Ok(());
        }
        if source.is_some() && details.steam_id.is_empty() {
            current.extra.remove("metadataSteamId");
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
#[derive(Serialize)]
pub struct LibraryPatch {
    pub games: Vec<UiGame>,
    pub notices: Vec<String>,
    pub revision: u64,
}
impl AppState {
    pub fn snapshot(&self) -> Result<Snapshot, String> {
        Ok(self.store.lock().map_err(|e| e.to_string())?.snapshot())
    }
    fn patch(&self, id: &str, cursor: &mut usize) -> Result<LibraryPatch, String> {
        let store = self.store.lock().map_err(|e| e.to_string())?;
        let games = store
            .library
            .games
            .iter()
            .find(|g| g.id == id)
            .map(|g| vec![store.view_game(g)])
            .unwrap_or_default();
        let notices = store.notices[(*cursor).min(store.notices.len())..].to_vec();
        *cursor = store.notices.len();
        Ok(LibraryPatch {
            games,
            notices,
            revision: store.revision,
        })
    }
    pub fn hydrate(&self, all: bool, notify: impl Fn(LibraryPatch)) -> Result<(), String> {
        self.cancel.store(false, Ordering::Relaxed);
        let ids: Vec<_> = {
            let store = self.store.lock().map_err(|e| e.to_string())?;
            store
                .library
                .games
                .iter()
                .filter(|g| all || metadata::needs_metadata(g))
                .map(|g| g.id.clone())
                .collect()
        };
        let mut notice_cursor = self.store.lock().map_err(|e| e.to_string())?.notices.len();
        for id in ids {
            if self.cancel.load(Ordering::Relaxed) {
                break;
            }
            if let Err(error) = enrich(self, &id, None) {
                let mut store = self.store.lock().map_err(|e| e.to_string())?;
                store.notices.push(error)
            }
            if let Ok(patch) = self.patch(&id, &mut notice_cursor) {
                notify(patch)
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
                        if let Ok(patch) = self.patch(&game.id, &mut notice_cursor) {
                            notify(patch)
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
            install_path: "/Volumes/Disconnected-Joynite-Test/Games/A.app".into(),
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

#[cfg(test)]
mod joynite_migration_tests {
    use super::*;
    #[test]
    fn migration_preserves_previous_library_media_and_new_edits() {
        let temp = tempfile::tempdir().unwrap();
        let old = temp.path().join("PlayniteCarousel");
        let root = temp.path().join("JoyniteDesktop");
        fs::create_dir_all(old.join("Media/game")).unwrap();
        fs::write(
            old.join("library.json"),
            br#"{"version":1,"games":[],"folders":[]}"#,
        )
        .unwrap();
        fs::write(old.join("Media/game/cover.png"), b"fixture").unwrap();
        migrate_library(&root, &[old.clone()]).unwrap();
        assert_eq!(
            fs::read(root.join("library.json")).unwrap(),
            fs::read(old.join("library.json")).unwrap()
        );
        assert_eq!(
            fs::read(root.join("Media/game/cover.png")).unwrap(),
            b"fixture"
        );
        fs::write(root.join("library.json"), b"edited").unwrap();
        migrate_library(&root, &[old.clone()]).unwrap();
        assert_eq!(fs::read(root.join("library.json")).unwrap(), b"edited");
        assert!(old.join("library.json").is_file());
    }
    #[test]
    fn launcher_identity_keeps_old_and_new_apps_out_of_library() {
        for id in [
            "io.github.joy-arz.JoyniteNative",
            "io.github.joy-arz.joynite.desktop",
            "io.github.joy-arz.PlayniteMac",
            "io.github.joy-arz.playnite-carousel",
        ] {
            assert!(crate::model::is_launcher_id(id));
        }
        assert!(!crate::model::is_launcher_id("com.game.inscryption"));
    }
}
#[cfg(test)]
mod performance_tests {
    use super::*;
    #[test]
    #[ignore]
    fn large_library_profile() {
        for count in [1000, 10000] {
            let root = tempfile::tempdir().unwrap();
            let games = (0..count)
                .map(|i| Game {
                    id: format!("benchmark-{i}"),
                    name: format!("Game {i} Adventure"),
                    ..Default::default()
                })
                .collect();
            let store = Store {
                library: Library {
                    games,
                    ..Default::default()
                },
                root: root.path().to_path_buf(),
                error: None,
                notices: vec![],
                revision: 1,
            };
            let start = std::time::Instant::now();
            let snapshot = store.snapshot();
            let snapshot_ms = start.elapsed().as_secs_f64() * 1000.0;
            let start = std::time::Instant::now();
            let bytes = serde_json::to_vec(&snapshot).unwrap();
            let json_ms = start.elapsed().as_secs_f64() * 1000.0;
            let start = std::time::Instant::now();
            save_library(root.path(), &store.library).unwrap();
            println!("BENCH shared count={count} snapshot_ms={snapshot_ms:.2} serialize_ms={json_ms:.2} save_ms={:.2} bytes={}",start.elapsed().as_secs_f64()*1000.0,bytes.len());
        }
    }
}
#[cfg(test)]
mod launch_and_patch_tests {
    use super::*;
    #[test]
    fn accepted_launch_counts_commit_atomically_and_failed_paths_do_not_count() {
        let root = tempfile::tempdir().unwrap();
        let game = Game {
            id: "counter".into(),
            name: "Counter".into(),
            launch_target: root.path().join("missing").to_string_lossy().into_owned(),
            ..Default::default()
        };
        let mut store = Store {
            library: Library {
                games: vec![game.clone()],
                ..Default::default()
            },
            root: root.path().to_path_buf(),
            error: None,
            notices: vec![],
            revision: 1,
        };
        assert!(launch(&game, root.path()).is_err());
        assert_eq!(store.library.games[0].launch_count, 0);
        store.record_launch("counter").unwrap();
        assert_eq!(store.library.games[0].launch_count, 1);
        let disk: Library =
            serde_json::from_slice(&fs::read(root.path().join("library.json")).unwrap()).unwrap();
        assert_eq!(disk.games[0].launch_count, 1);
        let blocked = root.path().join("blocked");
        fs::write(&blocked, b"file").unwrap();
        store.root = blocked;
        assert!(store.record_launch("counter").is_err());
        assert_eq!(store.library.games[0].launch_count, 1);
    }
    #[test]
    fn metadata_patch_contains_one_record_at_large_library_scale() {
        let root = tempfile::tempdir().unwrap();
        let state = AppState {
            backup: Default::default(),
            cancel: AtomicBool::new(false),
            store: Mutex::new(Store {
                root: root.path().to_path_buf(),
                library: Library {
                    games: (0..10000)
                        .map(|i| Game {
                            id: i.to_string(),
                            name: format!("Game {i}"),
                            ..Default::default()
                        })
                        .collect(),
                    ..Default::default()
                },
                error: None,
                notices: vec!["one notice".into()],
                revision: 12,
            }),
        };
        let mut cursor = 0;
        let patch = state.patch("25", &mut cursor).unwrap();
        assert_eq!(patch.games.len(), 1);
        assert_eq!(patch.games[0].game.id, "25");
        assert_eq!(patch.notices.len(), 1);
        assert!(serde_json::to_vec(&patch).unwrap().len() < 3000);
        assert!(state
            .patch("removed", &mut cursor)
            .unwrap()
            .games
            .is_empty());
        assert_eq!(cursor, 1);
    }
}

fn launch_action(
    game: &Game,
    action: &crate::model::LaunchAction,
    root: &Path,
) -> Result<(), String> {
    crate::launch_plan::validate_action(action)?;
    if action.kind == "url" {
        open_uri(&action.target)?;
        diagnostic(
            root,
            &game.id,
            "accepted",
            "Configured client URL accepted. Game-menu arrival is unverified.",
            None,
            None,
            None,
        );
        return Ok(());
    }
    let path = Path::new(&action.target);
    if !path.exists() {
        return Err(
            "Configured application is missing. Reconnect its disk or edit Launch settings.".into(),
        );
    }
    let directory = if action.working_directory.is_empty() {
        path.parent()
    } else {
        Some(Path::new(&action.working_directory))
    };
    if directory.is_some_and(|p| !p.is_dir()) {
        return Err("Configured working directory is unavailable".into());
    }
    #[cfg(windows)]
    {
        if !path.is_file()
            || !path
                .extension()
                .is_some_and(|e| e.eq_ignore_ascii_case("exe") || e.eq_ignore_ascii_case("lnk"))
        {
            return Err("Choose a Windows .exe or .lnk application".into());
        }
        crate::windows_launch::open_configured(
            path.as_os_str(),
            &crate::launch_plan::windows_arguments(&action.arguments),
            directory,
            action.run_as_admin,
        )?;
        diagnostic(root, &game.id, "accepted", "Configured Windows launch accepted. Complete any client/permission prompts; game-menu arrival is unverified.", None, None, None);
        return Ok(());
    }
    #[cfg(not(windows))]
    {
        if path.extension().is_some_and(|e| e == "desktop") {
            if !action.arguments.is_empty() {
                return Err("Edit launch arguments in the desktop entry itself".into());
            }
            return launch_desktop(path, root, &game.id);
        }
        if path
            .extension()
            .is_some_and(|e| ["sh", "bat", "cmd", "ps1"].iter().any(|x| e == *x))
        {
            return Err("Choose a game application or desktop entry".into());
        }
        let mut command = if path.extension().is_some_and(|e| e == "app") {
            #[cfg(target_os = "macos")]
            {
                let mut c = Command::new("/usr/bin/open");
                c.arg("-a").arg(path);
                if !action.arguments.is_empty() {
                    c.arg("--args");
                }
                c
            }
            #[cfg(not(target_os = "macos"))]
            {
                return Err("Mac application bundles require macOS".into());
            }
        } else {
            Command::new(path)
        };
        command.args(&action.arguments);
        if let Some(directory) = directory {
            command.current_dir(directory);
        }
        spawn_tracked(&mut command, root, &game.id)
    }
}

fn launch_desktop(path: &Path, root: &Path, id: &str) -> Result<(), String> {
    #[cfg(target_os = "linux")]
    {
        // Do not capture inherited pipes: a game can keep them open after GIO exits.
        let status = Command::new("gio").arg("launch").arg(path).stdin(Stdio::null()).stdout(Stdio::null()).stderr(Stdio::null()).status().map_err(|e| format!("Cannot open the desktop entry with GIO: {e}. Install GIO utilities or choose the game executable."))?;
        if !status.success() {
            return Err(format!("Desktop activation failed (GIO exit {}). Check that the desktop entry launches in your current desktop/Flatpak session, or choose its executable in Launch settings.",status.code().map_or("unknown".into(),|c|c.to_string())));
        }
        diagnostic(root, id, "accepted", "Desktop entry accepted by GIO, including its Exec/Path and activation settings. Game-menu arrival is unverified.", None, None, None);
        Ok(())
    }
    #[cfg(not(target_os = "linux"))]
    {
        let _ = (path, root, id);
        Err("Desktop entries require Linux".into())
    }
}

#[cfg(test)]
mod launch_settings_persistence_tests {
    use super::*;
    #[test]
    fn action_changes_commit_before_publish_and_survive_backups() {
        let t = tempfile::tempdir().unwrap();
        let mut store = Store {
            library: Library {
                games: vec![Game {
                    id: "game".into(),
                    launch_count: 9,
                    favorite: true,
                    ..Default::default()
                }],
                ..Default::default()
            },
            root: t.path().to_owned(),
            error: None,
            notices: vec![],
            revision: 0,
        };
        let action = crate::model::LaunchAction {
            kind: "url".into(),
            target: "steam://rungameid/42".into(),
            ..Default::default()
        };
        store.set_launch_action("game", Some(action)).unwrap();
        assert_eq!(store.revision, 1);
        let saved: Library =
            serde_json::from_slice(&fs::read(t.path().join("library.json")).unwrap()).unwrap();
        assert_eq!(
            saved.games[0].launch_action.as_ref().unwrap().target,
            "steam://rungameid/42"
        );
        assert_eq!(saved.games[0].launch_count, 9);
        let blocked = t.path().join("blocked");
        fs::write(&blocked, b"file").unwrap();
        store.root = blocked;
        assert!(store.set_launch_action("game", None).is_err());
        assert!(store.library.games[0].launch_action.is_some());
        assert_eq!(store.revision, 1);
        store.root = t.path().to_owned();
        store.set_launch_action("game", None).unwrap();
        assert!(store.library.games[0].launch_action.is_none());
        assert!(store.library.games[0].favorite);
        let backup: Library =
            serde_json::from_slice(&fs::read(t.path().join("library.json.backup")).unwrap())
                .unwrap();
        assert!(backup.games[0].launch_action.is_some());
    }
}
