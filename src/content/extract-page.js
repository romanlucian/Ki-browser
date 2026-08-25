export function extractPage() {
  const clean = (value = "") => value.replace(/\s+/g, " ").trim();
  const meta = (selector) => document.querySelector(selector)?.content?.trim() || "";

  const focusedCandidates = [
    document.querySelector("article"),
    document.querySelector("main"),
    document.querySelector('[role="main"]')
  ].filter((node) => (node?.innerText?.trim().length || 0) >= 400);

  const root = focusedCandidates[0] || document.body;

  const excludedSelector = [
    "script", "style", "noscript", "svg", "canvas", "nav", "footer", "header", "aside",
    "form", "dialog", "button", "input", "select", "textarea", "video", "audio", "iframe",
    "[hidden]", "[aria-hidden='true']", "[aria-modal='true']", "[role='button']",
    "[role='toolbar']", "[role='menu']", "[role='navigation']", "[role='dialog']",
    "[role='alertdialog']", "[class*='jwplayer']", "[class*='jw-']", "[class*='vjs-']",
    "[class*='plyr__']", "[class*='video-player']", "[class*='videoplayer']",
    "[class*='media-player']", "[class*='mediaplayer']", "[class*='player-control']",
    "[class*='cookie']", "[id*='cookie']", "[class*='consent']", "[id*='consent']"
  ].join(",");
  const isRendered = (node) => {
    const style = getComputedStyle(node);
    const rect = node.getBoundingClientRect();
    const viewportWidth = document.documentElement.clientWidth || window.innerWidth;
    return style.display !== "none" && style.visibility !== "hidden" && Number(style.opacity || 1) > 0 &&
      rect.width > 0 && rect.height > 0 && rect.right > 0 && rect.left < viewportWidth;
  };

  const clone = root.cloneNode(true);
  clone.querySelectorAll(excludedSelector).forEach((node) => node.remove());

  const shadowRoots = [];
  document.querySelectorAll("*").forEach((node) => {
    if (node.shadowRoot && (root === document.body || root.contains(node))) shadowRoots.push(node.shadowRoot);
  });
  const readingNodes = (selector) => [root, ...shadowRoots].flatMap(
    (scope) => [...scope.querySelectorAll(selector)]
  );
  const seenBlocks = new Set();
  // `tr` is here because a link aggregator lays its entries out in table rows and
  // has no paragraphs at all. Without it such a page reached the whole-document
  // fallback, which reads `innerText` from a DETACHED clone — and a detached node
  // is outside the layout tree, so the engine gives it textContent semantics with
  // no layout line breaks. The page then arrived as a single block whatever the
  // fallback did with newlines. These nodes are live, so their `innerText` breaks
  // lines where the layout does.
  const paragraphs = readingNodes("h1, h2, h3, p, li, blockquote, tr")
    .filter((node) => !node.closest(excludedSelector) && isRendered(node))
    // A row counts as a reading block only when nothing inside it already is, so a
    // documentation table whose cells hold paragraphs is not read twice — and `tr`
    // is in that list because sites lay tables out inside tables. Hacker News does,
    // and without it every outer row repeated the rows nested within it.
    .filter((node) => node.tagName !== "TR" || !node.querySelector("h1, h2, h3, p, li, blockquote, tr"))
    .map((node) => clean(node.innerText))
    .filter((text) => text.length >= 45 && text.length <= 1800)
    .filter((text) => {
      const key = text.toLocaleLowerCase();
      if (seenBlocks.has(key)) return false;
      seenBlocks.add(key);
      return true;
    });

  // `clean` collapses every run of whitespace, newlines included. On a page whose
  // content is not paragraphs — a link aggregator laying its entries out in table
  // rows — nothing qualifies as a reading block, this fallback runs, and the whole
  // document arrives as a single line. Structure detection needs at least twelve
  // blocks before it will judge anything, so such a page could never be recognised
  // as a listing, and its "key points" read "com)82 points by …".
  //
  // `innerText` already breaks lines where the layout does, so cleaning each line
  // on its own keeps that structure while still collapsing the spaces within it.
  const fallbackText = (clone.innerText || "")
    .split("\n")
    .map(clean)
    .filter(Boolean)
    .join("\n");
  const text = (paragraphs.length >= 2 ? paragraphs.join("\n") : fallbackText).slice(0, 48000);

  const pageUrl = new URL(location.href);
  let canonicalUrl = location.href;
  try {
    const candidate = new URL(document.querySelector('link[rel="canonical"]')?.href || location.href);
    if (/^https?:$/.test(candidate.protocol) && candidate.origin === pageUrl.origin) {
      canonicalUrl = candidate.href;
    }
  } catch {
    canonicalUrl = location.href;
  }
  const forms = [...document.forms];
  const formActions = forms.map((form) => {
    try {
      return new URL(form.action || location.href, location.href).origin;
    } catch {
      return "";
    }
  });

  const links = [...document.querySelectorAll("a[href]")]
    .slice(0, 500)
    .map((link) => {
      try {
        const url = new URL(link.href, location.href);
        return { host: url.hostname, external: url.origin !== pageUrl.origin };
      } catch {
        return null;
      }
    })
    .filter(Boolean);

  return {
    title:
      meta('meta[property="og:title"]') ||
      document.querySelector("h1")?.innerText?.trim() ||
      document.title ||
      pageUrl.hostname,
    description:
      meta('meta[name="description"]') || meta('meta[property="og:description"]'),
    byline:
      meta('meta[name="author"]') ||
      document.querySelector('[rel="author"], [itemprop="author"]')?.textContent?.trim() ||
      "",
    url: canonicalUrl,
    liveUrl: location.href,
    hostname: pageUrl.hostname,
    protocol: pageUrl.protocol,
    language: document.documentElement.lang || meta('meta[http-equiv="content-language"]') || "",
    headings: [...clone.querySelectorAll("h1, h2, h3")]
      .map((node) => clean(node.innerText))
      .filter(Boolean)
      .slice(0, 16),
    text,
    wordCount: (text.match(/[\p{Script=Han}\p{Script=Hiragana}\p{Script=Katakana}\p{Script=Hangul}]|[\p{L}\p{M}\p{N}]+/gu) || []).length,
    hasPasswordField: Boolean(document.querySelector('input[type="password"]')),
    formActions,
    externalLinkRatio: links.length
      ? links.filter((link) => link.external).length / links.length
      : 0
  };
}
