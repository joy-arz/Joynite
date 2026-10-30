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

pub fn validate_action(action: &crate::model::LaunchAction) -> Result<(), String> {
    if !["file", "url"].contains(&action.kind.as_str()) {
        return Err("Choose an application or a client URL".into());
    }
    if action.target.is_empty()
        || action.target.len() > 32768
        || action.target.contains('\0')
        || action.arguments.len() > 128
        || action.arguments.iter().any(|a| a.contains('\0'))
        || action.arguments.iter().map(String::len).sum::<usize>() > 16384
        || action.working_directory.len() > 32768
        || action.working_directory.contains('\0')
    {
        return Err(
            "Launch target/arguments are empty, too long, or contain null characters".into(),
        );
    }
    if action.kind == "url" {
        if !action.arguments.is_empty()
            || !action.working_directory.is_empty()
            || action.run_as_admin
        {
            return Err("Client URLs use their own launch arguments and permissions".into());
        }
        crate::library::validate_uri(&action.target)?;
    } else {
        if !Path::new(&action.target).is_absolute() {
            return Err("Choose an absolute application path".into());
        }
        if !action.working_directory.is_empty()
            && !Path::new(&action.working_directory).is_absolute()
        {
            return Err("Working directory must be an absolute folder path".into());
        }
        if Path::new(&action.target)
            .extension()
            .is_some_and(|e| e.eq_ignore_ascii_case("lnk") || e == "desktop")
            && !action.working_directory.is_empty()
        {
            return Err("Set the working directory in the shortcut or desktop entry itself".into());
        }
        if action.run_as_admin && !cfg!(windows) {
            return Err("Run as administrator is available only on Windows".into());
        }
    }
    Ok(())
}

#[cfg(any(windows, test))]
pub fn windows_arguments(arguments: &[String]) -> String {
    arguments
        .iter()
        .map(|argument| {
            let mut out = String::from("\"");
            let mut slashes = 0;
            for c in argument.chars() {
                if c == '\\' {
                    slashes += 1;
                    continue;
                }
                if c == '"' {
                    out.extend(std::iter::repeat_n('\\', slashes * 2 + 1));
                } else {
                    out.extend(std::iter::repeat_n('\\', slashes));
                }
                slashes = 0;
                out.push(c);
            }
            out.extend(std::iter::repeat_n('\\', slashes * 2));
            out.push('"');
            out
        })
        .collect::<Vec<_>>()
        .join(" ")
}

pub fn split_windows_arguments(input: &str) -> Result<Vec<String>, String> {
    if input.contains('\0') {
        return Err("Arguments contain a null character".into());
    }
    let chars: Vec<_> = input.chars().collect();
    let mut i = 0;
    let mut result = vec![];
    while i < chars.len() {
        while i < chars.len() && matches!(chars[i], ' ' | '\t') {
            i += 1;
        }
        if i == chars.len() {
            break;
        }
        let mut word = String::new();
        let mut quoted = false;
        while i < chars.len() {
            if !quoted && matches!(chars[i], ' ' | '\t') {
                break;
            }
            let mut slashes = 0;
            while i < chars.len() && chars[i] == '\\' {
                slashes += 1;
                i += 1;
            }
            if i < chars.len() && chars[i] == '"' {
                word.extend(std::iter::repeat_n('\\', slashes / 2));
                if slashes % 2 == 1 {
                    word.push('"');
                    i += 1;
                } else if quoted && chars.get(i + 1) == Some(&'"') {
                    word.push('"');
                    i += 2;
                } else {
                    quoted = !quoted;
                    i += 1;
                }
            } else {
                word.extend(std::iter::repeat_n('\\', slashes));
                if i < chars.len() && !quoted && matches!(chars[i], ' ' | '\t') {
                    break;
                }
                if i < chars.len() {
                    word.push(chars[i]);
                    i += 1;
                }
            }
        }
        if quoted {
            return Err("Unclosed quote in installed-game arguments".into());
        }
        result.push(word);
    }
    Ok(result)
}

#[cfg(test)]
mod action_tests {
    use super::*;
    use crate::model::{Game, LaunchAction};
    #[test]
    fn arguments_preserve_empty_values_spaces_quotes_and_trailing_slashes() {
        let args = [
            "",
            "plain",
            "a b",
            "quote\"value",
            r"C:\Program Files\Game\",
            "Unicode 遊戲",
            "&;$(literal)",
            "a\\\"b",
            "tab\tvalue",
        ]
        .map(String::from)
        .to_vec();
        assert_eq!(
            split_windows_arguments(&windows_arguments(&args)).unwrap(),
            args
        );
        assert_eq!(
            split_windows_arguments(r#"-path C:\Games\ -mode "two words""#).unwrap(),
            vec!["-path", r"C:\Games\", "-mode", "two words"]
        );
        assert!(split_windows_arguments("\"unfinished").is_err());
        assert!(split_windows_arguments("bad\0argument").is_err());
    }
    #[test]
    fn validates_url_and_shortcut_settings_and_retains_legacy_identity() {
        let mut action = LaunchAction {
            kind: "url".into(),
            target: "steam://rungameid/42".into(),
            ..Default::default()
        };
        assert!(validate_action(&action).is_ok());
        action.arguments = vec!["no".into()];
        assert!(validate_action(&action).is_err());
        action.arguments.clear();
        action.target = "javascript:alert(1)".into();
        assert!(validate_action(&action).is_err());
        let temp = tempfile::tempdir().unwrap();
        action = LaunchAction {
            kind: "file".into(),
            target: temp.path().join("Game.lnk").to_string_lossy().into(),
            working_directory: temp.path().to_string_lossy().into(),
            ..Default::default()
        };
        assert!(validate_action(&action).is_err());
        action.working_directory.clear();
        assert!(validate_action(&action).is_ok());
        let old: Game = serde_json::from_str(
            r#"{"id":"legacy","launchCount":9,"favorite":true,"unknown":"kept"}"#,
        )
        .unwrap();
        assert!(old.launch_action.is_none());
        let mut configured = old.clone();
        configured.launch_action = Some(action);
        let restored: Game =
            serde_json::from_slice(&serde_json::to_vec(&configured).unwrap()).unwrap();
        assert_eq!(restored.launch_count, 9);
        assert!(restored.favorite);
        assert_eq!(restored.extra["unknown"], "kept");
    }
}

#[cfg(all(test, windows))]
mod windows_os_argument_tests {
    #[test]
    fn microsoft_parser_receives_exact_arguments() {
        use windows_sys::Win32::{Foundation::LocalFree, UI::Shell::CommandLineToArgvW};
        let expected = vec![
            "".to_string(),
            "two words".into(),
            r"C:\Game Files\".into(),
            "quoted\"value".into(),
            "遊戲".into(),
        ];
        let line = format!("game.exe {}", super::windows_arguments(&expected));
        let wide: Vec<u16> = line.encode_utf16().chain([0]).collect();
        let mut count = 0;
        unsafe {
            let argv = CommandLineToArgvW(wide.as_ptr(), &mut count);
            assert!(!argv.is_null());
            let mut actual = vec![];
            for index in 1..count {
                let word = *argv.add(index as usize);
                let mut len = 0;
                while *word.add(len) != 0 {
                    len += 1;
                }
                actual.push(String::from_utf16(std::slice::from_raw_parts(word, len)).unwrap());
            }
            LocalFree(argv.cast());
            assert_eq!(actual, expected);
        }
    }
}
