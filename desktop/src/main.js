import { invoke, convertFileSrc } from "@tauri-apps/api/core";
import { listen } from "@tauri-apps/api/event";
import { open, save, ask, message } from "@tauri-apps/plugin-dialog";
import {
  wrap,
  slots,
  nearestPosition,
  filterGames,
  imageRole,
  direction,
} from "./model.mjs";
import "./style.css";
import logo from "./logo.svg";
import kofi from "./kofi.svg";
import { mergeLibraryPatch } from "./library-patch.mjs";
import { localLaunchCount } from "./home-order.mjs";
import { startSoftwareUpdates } from "./software-updates.js";
import {
  enable as enableStartup,
  disable as disableStartup,
  isEnabled as isStartupEnabled,
} from "@tauri-apps/plugin-autostart";

const $ = (s) => document.querySelector(s);
$("#app").innerHTML = `
<div class="backdrop" aria-hidden="true"><img id="fill0" class="image-fill"><img id="bg0"><img id="fill1" class="image-fill"><img id="bg1"><div class="shade"></div></div>
<header><button id="libraries" class="icon" title="Libraries (L)" aria-label="Toggle libraries">☰</button><strong class="brand"><img src="${logo}" alt=""> Joynite</strong><span id="filter-label">All games</span><div class="search-slot"></div><div class="search"><span>⌕</span><input id="search" type="search" tabindex="-1" placeholder="Find a game · Space" aria-label="Find a game"></div><button id="manage">＋ Add / manage</button><button id="details-toggle" class="icon" title="Details (Shift)" aria-label="Toggle game details">ⓘ</button></header>
<main><section id="stage" aria-label="Game carousel"><div id="cards"></div><button id="prev" class="nav" aria-label="Previous game">‹</button><button id="next" class="nav" aria-label="Next game">›</button><div id="empty" hidden><h1>Your next game starts here.</h1><p>Add a game or scan your installed libraries.</p><button id="empty-add">Add game</button></div></section><div class="caption"><span id="position"></span><span class="orange-line"></span><span id="genres"></span><span id="offline"></span></div></main>
<footer><div class="hints" id="hints"></div><span id="input-kind">⌨ Keyboard</span><div class="status-row"><span id="status" role="status">Loading your library…</span><button id="notices" hidden></button><button id="cancel" hidden>Stop metadata fetch</button><button id="settings-open" title="Settings (Command/Ctrl+,)" aria-label="Joynite settings">⚙ Settings</button><button id="support" title="Support joy-arz on Ko-fi" aria-label="Support Joynite on Ko-fi"><img src="${kofi}" alt="">Support Joynite</button></div></footer>
<aside id="library-panel" hidden><div class="panel-heading"><h2>Libraries</h2><button id="library-close" aria-label="Close libraries">×</button></div><nav id="filters"></nav><div class="panel-bottom"><button id="restore">Restore hidden games</button><button id="help">Help and notices</button></div></aside>
<aside id="details" hidden><div class="panel-heading"><h2>Game details</h2><button id="details-close" aria-label="Close details">×</button></div><div id="detail-content"></div></aside>
<dialog id="actions"><div class="dialog-heading"><h2>Your library</h2><button data-close aria-label="Close">×</button></div><div class="action-grid"><button id="add-game">Add game application</button><button id="add-folder">Add games / Wine-prefix folder</button><button id="scan">Scan installed games</button><button id="refresh">Refresh metadata</button><button id="edit-custom">Edit selected metadata / images</button><button id="publishers">Publisher metadata catalog</button><button id="preview-backup">Preview backup</button><button id="import">Restore library backup</button><button id="export">Back up library and images</button><button id="action-settings">Settings</button><button id="action-help">Help and notices</button></div></dialog>
<dialog id="metadata"><div class="dialog-heading"><h2>Find metadata</h2><button data-close aria-label="Close">×</button></div><p id="match-for"></p><form id="search-form"><input id="metadata-query" placeholder="Game title" aria-label="Game title"><button>Search Steam</button></form><div id="matches"></div><form id="page-form"><input id="metadata-page" placeholder="HTTPS Steam, GOG, itch.io or publisher page" aria-label="Store page"><button>Fetch page</button></form></dialog>
<dialog id="publisher-list"><div class="dialog-heading"><h2>Beyond the stores</h2><button data-close aria-label="Close">×</button></div><p>Bundled metadata does not change a game's platform compatibility.</p><div id="publisher-items"></div></dialog>
<dialog id="help-dialog"><div class="dialog-heading"><h2>Library help</h2><button data-close aria-label="Close">×</button></div><div id="help-content"></div></dialog>
<dialog id="custom-editor"><div class="dialog-heading"><h2>Custom metadata & images</h2><button data-close aria-label="Close">×</button></div><p>Saved locally. Automatic refresh preserves your overrides. Images are copied into the offline cache.</p><form id="custom-form" class="custom-form"><label>Title<input id="custom-name" required maxlength="50000"></label><label>Developer<input id="custom-developer" maxlength="50000"></label><label>Release date<input id="custom-releaseDate" maxlength="50000"></label><label>Genres, separated by commas<input id="custom-genres" maxlength="50000"></label><label>Description<textarea id="custom-summary" maxlength="50000"></textarea></label><button id="custom-reset-text" type="button">Restore automatic text</button><div id="custom-images"></div><div class="custom-footer"><button id="custom-cancel" type="button">Cancel</button><button class="primary" type="submit">Save offline</button></div></form></dialog>
<dialog id="settings-dialog"><div class="dialog-heading"><h2>Joynite settings</h2><button data-close aria-label="Close">×</button></div><label class="startup-setting"><input id="startup-enabled" type="checkbox">Launch Joynite when I sign in</label><p>Open your library automatically after signing in to this computer. Off by default. Keep Joynite in its installed location so the startup entry stays valid.</p><p id="startup-status" role="status"></p><button id="startup-refresh">Check startup setting</button><p id="update-check-status">Updates are checked quietly when Joynite opens.</p><button id="update-check">Check for updates…</button><h3>Library order</h3><p>Favorites first, then opens made through Joynite. Counts stay local and start at zero for older libraries.</p><p>Maintained by joy-arz.</p><button id="settings-support" class="support-link"><img src="${kofi}" alt="">Support Joynite on Ko-fi</button></dialog>
<div id="announcement" class="sr-only" aria-live="polite"></div>`;

