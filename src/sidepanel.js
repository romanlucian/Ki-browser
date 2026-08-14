import { analyzePage, canSimplifyToPlainEnglish, simplifyEnglish } from "./core/analyzer.js";
import { compareSources } from "./core/compare.js";
import { extractPage } from "./content/extract-page.js";
import { createAiAnalysis, DEFAULT_AI_SETTINGS, translateText } from "./providers/openai.js";

const $ = (selector) => document.querySelector(selector);
const views = [$("#introView"), $("#loadingView"), $("#resultsView"), $("#errorView")];
let currentPage = null;
let currentAnalysis = null;
let originalSummary = "";
let savedSource = null;
let settings = { ...DEFAULT_AI_SETTINGS };
let toastTimer = null;
let currentTabId = null;
let operationGeneration = 0;
let activeRemoteController = null;

function showView(view) {
  views.forEach((entry) => entry.classList.toggle("hidden", entry !== view));
}

function setLoading(label) {
  $("#loadingLabel").textContent = label;
  showView($("#loadingView"));
}

function showToast(message) {
  clearTimeout(toastTimer);
  $("#toast").textContent = message;
  $("#toast").classList.remove("hidden");
  toastTimer = setTimeout(() => $("#toast").classList.add("hidden"), 3200);
}

function showError(message) {
  $("#errorMessage").textContent = message;
  showView($("#errorView"));
}

function textList(element, items) {
  element.replaceChildren(
    ...items.map((item) => {
      const li = document.createElement("li");
      li.textContent = item;
      return li;
    })
  );
}

function sourceSnapshot() {
  return {
    title: currentPage.title,
    url: currentPage.url,
    hostname: currentPage.hostname,
    summary: currentAnalysis.summary,
    keyPoints: currentAnalysis.keyPoints,
    savedAt: new Date().toISOString()
  };
}

function renderRisk(risk) {
  const card = $("#riskCard");
  card.classList.remove("low", "caution", "high");
  card.classList.add(risk.level.toLowerCase());
  $("#riskLevel").textContent = `${risk.level} risk signals`;
  $("#riskScore").textContent = `${risk.score} / 100`;
  $("#riskSummary").textContent = risk.signals.length
    ? `${risk.signals.length} visible signal${risk.signals.length === 1 ? "" : "s"} worth checking. This is not a verdict on the site.`
    : "No obvious high-risk signals were found in the visible page. That does not prove the site is safe.";

  const signalBox = $("#riskSignals");
  signalBox.replaceChildren(
    ...risk.signals.map((signal) => {
      const row = document.createElement("div");
      row.className = "risk-signal";
      const title = document.createElement("strong");
      title.textContent = signal.title;
      const detail = document.createElement("span");
      detail.textContent = signal.detail;
      row.append(title, detail);
      return row;
    })
  );
  signalBox.classList.add("hidden");
  $("#riskToggle").classList.toggle("hidden", risk.signals.length === 0);
  $("#riskToggle").textContent = "Show signals";
}

function renderAnalysis() {
  $("#sourceHost").textContent = currentPage.hostname || "CURRENT PAGE";
  $("#pageTitle").textContent = currentPage.title;
  $("#sourceMeta").textContent = `${currentAnalysis.readMinutes} min read · ${currentPage.language || "language not declared"}`;
  $("#summaryText").textContent = currentAnalysis.summary;
  $("#modeBadge").textContent = currentAnalysis.mode.toUpperCase();
  textList($("#keyPoints"), currentAnalysis.keyPoints);
  $("#pointsSection").classList.toggle("hidden", currentAnalysis.keyPoints.length === 0);
  textList($("#claimsList"), currentAnalysis.claimsToCheck);
  $("#claimsSection").classList.toggle("hidden", currentAnalysis.claimsToCheck.length === 0);
  renderRisk(currentAnalysis.risk);
  renderCompareState();
  $("#translationOutput").classList.add("hidden");
  $("#aiButton").disabled = false;
  $("#aiButtonLabel").textContent = settings.enabled && settings.apiKey ? "Improve with AI" : "Add AI for a richer summary";
  $("#translateButton").disabled = false;
  $("#translateButton").textContent = "Translate";
  showView($("#resultsView"));
}

