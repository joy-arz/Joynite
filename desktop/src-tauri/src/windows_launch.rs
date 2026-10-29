use std::{ffi::OsStr, os::windows::ffi::OsStrExt, path::Path};
use windows_sys::Win32::{
    Foundation::GetLastError,
    System::Com::{
        CoInitializeEx, CoUninitialize, COINIT_APARTMENTTHREADED, COINIT_DISABLE_OLE1DDE,
    },
    UI::{
        Shell::{ShellExecuteExW, SEE_MASK_FLAG_NO_UI, SEE_MASK_NOASYNC, SHELLEXECUTEINFOW},
        WindowsAndMessaging::SW_SHOWNORMAL,
    },
};

fn wide(value: &OsStr) -> Result<Vec<u16>, String> {
    let mut value: Vec<_> = value.encode_wide().collect();
    if value.contains(&0) {
        return Err("Launch target contains a null character".into());
    }
    value.push(0);
    Ok(value)
}

pub fn open(target: &OsStr, arguments: &str, directory: Option<&Path>) -> Result<(), String> {
    let file = wide(target)?;
    let args = wide(OsStr::new(arguments))?;
    let directory = if Path::new(target)
        .extension()
        .is_some_and(|e| e.eq_ignore_ascii_case("lnk"))
    {
        None
    } else {
        directory
    };
    let cwd = directory.map(|p| wide(p.as_os_str())).transpose()?;
    // An owned STA keeps shell extensions independent of Tauri's runtime apartment.
    std::thread::spawn(move || unsafe {
        let result = CoInitializeEx(std::ptr::null(), (COINIT_APARTMENTTHREADED | COINIT_DISABLE_OLE1DDE) as u32);
        if result < 0 { return Err(format!("Windows launch initialization failed (HRESULT {result:#x})")); }
        let mut info: SHELLEXECUTEINFOW = std::mem::zeroed();
        info.cbSize = std::mem::size_of::<SHELLEXECUTEINFOW>() as u32;
        info.fMask = SEE_MASK_NOASYNC | SEE_MASK_FLAG_NO_UI;
        info.lpFile = file.as_ptr();
        info.lpParameters = if args.len() == 1 { std::ptr::null() } else { args.as_ptr() };
        info.lpDirectory = cwd.as_ref().map_or(std::ptr::null(), |v| v.as_ptr());
        info.nShow = SW_SHOWNORMAL;
        // The default verb preserves shortcut behavior and Windows permission prompts.
        let accepted = ShellExecuteExW(&mut info) != 0;
        let error = if accepted { 0 } else { GetLastError() };
        CoUninitialize();
        if accepted { Ok(()) } else {
            Err(match error {
                1223 => "Launch canceled at the Windows permission prompt. No launch was counted.".into(),
                5 => "Windows denied access (error 5). Use the game's working launcher shortcut (.lnk) or repair its client/permissions. Joynite does not bypass Windows protection.".into(),
                740 => "Windows requires elevation (error 740). Open the game's shortcut and approve its Windows permission prompt.".into(),
                _ => format!("Windows could not open the game (error {error}): {}", std::io::Error::from_raw_os_error(error as i32)),
            })
        }
    }).join().map_err(|_| "Windows launch worker stopped unexpectedly".to_string())?
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn unicode_paths_and_null_rejection() {
        assert_eq!(wide(OsStr::new("遊戲.exe")).unwrap().last(), Some(&0));
        assert!(wide(OsStr::new("game\0.exe")).is_err());
    }
    #[test]
    fn missing_executable_is_not_reported_as_accepted() {
        let temp = tempfile::tempdir().unwrap();
        let missing = temp.path().join("missing.exe");
        assert!(open(missing.as_os_str(), "", Some(temp.path())).is_err());
    }
}

pub fn pick_game() -> Result<Option<String>, String> {
    use std::os::windows::ffi::OsStringExt;
    use windows_sys::Win32::UI::Controls::Dialogs::{
        CommDlgExtendedError, GetOpenFileNameW, OFN_EXPLORER, OFN_FILEMUSTEXIST, OFN_NOCHANGEDIR,
        OFN_NODEREFERENCELINKS, OFN_PATHMUSTEXIST, OPENFILENAMEW,
    };
    let mut buffer = vec![0u16; 32768];
    let filter: Vec<u16> = "Windows game or shortcut\0*.exe;*.lnk\0\0"
        .encode_utf16()
        .collect();
    let title = wide(OsStr::new("Choose a game or its working desktop shortcut"))?;
    unsafe {
        let initialized = CoInitializeEx(
            std::ptr::null(),
            (COINIT_APARTMENTTHREADED | COINIT_DISABLE_OLE1DDE) as u32,
        );
        if initialized < 0 {
            return Err(format!(
                "Windows picker initialization failed (HRESULT {initialized:#x})"
            ));
        }
        let mut dialog: OPENFILENAMEW = std::mem::zeroed();
        dialog.lStructSize = std::mem::size_of::<OPENFILENAMEW>() as u32;
        dialog.lpstrFilter = filter.as_ptr();
        dialog.nFilterIndex = 1;
        dialog.lpstrFile = buffer.as_mut_ptr();
        dialog.nMaxFile = buffer.len() as u32;
        dialog.lpstrTitle = title.as_ptr();
        // Preserve the .lnk itself, rather than resolving it and losing arguments.
        dialog.Flags = OFN_EXPLORER
            | OFN_FILEMUSTEXIST
            | OFN_PATHMUSTEXIST
            | OFN_NOCHANGEDIR
            | OFN_NODEREFERENCELINKS;
        let selected = GetOpenFileNameW(&mut dialog) != 0;
        let error = if selected { 0 } else { CommDlgExtendedError() };
        CoUninitialize();
        if selected {
            let length = buffer.iter().position(|c| *c == 0).unwrap_or(buffer.len());
            Ok(Some(
                std::ffi::OsString::from_wide(&buffer[..length])
                    .to_string_lossy()
                    .into_owned(),
            ))
        } else if error == 0 {
            Ok(None)
        } else {
            Err(format!(
                "Windows could not open the game picker (dialog error {error:#x})"
            ))
        }
    }
}