let data = { games: [], folders: [], notices: [], platform: "" },
  visible = [],
  position = 0,
  filter = "All games",
  query = "",
  frame = 0,
  previousPosition = 0;
const cards = new Map();
const startupCounts = new Map();
let searchExpanded = false,
  searchSuggestion = 0;
let workerHasData = false,
  workerFailed = false;
let searchRevision = 0,
  searchResolve = null,
  searchWork = Promise.resolve();
const searchWorker = new Worker(
  new URL("./search-worker.mjs", import.meta.url),
  { type: "module" },
);
searchWorker.onmessage = ({ data: result }) => {
  if (result.revision !== searchRevision) return;
  const byID = new Map(data.games.map((g) => [g.id, g]));
  visible = result.ids.map((id) => byID.get(id)).filter(Boolean);
  position = 0;
  previousPosition = 0;
  cards.forEach((c) => c.remove());
  cards.clear();
  schedule();
  renderSearchSuggestions();
  searchResolve?.();
  searchResolve = null;
};
let busy = false,
  scanPending = null,
  hydratePending = null,
  hydrateQueued = false,
  hydrateQueuedAll = false,
  bgTimer = 0,
  bgIndex = 0,
  lastBg = "",
  matchID = null,
  controllerFrame = 0,
  lastPadTime = 0,
  suppressClickUntil = 0,
  held = 0,
  nextRepeat = 0,
  padButtons = [],
  input = "keyboard",
  padName = "",
  unlisten = null;
searchWorker.onerror = () => {
  workerFailed = true;
  visible = filterGames(data.games, filter, query, startupCounts);
  position = 0;
  schedule();
  renderSearchSuggestions();
  searchResolve?.();
  searchResolve = null;
};
const reduced = matchMedia("(prefers-reduced-motion: reduce)").matches;
const selected = () => visible[wrap(position, visible.length)] ?? null;
const status = (text) => {
  $("#status").textContent = text;
};
const localImage = (path) => (path ? convertFileSrc(path) : "");
const modalOpen = () => !!document.querySelector("dialog[open]");
const typing = (target) =>
  target instanceof HTMLElement &&
  (target.matches("input,textarea,select") || target.isContentEditable);
