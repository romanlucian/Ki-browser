import { DEFAULT_AI_SETTINGS, resolveStoredAISettings } from "./providers/openai.js";

const enabled = document.querySelector("#aiEnabled");
const fields = document.querySelector("#aiFields");
const apiKey = document.querySelector("#apiKey");
const model = document.querySelector("#model");
const status = document.querySelector("#status");

function renderEnabledState() {
  fields.classList.toggle("hidden", !enabled.checked);
}

async function load() {
  const stored = await chrome.storage.local.get("aiSettings");
  const settings = resolveStoredAISettings(stored.aiSettings);
  enabled.checked = settings.enabled;
  apiKey.value = settings.apiKey;
  model.value = settings.model;
  renderEnabledState();
}

async function save() {
  status.textContent = "";
  if (enabled.checked && !apiKey.value.trim()) {
    status.textContent = "Add an API key, or turn Optional AI off.";
    return;
  }

  if (enabled.checked) {
    const granted = await chrome.permissions.request({ origins: ["https://api.openai.com/*"] });
    if (!granted) {
      status.textContent = "AI was not enabled because API access was not granted.";
      return;
    }
  }

  await chrome.storage.local.set({
    aiSettings: {
      enabled: enabled.checked,
      apiKey: apiKey.value.trim(),
      model: model.value.trim() || DEFAULT_AI_SETTINGS.model,
      modelCustomized: Boolean(model.value.trim() && model.value.trim() !== DEFAULT_AI_SETTINGS.model)
    }
  });
  if (!enabled.checked) {
    await chrome.permissions.remove({ origins: ["https://api.openai.com/*"] });
  }
  status.textContent = "Settings saved.";
}

async function clearKey() {
  apiKey.value = "";
  enabled.checked = false;
  renderEnabledState();
  await chrome.storage.local.set({ aiSettings: { ...DEFAULT_AI_SETTINGS } });
  await chrome.permissions.remove({ origins: ["https://api.openai.com/*"] });
  status.textContent = "API key removed.";
}

enabled.addEventListener("change", renderEnabledState);
document.querySelector("#saveButton").addEventListener("click", save);
document.querySelector("#clearKeyButton").addEventListener("click", clearKey);

await load();
