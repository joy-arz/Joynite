import test from "node:test";
import assert from "node:assert/strict";
import {
  stableVersion,
  newerVersion,
  shouldNotify,
  postpone,
  skip,
} from "../src/update-policy.mjs";
test("stable releases compare numerically and reject unsafe or prerelease versions", () => {
  assert(newerVersion("v0.10.0", "0.9.9"));
  assert(!newerVersion("0.5.0", "0.5.0"));
  assert(!newerVersion("0.4.0", "0.5.0"));
  for (const value of [
    "",
    null,
    "0.6.0-rc.1",
    "01.2.3",
    "x.2.3",
    "1.2.3<script>",
  ])
    assert.equal(stableVersion(value), null);
  assert.equal(stableVersion("v1.2.3+build4"), "1.2.3");
});
test("skip suppresses only that version across restart serialization", () => {
  const preferences = JSON.parse(JSON.stringify(skip("v0.6.0")));
  assert(!shouldNotify("0.6.0", preferences));
  assert(shouldNotify("0.7.0", preferences));
});
test("later snoozes for 24 hours and a new release bypasses it", () => {
  const now = 2000000000000,
    prefs = postpone("0.6.0", now);
  assert(!shouldNotify("0.6.0", prefs, now + 1000));
  assert(shouldNotify("0.6.0", prefs, now + 86400000));
  assert(shouldNotify("0.7.0", prefs, now + 1000));
  assert(shouldNotify("0.6.0", {}, now));
});
