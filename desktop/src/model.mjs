import { homeOrder } from "./home-order.mjs";
import { normalizeSearch, searchIndex, searchScore } from "./search.mjs";
export const wrap = (index, count) =>
  count > 0 ? ((index % count) + count) % count : null;
export const offsets = (count) =>
  count === 0 ? [] : count === 1 ? [0] : [-4, -3, -2, -1, 0, 1, 2, 3, 4];
export function slots(position, games) {
  return offsets(games.length).map((offset) => ({
    key: position + offset,
    offset,
    game: games[wrap(position + offset, games.length)],
  }));
}
export function nearestPosition(position, index, count) {
  if (!count) return 0;
  const current = wrap(position, count);
  let delta = index - current;
  if (delta > count / 2) delta -= count;
  if (delta < -count / 2) delta += count;
  return position + delta;
}
export function filterGames(games, filter, query, counts = null) {
  const term = normalizeSearch(query.slice(0, 64));
  const index = searchIndex(games),
    scores = new Map();
  const results = games
    .filter(
      (g) =>
        !g.hidden &&
        (filter === "All games" ||
          (filter === "Favorites" && g.favorite) ||
          (filter === "Recently played" && g.lastPlayed) ||
          g.store === filter) &&
        (!term ||
          (() => {
            const score = searchScore(index.get(g.id), term);
            if (score === null) return false;
            scores.set(g.id, score);
            return true;
          })()),
    )
    .sort((a, b) =>
      term && scores.get(a.id) !== scores.get(b.id)
        ? scores.get(a.id) - scores.get(b.id)
        : filter === "Recently played"
          ? (b.lastPlayed || 0) - (a.lastPlayed || 0)
          : a.name.localeCompare(b.name),
    );
  if (term) {
    const direct = results.filter((g) => (scores.get(g.id) ?? 10) < 4);
    return direct.length ? direct : results.slice(0, 50);
  }
  return filter !== "Recently played" ? homeOrder(results, counts) : results;
}
export const imageRole = (game, role) =>
  game.images?.[role] ??
  (role === "background" ? game.images?.landscape : null) ??
  game.images?.portrait ??
  null;
export const direction = (x, dpadLeft, dpadRight) =>
  dpadLeft ? -1 : dpadRight ? 1 : x < -0.55 ? -1 : x > 0.55 ? 1 : 0;