function report(error) {
  status(String(error));
  message(String(error), { title: "Joynite", kind: "error" }).catch(() => {});
}
function patchLibrary(patch) {
  const next = mergeLibraryPatch(data, patch);
  if (next === data) return;
  const changed = new Map(patch.games.map((g) => [g.id, g]));
  const needsFilter = data.games.some((g) => {
    const next = changed.get(g.id);
    return (
      next &&
      (g.name !== next.name ||
        g.favorite !== next.favorite ||
        g.hidden !== next.hidden ||
        g.store !== next.store ||
        (query && JSON.stringify(g.genres) !== JSON.stringify(next.genres)))
    );
  });
  if (needsFilter) {
    snapshot(next);
    return;
  }
  data = next;
  visible = visible.map((g) => changed.get(g.id) || g);
  schedule();
  if (!$("#details").hidden) renderDetails();
  $("#notices").hidden = !data.notices.length;
  $("#notices").textContent = `${data.notices.length} notices`;
}
function snapshot(next) {
  if ((next.revision || 0) < (data.revision || 0)) return;
  workerHasData = false;
  searchRevision++;
  searchResolve?.();
  searchResolve = null;
  const id = selected()?.id;
  const oldIDs = visible.map((g) => g.id).join("\n");
  data = next;
  for (const game of data.games)
    if (!startupCounts.has(game.id))
      startupCounts.set(game.id, localLaunchCount(game));
  visible = filterGames(data.games, filter, query, startupCounts);
  const newIDs = visible.map((g) => g.id).join("\n");
  if (oldIDs !== newIDs) {
    const index = visible.findIndex((g) => g.id === id);
    position = index < 0 ? 0 : nearestPosition(position, index, visible.length);
    cards.forEach((c) => c.remove());
    cards.clear();
  }
  renderFilters();
  schedule();
  if (!$("#details").hidden) renderDetails();
  $("#notices").hidden = !data.notices.length;
  $("#notices").textContent = `${data.notices.length} notices`;
  if (data.error) status(data.error);
}
function changeFilter() {
  searchRevision++;
  searchResolve?.();
  searchResolve = null;
  visible = filterGames(data.games, filter, query, startupCounts);
  position = 0;
  previousPosition = 0;
  cards.forEach((c) => c.remove());
  cards.clear();
  $("#filter-label").textContent = filter;
  schedule();
  if (!$("#details").hidden) renderDetails();
}
function schedule() {
  if (!frame) frame = requestAnimationFrame(render);
  clearTimeout(bgTimer);
  bgTimer = setTimeout(updateBackground, 85);
}
function move(delta) {
  if (visible.length < 2) return;
  position += delta;
  schedule();
  if (!$("#details").hidden) renderDetails();
}
function makeCard() {
  const card = document.createElement("button");
  card.className = "card";
  card.tabIndex = -1;
  card.innerHTML =
    '<img class="image-fill" decoding="async" draggable="false"><img class="cover" decoding="async" draggable="false"><div class="card-shade"></div><div class="card-body"><div class="badge-row"><span class="badge"></span><span class="heart"></span></div><div class="card-info"><h2></h2><p class="developer"></p><p class="summary"></p><div class="ready">▶ <span>Ready to play</span><span>↵</span></div></div></div>';
  return card;
}
function transform(offset, width) {
  const d = Math.abs(offset),
    scale = d === 0 ? 1 : d === 1 ? 0.78 : d === 2 ? 0.59 : 0.45,
    x =
      d === 0
        ? 0
        : Math.sign(offset) *
          width *
          (d === 1 ? 0.8 : d === 2 ? 1.37 : 1.85 + (d - 3) * 0.45);
  return `translate3d(calc(-50% + ${x}px),-50%,0) scale(${scale})`;
}
function render() {
  frame = 0;
  const stage = $("#stage");
  const width = Math.max(
    205,
    Math.min(
      stage.clientWidth * 0.28,
      390,
      ((stage.clientHeight - 28) * 2) / 3,
    ),
  );
  const list = slots(position, visible),
    wanted = new Set(list.map((s) => s.key));
  for (const [key, node] of cards) {
    if (!wanted.has(key)) {
      node.remove();
      cards.delete(key);
    }
  }
  for (const slot of list) {
    const { game, offset, key } = slot;
    let card = cards.get(key),
      fresh = !card;
    if (fresh) {
      card = makeCard();
      cards.set(key, card);
      $("#cards").append(card);
      card.addEventListener("click", () => {
        if (performance.now() < suppressClickUntil) return;
        const delta = Number(card.dataset.key) - position;
        move(delta);
      });
      card.addEventListener("contextmenu", (e) => {
        e.preventDefault();
        move(Number(card.dataset.key) - position);
        toggleDetails(true);
      });
      card.dataset.key = String(key);
    }
    const fillAsset = localImage(game.images?.portraitFill);
    const fill = card.querySelector(".image-fill");
    if (fill.dataset.asset !== fillAsset) {
      fill.hidden = !fillAsset;
      if (fillAsset) fill.src = fillAsset;
      else fill.removeAttribute("src");
      fill.dataset.asset = fillAsset;
    }
    const asset = localImage(imageRole(game, "portrait"));
    if (card.dataset.asset !== asset) {
      const image = card.querySelector(".cover");
      if (asset) image.src = asset;
      else image.removeAttribute("src");
      image.hidden = !asset;
      card.dataset.asset = asset;
    }
    const signature = `${game.id}/${game.metadataUpdated}/${game.favorite}/${game.name}`;
    if (card.dataset.signature !== signature) {
      card.querySelector("h2").textContent = game.name;
      card.querySelector(".badge").textContent =
        game.compatibility?.label ||
        (game.store === "Mac" ? "Local" : game.store);
      card.querySelector(".heart").textContent = game.favorite ? "♥" : "";
      card.querySelector(".developer").textContent = game.developer || "";
      card.querySelector(".summary").textContent =
        game.summary || "Ready in your library.";
      card.dataset.signature = signature;
    }
    card.classList.toggle("selected", offset === 0);
    card.setAttribute(
      "aria-label",
      game.name + (offset === 0 ? ", selected" : ""),
    );
    card.style.width = `${width}px`;
    card.style.height = `${width * 1.5}px`;
    card.style.zIndex = String(6 - Math.abs(offset));
    card.style.opacity =
      Math.abs(offset) > 2
        ? "0"
        : offset === 0
          ? "1"
          : Math.abs(offset) === 1
            ? ".84"
            : ".54";
    card.style.pointerEvents = Math.abs(offset) > 2 ? "none" : "auto";
    card.setAttribute("aria-hidden", Math.abs(offset) > 2 ? "true" : "false");
    if (fresh) {
      card.style.transition = "none";
      requestAnimationFrame(() => {
        card.style.transition = "";
      });
    }
    card.style.transform = transform(offset, width);
  }
  previousPosition = position;
  const game = selected();
  $("#empty").hidden = !!game;
  $("#position").textContent = game
    ? `${wrap(position, visible.length) + 1} / ${visible.length}`
    : "";
  $("#genres").textContent = (game?.genres || []).slice(0, 3).join(" • ");
  $("#offline").textContent = imageRole(game || {}, "portrait")
    ? "◉ Saved offline"
    : "";
  $("#announcement").textContent = game?.name || "No games";
  renderHints();
}
async function updateBackground() {
  const game = selected(),
    asset = localImage(imageRole(game || {}, "background"));
  if (asset === lastBg) return;
  lastBg = asset;
  const next = $(`#bg${1 - bgIndex}`),
    old = $(`#bg${bgIndex}`);
  if (!asset) {
    old.classList.remove("shown");
    $(`#fill${bgIndex}`).classList.remove("shown");
    return;
  }
  const nextFill = $(`#fill${1 - bgIndex}`),
    oldFill = $(`#fill${bgIndex}`),
    fillAsset = localImage(game.images?.backgroundFill);
  nextFill.hidden = !fillAsset;
  if (fillAsset) nextFill.src = fillAsset;
  next.src = asset;
  try {
    await next.decode();
  } catch {
    return;
  }
  if (asset !== lastBg) return;
  next.classList.add("shown");
  nextFill.classList.add("shown");
  old.classList.remove("shown");
  oldFill.classList.remove("shown");
  bgIndex = 1 - bgIndex;
}
function renderFilters() {
  const nav = $("#filters");
  nav.replaceChildren();
  for (const name of [
    "All games",
    "Favorites",
    "Recently played",
    "Mac",
    "Steam",
    "GOG",
    "Epic",
    "itch.io",
  ]) {
    const button = document.createElement("button");
    button.textContent = name === "Mac" ? "Local games" : name;
    button.classList.toggle("active", filter === name);
    button.addEventListener("click", () => {
      filter = name;
      changeFilter();
      $("#library-panel").hidden = true;
    });
    nav.append(button);
  }
}
function toggleDetails(force) {
  $("#details").hidden = force === undefined ? !$("#details").hidden : !force;
  if (!$("#details").hidden) renderDetails();
}
function toggleLibraries() {
  $("#library-panel").hidden = !$("#library-panel").hidden;
}
function closePanels() {
  $("#details").hidden = true;
  $("#library-panel").hidden = true;
}
function renderDetails() {
  const game = selected(),
    container = $("#detail-content");
  container.replaceChildren();
  if (!game) return;
  const image = document.createElement("img");
  image.className = "inspect-image";
  const landscape = localImage(imageRole(game, "landscape"));
  if (landscape) {
    image.src = landscape;
    image.decoding = "async";
    const frame = document.createElement("div");
    frame.className = "inspect-wrap";
    if (game.images?.landscapeFill) {
      const fill = document.createElement("img");
      fill.src = localImage(game.images.landscapeFill);
      fill.className = "image-fill";
      frame.append(fill);
    }
    frame.append(image);
    container.append(frame);
  }
  const title = document.createElement("h1");
  title.textContent = game.name;
  container.append(title);
  const play = document.createElement("button");
  play.className = "primary";
  play.textContent = "▶ Play";
  play.onclick = () => launchSelected();
  container.append(play);
  const description = document.createElement("p");
  description.className = "description";
  description.textContent =
    game.summary || "Find metadata to add a description.";
  container.append(description);
  invoke("launch_diagnostics", { id: game.id })
    .then((report) => {
      if (!report || selected()?.id !== game.id || !container.isConnected)
        return;
      const p = document.createElement("p");
      p.className = "launch-diagnostic";
      p.textContent = `Last launch: ${report.state}. ${report.detail}${report.exitCode != null ? ` Exit code: ${report.exitCode}.` : ""}`;
      container.append(p);
    })
    .catch(() => {});
  for (const [label, value] of [
    ["Developer", game.developer],
    ["Released", game.releaseDate],
    ["Genres", (game.genres || []).join(", ")],
    ["Runtime", game.compatibility?.label],
    ["Metadata", game.metadataSource],
    ["Opened through Joynite", String(localLaunchCount(game))],
    [
      "Launch tracking",
      "Only successful Joynite launch requests are counted. No external play history is read.",
    ],
  ]) {
    if (value) {
      const item = document.createElement("div");
      item.className = "field";
      const caption = document.createElement("small");
      caption.textContent = label;
      const text = document.createElement("span");
      text.textContent = value;
      item.append(caption, text);
      container.append(item);
    }
  }
  for (const [label, action] of [
    [game.favorite ? "Remove favorite" : "Add favorite", () => favorite()],
    ["Edit metadata and images…", () => showCustomEditor()],
    ["Find metadata…", () => showMetadata()],
    [
      "Publisher / store page",
      () =>
        game.storeURL &&
        invoke("open_page", { url: game.storeURL }).catch(report),
    ],
    ["Uninstall…", () => uninstallSelected()],
    ["Hide from library", () => updateGame({ hidden: true })],
  ]) {
    const button = document.createElement("button");
    button.textContent = label;
    button.className = "detail-action";
    button.onclick = action;
    if (label === "Uninstall…") button.classList.add("orange");
    container.append(button);
  }
  if (game.pendingUninstall) {
    const p = document.createElement("p");
    p.className = "muted";
    p.textContent =
      "Complete uninstall in the original client. Metadata is kept until removal is confirmed.";
    container.append(p);
  }
}
async function launchSelected() {
  const game = selected();
  if (!game) return;
  try {
    status(`Launching ${game.name}…`);
    snapshot(await invoke("launch_game", { id: game.id }));
    status(`Launch request sent for ${game.name}.`);
  } catch (e) {
    report(e);
  }
}
async function updateGame(patch) {
  const game = selected();
  if (!game) return;
  try {
    snapshot(
      await invoke("update_game", {
        id: game.id,
        favorite: null,
        hidden: null,
        ...patch,
      }),
    );
  } catch (e) {
    report(e);
  }
}
const favorite = () => {
  const game = selected();
  if (game) updateGame({ favorite: !game.favorite });
};
async function scan() {
  if (scanPending) return scanPending;
  scanPending = (async () => {
    try {
      status("Scanning installed games and compatibility prefixes…");
      snapshot(await invoke("scan_games"));
      status(`${data.games.length} installed entries. Library updated.`);
    } catch (e) {
      report(e);
    } finally {
      scanPending = null;
    }
  })();
  return scanPending;
}
async function hydrate(all = false) {
  if (hydratePending) {
    hydrateQueued = true;
    hydrateQueuedAll ||= all;
    return hydratePending;
  }
  busy = true;
  $("#cancel").hidden = false;
  status("Fetching missing metadata and caching artwork…");
  hydratePending = invoke("hydrate_metadata", { all })
    .then(snapshot)
    .then(() => status("Metadata and offline artwork updated."))
    .catch(report)
    .finally(() => {
      busy = false;
      $("#cancel").hidden = true;
      hydratePending = null;
      if (hydrateQueued) {
        const refreshAll = hydrateQueuedAll;
        hydrateQueued = false;
        hydrateQueuedAll = false;
        hydrate(refreshAll);
      }
    });
  return hydratePending;
}
async function addGame() {
  closeDialogs();
  const path = data.platform === "windows" ? await invoke("pick_windows_game") : await open({
    title: "Add a game application",
    directory: false,
    multiple: false,
    filters:
      data.platform === "macos"
        ? [{ name: "Mac game", extensions: ["app"] }]
        : data.platform === "windows"
          ? [{ name: "Windows game", extensions: ["exe", "lnk"] }]
          : [{ name: "Linux game", extensions: ["AppImage", "desktop"] }],
  });
  if (path) {
    snapshot(await invoke("add_game", { path }));
    await hydrate();
  }
}
async function addFolder() {
  closeDialogs();
  const path = await open({
    title: "Choose a games folder or Wine prefix",
    directory: true,
    multiple: false,
  });
  if (path) {
    snapshot(await invoke("add_folder", { path }));
    await hydrate();
  }
}
async function uninstallSelected() {
  const game = selected();
  if (!game) return;
  try {
    const plan = await invoke("uninstall_plan", { id: game.id });
    const confirmed = await ask(plan.message, {
      title: plan.title,
      kind: "warning",
      okLabel: plan.method === "trash" ? "Move to Trash" : "Open uninstaller",
      cancelLabel: "Cancel",
    });
    if (!confirmed) return;
    status(`Uninstalling ${game.name}…`);
    snapshot(await invoke("uninstall_game", { id: game.id }));
    status(
      plan.method === "trash"
        ? `Uninstalled ${game.name}.`
        : "Complete uninstall in the original client. Metadata stays until removal is confirmed.",
    );
  } catch (e) {
    report(e);
  }
}
function closeDialogs() {
  document.querySelectorAll("dialog[open]").forEach((d) => d.close());
}
function showMetadata() {
  const game = selected();
  if (!game) return;
  matchID = game.id;
  closeDialogs();
  $("#match-for").textContent =
    `Match ${game.name} without changing how it launches.`;
  $("#metadata-query").value = game.name;
  $("#metadata-page").value = game.storeURL || "";
  $("#matches").replaceChildren();
  $("#metadata").showModal();
  searchMetadata();
}
async function searchMetadata() {
  try {
    const items = await invoke("search_metadata", {
      query: $("#metadata-query").value,
    });
    const container = $("#matches");
    container.replaceChildren();
    for (const item of Array.isArray(items) ? items : []) {
      const row = document.createElement("button");
      row.className = "match";
      row.textContent = `${item.name} — Use match`;
      row.onclick = () =>
        applyMetadata(`https://store.steampowered.com/app/${item.id}/`);
      container.append(row);
    }
    if (!container.children.length)
      container.textContent = "No results. Try another title or a store page.";
  } catch (e) {
    $("#matches").textContent = String(e);
  }
}
async function applyMetadata(source) {
  const id = matchID || selected()?.id;
  if (!id) return;
  try {
    status("Saving metadata and artwork…");
    snapshot(await invoke("apply_metadata", { id, source }));
    closeDialogs();
    status("Metadata saved for offline use.");
  } catch (e) {
    report(e);
  }
}
async function showPublishers() {
  closeDialogs();
  matchID = selected()?.id;
  const entries = await invoke("publisher_catalog");
  const container = $("#publisher-items");
  container.replaceChildren();
  for (const entry of entries) {
    const row = document.createElement("div");
    row.className = "publisher";
    const text = document.createElement("span");
    text.textContent = `${entry.name} — ${entry.developer}`;
    const button = document.createElement("button");
    button.textContent = "Use for selected game";
    button.disabled = !matchID;
    button.onclick = () => applyMetadata(entry.id);
    row.append(text, button);
    container.append(row);
  }
  $("#publisher-list").showModal();
}
function showHelp() {
  closeDialogs();
  const content = $("#help-content");
  content.replaceChildren();
  for (const text of [
    "Games are detected at startup. Use Add / manage → Scan or Command/Ctrl-R to scan again. Add a games folder to include another disk or a Wine prefix.",
    "Left/Right or A/D browses continuously. Enter launches directly. Shift toggles details, L toggles libraries, F toggles favorites, and Escape closes panels. Shortcuts pause in text fields and dialogs.",
    "Controller: D-pad/stick or shoulders browse. Bottom face button launches; top opens details, left opens libraries, right closes panels. Controller input pauses while the app is inactive.",
    "Three local artwork roles: fitted portrait cover, landscape inspection image, alternate backdrop. Missing roles use the last cached fallback; no remote image request is made by the renderer.",
    "Native Mac apps and Linux AppImages can move to Trash. Steam and Wine Steam open the correct client uninstall dialog. Other package installations use their original client/system manager. Data in a moved application bundle moves with it; external saves stay in place.",
    "Wine/CrossOver/Sikarugir entries preserve their prefix identity and reuse the installed runtime. No Wine, Steam, or wrapper settings are rewritten. No new game compatibility or anti-cheat support is supplied.",
    "The shared desktop edition copies a native Mac library on first run into its own JoyniteDesktop data directory. ZIP backups include metadata and available cached/custom images, verified before restore. Legacy JSON imports remain available.",
    "Notices",
    ...data.notices,
    ...data.folders.map((s) => `Additional folder: ${s}`),
  ]) {
    const p = document.createElement("p");
    p.textContent = text;
    content.append(p);
  }
  $("#help-dialog").showModal();
}
function useKeyboard() {
  if (input !== "keyboard") {
    input = "keyboard";
    renderHints();
  }
}
function renderHints() {
  const playstation = /playstation|dualsense|dualshock/i.test(padName),
    labels =
      input === "controller"
        ? [
            ["◀ ▶", "Browse"],
            [playstation ? "×" : "A", "Play"],
            [playstation ? "△" : "Y", "Details"],
            [playstation ? "□" : "X", "Libraries"],
            [playstation ? "○" : "B", "Close panels"],
          ]
        : [
            ["← →", "Browse"],
            ["Enter", "Play"],
            ["Shift", "Details"],
            ["L", "Libraries"],
            ["F", "Favorite"],
            ["Space", "Search"],
          ];
  const hints = $("#hints");
  const signature = JSON.stringify(labels);
  if (hints.dataset.signature !== signature) {
    hints.replaceChildren();
    for (const [key, title] of labels) {
      const span = document.createElement("span");
      const k = document.createElement("kbd");
      k.textContent = key;
      span.append(k, document.createTextNode(title));
      hints.append(span);
    }
    hints.dataset.signature = signature;
  }
  $("#input-kind").textContent =
    input === "controller" ? `◉ ${padName || "Controller"}` : "⌨ Keyboard";
}
const searchBox = $(".search");
const suggestions = document.createElement("div");
suggestions.className = "search-suggestions";
suggestions.id = "search-results";
suggestions.setAttribute("role", "listbox");
$("#search").setAttribute("role", "combobox");
$("#search").setAttribute("aria-controls", "search-results");
$("#search").setAttribute("aria-expanded", "false");
searchBox.append(suggestions);
function openSearch() {
  if (searchExpanded) return;
  searchExpanded = true;
  searchSuggestion = 0;
  $("#search").setAttribute("aria-expanded", "true");
  searchBox.classList.add("expanded");
  document.body.classList.add("searching");
  $("#search").focus();
  renderSearchSuggestions();
}
function closeSearch(id = null) {
  if (id) {
    query = "";
    $("#search").value = "";
    changeFilter();
    const index = visible.findIndex((g) => g.id === id);
    if (index >= 0) {
      position = index;
      schedule();
    }
  } else {
    query = "";
    $("#search").value = "";
    changeFilter();
  }
  searchExpanded = false;
  $("#search").setAttribute("aria-expanded", "false");
  $("#search").removeAttribute("aria-activedescendant");
  searchBox.classList.remove("expanded");
  document.body.classList.remove("searching");
  $("#search").blur();
}
function renderSearchSuggestions() {
  suggestions.replaceChildren();
  const caption = document.createElement("p");
  caption.textContent = query
    ? "Closest matches"
    : "Enter selects. ↑ ↓ choose. Escape cancels.";
  suggestions.append(caption);
  for (const [index, game] of visible.slice(0, 5).entries()) {
    const button = document.createElement("button");
    button.textContent = game.name;
    button.id = `search-match-${index}`;
    button.setAttribute("role", "option");
    button.setAttribute("aria-selected", String(index === searchSuggestion));
    button.tabIndex = -1;
    if (index === searchSuggestion)
      $("#search").setAttribute("aria-activedescendant", button.id);
    button.onclick = () => closeSearch(game.id);
    suggestions.append(button);
  }
  if (!visible.length) {
    const p = document.createElement("p");
    p.textContent = "No close matches. Try another title.";
    suggestions.append(p);
  }
}
$("#search").addEventListener("focus", openSearch);
$("#app").addEventListener("pointerdown", (event) => {
  if (searchExpanded && event.target === $("#app")) closeSearch();
});
window.addEventListener("keydown", (event) => {
  useKeyboard();
  if (modalOpen()) return;
  if ((event.metaKey || event.ctrlKey) && event.key === ",") {
    event.preventDefault();
    showSettings();
    return;
  }
  if ((event.metaKey || event.ctrlKey) && event.key.toLowerCase() === "f") {
    event.preventDefault();
    openSearch();
    return;
  }
  if ((event.metaKey || event.ctrlKey) && event.key.toLowerCase() === "r") {
    event.preventDefault();
    scan();
    return;
  }
  if (
    event.key === " " &&
    !typing(event.target) &&
    !event.altKey &&
    !event.metaKey &&
    !event.ctrlKey
  ) {
    event.preventDefault();
    if (!event.repeat) openSearch();
    return;
  }
  if (
    event.target instanceof HTMLElement &&
    event.target.matches("button:not(.card),a") &&
    ["Enter", " "].includes(event.key)
  )
    return;
  if (event.key === "Tab") {
    event.preventDefault();
    return;
  }
  if (
    searchExpanded &&
    ["ArrowUp", "ArrowDown"].includes(event.key) &&
    !event.metaKey &&
    !event.ctrlKey &&
    !event.altKey
  ) {
    event.preventDefault();
    const count = Math.min(5, visible.length);
    if (count) {
      searchSuggestion =
        (searchSuggestion + (event.key === "ArrowDown" ? 1 : -1) + count) %
        count;
      renderSearchSuggestions();
    }
    return;
  }
  if (searchExpanded && event.key === "Enter") {
    event.preventDefault();
    if (!event.repeat) {
      const revision = searchRevision;
      searchWork.then(() => {
        if (searchExpanded && revision === searchRevision && visible.length)
          closeSearch((visible[searchSuggestion] || visible[0]).id);
      });
    }
    return;
  }
  if (typing(event.target)) {
    if (event.key === "Escape") {
      closeSearch();
    }
    return;
  }
  if (event.altKey || event.metaKey || event.ctrlKey) return;
  switch (event.key) {
    case "ArrowLeft":
    case "a":
      event.preventDefault();
      move(-1);
      break;
    case "ArrowRight":
    case "d":
      event.preventDefault();
      move(1);
      break;
    case "Enter":
      event.preventDefault();
      if (!event.repeat) launchSelected();
      break;
    case "Shift":
      if (!event.repeat) toggleDetails();
      break;
    case "l":
      if (!event.repeat) toggleLibraries();
      break;
    case "f":
      if (!event.repeat) favorite();
      break;
    case "Escape":
      closePanels();
      break;
  }
});
window.addEventListener("pointerdown", useKeyboard);
let lastWheel = 0;
$("#stage").addEventListener(
  "wheel",
  (event) => {
    if (modalOpen() || searchExpanded) return;
    const delta =
      Math.abs(event.deltaX) > Math.abs(event.deltaY)
        ? event.deltaX
        : event.deltaY;
    if (Math.abs(delta) > 3) {
      event.preventDefault();
      useKeyboard();
      if (performance.now() - lastWheel > 120) {
        lastWheel = performance.now();
        move(delta > 0 ? 1 : -1);
      }
    }
  },
  { passive: false },
);
let pointer = null;
$("#stage").addEventListener("pointerdown", (event) => {
  if (event.target.closest(".nav")) return;
  pointer = { x: event.clientX, id: event.pointerId };
});
$("#stage").addEventListener("pointerup", (event) => {
  if (pointer) {
    const delta = event.clientX - pointer.x;
    if (Math.abs(delta) > 55) {
      suppressClickUntil = performance.now() + 250;
      move(delta < 0 ? 1 : -1);
    }
    pointer = null;
  }
});
function stopController() {
  cancelAnimationFrame(controllerFrame);
  controllerFrame = 0;
  held = 0;
  padButtons = [];
}
function startController() {
  if (
    controllerFrame ||
    document.hidden ||
    !document.hasFocus() ||
    ![...(navigator.getGamepads?.() || [])].some(Boolean)
  )
    return;
  controllerFrame = requestAnimationFrame(pollController);
}
function pollController(time) {
  controllerFrame = 0;
  if (document.hidden || !document.hasFocus()) return;
  const pad = [...(navigator.getGamepads?.() || [])].find(Boolean);
  if (!pad) return;
  if (time - lastPadTime < 30) {
    controllerFrame = requestAnimationFrame(pollController);
    return;
  }
  lastPadTime = time;
  padName = pad.id;
  if (!modalOpen() && !typing(document.activeElement)) {
    const dir = direction(
      pad.axes[0] || 0,
      pad.buttons[14]?.pressed,
      pad.buttons[15]?.pressed,
    );
    if (dir) {
      if (dir !== held || time >= nextRepeat) {
        move(dir);
        nextRepeat = time + (dir === held ? 140 : 360);
      }
      input = "controller";
      renderHints();
    }
    held = dir;
    const action = {
      0: launchSelected,
      1: closePanels,
      2: toggleLibraries,
      3: () => toggleDetails(),
      4: () => move(-1),
      5: () => move(1),
      11: favorite,
    };
    pad.buttons.forEach((button, index) => {
      if (button.pressed && !padButtons[index] && action[index]) {
        input = "controller";
        action[index]();
        renderHints();
      }
    });
    padButtons = pad.buttons.map((b) => b.pressed);
  } else {
    held = 0;
    padButtons = pad.buttons.map((b) => b.pressed);
  }
  controllerFrame = requestAnimationFrame(pollController);
}
window.addEventListener("gamepadconnected", startController);
window.addEventListener("gamepaddisconnected", () => {
  stopController();
  useKeyboard();
  startController();
});
window.addEventListener("blur", stopController);
window.addEventListener("focus", () => {
  startController();
  if (!busy && data.games.some((g) => g.pendingUninstall)) scan();
});
document.addEventListener("visibilitychange", () =>
  document.hidden ? stopController() : startController(),
);
$("#edit-custom").onclick = showCustomEditor;
$("#search").addEventListener("input", (event) => {
  query = event.target.value;
  searchSuggestion = 0;
  if (data.games.length <= 500 || workerFailed) {
    changeFilter();
    renderSearchSuggestions();
    return;
  }
  searchRevision++;
  searchResolve?.();
  searchWork = new Promise((resolve) => {
    searchResolve = resolve;
  });
  suggestions.replaceChildren();
  const caption = document.createElement("p");
  caption.textContent = "Finding matches…";
  suggestions.append(caption);
  const request = { filter, query, revision: searchRevision };
  if (!workerHasData) {
    request.games = data.games.map(
      ({ id, name, genres, hidden, store, favorite, lastPlayed }) => ({
        id,
        name,
        genres,
        hidden,
        store,
        favorite,
        lastPlayed,
      }),
    );
    request.counts = [...startupCounts];
    workerHasData = true;
  }
  searchWorker.postMessage(request);
});
$("#libraries").onclick = toggleLibraries;
$("#library-close").onclick = () => {
  $("#library-panel").hidden = true;
};
$("#details-toggle").onclick = () => toggleDetails();
$("#details-close").onclick = () => toggleDetails(false);
$("#prev").onclick = () => move(-1);
$("#next").onclick = () => move(1);
$("#manage").onclick = () => $("#actions").showModal();
$("#empty-add").onclick = () => addGame().catch(report);
$("#add-game").onclick = () => addGame().catch(report);
$("#add-folder").onclick = () => addFolder().catch(report);
$("#scan").onclick = () => {
  closeDialogs();
  scan().then(() => hydrate());
};
$("#refresh").onclick = () => {
  closeDialogs();
  hydrate(true);
};
$("#publishers").onclick = () => showPublishers().catch(report);
$("#help").onclick = showHelp;
$("#action-help").onclick = showHelp;
$("#notices").onclick = showHelp;
$("#cancel").onclick = () => invoke("cancel_metadata").catch(report);
$("#restore").onclick = () =>
  invoke("restore_hidden").then(snapshot).catch(report);
