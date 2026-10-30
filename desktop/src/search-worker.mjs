import { filterGames } from "./model.mjs";
let counts = null;
let games = [],
  timer;
self.onmessage = ({ data }) => {
  if (data.games) games = data.games;
  if (data.counts) counts = new Map(data.counts);
  clearTimeout(timer);
  timer = setTimeout(() => {
    const ids = filterGames(games, data.filter, data.query, counts).map(
      (g) => g.id,
    );
    self.postMessage({ revision: data.revision, ids });
  }, 0);
};
