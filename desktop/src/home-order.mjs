export const localLaunchCount = (game) =>
  Number.isInteger(game.launchCount) && game.launchCount >= 0
    ? Math.min(game.launchCount, 4294967295)
    : 0;
const byName = (a, b) =>
  a.name.localeCompare(b.name, undefined, {
    numeric: true,
    sensitivity: "base",
  }) || a.id.localeCompare(b.id);
export function homeOrder(games, counts = null) {
  const ranked = games
    .filter((g) => !g.hidden)
    .sort(
      (a, b) =>
        Number(!!b.favorite) - Number(!!a.favorite) ||
        (counts?.get(b.id) ?? localLaunchCount(b)) -
          (counts?.get(a.id) ?? localLaunchCount(a)) ||
        byName(a, b),
    );
  const top = ranked.slice(0, 5),
    rest = ranked.slice(5);
  return [top[0], top[2], top[4], ...rest, top[3], top[1]].filter(Boolean);
}
