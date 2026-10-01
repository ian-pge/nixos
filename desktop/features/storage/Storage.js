.pragma library

var definitions = [
  {id: "docker", label: "Docker", height: 34},
  {id: "nix", label: "Nix store", height: 34},
  {id: "applications", label: "Applications et caches", height: 52},
  {id: "personal", label: "Fichiers personnels\net projets", height: 44},
  {id: "vm", label: "VM", height: 34},
  {id: "other", label: "Système et autres", height: 34}
];

function known(value) {
  return typeof value === "number" && isFinite(value) && value >= 0;
}

function rows(snapshot) {
  const source = snapshot && Array.isArray(snapshot.categories) ? snapshot.categories : [];
  let y = 0;
  return definitions.map(definition => {
    const reading = source.find(category => category.id === definition.id);
    const row = Object.assign({}, definition, {
      bytes: reading && known(reading.bytes) ? reading.bytes : null,
      partial: reading ? reading.partial === true : true,
      cacheBytes: reading && known(reading.cacheBytes) ? reading.cacheBytes : null,
      dataBytes: reading && known(reading.dataBytes) ? reading.dataBytes : null,
      y: y
    });
    y += row.height;
    return row;
  });
}

function sum(rows) {
  return rows.reduce((total, row) => total + (known(row.bytes) ? row.bytes : 0), 0);
}

function incomplete(rows) {
  return rows.some(row => row.partial || !known(row.bytes));
}

// Deliberately use the measured category sum. Allocated filesystem blocks and
// recursively measured files are not interchangeable, especially with Btrfs.
function segments(rows) {
  const total = sum(rows);
  let start = -90;
  return rows.map(row => {
    const sweep = total > 0 && known(row.bytes) ? row.bytes / total * 360 : 0;
    const segment = {id: row.id, startAngle: start, sweepAngle: sweep};
    start += sweep;
    return segment;
  });
}

function formatBytes(bytes) {
  if (!known(bytes)) return "—";
  if (bytes === 0) return "0 Gio";
  const gib = bytes / 1073741824;
  if (gib >= 1024) return (gib / 1024).toFixed(1).replace(".", ",") + " Tio";
  if (gib < 0.1) return "< 0,1 Gio";
  return gib.toFixed(1).replace(".", ",") + " Gio";
}

function percent(bytes, total) {
  if (!known(bytes) || total <= 0) return "—";
  if (bytes === 0) return "0 %";
  const value = bytes / total * 100;
  return value < 1 ? "< 1 %" : Math.round(value) + " %";
}

function timestamp(updatedAt, now) {
  if (!known(updatedAt) || updatedAt <= 0) return "Aucune mesure";
  const minutes = Math.max(0, Math.floor((now - updatedAt) / 60000));
  if (minutes < 1) return "À l’instant";
  if (minutes < 60) return "Il y a " + minutes + " min";
  if (minutes < 1440) return "Il y a " + Math.floor(minutes / 60) + " h";
  return "Il y a " + Math.floor(minutes / 1440) + " j";
}
