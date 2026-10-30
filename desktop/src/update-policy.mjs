export const reminderKey = "joynite.update-reminder.v1";
export function stableVersion(raw) {
  if (typeof raw !== "string" || raw.length > 80) return null;
  const value = raw.replace(/^v/, "").split("+")[0];
  if (!/^(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)$/.test(value)) return null;
  return value;
}
export function newerVersion(candidate, current) {
  const left = stableVersion(candidate),
    right = stableVersion(current);
  if (!left || !right) return false;
  const a = left.split(".").map(BigInt),
    b = right.split(".").map(BigInt);
  for (let i = 0; i < 3; i++) {
    if (a[i] !== b[i]) return a[i] > b[i];
  }
  return false;
}
export function shouldNotify(version, preferences = {}, now = Date.now()) {
  const value = stableVersion(version);
  return (
    !!value &&
    stableVersion(preferences.skippedVersion) !== value &&
    (stableVersion(preferences.postponedVersion) !== value ||
      !Number.isFinite(preferences.postponedUntil) ||
      preferences.postponedUntil <= now)
  );
}
export function postpone(version, now = Date.now()) {
  return {
    postponedVersion: stableVersion(version),
    postponedUntil: now + 86400000,
  };
}
export function skip(version) {
  return { skippedVersion: stableVersion(version) };
}
