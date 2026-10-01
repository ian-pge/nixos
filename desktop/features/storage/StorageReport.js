.pragma library

var ids = ["docker", "nix", "applications", "personal", "vm", "other"];
function bytes(value) {
  return typeof value === "number" && isFinite(value) && value >= 0
    && value <= Number.MAX_SAFE_INTEGER;
}

// Cached reports may outlive a shell revision. Reject malformed/old schemas,
// retain the last good snapshot on errors, and never turn unknown into zero.
function parse(text, now) {
  const report = JSON.parse(text);
  if (!report || report.schemaVersion !== 1 || !bytes(report.measuredAt)
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
  }
  return report;
}
