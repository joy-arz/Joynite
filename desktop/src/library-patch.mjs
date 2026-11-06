export function mergeLibraryPatch(current, patch) {
  if (
    !patch ||
    !Number.isFinite(patch.revision) ||
    patch.revision < (current.revision || 0)
  )
    return current;
  const changes = new Map((patch.games || []).map((g) => [g.id, g]));
  return {
    ...current,
    revision: patch.revision,
    games: current.games.map((g) => changes.get(g.id) || g),
    notices: [
      ...new Set([...(current.notices || []), ...(patch.notices || [])]),
    ],
  };
}
