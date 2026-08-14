import test from "node:test";
import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import {
  createAiAnalysis,
  DEFAULT_AI_SETTINGS,
  resolveStoredAISettings
} from "../src/providers/openai.js";

const page = {
  title: "Private search",
  hostname: "example.org",
  language: "fr",
  url: "https://example.org/results?q=private-token#account",
  text: "Le document contient un texte visible qui doit rester dans la langue source."
};

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

test("extension AI uses source language, structured output, and no full URL", async () => {
  installChromeStub();
  let requestBody;
  globalThis.fetch = async (_url, options) => {
    requestBody = JSON.parse(options.body);
    return new Response(
      JSON.stringify({
        status: "completed",
        output: [{
          type: "message",
          content: [{
            type: "output_text",
            text: JSON.stringify({
              summary: "Résumé fidèle.",
              keyPoints: ["Point vérifiable."],
              claimsToCheck: []
            })
          }]
        }]
      }),
      { status: 200, headers: { "Content-Type": "application/json" } }
    );
  };

  const result = await createAiAnalysis(page, {
    enabled: true,
    apiKey: "test-key",
    model: "gpt-5.6-luna"
  });

  assert.equal(result.summary, "Résumé fidèle.");
  assert.equal(requestBody.store, false);
  assert.equal(requestBody.reasoning.effort, "none");
  assert.equal(requestBody.text.format.type, "json_schema");
  assert.equal(requestBody.text.format.strict, true);
  assert.match(requestBody.instructions, /source language/i);
  const input = JSON.parse(requestBody.input);
  assert.equal(input.sourceHost, "example.org");
  assert.equal(input.sourceLanguage, "fr");
  assert.equal("url" in input, false);
  assert.equal(requestBody.input.includes("private-token"), false);
});

test("extension AI refuses an unvalidated page source instead of uploading hostname text", async () => {
  installChromeStub();
  globalThis.fetch = async () => assert.fail("invalid page source must not reach the provider");

  await assert.rejects(
    createAiAnalysis(
      { ...page, url: "data:text/plain,private", liveUrl: "file:///tmp/private", hostname: "secret.example?q=token" },
      { enabled: true, apiKey: "test", model: "gpt-5.6-luna" }
    ),
    /could not be validated/i
  );
});

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
    createAiAnalysis(page, { enabled: true, apiKey: "test", model: "gpt-5.6-luna" }),
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
    createAiAnalysis(page, { enabled: true, apiKey: "test", model: "gpt-5.6-luna" }),
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
    createAiAnalysis(page, { enabled: true, apiKey: "test", model: DEFAULT_AI_SETTINGS.model }),
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

test("extension AI rejects schema-shaped output with invalid item types", async () => {
  installChromeStub();
  globalThis.fetch = async () => new Response(
    JSON.stringify({
      status: "completed",
      output: [{
        type: "message",
        content: [{
          type: "output_text",
          text: JSON.stringify({
            summary: "Looks superficially valid.",
            keyPoints: [42],
            claimsToCheck: []
          })
        }]
      }]
    }),
    { status: 200, headers: { "Content-Type": "application/json" } }
  );

  await assert.rejects(
    createAiAnalysis(page, { enabled: true, apiKey: "test", model: "gpt-5.6-luna" }),
    /unexpected format/i
  );
});
