// List the Cursor models this account can actually select, with the parameters
// each one accepts and its default variant.
//
// This exists because neither of the obvious sources gives you a usable model
// ID. Cursor's model picker and the billing export both show display names --
// "Cursor Grok 4.5" and `cursor-grok-4.5-high-fast` are the same model, whose
// selectable ID is `grok-4.5`. Writing either display form into an agent
// prompt fails silently: Cursor falls back to the parent chat's model without
// reporting anything. Billing suffixes such as `-fast` or `-medium` are also
// not a faithful audit of the `fast=` / effort parameters you configured.
//
// The catalog is account- and team-specific, so this is the only authoritative
// answer for a given deployment. See DEPLOY.md Step 6.
//
// Usage:
//   npm install
//   CURSOR_API_KEY=<key> node list-models.mjs
//   node list-models.mjs --key-file ~/.cursor-api-key
//   node list-models.mjs --json > models.json
//
// Requires Node 22.13 or later. Get a key from https://cursor.com/dashboard/api

import { readFileSync } from "node:fs";

const args = process.argv.slice(2);
const wantJson = args.includes("--json");

function keyFileArg() {
  const i = args.indexOf("--key-file");
  return i === -1 ? undefined : args[i + 1];
}

function loadKey() {
  const file = keyFileArg();
  if (file) {
    const k = readFileSync(file, "utf8").trim();
    if (k) return k;
    throw new Error(`Key file is empty: ${file}`);
  }
  const env = process.env.CURSOR_API_KEY?.trim();
  if (env) return env;
  throw new Error(
    "No API key. Set CURSOR_API_KEY or pass --key-file <path>.\n" +
      "Create a key at https://cursor.com/dashboard/api"
  );
}

let Cursor;
try {
  ({ Cursor } = await import("@cursor/sdk"));
} catch (err) {
  console.error("Could not load @cursor/sdk. Run `npm install` in this directory first.");
  console.error(`(${err.message})`);
  process.exit(1);
}

let apiKey;
try {
  apiKey = loadKey();
} catch (err) {
  console.error(err.message);
  process.exit(1);
}

let models;
try {
  models = await Cursor.models.list({ apiKey });
} catch (err) {
  console.error(`Failed to fetch the model catalog: ${err.message}`);
  process.exit(1);
}

if (wantJson) {
  console.log(JSON.stringify(models, null, 2));
  process.exit(0);
}

console.log(`${models.length} models available to this account.`);
console.log("The ID below is what goes in an agent prompt's `model:` line.\n");

for (const m of models) {
  console.log(m.id);
  if (m.displayName) console.log(`  shown as: ${m.displayName}`);
  if (m.aliases?.length) console.log(`  aliases:  ${m.aliases.join(", ")}`);

  for (const p of m.parameters ?? []) {
    console.log(`  param ${p.id}: ${p.values.map((v) => v.value).join(" | ")}`);
  }

  // The default matters more than it looks: omitting a parameter selects this
  // variant, and on every family that offers the choice it is the costly one.
  const dflt = (m.variants ?? []).find((v) => v.isDefault);
  if (dflt) {
    console.log(`  default:  [${dflt.params.map((p) => `${p.id}=${p.value}`).join(",")}]`);
  }
  console.log();
}