function renderCompareState() {
  const isSame = savedSource?.url === currentPage?.url;
  if (!savedSource) {
    $("#compareTitle").textContent = "Compare another page";
    $("#compareDescription").textContent = "Save this view, open a second source, then compare their themes and figures.";
    $("#compareButton").textContent = "Save as source one";
  } else if (isSame) {
    $("#compareTitle").textContent = "Source one is saved";
    $("#compareDescription").textContent = "Open another page and click the Clearframe toolbar icon, then analyze it.";
    $("#compareButton").textContent = "Saved";
  } else {
    $("#compareTitle").textContent = "Ready to compare";
    $("#compareDescription").textContent = `${savedSource.hostname} ↔ ${currentPage.hostname}`;
    $("#compareButton").textContent = "Compare these sources";
  }
  $("#compareButton").disabled = Boolean(savedSource && isSame);
  $("#clearCompareButton").classList.toggle("hidden", !savedSource);
  $("#comparisonOutput").classList.add("hidden");
}

async function loadSettings() {
  const stored = await chrome.storage.local.get(["aiSettings", "comparisonSource"]);
  settings = { ...DEFAULT_AI_SETTINGS, ...(stored.aiSettings || {}) };
  savedSource = stored.comparisonSource || null;
}

async function analyzeActivePage() {
  activeRemoteController?.abort();
  activeRemoteController = null;
  const generation = ++operationGeneration;
  setLoading("Reading the page…");
  try {
    const [tab] = await chrome.tabs.query({ active: true, currentWindow: true });
    if (!tab?.id || !/^https?:/i.test(tab.url || "")) {
      throw new Error("Open a normal web page, then click the Clearframe toolbar icon again.");
    }
    currentTabId = tab.id;
    const [result] = await chrome.scripting.executeScript({
      target: { tabId: tab.id },
      func: extractPage
    });
    if (!result?.result?.text) {
      throw new Error("This page does not expose enough readable text. Try an article, guide, or product page.");
    }
    if (generation !== operationGeneration) return;
    currentPage = result.result;
    currentAnalysis = analyzePage(currentPage);
    originalSummary = currentAnalysis.summary;
    renderAnalysis();
  } catch (error) {
    if (generation !== operationGeneration) return;
    showError(error.message || "The browser blocked access to this page.");
  }
}

async function improveWithAi() {
  if (!settings.enabled || !settings.apiKey) {
    await chrome.runtime.openOptionsPage();
    return;
  }
  const button = $("#aiButton");
  const generation = ++operationGeneration;
  const sourceURL = currentPage?.liveUrl || currentPage?.url;
  const controller = new AbortController();
  activeRemoteController?.abort();
  activeRemoteController = controller;
  button.disabled = true;
  $("#aiButtonLabel").textContent = "Reading carefully…";
  try {
    const aiResult = await createAiAnalysis(currentPage, settings, controller.signal);
    if (generation !== operationGeneration || sourceURL !== (currentPage?.liveUrl || currentPage?.url)) return;
    currentAnalysis = { ...currentAnalysis, ...aiResult, mode: "AI" };
    originalSummary = currentAnalysis.summary;
    renderAnalysis();
    showToast("AI summary ready. The disclosed title, hostname, language, and extracted text were sent for this request.");
  } catch (error) {
    if (generation !== operationGeneration) return;
    showToast(error.message || "AI summary failed.");
  } finally {
    if (activeRemoteController === controller) activeRemoteController = null;
    if (generation === operationGeneration) {
      button.disabled = false;
      $("#aiButtonLabel").textContent = "Improve with AI";
    }
  }
}

async function translateSummary() {
  const target = $("#languageSelect").value;
  const output = $("#translationOutput");
  $("#translateButton").disabled = true;
  $("#translateButton").textContent = "Working…";
  const generation = ++operationGeneration;
  const sourceURL = currentPage?.liveUrl || currentPage?.url;
  const controller = new AbortController();
  activeRemoteController?.abort();
  activeRemoteController = controller;
  try {
    let translated;
    if (target === "plain-en" && canSimplifyToPlainEnglish(currentPage.language)) {
      translated = simplifyEnglish(originalSummary);
    } else {
      if (!settings.enabled || !settings.apiKey) {
        await chrome.runtime.openOptionsPage();
        throw new Error("This source needs Optional AI for translation. Local Plain English is available only for English pages.");
      }
      translated = await translateText(
        originalSummary,
        currentPage.language || "the source language",
        target === "plain-en" ? "Plain English" : target,
        settings,
        controller.signal
      );
    }
    if (generation !== operationGeneration || sourceURL !== (currentPage?.liveUrl || currentPage?.url)) return;
    output.textContent = translated;
    output.classList.remove("hidden");
  } catch (error) {
    if (generation !== operationGeneration) return;
    showToast(error.message || "Translation failed.");
  } finally {
    if (activeRemoteController === controller) activeRemoteController = null;
    if (generation === operationGeneration) {
      $("#translateButton").disabled = false;
      $("#translateButton").textContent = "Translate";
    }
  }
}

