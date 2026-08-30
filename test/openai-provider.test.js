import test from "node:test";
import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import {
  DEFAULT_AI_SETTINGS,
  resolveStoredAISettings,
  translateText
} from "../src/providers/openai.js";

function installChromeStub() {
  globalThis.chrome = {
    permissions: { contains: async () => true },
    storage: {
      local: {
        get: async () => ({ safetyId: "clearframe_test" }),
        set: async () => {}
      }
    }
  };
}

test("extension AI reports incomplete responses", async () => {
  installChromeStub();
  globalThis.fetch = async () => new Response(
    JSON.stringify({
      status: "incomplete",
      incomplete_details: { reason: "max_output_tokens" },
      output: []
    }),
    { status: 200, headers: { "Content-Type": "application/json" } }
  );

  await assert.rejects(
    translateText("Text.", "en", "French", { enabled: true, apiKey: "test", model: "gpt-5.6-luna" }),
    /incomplete.*max_output_tokens/i
  );
});

test("extension AI reports failed response status", async () => {
  installChromeStub();
  globalThis.fetch = async () => new Response(
    JSON.stringify({
      status: "failed",
      error: { message: "Provider processing failed." },
      output: []
    }),
    { status: 200, headers: { "Content-Type": "application/json" } }
  );

  await assert.rejects(
    translateText("Text.", "en", "French", { enabled: true, apiKey: "test", model: "gpt-5.6-luna" }),
    /provider processing failed/i
  );
});

test("extension AI directs unavailable-model errors to Settings", async () => {
  installChromeStub();
  globalThis.fetch = async () => new Response(
    JSON.stringify({
      error: {
        message: "The requested model does not exist.",
        type: "invalid_request_error",
        code: "model_not_found"
      }
    }),
    { status: 404, headers: { "Content-Type": "application/json" } }
  );

  await assert.rejects(
    translateText("Text.", "en", "French", { enabled: true, apiKey: "test", model: DEFAULT_AI_SETTINGS.model }),
    /open settings.*supported model.*local result is still available/i
  );
});

test("extension default model matches the shared provider contract", async () => {
  const contractURL = new URL(
    "../macos/ClearframeBrowser/Tests/ClearframeCoreTests/Fixtures/provider-contract.json",
    import.meta.url
  );
  const contract = JSON.parse(await readFile(contractURL, "utf8"));
  assert.equal(DEFAULT_AI_SETTINGS.model, contract.defaultModel);
});

test("extension updates untouched defaults but preserves a customized model", () => {
  assert.equal(
    resolveStoredAISettings({ model: "retired-default-model", modelCustomized: false }).model,
    DEFAULT_AI_SETTINGS.model
  );
  assert.equal(
    resolveStoredAISettings({ model: "owner-selected-model", modelCustomized: true }).model,
    "owner-selected-model"
  );
});
