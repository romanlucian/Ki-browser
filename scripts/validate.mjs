import { access, readFile } from "node:fs/promises";
import path from "node:path";

const root = process.cwd();
const manifest = JSON.parse(await readFile(path.join(root, "manifest.json"), "utf8"));
const required = [
  manifest.background.service_worker,
  manifest.side_panel.default_path,
  manifest.options_page,
  "src/sidepanel.js",
  "src/core/analyzer.js",
  "src/core/compare.js",
  "src/providers/openai.js"
];

for (const file of required) {
  await access(path.join(root, file));
}

if (manifest.manifest_version !== 3) throw new Error("Expected Manifest V3.");
if (manifest.permissions.includes("tabs")) throw new Error("Avoid persistent tabs permission.");
if ((manifest.host_permissions || []).includes("<all_urls>")) {
  throw new Error("Avoid broad persistent page access.");
}
if (!manifest.permissions.includes("activeTab")) throw new Error("Expected activeTab privacy boundary.");

console.log(`Validated ${required.length} referenced files and least-privilege manifest checks.`);