document
  .querySelectorAll("[data-close]")
  .forEach(
    (button) => (button.onclick = () => button.closest("dialog").close()),
  );
$("#search-form").onsubmit = (e) => {
  e.preventDefault();
  searchMetadata();
};
$("#page-form").onsubmit = (e) => {
  e.preventDefault();
  applyMetadata($("#metadata-page").value);
};
let backupWorking = false;
async function backupOperation(command, path) {
  if (backupWorking) throw new Error("Another backup operation is active.");
  backupWorking = true;
  closeDialogs();
  const panel = document.createElement("section");
  panel.className = "backup-activity";
  panel.setAttribute("aria-live", "polite");
  const label = document.createElement("p"),
    progress = document.createElement("progress"),
    cancel = document.createElement("button");
  label.textContent =
    command === "export_library"
      ? "Backing up library and images…"
      : command === "preview_backup"
        ? "Verifying backup preview…"
        : "Verifying and restoring backup…";
  progress.max = 1;
  progress.value = 0;
  cancel.textContent = "Cancel";
  cancel.onclick = () => {
    invoke("cancel_backup").catch(() => {});
    cancel.disabled = true;
    label.textContent = "Cancelling…";
  };
  panel.append(label, progress, cancel);
  $("#app").append(panel);
  const timer = setInterval(async () => {
    try {
      const state = await invoke("backup_status");
      if (state.active && !cancel.disabled) {
        label.textContent = state.phase;
        progress.max = state.total || 1;
        progress.value = state.completed || 0;
      }
    } catch {}
  }, 250);
  try {
    return await invoke(command, { path });
  } finally {
    clearInterval(timer);
    panel.remove();
    backupWorking = false;
  }
}
$("#preview-backup").onclick = async () => {
  try {
    const path = await open({
      title: "Preview backup",
      filters: [{ name: "Joynite backup", extensions: ["zip"] }],
      multiple: false,
    });
    if (path) {
      const result = await backupOperation("preview_backup", path);
      closeDialogs();
      await message(
        `Adds ${result.additions.length} games. Keeps all ${result.kept} existing records and edits. Available artwork hashes verified. No changes made.\n\n${result.additions.slice(0, 10).join("\n")}`,
        { title: "Backup verified" },
      );
    }
  } catch (error) {
    if (String(error).toLowerCase().includes("cancelled"))
      status("Backup preview cancelled.");
    else report(error);
  }
};
$("#export").onclick = async () => {
  try {
    const path = await save({
      title: "Export library",
      defaultPath: "Joynite-backup.zip",
      filters: [{ name: "Library backup", extensions: ["zip"] }],
    });
    if (path) {
      await backupOperation("export_library", path);
      status("Library and artwork backed up.");
    }
    closeDialogs();
  } catch (e) {
    if (String(e).toLowerCase().includes("cancelled"))
      status("Backup operation cancelled. Existing library kept.");
    else report(e);
  }
};
$("#import").onclick = async () => {
  try {
    const path = await open({
      title: "Import library",
      filters: [
        { name: "Library backup / legacy JSON", extensions: ["zip", "json"] },
      ],
      multiple: false,
    });
    if (path) {
      snapshot(await backupOperation("import_library", path));
      hydrate();
    }
    closeDialogs();
  } catch (e) {
    if (String(e).toLowerCase().includes("cancelled"))
      status("Backup operation cancelled. Existing library kept.");
    else report(e);
  }
};
window.addEventListener("resize", schedule);
window.addEventListener("beforeunload", () => {
  unlisten?.();
  stopController();
});
async function startup() {
  unlisten = await listen("library-patched", (event) =>
    patchLibrary(event.payload),
  );
  snapshot(await invoke("get_library"));
  if (data.error) {
    status(data.error);
    return;
  }
  await scan();
  hydrate();
  startController();
}
startup().catch(report);

