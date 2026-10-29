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
pub fn export(library: &Library, root: &Path, path: &Path) -> Result<(), String> {
    let parent = path.parent().ok_or("Choose a backup destination")?;
    let mut temp = tempfile::NamedTempFile::new_in(parent).map_err(fail)?;
    {
        let mut archive = ZipWriter::new(temp.as_file_mut());
        let options =
            SimpleFileOptions::default().compression_method(zip::CompressionMethod::Deflated);
        let mut hashes = BTreeMap::new();
        let mut total = 0u64;
        let mut add = |name: String, bytes: Vec<u8>| -> Result<(), String> {
            total += bytes.len() as u64;
            if bytes.len() > 25_000_000 || total > 1_000_000_000 || hashes.len() >= 50_000 {
                return Err("Backup exceeds the supported size".into());
            }
            if hashes.insert(name.clone(), digest(&bytes)).is_some() {
                return Err("Duplicate backup path".into());
            }
            archive.start_file(name, options).map_err(fail)?;
            archive.write_all(&bytes).map_err(fail)
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
    temp.as_file().sync_all().map_err(fail)?;
    temp.persist(path).map_err(fail)?;
    Ok(())
}
pub fn restore(path: &Path, current: &Library, root: &Path) -> Result<Library, String> {
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
    let mut created = vec![];
    let commit = (|| -> Result<(), String> {
        for name in hashes.keys().filter(|n| {
            n.starts_with("Media/") && folders.contains(n.split('/').nth(1).unwrap_or(""))
        }) {
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
