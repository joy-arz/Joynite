#![cfg_attr(target_os = "macos", allow(dead_code))]
use crate::{
    discovery::Scan,
    model::{Game, LaunchAction},
};
use std::{
    collections::{BTreeMap, HashSet},
    fs,
    path::{Path, PathBuf},
};

fn children(root: &Path) -> Vec<PathBuf> {
    fs::read_dir(root)
        .map(|r| {
            r.filter_map(Result::ok)
                .take(4096)
                .map(|e| e.path())
                .collect()
        })
        .unwrap_or_default()
}
fn bounded_file(path: &Path) -> Option<Vec<u8>> {
    if fs::metadata(path).ok()?.len() > 2_000_000 {
        return None;
    }
    fs::read(path).ok()
}
fn relative(root: &Path, text: &str) -> Option<PathBuf> {
    let text = text.replace('\\', "/");
    let path = Path::new(&text);
    if text.contains(':')
        || path.is_absolute()
        || path
            .components()
            .any(|c| matches!(c, std::path::Component::ParentDir))
    {
        return None;
    }
    Some(root.join(path))
}
pub fn gog_game(manifest: &Path) -> Option<Game> {
    let id = manifest.file_stem()?.to_str()?.strip_prefix("goggame-")?;
    if id.is_empty() || !id.bytes().all(|b| b.is_ascii_digit()) {
        return None;
    }
    let data: serde_json::Value = serde_json::from_slice(&bounded_file(manifest)?).ok()?;
    if data["gameId"].as_str().is_some_and(|value| value != id) {
        return None;
    }
    let tasks: Vec<_> = data["playTasks"]
        .as_array()?
        .iter()
        .filter(|t| {
            t["isPrimary"] == true
                && (t["type"].is_null() || t["type"] == "FileTask" || t["type"] == 0)
        })
        .collect();
    if tasks.len() != 1 {
        return None;
    }
    let task = tasks[0];
    let root = manifest.parent()?;
    let directory = relative(root, task["workingDir"].as_str().unwrap_or(""))?;
    let task_path = task["path"].as_str()?;
    let direct = relative(root, task_path)?;
    let target = if direct.is_file() {
        direct
    } else {
        relative(&directory, task_path)?
    };
    if !directory.is_dir()
        || !target.is_file()
        || !target
            .extension()
            .is_some_and(|e| e.eq_ignore_ascii_case("exe"))
        || !target
            .canonicalize()
            .ok()?
            .starts_with(root.canonicalize().ok()?)
    {
        return None;
    }
    let action = LaunchAction {
        kind: "file".into(),
        target: target.to_string_lossy().into(),
        arguments: crate::launch_plan::split_windows_arguments(
            task["arguments"].as_str().unwrap_or(""),
        )
        .ok()?,
        working_directory: directory.to_string_lossy().into(),
        run_as_admin: false,
    };
    let mut game = Game {
        id: format!("gog:{id}"),
        name: data["name"].as_str().filter(|n| !n.is_empty())?.into(),
        store: "GOG".into(),
        store_id: id.into(),
        launch_kind: "executable".into(),
        launch_target: action.target.clone(),
        install_path: root.to_string_lossy().into(),
        ..Default::default()
    };
    game.extra.insert(
        "defaultLaunchAction".into(),
        serde_json::to_value(action).ok()?,
    );
    Some(game)
}

pub fn scan_gog(roots: &[PathBuf], out: &mut Scan) {
    let mut seen = HashSet::new();
    for root in roots {
        let mut folders = vec![root.clone()];
        folders.extend(
            children(root)
                .into_iter()
                .filter(|p| p.is_dir() && !p.is_symlink()),
        );
        for folder in folders {
            for manifest in children(&folder).into_iter().filter(|p| {
                p.extension().is_some_and(|e| e == "info")
                    && p.file_name()
                        .is_some_and(|n| n.to_string_lossy().starts_with("goggame-"))
            }) {
                if !seen.insert(manifest.clone()) {
                    continue;
                }
                if let Some(game) = gog_game(&manifest) {
                    out.games.push(game);
                } else {
                    out.warnings.push(format!(
                        "GOG launch task could not be resolved: {}. Add its working shortcut.",
                        manifest.display()
                    ));
                }
            }
        }
    }
}

