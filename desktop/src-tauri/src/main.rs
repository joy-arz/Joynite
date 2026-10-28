#![cfg_attr(not(debug_assertions), windows_subsystem = "windows")]
mod discovery;
mod library;
mod metadata;
mod model;
mod vdf;
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
        state.hydrate(all, |snapshot| {
            let _ = app.emit("library-updated", &snapshot);
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
            (store.game(&id)?, store.root.clone())
        };
        library::launch(&game, &root)?;
        let mut store = state.store.lock().map_err(|e| e.to_string())?;
        store.ensure_writable()?;
        if let Some(game) = store.library.games.iter_mut().find(|g| g.id == id) {
            game.last_played = Some(model::now())
        }
        store.save()?;
        Ok(store.snapshot())
    })
    .await
    .map_err(|e| e.to_string())?
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
    if !["app", "exe", "appimage", "desktop"].contains(&extension.as_str()) {
        return Err("Choose a .app, .exe, .AppImage, or .desktop game".into());
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
        name: path
            .file_stem()
            .unwrap_or_default()
            .to_string_lossy()
            .replace('_', " "),
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
async fn export_library(state: State<'_>, path: String) -> Result<(), String> {
    let path = PathBuf::from(path);
    if path.extension().is_none_or(|e| e != "json") {
        return Err("Choose a JSON file".into());
    }
    let store = state.store.lock().map_err(|e| e.to_string())?;
    let bytes = serde_json::to_vec_pretty(&store.library).map_err(|e| e.to_string())?;
    std::fs::write(path, bytes).map_err(|e| e.to_string())
}
#[tauri::command]
async fn import_library(state: State<'_>, path: String) -> Result<Snapshot, String> {
    let bytes = std::fs::read(path).map_err(|e| e.to_string())?;
    if bytes.len() > 25_000_000 {
        return Err("Library exceeds 25 MB".into());
    }
    let incoming: model::Library = serde_json::from_slice(&bytes).map_err(|e| e.to_string())?;
    if incoming.version != 1 {
        return Err("Unsupported library version".into());
    }
    let mut store = state.store.lock().map_err(|e| e.to_string())?;
    store.ensure_writable()?;
    for mut game in incoming.games {
        game.extra.remove("images");
        if !store.library.games.iter().any(|g| g.id == game.id) {
            store.library.games.push(game)
        }
    }
    store.save()?;
    Ok(store.snapshot())
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
                store: Mutex::new(store),
                cancel: AtomicBool::new(false),
            }));
            Ok(())
        })
        .invoke_handler(tauri::generate_handler![
            get_library,
            scan_games,
            hydrate_metadata,
            cancel_metadata,
            launch_game,
            update_game,
            restore_hidden,
            add_folder,
            add_game,
            search_metadata,
            apply_metadata,
            publisher_catalog,
            uninstall_plan,
            uninstall_game,
            open_page,
            export_library,
            import_library
        ])
        .run(tauri::generate_context!())
        .expect("Could not start Playnite Carousel");
}
