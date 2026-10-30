import test from "node:test";
import assert from "node:assert/strict";
import { mergeLibraryPatch } from "../src/library-patch.mjs";
test("changed records preserve other references and do not resurrect removed games", () => {
  const games = Array.from({ length: 10000 }, (_, i) => ({
    id: String(i),
    name: `Game ${i}`,
  }));
  const original = { games, revision: 10, notices: ["kept"] };
  const changed = { ...games[25], summary: "Updated" };
  const next = mergeLibraryPatch(original, {
    revision: 11,
    games: [changed, { id: "removed" }],
    notices: ["new", "kept"],
  });
  assert.equal(next.games.length, 10000);
  assert.equal(next.games[25], changed);
  assert.equal(next.games[26], games[26]);
  assert.deepEqual(next.notices, ["kept", "new"]);
  assert.equal(
    mergeLibraryPatch(next, { revision: 10, games: [], notices: [] }),
    next,
  );
  assert.equal(
    mergeLibraryPatch(next, { revision: NaN, games: [], notices: [] }),
    next,
  );
});