pub fn registry_gog_roots(text: &str) -> Vec<PathBuf> {
    let mut result = vec![];
    let mut key = String::new();
    let mut values = BTreeMap::<String, String>::new();
    let finish = |key: &str, values: &BTreeMap<String, String>, result: &mut Vec<PathBuf>| {
        if key.rsplit('\\').next().is_some_and(|s| {
            s.strip_suffix("_is1")
                .is_some_and(|id| !id.is_empty() && id.bytes().all(|b| b.is_ascii_digit()))
        }) && values
            .get("Publisher")
            .is_some_and(|v| v.eq_ignore_ascii_case("GOG.com"))
        {
            if let Some(path) = values.get("InstallLocation").filter(|s| !s.is_empty()) {
                result.push(PathBuf::from(path));
            }
        }
    };
    for line in text.lines() {
        let line = line.trim();
        if line.starts_with("HKEY_") {
            finish(&key, &values, &mut result);
            key = line.into();
            values.clear();
        } else if let Some((name, value)) = line.split_once("REG_SZ") {
            values.insert(name.trim().into(), value.trim().into());
        }
    }
    finish(&key, &values, &mut result);
    result
}
#[cfg(windows)]
pub fn windows_gog_roots() -> Vec<PathBuf> {
    use std::os::windows::process::CommandExt;
    let mut roots = vec![PathBuf::from(r"C:\GOG Games")];
    for base in [
        r"HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall",
        r"HKLM\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall",
        r"HKCU\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall",
        r"HKCU\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall",
    ] {
        if let Ok(output) = std::process::Command::new("reg.exe")
            .args(["query", base, "/s"])
            .creation_flags(0x08000000)
            .output()
        {
            roots.extend(registry_gog_roots(&String::from_utf8_lossy(&output.stdout)));
        }
    }
    if let Ok(program) = std::env::var("ProgramFiles(x86)") {
        roots.push(PathBuf::from(program).join("GOG Galaxy/Games"));
    }
    roots.sort();
    roots.dedup();
    roots
}