async function handleCompare() {
  if (!savedSource) {
    savedSource = sourceSnapshot();
    await chrome.storage.local.set({ comparisonSource: savedSource });
    renderCompareState();
    showToast("Source one saved. Open a second page to compare.");
    return;
  }
  if (savedSource.url === currentPage.url) return;

  const current = sourceSnapshot();
  const comparison = compareSources(savedSource, current);
  const output = $("#comparisonOutput");
  const themes = comparison.sharedThemes.length
    ? comparison.sharedThemes.join(" · ")
    : "No strong shared themes found";
  const makeItems = (items) =>
    items.length ? `<ul>${items.map((item) => `<li>${escapeHtml(item)}</li>`).join("")}</ul>` : "<p>None extracted.</p>";

  output.innerHTML = `
    <h3>${comparison.overlapPercent}% topical overlap</h3>
    <div class="comparison-meter"><span style="width:${comparison.overlapPercent}%"></span></div>
    <p>${escapeHtml(themes)}</p>
    <h3>${escapeHtml(savedSource.hostname)}</h3>
    ${makeItems(comparison.firstPoints)}
    <p><strong>Figures:</strong> ${escapeHtml(comparison.firstNumbers.join(", ") || "none extracted")}</p>
    <h3>${escapeHtml(current.hostname)}</h3>
    ${makeItems(comparison.secondPoints)}
    <p><strong>Figures:</strong> ${escapeHtml(comparison.secondNumbers.join(", ") || "none extracted")}</p>
    <p>${escapeHtml(comparison.note)}</p>`;
  output.classList.remove("hidden");
}

function escapeHtml(value = "") {
  return value.replace(/[&<>'"]/g, (character) => ({
    "&": "&amp;",
    "<": "&lt;",
    ">": "&gt;",
    "'": "&#39;",
    '"': "&quot;"
  })[character]);
}

async function clearComparison() {
  savedSource = null;
  await chrome.storage.local.remove("comparisonSource");
  renderCompareState();
  showToast("Saved source cleared.");
}

$("#analyzeButton").addEventListener("click", analyzeActivePage);
$("#refreshButton").addEventListener("click", analyzeActivePage);
$("#retryButton").addEventListener("click", analyzeActivePage);
$("#settingsButton").addEventListener("click", () => chrome.runtime.openOptionsPage());
$("#aiButton").addEventListener("click", improveWithAi);
$("#translateButton").addEventListener("click", translateSummary);
$("#compareButton").addEventListener("click", handleCompare);
$("#clearCompareButton").addEventListener("click", clearComparison);
$("#riskToggle").addEventListener("click", () => {
  const signals = $("#riskSignals");
  signals.classList.toggle("hidden");
  $("#riskToggle").textContent = signals.classList.contains("hidden") ? "Show signals" : "Hide signals";
});

await loadSettings();

function invalidateCurrentPage(message) {
  activeRemoteController?.abort();
  activeRemoteController = null;
  operationGeneration += 1;
  currentPage = null;
  currentAnalysis = null;
  originalSummary = "";
  $("#aiButton").disabled = false;
  $("#aiButtonLabel").textContent = "Improve with AI";
  $("#translateButton").disabled = false;
  $("#translateButton").textContent = "Translate";
  showView($("#introView"));
  if (message) showToast(message);
}

chrome.tabs.onUpdated.addListener((tabId, changeInfo, tab) => {
  if (tabId !== currentTabId || !tab.active || (!changeInfo.url && changeInfo.status !== "loading")) return;
  invalidateCurrentPage("Page changed. Analyze again when you want a fresh local result.");
});

chrome.tabs.onActivated.addListener(({ tabId }) => {
  if (currentTabId === null || tabId === currentTabId) return;
  currentTabId = tabId;
  invalidateCurrentPage("Active tab changed. Click Clearframe again before analyzing this page.");
});
