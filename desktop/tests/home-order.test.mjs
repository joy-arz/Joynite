import test from "node:test";
import assert from "node:assert/strict";
import { homeOrder, localLaunchCount } from "../src/home-order.mjs";
import { slots, filterGames } from "../src/model.mjs";
const games = Array.from({ length: 9 }, (_, i) => ({
  id: String(i + 1),
  name: `Game ${i + 1}`,
  launchCount: 90 - i * 10,
  genres: [],
}));
test("top five fan around the center and remaining ranks continue to the right", () => {
  const ring = homeOrder(games);
  assert.deepEqual(
    slots(0, ring)
      .filter((s) => Math.abs(s.offset) <= 2)
      .map((s) => s.game.id),
    ["4", "2", "1", "3", "5"],
  );
  assert.deepEqual(
    ring.map((g) => g.id),
    ["1", "3", "5", "6", "7", "8", "9", "4", "2"],
  );
  assert.equal(new Set(ring.map((g) => g.id)).size, games.length);
});
test("favorites outrank counts including more than five favorites; ties are deterministic", () => {
  const items = games.map((g) => ({ ...g, favorite: Number(g.id) > 2 }));
  assert.equal(homeOrder(items)[0].id, "3");
  const rankedRight = homeOrder(items).map((g) => g.id);
  assert.deepEqual(rankedRight, ["3", "5", "7", "8", "9", "1", "2", "6", "4"]);
  assert.deepEqual(
    homeOrder([
      { id: "b", name: "Beta" },
      { id: "a", name: "Alpha" },
    ]).map((g) => g.id),
    ["a", "b"],
  );
});
test("legacy libraries start at zero, hidden games stay out, search ignores home arrangement", () => {
  assert.equal(localLaunchCount({ lastPlayed: 99999999 }), 0);
  assert.equal(localLaunchCount({ launchCount: -1 }), 0);
  assert.equal(homeOrder([{ ...games[0], hidden: true }]).length, 0);
  assert.deepEqual(
    filterGames(games, "All games", "game 9")
      .map((g) => g.id)
      .slice(0, 1),
    ["9"],
  );
  for (const n of [0, 1, 2, 3, 4, 5])
    assert.equal(homeOrder(games.slice(0, n)).length, n);
});
test("launch counts are frozen for the open session and are re-ranked on a fresh launch", () => {
  const counts = new Map(games.map((g) => [g.id, g.launchCount]));
  const next = games.map((g) =>
    g.id === "9" ? { ...g, launchCount: 500 } : g,
  );
  assert.equal(homeOrder(next, counts)[0].id, "1");
  assert.equal(homeOrder(next)[0].id, "9");
});