fn unescape(value: &str) -> String {
    let mut chars = value.chars();
    let mut result = String::new();
    while let Some(c) = chars.next() {
        if c != '\\' {
            result.push(c);
            continue;
        }
        match chars.next() {
            Some('s') => result.push(' '),
            Some('n') => result.push('\n'),
            Some('t') => result.push('\t'),
            Some('r') => result.push('\r'),
            Some('\\') => result.push('\\'),
            Some(c) => {
                result.push('\\');
                result.push(c);
            }
            None => result.push('\\'),
        }
    }
    result
}
pub fn desktop_game(path: &Path) -> Option<Game> {
    let content = String::from_utf8(bounded_file(path)?).ok()?;
    let mut active = false;
    let mut fields = BTreeMap::new();
    for line in content.lines() {
        let line = line.trim();
        if line.starts_with('[') {
            active = line == "[Desktop Entry]";
            continue;
        }
        if active && !line.starts_with('#') {
            if let Some((key, value)) = line.split_once('=') {
                fields.insert(key.trim(), value.trim());
            }
        }
    }
    if fields.get("Type") != Some(&"Application")
        || fields.get("Hidden") == Some(&"true")
        || fields.get("NoDisplay") == Some(&"true")
        || !fields
            .get("Categories")
            .is_some_and(|v| v.split(';').any(|c| c == "Game"))
        || !fields.contains_key("Exec") && fields.get("DBusActivatable") != Some(&"true")
    {
        return None;
    }
    Some(Game {
        id: format!("desktop:{}", path.display()),
        name: unescape(fields.get("Name")?),
        summary: unescape(fields.get("Comment").unwrap_or(&"")),
        launch_kind: "desktop".into(),
        launch_target: path.to_string_lossy().into(),
        install_path: path.to_string_lossy().into(),
        ..Default::default()
    })
}
pub fn scan_desktop_roots(roots: &[PathBuf], out: &mut Scan) {
    fn walk(
        root: &Path,
        directory: &Path,
        depth: usize,
        seen: &mut HashSet<String>,
        out: &mut Scan,
    ) {
        if depth > 4 {
            return;
        }
        for path in children(directory) {
            if path.is_dir() && !path.is_symlink() {
                walk(root, &path, depth + 1, seen, out);
            } else if path.extension().is_some_and(|e| e == "desktop") {
                let id = path
                    .strip_prefix(root)
                    .unwrap_or(&path)
                    .to_string_lossy()
                    .replace(['/', '\\'], "-");
                if seen.insert(id) {
                    if let Some(game) = desktop_game(&path) {
                        out.games.push(game);
                    }
                }
            }
        }
    }
    let mut seen = HashSet::new();
    for root in roots {
        walk(root, root, 0, &mut seen, out);
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn gog_manifest_uses_primary_task_arguments_and_working_directory() {
        let temp = tempfile::tempdir().unwrap();
        let root = temp.path().join("Game");
        fs::create_dir_all(root.join("bin")).unwrap();
        fs::write(root.join("bin/game.exe"), b"fixture").unwrap();
        let path = root.join("goggame-123.info");
        let mut data = serde_json::json!({"gameId":"123","name":"Game","playTasks":[{"isPrimary":true,"type":"FileTask","path":"game.exe","workingDir":"bin","arguments":"--profile \"Player One\""},{"isPrimary":false,"type":"FileTask","path":"uninstall.exe"}]});
        fs::write(&path, serde_json::to_vec(&data).unwrap()).unwrap();
        let game = gog_game(&path).unwrap();
        assert_eq!(game.id, "gog:123");
        assert_eq!(game.store_id, "123");
        assert_eq!(
            game.extra["defaultLaunchAction"]["arguments"],
            serde_json::json!(["--profile", "Player One"])
        );
        assert!(
            game.launch_target.ends_with("bin/game.exe")
                || game.launch_target.ends_with("bin\\game.exe")
        );
        let mut out = Scan::default();
        scan_gog(&[temp.path().to_owned()], &mut out);
        assert_eq!(out.games.len(), 1);
        data["playTasks"][0]["path"] = "../outside.exe".into();
        fs::write(&path, serde_json::to_vec(&data).unwrap()).unwrap();
        assert!(gog_game(&path).is_none());
    }
    #[test]
    fn registry_reads_only_gog_install_locations() {
        let text="HKEY_LOCAL_MACHINE\\Software\\Uninstall\\123_is1\n    Publisher    REG_SZ    GOG.com\n    InstallLocation    REG_SZ    D:\\My Games\\Game\nHKEY_CURRENT_USER\\Software\\Uninstall\\Other\n    Publisher    REG_SZ    Other\n    InstallLocation    REG_SZ    C:\\Other\n";
        assert_eq!(
            registry_gog_roots(text),
            vec![PathBuf::from(r"D:\My Games\Game")]
        );
    }
    #[test]
    fn desktop_sections_hidden_overrides_and_exact_game_category() {
        let t = tempfile::tempdir().unwrap();
        let user = t.path().join("user");
        let system = t.path().join("system");
        fs::create_dir_all(&user).unwrap();
        fs::create_dir_all(&system).unwrap();
        let game="[Desktop Entry]\nType=Application\nName=Real\\sGame\nComment=Saved summary\nCategories=Game;StrategyGame;\nExec=flatpak run org.example.Game %U\n[Desktop Action Other]\nName=Wrong Name\n";
        fs::write(system.join("game.desktop"), game).unwrap();
        let entry = desktop_game(&system.join("game.desktop")).unwrap();
        assert_eq!(entry.name, "Real Game");
        assert_eq!(entry.summary, "Saved summary");
        fs::write(user.join("game.desktop"), "[Desktop Entry]\nHidden=true\n").unwrap();
        let mut out = Scan::default();
        scan_desktop_roots(&[user, system.clone()], &mut out);
        assert!(out.games.is_empty());
        fs::write(
            system.join("bad.desktop"),
            game.replace("Categories=Game;StrategyGame;", "Categories=NotGame;"),
        )
        .unwrap();
        assert!(desktop_game(&system.join("bad.desktop")).is_none());
    }
}
