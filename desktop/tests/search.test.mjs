import test from "node:test";
import assert from "node:assert/strict";
import { filterGames } from "../src/model.mjs";
const games = [
  "Inscryption",
  "Minecraft",
  "Pokémon",
  "The Binding of Isaac",
].map((name, i) => ({ id: String(i), name, genres: [], store: "Steam" }));
test("case, accents, omissions, multiple typos and unrelated queries", () => {
  for (const query of ["INSCRYPTION", "incryption", "inkriotion"])
    assert.equal(filterGames(games, "All games", query)[0].name, "Inscryption");
  assert.equal(filterGames(games, "All games", "pokemon")[0].name, "Pokémon");
  assert.equal(filterGames(games, "All games", "zzzzzzzzzz").length, 0);
  assert.equal(
    filterGames(games, "All games", "binding")[0].name,
    "The Binding of Isaac",
  );
  assert.equal(filterGames(games, "Favorites", "inscryption").length, 0);
});