const customFields = ["name", "developer", "releaseDate", "genres", "summary"];
let editorID = null,
  editorBaseline = {},
  resetText = false,
  editorImages = {},
  resetImages = new Set();
function showCustomEditor() {
  const game = selected();
  if (!game) return;
  closeDialogs();
  editorID = game.id;
  resetText = false;
  editorImages = {};
  resetImages = new Set();
  editorBaseline = Object.fromEntries(
    customFields.map((key) => [
      key,
      key === "genres" ? (game.genres || []).join(", ") : game[key] || "",
    ]),
  );
  for (const key of customFields)
    $("#custom-" + key).value = editorBaseline[key];
  renderCustomImages();
  $("#custom-editor").showModal();
}
function renderCustomImages() {
  const game = data.games.find((g) => g.id === editorID),
    box = $("#custom-images");
  box.replaceChildren();
  for (const [role, label, field] of [
    ["portrait", "Card cover (2:3)", "customArtwork"],
    ["landscape", "Inspection image (16:9)", "customLandscape"],
    ["background", "Alternate background", "customBackground"],
  ]) {
    const row = document.createElement("div");
    row.className = "custom-row";
    const title = document.createElement("strong");
    title.textContent = label;
    const current = document.createElement("small");
    current.textContent =
      editorImages[role]?.split(/[\\/]/).pop() ||
      (resetImages.has(role)
        ? "Automatic image"
        : game?.[field]
          ? "Custom image saved offline"
          : "Automatic image");
    const choose = document.createElement("button");
    choose.type = "button";
    choose.textContent = "Choose image";
    choose.onclick = async () => {
      try {
        const path = await open({
          title: label,
          multiple: false,
          filters: [
            {
              name: "Images",
              extensions: ["png", "jpg", "jpeg", "webp", "gif"],
            },
          ],
        });
        if (path) {
          editorImages[role] = path;
          resetImages.delete(role);
          renderCustomImages();
        }
      } catch (e) {
        report(e);
      }
    };
    const reset = document.createElement("button");
    reset.type = "button";
    reset.textContent = "Use automatic";
    reset.onclick = () => {
      delete editorImages[role];
      resetImages.add(role);
      renderCustomImages();
    };
    row.append(title, current, choose, reset);
    box.append(row);
  }
}
$("#custom-reset-text").onclick = () => {
  const game = data.games.find((g) => g.id === editorID);
  resetText = true;
  editorBaseline = { ...editorBaseline, ...game?.automaticMetadata };
  for (const key of customFields)
    $("#custom-" + key).value = editorBaseline[key] || "";
};
$("#custom-cancel").onclick = () => $("#custom-editor").close();
$("#custom-form").onsubmit = async (event) => {
  event.preventDefault();
  const button = event.submitter;
  button.disabled = true;
  try {
    const changes = Object.fromEntries(
      customFields
        .map((key) => [key, $("#custom-" + key).value.trim()])
        .filter(([key, value]) => value !== (editorBaseline[key] || "")),
    );
    snapshot(
      await invoke("save_custom_metadata", {
        id: editorID,
        changes,
        resetText,
        images: editorImages,
        resetImages: [...resetImages],
      }),
    );
    $("#custom-editor").close();
    status("Custom metadata and images saved offline.");
  } catch (e) {
    report(e);
  } finally {
    button.disabled = false;
  }
};

