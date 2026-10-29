use std::path::Path;
#[cfg(any(windows, test))]
use std::path::PathBuf;

pub fn display_title(path: &Path) -> String {
    clean_title(&path.file_stem().unwrap_or_default().to_string_lossy())
}

pub fn clean_title(name: &str) -> String {
    let mut title = name.replace('_', " ");
    for suffix in [
        "-Win64-Shipping",
        "-Win32-Shipping",
        "-Shipping",
        " Win64 Shipping",
        " Win32 Shipping",
    ] {
        if title
            .to_ascii_lowercase()
            .ends_with(&suffix.to_ascii_lowercase())
        {
            title.truncate(title.len() - suffix.len());
            break;
        }
    }
    let mut spaced = String::new();
    let chars: Vec<_> = title.chars().collect();
    for (i, c) in chars.iter().copied().enumerate() {
        if i > 0 {
            let previous = chars[i - 1];
            if (previous.is_lowercase() && c.is_uppercase())
                || (previous.is_alphabetic() && c.is_ascii_digit())
                || (previous.is_ascii_digit() && c.is_alphabetic())
            {
                spaced.push(' ');
            }
        }
        spaced.push(c);
    }
    spaced.trim().to_string()
}

#[cfg(any(windows, test))]
pub fn riot_target(
    target: &Path,
    program_data: &Path,
) -> Result<Option<(PathBuf, String)>, String> {
    let stem = target
        .file_stem()
        .unwrap_or_default()
        .to_string_lossy()
        .to_ascii_lowercase();
    let product = if [
        "valorant",
        "valorant-win64-shipping",
        "valorant-win32-shipping",
    ]
    .contains(&stem.as_str())
    {
        "valorant"
    } else {
        return Ok(None);
    };
    let manifest = program_data.join("Riot Games/RiotClientInstalls.json");
    let mut candidates = vec![];
    if let Ok(bytes) = std::fs::read(manifest) {
        if let Ok(data) = serde_json::from_slice::<serde_json::Value>(&bytes) {
            if let Some(client) = data["rc_live"].as_str() {
                candidates.push(PathBuf::from(client));
            }
        }
    }
    for parent in target.ancestors().skip(1).take(6) {
        candidates.push(parent.join("Riot Client/RiotClientServices.exe"));
    }
    if let Some(client) = candidates.into_iter().find(|p| p.is_file()) {
        Ok(Some((
            client,
            format!("--launch-product={product} --launch-patchline=live"),
        )))
    } else {
        Err("VALORANT needs Riot Client. Add its working desktop shortcut (.lnk), or repair Riot Client and rescan; the protected game executable cannot be started directly.".into())
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn packaged_executables_get_searchable_titles() {
        assert_eq!(clean_title("Expedition33-Win64-Shipping"), "Expedition 33");
        assert_eq!(clean_title("VALORANT-Win64-Shipping"), "VALORANT");
        assert_eq!(clean_title("Loop_Hero"), "Loop Hero");
    }
    #[test]
    fn riot_uses_registered_client_and_never_protected_binary() {
        let temp = tempfile::tempdir().unwrap();
        let client = temp.path().join("Riot Client/RiotClientServices.exe");
        std::fs::create_dir_all(client.parent().unwrap()).unwrap();
        std::fs::write(&client, b"fixture").unwrap();
        let target = temp.path().join("VALORANT/live/VALORANT.exe");
        let (resolved, args) = riot_target(&target, temp.path()).unwrap().unwrap();
        assert_eq!(resolved, client);
        assert_eq!(args, "--launch-product=valorant --launch-patchline=live");
        assert!(riot_target(&temp.path().join("other.exe"), temp.path())
            .unwrap()
            .is_none());
        std::fs::remove_file(&client).unwrap();
        assert!(riot_target(&target, temp.path())
            .unwrap_err()
            .contains("shortcut"));
    }
    #[test]
    fn riot_respects_registered_client_on_another_drive_or_folder() {
        let temp = tempfile::tempdir().unwrap();
        let client = temp.path().join("Custom Games/RiotClientServices.exe");
        std::fs::create_dir_all(client.parent().unwrap()).unwrap();
        std::fs::write(&client, b"fixture").unwrap();
        let data = temp.path().join("ProgramData/Riot Games");
        std::fs::create_dir_all(&data).unwrap();
        std::fs::write(
            data.join("RiotClientInstalls.json"),
            serde_json::to_vec(&serde_json::json!({"rc_live":client})).unwrap(),
        )
        .unwrap();
        let target = temp.path().join("Unrelated/VALORANT-Win64-Shipping.exe");
        assert_eq!(
            riot_target(&target, &temp.path().join("ProgramData"))
                .unwrap()
                .unwrap()
                .0,
            client
        );
    }
}
