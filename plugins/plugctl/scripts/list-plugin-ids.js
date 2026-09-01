#!/usr/bin/env node
// Liest "claude plugin list --json" von stdin und gibt eine Plugin-ID pro Zeile aus.
//
// Warum so defensiv: die JSON-Struktur von "claude plugin list --json" hat sich
// zwischen Claude-Code-Versionen bereits geaendert (mal ein Objekt mit den IDs
// als Keys, mal ein Array von Objekten, teils nach Scope gruppiert). Statt auf
// einen festen Pfad zu setzen, wird der Baum abgelaufen und alles eingesammelt,
// was wie ein Plugin-Eintrag aussieht.

const PLUGIN_FIELDS = ["version", "marketplace", "enabled", "source", "id", "scope"];
const SKIP_KEYS = new Set(["marketplaces", "errors", "warnings"]);

const ids = new Set();

function push(name, marketplace) {
  if (!name || typeof name !== "string") return;
  if (name.includes("@")) ids.add(name);
  else if (marketplace && typeof marketplace === "string") ids.add(`${name}@${marketplace}`);
  else ids.add(name);
}

function looksLikePlugin(v) {
  return v && typeof v === "object" && !Array.isArray(v)
    && PLUGIN_FIELDS.some((k) => k in v);
}

function walk(node, keyHint) {
  if (!node) return;

  if (Array.isArray(node)) {
    for (const entry of node) {
      if (typeof entry === "string") push(entry);
      else if (looksLikePlugin(entry)) push(entry.id || entry.name || keyHint, entry.marketplace);
      else if (entry && typeof entry === "object") walk(entry, keyHint);
    }
    return;
  }

  if (typeof node !== "object") return;

  for (const [key, value] of Object.entries(node)) {
    if (SKIP_KEYS.has(key)) continue;

    // Form: { "enabledPlugins": { "name@marketplace": true } }
    if (typeof value === "boolean" || typeof value === "string") {
      if (key.includes("@")) push(key);
      continue;
    }
    if (Array.isArray(value)) { walk(value, key); continue; }
    if (looksLikePlugin(value)) { push(value.id || key, value.marketplace); continue; }
    if (value && typeof value === "object") walk(value, key);
  }
}

let buf = "";
process.stdin.setEncoding("utf8");
process.stdin.on("data", (chunk) => { buf += chunk; });
process.stdin.on("end", () => {
  let parsed;
  try {
    parsed = JSON.parse(buf);
  } catch {
    process.stderr.write("Konnte die Ausgabe von 'claude plugin list --json' nicht parsen.\n");
    process.exit(3);
  }
  walk(parsed);
  if (ids.size === 0) process.exit(4);
  process.stdout.write([...ids].join("\n") + "\n");
});
