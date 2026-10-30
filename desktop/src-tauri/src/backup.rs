use crate::{
    library::save_library,
    model::{hash, Library},
};
use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256};
use std::{
    collections::{BTreeMap, BTreeSet},
    fs,
    io::{Read, Write},
    path::Path,
};
use zip::{write::SimpleFileOptions, ZipArchive, ZipWriter};
#[derive(Serialize, Deserialize)]
struct Manifest {
    format: u32,
    files: BTreeMap<String, String>,
}
fn digest(data: &[u8]) -> String {
    format!("{:x}", Sha256::digest(data))
}
fn valid(path: &str) -> bool {
    path == "library.json"
        || regex::Regex::new(r"^Media/[a-f0-9]{64}/[a-f0-9]{64}(\.fill)?\.png$")
            .unwrap()
            .is_match(path)
}
fn fail(error: impl std::fmt::Display) -> String {
    error.to_string()
}
#[cfg(test)]
pub fn export(library: &Library, root: &Path, path: &Path) -> Result<(), String> {
    export_controlled(library, root, path, None)
}
pub fn export_controlled(
    library: &Library,
    root: &Path,
    path: &Path,
    control: Option<&Control>,
) -> Result<(), String> {
    let expected = 1 + library
        .games
        .iter()
        .map(|g| {
            fs::read_dir(root.join("Media").join(hash(&g.id)))
                .map(|e| e.count() as u64)
                .unwrap_or(0)
        })
        .sum::<u64>();
    tick(control, 0, expected, "Backing up library and images")?;
    let parent = path.parent().ok_or("Choose a backup destination")?;
    let mut temp = tempfile::NamedTempFile::new_in(parent).map_err(fail)?;
    {
        let mut archive = ZipWriter::new(temp.as_file_mut());
        let options =
            SimpleFileOptions::default().compression_method(zip::CompressionMethod::Deflated);
        let mut hashes = BTreeMap::new();
        let mut total = 0u64;
        let mut add = |name: String, bytes: Vec<u8>| -> Result<(), String> {
            tick(
                control,
                hashes.len() as u64,
                expected,
                "Backing up library and images",
            )?;
            total += bytes.len() as u64;
            if bytes.len() > 25_000_000 || total > 1_000_000_000 || hashes.len() >= 50_000 {
                return Err("Backup exceeds the supported size".into());
            }
            if hashes.insert(name.clone(), digest(&bytes)).is_some() {
                return Err("Duplicate backup path".into());
            }
            archive.start_file(name, options).map_err(fail)?;
            for chunk in bytes.chunks(65536) {
                if let Some(c) = control {
                    c.check()?;
                }
                archive.write_all(chunk).map_err(fail)?;
            }
            Ok(())
        };
        add(
            "library.json".into(),
            serde_json::to_vec(library).map_err(fail)?,
        )?;
        let mut ids = BTreeSet::new();
        for game in &library.games {
            if !ids.insert(&game.id) {
                continue;
            }
            let folder = root.join("Media").join(hash(&game.id));
            if fs::symlink_metadata(&folder).is_ok_and(|m| m.file_type().is_symlink()) {
                continue;
            }
            if let Ok(entries) = fs::read_dir(folder) {
                for entry in entries {
                    let entry = entry.map_err(fail)?;
                    if !entry.file_type().map_err(fail)?.is_file() {
                        continue;
                    }
                    let name = format!(
                        "Media/{}/{}",
                        hash(&game.id),
                        entry.file_name().to_string_lossy()
                    );
                    if valid(&name) {
                        add(name, fs::read(entry.path()).map_err(fail)?)?
                    }
                }
            }
        }
        let manifest = Manifest {
            format: 1,
            files: hashes,
        };
        archive.start_file("manifest.json", options).map_err(fail)?;
        archive
            .write_all(&serde_json::to_vec(&manifest).map_err(fail)?)
            .map_err(fail)?;
        archive.finish().map_err(fail)?;
    }
    if let Some(c) = control {
        c.check()?;
    }
    temp.as_file().sync_all().map_err(fail)?;
    temp.persist(path).map_err(fail)?;
    if let Some(c) = control {
        let _ = c.update(expected, expected, "Backup complete");
    }
    Ok(())
}
#[cfg(test)]
pub fn restore(path: &Path, current: &Library, root: &Path) -> Result<Library, String> {
    restore_controlled(path, current, root, None)
}
pub fn restore_controlled(
    path: &Path,
    current: &Library,
    root: &Path,
    control: Option<&Control>,
) -> Result<Library, String> {
    restore_impl(path, current, root, control, false)
}
pub fn preview_controlled(
    path: &Path,
    current: &Library,
    root: &Path,
    control: Option<&Control>,
) -> Result<Library, String> {
    restore_impl(path, current, root, control, true)
}
fn restore_impl(
    path: &Path,
    current: &Library,
    root: &Path,
    control: Option<&Control>,
    preview_only: bool,
) -> Result<Library, String> {
    if let Some(c) = control {
        c.check()?;
    }
    let file = fs::File::open(path).map_err(fail)?;
    let mut archive = ZipArchive::new(file).map_err(fail)?;
    if archive.len() > 50_001 {
        return Err("Backup has too many entries".into());
    }
    let stage = tempfile::tempdir().map_err(fail)?;
    let mut hashes = BTreeMap::new();
    let mut total = 0u64;
    let mut manifest = None;
    for i in 0..archive.len() {
        tick(
            control,
            i as u64,
            archive.len() as u64 + 1,
            "Verifying backup integrity",
        )?;
        let mut entry = archive.by_index(i).map_err(fail)?;
        let name = entry.name().to_string();
        if !entry.is_file()
            || entry.is_symlink()
            || (!valid(&name) && name != "manifest.json")
            || hashes.contains_key(&name)
            || (name == "manifest.json" && manifest.is_some())
            || entry.size() > 25_000_000
        {
            return Err(format!("Invalid backup entry: {name}"));
        }
        total = total
            .checked_add(entry.size())
            .ok_or("Backup is too large")?;
        if total > 1_000_000_000 {
            return Err("Backup exceeds the supported size".into());
        }
        let mut bytes = Vec::new();
        entry
            .by_ref()
            .take(25_000_001)
            .read_to_end(&mut bytes)
            .map_err(fail)?;
        if bytes.len() > 25_000_000 {
            return Err("Backup entry is too large".into());
        }
        if name == "manifest.json" {
            manifest = Some(serde_json::from_slice::<Manifest>(&bytes).map_err(fail)?);
            continue;
        }
        hashes.insert(name.clone(), digest(&bytes));
        let target = stage.path().join(&name);
        fs::create_dir_all(target.parent().unwrap()).map_err(fail)?;
        fs::write(target, &bytes).map_err(fail)?;
    }
    let manifest = manifest.ok_or("Backup manifest is missing")?;
    if manifest.format != 1 || manifest.files != hashes || !hashes.contains_key("library.json") {
        return Err("Backup integrity verification failed".into());
    }
    let incoming: Library =
        serde_json::from_slice(&fs::read(stage.path().join("library.json")).map_err(fail)?)
            .map_err(fail)?;
    if incoming.version != 1 {
        return Err("Unsupported library version".into());
    }
    let mut next = current.clone();
    let mut ids: BTreeSet<String> = current.games.iter().map(|g| g.id.clone()).collect();
    let mut folders = BTreeSet::new();
    for mut game in incoming.games {
        if ids.insert(game.id.clone()) {
            folders.insert(hash(&game.id));
            game.extra.remove("images");
            next.games.push(game)
        }
    }
    for folder in incoming.folders {
        if !next.folders.contains(&folder) {
            next.folders.push(folder);
        }
    }
    if preview_only {
        return Ok(next);
    }
    let mut created = vec![];
    let commit = (|| -> Result<(), String> {
        for name in hashes.keys().filter(|n| {
            n.starts_with("Media/") && folders.contains(n.split('/').nth(1).unwrap_or(""))
        }) {
            if let Some(c) = control {
                c.check()?;
            }
            let target = root.join(name);
            for path in [
                root.join("Media"),
                target.parent().unwrap().to_path_buf(),
                target.clone(),
            ] {
                if fs::symlink_metadata(&path).is_ok_and(|m| m.file_type().is_symlink()) {
                    return Err("Restore destination contains a symbolic link".into());
                }
            }
            if target.exists() {
                if digest(&fs::read(&target).map_err(fail)?) != hashes[name] {
                    return Err("Restore would replace existing artwork".into());
                }
                continue;
            }
            fs::create_dir_all(target.parent().unwrap()).map_err(fail)?;
            fs::copy(stage.path().join(name), &target).map_err(fail)?;
            created.push(target);
        }
        if let Some(c) = control {
            c.check()?;
        }
        save_library(root, &next)
    })();
    if let Err(error) = commit {
        for path in created {
            let _ = fs::remove_file(path);
        }
        return Err(error);
    }
    Ok(next)
}
#[cfg(test)]
mod tests {
    use super::*;
    use crate::model::Game;
    #[test]
    fn portable_restore_preserves_artwork_and_existing_edits() {
        let source = tempfile::tempdir().unwrap();
        let destination = tempfile::tempdir().unwrap();
        let mut game = Game {
            id: "backup-game".into(),
            name: "Inscryption".into(),
            ..Default::default()
        };
        let key = format!("{}.png", "a".repeat(64));
        game.custom_artwork = Some(key.clone());
        let image = source.path().join("Media").join(hash(&game.id)).join(&key);
        fs::create_dir_all(image.parent().unwrap()).unwrap();
        fs::write(&image, b"offline artwork").unwrap();
        let library = Library {
            games: vec![game.clone()],
            ..Default::default()
        };
        let zip = source.path().join("backup.zip");
        export(&library, source.path(), &zip).unwrap();
        let preview =
            preview_controlled(&zip, &Library::default(), destination.path(), None).unwrap();
        assert_eq!(preview.games.len(), 1);
        assert!(!destination.path().join("library.json").exists());
        let restored = restore(&zip, &Library::default(), destination.path()).unwrap();
        assert_eq!(restored.games[0].name, "Inscryption");
        assert_eq!(
            fs::read(
                destination
                    .path()
                    .join("Media")
                    .join(hash(&game.id))
                    .join(&key)
            )
            .unwrap(),
            b"offline artwork"
        );
        let mut current = restored;
        current.games[0].name = "Kept edit".into();
        assert_eq!(
            restore(&zip, &current, destination.path()).unwrap().games[0].name,
            "Kept edit"
        );
        fs::write(&zip, b"interrupted download").unwrap();
        assert!(restore(&zip, &current, destination.path()).is_err());
        let saved: Library =
            serde_json::from_slice(&fs::read(destination.path().join("library.json")).unwrap())
                .unwrap();
        assert_eq!(saved.games[0].name, "Kept edit");
    }
    #[test]
    fn rejects_path_escape_and_hash_mismatch() {
        let dir = tempfile::tempdir().unwrap();
        for path in ["../escape", "library.json"] {
            let file = fs::File::create(dir.path().join("bad.zip")).unwrap();
            let mut zip = ZipWriter::new(file);
            let options = SimpleFileOptions::default();
            zip.start_file(path, options).unwrap();
            zip.write_all(b"{}").unwrap();
            zip.start_file("manifest.json", options).unwrap();
            zip.write_all(br#"{"format":1,"files":{"library.json":"incorrect"}}"#)
                .unwrap();
            zip.finish().unwrap();
            assert!(restore(&dir.path().join("bad.zip"), &Library::default(), dir.path()).is_err());
            assert!(!dir.path().join("library.json").exists());
        }
    }
}
#[derive(Clone, Default, Serialize)]
pub struct Status {
    pub active: bool,
    pub completed: u64,
    pub total: u64,
    pub phase: String,
}
#[derive(Default)]
pub struct Control {
    active: std::sync::atomic::AtomicBool,
    cancelled: std::sync::atomic::AtomicBool,
    status: std::sync::Mutex<Status>,
}
pub struct Run<'a>(&'a Control);
impl Drop for Run<'_> {
    fn drop(&mut self) {
        self.0
            .active
            .store(false, std::sync::atomic::Ordering::Release);
    }
}
impl Control {
    pub fn begin(&self, phase: &str) -> Result<Run<'_>, String> {
        self.active
            .compare_exchange(
                false,
                true,
                std::sync::atomic::Ordering::AcqRel,
                std::sync::atomic::Ordering::Acquire,
            )
            .map_err(|_| "Another backup operation is active")?;
        self.cancelled
            .store(false, std::sync::atomic::Ordering::Release);
        if let Ok(mut status) = self.status.lock() {
            *status = Status {
                active: true,
                completed: 0,
                total: 1,
                phase: phase.into(),
            };
        }
        Ok(Run(self))
    }
    pub fn cancel(&self) {
        self.cancelled
            .store(true, std::sync::atomic::Ordering::Release);
    }
    pub fn check(&self) -> Result<(), String> {
        if self.cancelled.load(std::sync::atomic::Ordering::Acquire) {
            Err("Backup operation cancelled".into())
        } else {
            Ok(())
        }
    }
    pub fn update(&self, completed: u64, total: u64, phase: &str) -> Result<(), String> {
        self.check()?;
        let mut status = self.status.lock().map_err(fail)?;
        *status = Status {
            active: true,
            completed,
            total: total.max(1),
            phase: phase.into(),
        };
        Ok(())
    }
    pub fn status(&self) -> Status {
        let mut status = self.status.lock().map(|s| s.clone()).unwrap_or_default();
        status.active = self.active.load(std::sync::atomic::Ordering::Acquire);
        status
    }
}
fn tick(control: Option<&Control>, completed: u64, total: u64, phase: &str) -> Result<(), String> {
    if let Some(c) = control {
        c.update(completed, total, phase)?;
    }
    Ok(())
}
#[cfg(test)]
mod cancellation_tests {
    use super::*;
    #[test]
    fn cancellation_keeps_existing_backup_and_library() {
        let root = tempfile::tempdir().unwrap();
        let path = root.path().join("backup.zip");
        fs::write(&path, b"original backup").unwrap();
        let control = Control::default();
        let run = control.begin("Backup").unwrap();
        assert!(control.begin("Other").is_err());
        control.cancel();
        assert!(
            export_controlled(&Library::default(), root.path(), &path, Some(&control)).is_err()
        );
        assert_eq!(fs::read(&path).unwrap(), b"original backup");
        assert!(
            restore_controlled(&path, &Library::default(), root.path(), Some(&control)).is_err()
        );
        assert!(!root.path().join("library.json").exists());
        drop(run);
        assert!(!control.status().active);
        assert!(control.begin("Retry").is_ok());
    }
}
