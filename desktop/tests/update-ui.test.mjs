import test from "node:test";
import assert from "node:assert/strict";
import { JSDOM } from "jsdom";
import { mockIPC, clearMocks } from "@tauri-apps/api/mocks";
import { startSoftwareUpdates } from "../src/software-updates.js";
import { reminderKey } from "../src/update-policy.mjs";

test("quiet background update UX, later, skip, next release, offline and install actions", async () => {
  const dom = new JSDOM(
    '<main id="app"></main><p id="update-check-status"></p><button id="update-check"></button>',
    { url: "https://joynite.test" },
  );
  global.window = dom.window;
  global.document = dom.window.document;
  global.localStorage = dom.window.localStorage;
  Object.defineProperty(global, "navigator", {
    value: dom.window.navigator,
    configurable: true,
  });
  let online = true,
    enabled = true,
    available = true,
    version = "0.6.0",
    checkCount = 0,
    installCount = 0,
    restarts = 0;
  Object.defineProperty(navigator, "onLine", {
    get: () => online,
    configurable: true,
  });
  mockIPC((command) => {
    if (command === "update_checks_enabled") return enabled;
    if (command === "plugin:updater|check") {
      checkCount++;
      return available
        ? { rid: 100, currentVersion: "0.5.0", version, rawJson: {} }
        : null;
    }
    if (command === "plugin:updater|download_and_install") {
      installCount++;
      return null;
    }
    if (command === "plugin:process|restart") {
      restarts++;
      return null;
    }
    if (command === "plugin:resources|close") return null;
    throw new Error("Unexpected IPC command: " + command);
  });
  const notice = () => document.querySelector(".software-update");
  const create = () => {
    document.querySelector("#app").replaceChildren();
    return startSoftwareUpdates(document.querySelector("#app"), {
      delay: 3600000,
    });
  };
  let controller = create();
  available = false;
  await controller.checkNow();
  assert(notice().hidden);
  assert.equal(checkCount, 1);
  available = true;
  controller = create();
  await controller.checkNow();
  assert(!notice().hidden);
  assert(notice().querySelector("h2").textContent.includes("0.6.0"));
  notice().querySelector(".update-later").click();
  await new Promise((resolve) => setTimeout(resolve, 0));
  assert(notice().hidden);
  controller = create();
  await controller.checkNow();
  assert(notice().hidden);
  await controller.checkNow(true);
  assert(!notice().hidden);
  notice().querySelector(".update-skip").click();
  await new Promise((resolve) => setTimeout(resolve, 0));
  assert.equal(
    JSON.parse(localStorage.getItem(reminderKey)).skippedVersion,
    "0.6.0",
  );
  controller = create();
  await controller.checkNow();
  assert(notice().hidden);
  version = "0.7.0";
  controller = create();
  await controller.checkNow();
  assert(!notice().hidden);
  notice().querySelector(".update-now").click();
  await new Promise((resolve) => setTimeout(resolve, 0));
  assert.equal(installCount, 1);
  assert.equal(restarts, 1);
  online = false;
  const before = checkCount;
  controller = create();
  await controller.checkNow();
  assert.equal(checkCount, before);
  assert(notice().hidden);
  online = true;
  enabled = false;
  controller = create();
  await controller.checkNow();
  assert.equal(checkCount, before);
  assert(notice().hidden);
  window.dispatchEvent(new dom.window.Event("beforeunload"));
  clearMocks();
  dom.window.close();
});
