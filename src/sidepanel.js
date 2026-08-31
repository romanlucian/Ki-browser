import { analyzePage, assessStructure, readableText } from "./core/analyzer.js";
import { extractPage } from "./content/extract-page.js";

const $ = (selector) => document.querySelector(selector);
const views = [$("#introView"), $("#loadingView"), $("#resultsView"), $("#noticeView"), $("#errorView")];
let currentPage = null;
let currentAnalysis = null;
let currentText = "";
let structureOverridden = false;
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
  $("#textSize").textContent = `${currentText.length} CHARACTERS`;
  $("#copyExplainer").textContent = currentText
    ? "Limeghost pulled the readable text off this page, without the menus, footers and player controls."
    : "There is not enough readable text on this page to copy.";
  $("#copyButton").disabled = currentText.length === 0;
  $("#copyButtonLabel").textContent = "Copy page for AI";
  renderRisk(currentAnalysis.risk);
  showView($("#resultsView"));
}

async function copyForAi() {
  const payload = [
    `Title:  ${currentPage.title}`,
    `URL:    ${currentPage.url}`,
    "",
    currentText
  ].join("\n");
  await navigator.clipboard.writeText(payload);
  $("#copyButtonLabel").textContent = "Copied — paste it into your AI";
}
async function analyzeActivePage() {
  activeRemoteController?.abort();
  activeRemoteController = null;
  const generation = ++operationGeneration;
  setLoading("Reading the page…");
  try {
    const [tab] = await chrome.tabs.query({ active: true, currentWindow: true });
    if (!tab?.id || !/^https?:/i.test(tab.url || "")) {
      throw new Error("Open a normal web page, then click the Limeghost toolbar icon again.");
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
    structureOverridden = false;
    if (assessStructure(currentPage) === "listing") {
      showView($("#noticeView"));
      return;
    }
    finishAnalysis();
  } catch (error) {
    if (generation !== operationGeneration) return;
    showError(error.message || "The browser blocked access to this page.");
  }
}

function finishAnalysis() {
  currentAnalysis = analyzePage(currentPage);
  currentText = readableText(currentPage);
  renderAnalysis();
}

// The page was already extracted for the structure check, so trust the reader's
// judgment and summarize the same page object instead of reading it again.
function analyzeDespiteStructure() {
  if (!currentPage) return;
  structureOverridden = true;
  finishAnalysis();
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
$("#analyzeButton").addEventListener("click", analyzeActivePage);
$("#refreshButton").addEventListener("click", analyzeActivePage);
$("#retryButton").addEventListener("click", analyzeActivePage);
$("#copyButton").addEventListener("click", copyForAi);
$("#analyzeAnywayButton").addEventListener("click", analyzeDespiteStructure);
$("#riskToggle").addEventListener("click", () => {
  const signals = $("#riskSignals");
  signals.classList.toggle("hidden");
  $("#riskToggle").textContent = signals.classList.contains("hidden") ? "Show signals" : "Hide signals";
});


function invalidateCurrentPage(message) {
  activeRemoteController?.abort();
  activeRemoteController = null;
  operationGeneration += 1;
  currentPage = null;
  currentAnalysis = null;
  currentText = "";
  structureOverridden = false;
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
  invalidateCurrentPage("Active tab changed. Click Limeghost again before analyzing this page.");
});