async function refreshStartup() {
  const toggle = $("#startup-enabled");
  toggle.disabled = true;
  try {
    toggle.checked = await isStartupEnabled();
    $("#startup-status").textContent = toggle.checked
      ? "Joynite will open after sign-in."
      : "Startup launch is off.";
  } catch (error) {
    $("#startup-status").textContent = String(error);
    throw error;
  } finally {
    toggle.disabled = false;
  }
}
async function showSettings() {
  closeDialogs();
  $("#settings-dialog").showModal();
  try {
    await refreshStartup();
  } catch {}
}
$("#startup-enabled").onchange = async (event) => {
  const toggle = event.target,
    desired = toggle.checked;
  toggle.disabled = true;
  try {
    if (desired) await enableStartup();
    else await disableStartup();
    await refreshStartup();
  } catch (error) {
    try {
      toggle.checked = await isStartupEnabled();
    } catch {
      toggle.checked = !desired;
    }
    $("#startup-status").textContent =
      `Could not update startup launch: ${error}`;
  } finally {
    toggle.disabled = false;
  }
};
$("#startup-refresh").onclick = () => refreshStartup().catch(() => {});
$("#settings-open").onclick = showSettings;
$("#action-settings").onclick = showSettings;
for (const id of ["#support", "#settings-support"])
  $(id).onclick = () =>
    invoke("open_page", { url: "https://ko-fi.com/joyarz" }).catch(report);

startSoftwareUpdates($("#app"));

window.addEventListener("focus", () => {
  if (!$("#details").hidden) renderDetails();
});
