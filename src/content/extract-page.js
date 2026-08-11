export function extractPage() {
  const clean = (value = "") => value.replace(/\s+/g, " ").trim();
  const meta = (selector) => document.querySelector(selector)?.content?.trim() || "";

  const focusedCandidates = [
    document.querySelector("article"),
    document.querySelector("main"),
    document.querySelector('[role="main"]')
  ].filter((node) => (node?.innerText?.trim().length || 0) >= 400);

  const root = focusedCandidates[0] || document.body;

  const clone = root.cloneNode(true);
  clone
    .querySelectorAll(
      "script, style, noscript, svg, canvas, nav, footer, header, aside, form, dialog, [aria-hidden='true']"
    )
    .forEach((node) => node.remove());

  const paragraphs = [...clone.querySelectorAll("p, li, blockquote")]
    .map((node) => clean(node.innerText))
    .filter((text) => text.length >= 45 && text.length <= 1800);

  const fallbackText = clean(clone.innerText || "");
  const text = clean(paragraphs.length >= 3 ? paragraphs.join("\n") : fallbackText).slice(
    0,
    48000
  );

  const canonicalHref = document.querySelector('link[rel="canonical"]')?.href;
  const canonicalUrl = canonicalHref || location.href;
  const pageUrl = new URL(location.href);
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
    language: document.documentElement.lang || navigator.language || "",
    headings: [...clone.querySelectorAll("h1, h2, h3")]
      .map((node) => clean(node.innerText))
      .filter(Boolean)
      .slice(0, 16),
    text,
    wordCount: text ? text.split(/\s+/).length : 0,
    hasPasswordField: Boolean(document.querySelector('input[type="password"]')),
    formActions,
    externalLinkRatio: links.length
      ? links.filter((link) => link.external).length / links.length
      : 0
  };
}
