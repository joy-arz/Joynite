export const normalizeSearch = (text) =>
  String(text)
    .normalize("NFKD")
    .replace(/\p{M}/gu, "")
    .toLowerCase()
    .replace(/[^\p{L}\p{N}]/gu, "");
export function similarity(left, right) {
  const a = [...left],
    b = [...right],
    n = Math.max(a.length, b.length);
  if (!n || Math.abs(a.length - b.length) > n / 2) return 0;
  let previous = Array.from({ length: b.length + 1 }, (_, i) => i),
    older = previous;
  for (let i = 0; i < a.length; i++) {
    const row = [i + 1];
    for (let j = 0; j < b.length; j++) {
      row[j + 1] = Math.min(
        row[j] + 1,
        previous[j + 1] + 1,
        previous[j] + (a[i] === b[j] ? 0 : 1),
      );
      if (i > 0 && j > 0 && a[i] === b[j - 1] && a[i - 1] === b[j])
        row[j + 1] = Math.min(row[j + 1], older[j - 1] + 1);
    }
    older = previous;
    previous = row;
  }
  return 1 - previous[b.length] / n;
}
const indexes = new WeakMap();
export function searchIndex(games) {
  if (indexes.has(games)) return indexes.get(games);
  const index = new Map(
    games.map((g) => [
      g.id,
      {
        title: normalizeSearch(g.name.slice(0, 256)),
        words: g.name.split(/[^\p{L}\p{N}]+/u).map(normalizeSearch),
        genres: normalizeSearch((g.genres || []).join(" ")),
      },
    ]),
  );
  indexes.set(games, index);
  return index;
}
export function searchScore(entry, q) {
  if (!q || entry.title === q) return 0;
  if (entry.title.startsWith(q)) return 1;
  if (entry.title.includes(q)) return 2;
  if (entry.genres.includes(q)) return 3;
  if ([...q].length < 4) return null;
  const score = Math.max(
    ...[
      ...(q.length >= entry.title.length * 0.7 ? [entry.title] : []),
      ...entry.words.filter((w) => w.length >= 4),
    ].map((w) => similarity(q, w)),
  );
  return score >= 0.5 ? 5 - score : null;
}
