import { filterGames } from "./model.mjs";
let games = [],
  timer;
self.onmessage = ({ data }) => {
  if (data.games) games = data.games;
  clearTimeout(timer);
  timer = setTimeout(() => {
    const ids = filterGames(games, data.filter, data.query).map((g) => g.id);
    self.postMessage({ revision: data.revision, ids });
  }, 0);
};
