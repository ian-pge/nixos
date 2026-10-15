.pragma library

var ids = ["docker", "nix", "applications", "personal", "vm", "other"];
var dockerIds = ["layers", "volumes", "buildCache", "containers", "other"];
function bytes(value) {
  return typeof value === "number" && isFinite(value) && value >= 0
    && value <= Number.MAX_SAFE_INTEGER;
}

// Cached reports may outlive a shell revision. Reject malformed/old schemas,
// retain the last good snapshot on errors, and never turn unknown into zero.
function parse(text, now) {
  const report = JSON.parse(text);
  if (!report || report.schemaVersion !== 2 || !bytes(report.measuredAt)
      || report.measuredAt <= 0 || report.measuredAt > now + 60000
      || typeof report.estimated !== "boolean" || !report.disk
      || !bytes(report.disk.totalBytes) || report.disk.totalBytes === 0
      || !bytes(report.disk.usedBytes) || !bytes(report.disk.availableBytes)
      || report.disk.usedBytes > report.disk.totalBytes
      || report.disk.availableBytes > report.disk.totalBytes
      || !Array.isArray(report.categories) || report.categories.length !== ids.length)
    throw new Error("Invalid storage report");
  const seen = {};
  for (const row of report.categories) {
    if (!row || !ids.includes(row.id) || seen[row.id]
        || (row.bytes !== null && !bytes(row.bytes)) || typeof row.partial !== "boolean")
      throw new Error("Invalid storage category");
    seen[row.id] = true;
    if (row.id === "applications") {
      for (const key of ["cacheBytes", "dataBytes"])
        if (row[key] !== null && !bytes(row[key])) throw new Error("Invalid application detail");
    }
    if (row.id === "docker") {
      if (!Array.isArray(row.breakdown) || row.breakdown.length !== dockerIds.length)
        throw new Error("Invalid Docker detail");
      const parts = {};
      for (const part of row.breakdown) {
        if (!part || !dockerIds.includes(part.id) || parts[part.id]
            || (part.bytes !== null && !bytes(part.bytes)) || typeof part.partial !== "boolean")
          throw new Error("Invalid Docker detail");
        parts[part.id] = true;
      }
      if (row.bytes !== null && row.breakdown.reduce((sum, part) => sum + (part.bytes ?? 0), 0) > row.bytes)
        throw new Error("Inconsistent Docker detail");
    }
    if (row.id === "personal") {
      if (!Array.isArray(row.largestEntries) || row.largestEntries.length > 5)
        throw new Error("Invalid personal detail");
      const paths = {};
      let previous = Number.MAX_SAFE_INTEGER;
      for (const entry of row.largestEntries) {
        if (!entry || typeof entry.path !== "string" || !entry.path.startsWith("~/")
            || entry.path.length > 4096 || /[\x00-\x1f\x7f]/.test(entry.path)
            || entry.path.slice(2).split("/").some(part => part === "" || part === "." || part === "..")
            || Object.keys(paths).some(path => path === entry.path || path.startsWith(entry.path + "/")
              || entry.path.startsWith(path + "/"))
            || !bytes(entry.bytes) || entry.bytes > previous
            || (row.bytes !== null && entry.bytes > row.bytes)
            || !["file", "directory"].includes(entry.kind) || typeof entry.partial !== "boolean")
          throw new Error("Invalid personal entry");
        paths[entry.path] = true;
        previous = entry.bytes;
      }
      if (row.bytes !== null && row.largestEntries.reduce((sum, entry) => sum + entry.bytes, 0) > row.bytes)
        throw new Error("Inconsistent personal detail");
    }
  }
  return report;
}
