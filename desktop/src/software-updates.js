import { invoke } from "@tauri-apps/api/core";
import { check } from "@tauri-apps/plugin-updater";
import { relaunch } from "@tauri-apps/plugin-process";
import {
  reminderKey,
  newerVersion,
  shouldNotify,
  postpone,
  skip,
} from "./update-policy.mjs";

export function startSoftwareUpdates(root, options = {}) {
  const notice = document.createElement("section");
  notice.className = "software-update";
  notice.hidden = true;
  notice.setAttribute("aria-label", "Software update");
  notice.setAttribute("aria-live", "polite");
  notice.innerHTML =
    '<h2></h2><p class="update-message"></p><div class="update-buttons"><button class="update-now">Update now</button><button class="update-later">Update later</button></div><button class="update-skip">Don’t remind me again</button><small>Reminders return when a newer version is released.</small>';
  root.append(notice);
  let candidate = null,
    busy = false,
    checking = false,
    started = false,
    preferences = {};
  try {
    preferences = JSON.parse(localStorage.getItem(reminderKey) || "{}");
    if (!preferences || typeof preferences !== "object") preferences = {};
  } catch {}
  const message = notice.querySelector(".update-message");
  const status = document.querySelector("#update-check-status");
  const setStatus = (text) => {
    if (status) status.textContent = text;
  };
  const save = (value) => {
    preferences = value;
    try {
      localStorage.setItem(reminderKey, JSON.stringify(value));
    } catch {
      setStatus("Update reminder preference could not be saved.");
    }
  };
  async function dismiss(value) {
    if (busy || !candidate) return;
    save(value(candidate.version));
    notice.hidden = true;
    const old = candidate;
    candidate = null;
    await old.close().catch(() => {});
  }
  notice.querySelector(".update-later").onclick = () => dismiss(postpone);
  notice.querySelector(".update-skip").onclick = () => dismiss(skip);
  notice.querySelector(".update-now").onclick = async () => {
    if (!candidate || busy) return;
    busy = true;
    notice
      .querySelectorAll("button")
      .forEach((button) => (button.disabled = true));
    let downloaded = 0,
      total = 0;
    message.textContent = "Downloading signed update…";
    try {
      await candidate.downloadAndInstall(
        (event) => {
          if (event.event === "Started") {
            total = event.data.contentLength || 0;
            downloaded = 0;
          }
          if (event.event === "Progress") {
            downloaded += event.data.chunkLength;
            message.textContent = total
              ? `Downloading update… ${Math.min(100, Math.floor((downloaded * 100) / total))}%`
              : "Downloading signed update…";
          }
          if (event.event === "Finished")
            message.textContent = "Verifying and installing update…";
        },
        { timeout: 120000 },
      );
      message.textContent = "Update installed. Reopening Joynite…";
      await relaunch();
    } catch (error) {
      message.textContent = `Update could not finish. Your current version remains available. ${String(error)}`;
    } finally {
      busy = false;
      notice
        .querySelectorAll("button")
        .forEach((button) => (button.disabled = false));
    }
  };
  async function checkNow(manual = false) {
    if (checking || busy || (!manual && started)) return;
    started = true;
    if (!navigator.onLine) {
      setStatus("Offline. Update checks resume next launch.");
      return;
    }
    checking = true;
    try {
      if (!(await invoke("update_checks_enabled"))) {
        setStatus("Offline mode. Update checks resume next launch.");
        return;
      }
      const result = await check({ timeout: 8000 });
      if (!result) {
        setStatus("Joynite is up to date.");
        return;
      }
      if (!newerVersion(result.version, result.currentVersion)) {
        await result.close();
        return;
      }
      setStatus(`Joynite ${result.version} is available.`);
      if (!manual && !shouldNotify(result.version, preferences)) {
        await result.close();
        return;
      }
      if (candidate) await candidate.close().catch(() => {});
      candidate = result;
      notice.querySelector("h2").textContent =
        `Joynite ${result.version} is available`;
      message.textContent =
        "A new official release is ready. Your library stays in place.";
      notice.hidden = false;
    } catch {
      setStatus("Could not reach GitHub. Joynite remains ready to use.");
    } finally {
      checking = false;
    }
  }
  const timer = setTimeout(() => checkNow(), options.delay ?? 3000);
  document
    .querySelector("#update-check")
    ?.addEventListener("click", () => checkNow(true));
  window.addEventListener(
    "beforeunload",
    () => {
      clearTimeout(timer);
      candidate?.close().catch(() => {});
    },
    { once: true },
  );
  return { checkNow };
}
