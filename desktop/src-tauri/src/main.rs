#![cfg_attr(not(debug_assertions), windows_subsystem = "windows")]
mod backup;
mod discovery;
mod launch_plan;
mod library;
mod metadata;
mod model;
mod vdf;
#[cfg(windows)]
mod windows_launch;
use library::{AppState, Snapshot, Store};
use model::Game;
use std::{
    path::PathBuf,
    sync::{
        atomic::{AtomicBool, Ordering},
        Arc, Mutex,
    },
};
use tauri::{Emitter, Manager};
type State<'a> = tauri::State<'a, Arc<AppState>>;
#[tauri::command]
async fn get_library(state: State<'_>) -> Result<Snapshot, String> {
    state.snapshot()
}
#[tauri::command]
async fn scan_games(state: State<'_>) -> Result<Snapshot, String> {
    let state = state.inner().clone();
    tauri::async_runtime::spawn_blocking(move || {
        state.store.lock().map_err(|e| e.to_string())?.scan()?;
        state.snapshot()
    })
    .await
    .map_err(|e| e.to_string())?
}
#[tauri::command]
async fn hydrate_metadata(
    app: tauri::AppHandle,
    state: State<'_>,
    all: bool,
) -> Result<Snapshot, String> {
    let state = state.inner().clone();
    tauri::async_runtime::spawn_blocking(move || {
        state.hydrate(all, |patch| {
            let _ = app.emit("library-patched", &patch);
        })?;
        state.snapshot()
    })
    .await
    .map_err(|e| e.to_string())?
}
#[tauri::command]
fn cancel_metadata(state: State<'_>) {
    state.cancel.store(true, Ordering::Relaxed);
}
#[tauri::command]
async fn launch_game(state: State<'_>, id: String) -> Result<Snapshot, String> {
    let state = state.inner().clone();
    tauri::async_runtime::spawn_blocking(move || {
        let (game, root) = {
            let store = state.store.lock().map_err(|e| e.to_string())?;
            store.ensure_writable()?;
            (store.game(&id)?, store.root.clone())
        };
        if let Err(error) = library::launch(&game, &root) {
            library::record_failed_launch(&game, &root, &error);
            return Err(error);
        }
        let mut store = state.store.lock().map_err(|e| e.to_string())?;
        store.record_launch(&id)?;
        Ok(store.snapshot())
    })
    .await
    .map_err(|e| e.to_string())?
}
#[tauri::command]
fn launch_diagnostics(state: State<'_>, id: String) -> Result<serde_json::Value, String> {
    let store = state.store.lock().map_err(|e| e.to_string())?;
    store.game(&id)?;
    let path = store
        .root
        .join("Logs")
        .join(model::hash(&id) + ".launch.json");
    if !path.exists() {
        return Ok(serde_json::Value::Null);
    }
    if std::fs::metadata(&path).map_err(|e| e.to_string())?.len() > 65536 {
        return Err("Diagnostic report is too large".into());
    }
    serde_json::from_slice(&std::fs::read(path).map_err(|e| e.to_string())?)
        .map_err(|e| e.to_string())
}
#[tauri::command]
async fn update_game(
    state: State<'_>,
    id: String,
    favorite: Option<bool>,
    hidden: Option<bool>,
) -> Result<Snapshot, String> {
    let mut store = state.store.lock().map_err(|e| e.to_string())?;
    store.ensure_writable()?;
    let game = store
        .library
        .games
        .iter_mut()
        .find(|g| g.id == id)
        .ok_or("Game no longer exists")?;
    if let Some(value) = favorite {
        game.favorite = value
    }
    if let Some(value) = hidden {
        game.hidden = Some(value)
    }
    store.save()?;
    Ok(store.snapshot())
}
#[tauri::command]
async fn restore_hidden(state: State<'_>) -> Result<Snapshot, String> {
    let mut store = state.store.lock().map_err(|e| e.to_string())?;
    store.ensure_writable()?;
    for game in &mut store.library.games {
        game.hidden = Some(false)
    }
    store.save()?;
    Ok(store.snapshot())
}
#[tauri::command]
async fn add_folder(state: State<'_>, path: String) -> Result<Snapshot, String> {
    let path = PathBuf::from(path);
    if !path.is_dir() {
        return Err("Choose an existing game folder".into());
    }
    let state = state.inner().clone();
    tauri::async_runtime::spawn_blocking(move || {
        let mut store = state.store.lock().map_err(|e| e.to_string())?;
        store.ensure_writable()?;
        let path = path.to_string_lossy().into_owned();
        if !store.library.folders.contains(&path) {
            store.library.folders.push(path)
        }
        store.scan()?;
        Ok(store.snapshot())
    })
    .await
    .map_err(|e| e.to_string())?
}
#[tauri::command]
async fn pick_windows_game() -> Result<Option<String>, String> {
    #[cfg(windows)]
    return tauri::async_runtime::spawn_blocking(|| {
        std::thread::spawn(crate::windows_launch::pick_game)
            .join()
            .map_err(|_| "Windows game picker stopped unexpectedly".to_string())?
    })
    .await
    .map_err(|e| e.to_string())?;
    #[cfg(not(windows))]
    Err("Windows game selection requires Windows".into())
}
#[tauri::command]
async fn add_game(state: State<'_>, path: String) -> Result<Snapshot, String> {
    let path = PathBuf::from(path);
    if !path.exists() {
        return Err("Choose an existing game application".into());
    }
    let extension = path
        .extension()
        .unwrap_or_default()
        .to_string_lossy()
        .to_lowercase();
    if !["app", "exe", "lnk", "appimage", "desktop"].contains(&extension.as_str()) {
        return Err("Choose a .app, .exe, .lnk, .AppImage, or .desktop game".into());
    }
    let target = path.to_string_lossy().into_owned();
    let kind = if extension == "app" {
        "application"
    } else if extension == "desktop" {
        "desktop"
    } else {
        "executable"
    };
    let game = Game {
        id: format!(
            "{}:{target}",
            if extension == "app" { "app" } else { "file" }
        ),
        name: launch_plan::display_title(&path),
        launch_kind: kind.into(),
        launch_target: target.clone(),
        install_path: target,
        ..Default::default()
    };
    let mut store = state.store.lock().map_err(|e| e.to_string())?;
    store.ensure_writable()?;
    if let Some(existing) = store
        .library
        .games
        .iter_mut()
        .find(|g| g.install_path == game.install_path)
    {
        existing.hidden = Some(false)
    } else {
        store.library.games.push(game)
    }
    store.save()?;
    Ok(store.snapshot())
}
#[tauri::command]
async fn search_metadata(query: String) -> Result<serde_json::Value, String> {
    tauri::async_runtime::spawn_blocking(move || metadata::Client::new()?.search(&query))
        .await
        .map_err(|e| e.to_string())?
}
#[tauri::command]
async fn apply_metadata(state: State<'_>, id: String, source: String) -> Result<Snapshot, String> {
    let state = state.inner().clone();
    tauri::async_runtime::spawn_blocking(move || {
        library::enrich(&state, &id, Some(&source))?;
        state.snapshot()
    })
    .await
    .map_err(|e| e.to_string())?
}
#[tauri::command]
fn publisher_catalog() -> Vec<metadata::Publisher> {
    metadata::publishers()
}
#[tauri::command]
async fn uninstall_plan(state: State<'_>, id: String) -> Result<library::UninstallPlan, String> {
    let store = state.store.lock().map_err(|e| e.to_string())?;
    if let Some(error) = &store.error {
        return Err(error.clone());
    }
    library::uninstall_plan(&store.game(&id)?)
}
#[tauri::command]
async fn uninstall_game(state: State<'_>, id: String) -> Result<Snapshot, String> {
    let state = state.inner().clone();
    tauri::async_runtime::spawn_blocking(move || {
        let mut store = state.store.lock().map_err(|e| e.to_string())?;
        store.ensure_writable()?;
        library::uninstall(&mut store, &id)?;
        Ok(store.snapshot())
    })
    .await
    .map_err(|e| e.to_string())?
}
#[tauri::command]
fn open_page(url: String) -> Result<(), String> {
    if !url.starts_with("https://") {
        return Err("Only HTTPS publisher pages are supported".into());
    }
    library::open_uri(&url)
}
#[tauri::command]
fn backup_status(state: State<'_>) -> backup::Status {
    state.backup.status()
}
#[tauri::command]
fn cancel_backup(state: State<'_>) {
    state.backup.cancel();
}
#[tauri::command]
async fn preview_backup(state: State<'_>, path: String) -> Result<serde_json::Value, String> {
    let state = state.inner().clone();
    let _operation = state.backup.begin("Verifying backup preview")?;
    let worker = state.clone();
    tauri::async_runtime::spawn_blocking(move || {
        let (current, root) = {
            let store = worker.store.lock().map_err(|e| e.to_string())?;
            (store.library.clone(), store.root.clone())
        };
        let next = backup::preview_controlled(
            std::path::Path::new(&path),
            &current,
            &root,
            Some(&worker.backup),
        )?;
        let ids: std::collections::BTreeSet<_> =
            current.games.iter().map(|g| g.id.as_str()).collect();
        let additions: Vec<_> = next
            .games
            .iter()
            .filter(|g| !ids.contains(g.id.as_str()))
            .map(|g| g.name.clone())
            .collect();
        Ok(serde_json::json!({"additions":additions,"kept":current.games.len()}))
    })
    .await
    .map_err(|e| e.to_string())?
}
#[tauri::command]
async fn export_library(state: State<'_>, path: String) -> Result<(), String> {
    let state = state.inner().clone();
    let _operation = state.backup.begin("Backing up library and images")?;
    let worker = state.clone();
    tauri::async_runtime::spawn_blocking(move || {
        let state = worker;
        let path = PathBuf::from(path);
        let store = state.store.lock().map_err(|e| e.to_string())?;
        if path.extension().is_none_or(|e| e != "zip") {
            return Err("Choose a ZIP backup".into());
        }
        let library = store.library.clone();
        let root = store.root.clone();
        drop(store);
        backup::export_controlled(&library, &root, &path, Some(&state.backup))
    })
    .await
    .map_err(|e| e.to_string())?
}
#[tauri::command]
async fn import_library(state: State<'_>, path: String) -> Result<Snapshot, String> {
    let state = state.inner().clone();
    let _operation = state.backup.begin("Verifying and restoring backup")?;
    let worker = state.clone();
    tauri::async_runtime::spawn_blocking(move || {
        let state = worker;
        let path = PathBuf::from(path);
        let mut store = state.store.lock().map_err(|e| e.to_string())?;
        store.ensure_writable()?;
        let next = if path.extension().is_some_and(|e| e == "zip") {
            backup::restore_controlled(&path, &store.library, &store.root, Some(&state.backup))?
        } else {
            let bytes = std::fs::read(path).map_err(|e| e.to_string())?;
            if bytes.len() > 25_000_000 {
                return Err("Library exceeds 25 MB".into());
            }
            let incoming: model::Library =
                serde_json::from_slice(&bytes).map_err(|e| e.to_string())?;
            if incoming.version != 1 {
                return Err("Unsupported library version".into());
            }
            let mut next = store.library.clone();
            let mut ids: std::collections::BTreeSet<String> =
                next.games.iter().map(|g| g.id.clone()).collect();
            for mut game in incoming.games {
                if ids.insert(game.id.clone()) {
                    game.extra.remove("images");
                    next.games.push(game)
                }
            }
            state.backup.check()?;
            library::save_library(&store.root, &next)?;
            next
        };
        store.library = next;
        store.revision += 1;
        Ok(store.snapshot())
    })
    .await
    .map_err(|e| e.to_string())?
}
#[tauri::command]
async fn save_custom_metadata(
    state: State<'_>,
    id: String,
    changes: std::collections::BTreeMap<String, String>,
    reset_text: bool,
    images: std::collections::BTreeMap<String, String>,
    reset_images: Vec<String>,
) -> Result<Snapshot, String> {
    let state = state.inner().clone();
    tauri::async_runtime::spawn_blocking(move || {
        if changes.values().any(|v| v.len() > 50_000) {
            return Err("Metadata fields must be shorter than 50,000 bytes".into());
        }
        if changes.get("name").is_some_and(|s| s.trim().is_empty()) {
            return Err("Game title cannot be empty".into());
        }
        let root = {
            let store = state.store.lock().map_err(|e| e.to_string())?;
            store.ensure_writable()?;
            store.game(&id)?;
            store.root.clone()
        };
        let mut imported = std::collections::BTreeMap::new();
        for (role, path) in images {
            if !["portrait", "landscape", "background"].contains(&role.as_str()) {
                return Err("Unsupported image role".into());
            }
            imported.insert(
                role,
                metadata::import_image(std::path::Path::new(&path), &root, &id)?,
            );
        }
        let mut store = state.store.lock().map_err(|e| e.to_string())?;
        store.ensure_writable()?;
        let game = store
            .library
            .games
            .iter_mut()
            .find(|g| g.id == id)
            .ok_or("Game no longer exists")?;
        game.apply_custom(changes, reset_text);
        if reset_images.iter().any(|s| s == "portrait") {
            game.custom_artwork = None
        }
        if reset_images.iter().any(|s| s == "landscape") {
            game.custom_landscape = None
        }
        if reset_images.iter().any(|s| s == "background") {
            game.custom_background = None
        }
        if let Some(key) = imported.remove("portrait") {
            game.custom_artwork = Some(key)
        }
        if let Some(key) = imported.remove("landscape") {
            game.custom_landscape = Some(key)
        }
        if let Some(key) = imported.remove("background") {
            game.custom_background = Some(key)
        }
        game.refresh_source();
        store.save()?;
        Ok(store.snapshot())
    })
    .await
    .map_err(|e| e.to_string())?
}
#[tauri::command]
fn update_checks_enabled() -> bool {
    std::env::var("JOYNITE_OFFLINE")
        .or_else(|_| std::env::var("PLAYNITE_OFFLINE"))
        .as_deref()
        != Ok("1")
}
fn main() {
    if std::env::args().any(|a| a == "--diagnostics") {
        if let Some(home) = dirs::home_dir() {
            let scan = discovery::scan(&home, &[]);
            if let Ok(text) = serde_json::to_string_pretty(&scan) {
                println!("{text}")
            }
        }
        return;
    }
    tauri::Builder::default()
        .plugin(tauri_plugin_single_instance::init(|app, _, _| {
            if let Some(window) = app.get_webview_window("main") {
                let _ = window.show();
                let _ = window.set_focus();
            }
        }))
        .plugin(tauri_plugin_dialog::init())
        .plugin(tauri_plugin_updater::Builder::new().build())
        .plugin(tauri_plugin_process::init())
        .plugin(
            tauri_plugin_autostart::Builder::new()
                .app_name("Joynite")
                .build(),
        )
        .setup(|app| {
            let mut store = Store::open();
            let media = store.root.join("Media");
            if let Err(error) = std::fs::create_dir_all(&media) {
                store.error = Some(format!("Artwork cache is unavailable: {error}"));
            }
            if media.exists() {
                app.asset_protocol_scope().allow_directory(media, true)?;
            }
            app.manage(Arc::new(AppState {
                backup: backup::Control::default(),
                store: Mutex::new(store),
                cancel: AtomicBool::new(false),
            }));
            Ok(())
        })
        .invoke_handler(tauri::generate_handler![
            update_checks_enabled,
            get_library,
            scan_games,
            hydrate_metadata,
            cancel_metadata,
            launch_game,
            launch_diagnostics,
            update_game,
            restore_hidden,
            add_folder,
            add_game,
            pick_windows_game,
            search_metadata,
            apply_metadata,
            publisher_catalog,
            uninstall_plan,
            uninstall_game,
            open_page,
            preview_backup,
            backup_status,
            cancel_backup,
            export_library,
            import_library,
            save_custom_metadata
        ])
        .run(tauri::generate_context!())
        .expect("Could not start Joynite");
}
