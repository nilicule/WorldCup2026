// Freshness-first service worker for the World Cup 2026 tracker.
// Online: always serve the latest HTML and scores (network-first), so pushed
// score updates and redeploys appear immediately. Offline: last-cached copies.
const CACHE_VERSION = "wc2026-pwa-v1";
const SCORES_URL = "https://raw.githubusercontent.com/nilicule/WorldCup2026/refs/heads/main/worldcup2026-results.json";
const SHELL = [
  "./", "./index.html", "./manifest.webmanifest", "./favicon.svg",
  "./icon-192.png", "./icon-512.png", "./icon-maskable-512.png", "./icon-180.png"
];

self.addEventListener("install", (event) => {
  event.waitUntil(
    caches.open(CACHE_VERSION).then((c) => c.addAll(SHELL)).then(() => self.skipWaiting())
  );
});

self.addEventListener("activate", (event) => {
  event.waitUntil(
    caches.keys()
      .then((keys) => Promise.all(keys.filter((k) => k !== CACHE_VERSION).map((k) => caches.delete(k))))
      .then(() => self.clients.claim())
  );
});

async function networkFirst(req) {
  const cache = await caches.open(CACHE_VERSION);
  try {
    const res = await fetch(req);
    if (res && res.ok) cache.put(req, res.clone());
    return res;
  } catch (err) {
    const cached = await cache.match(req, { ignoreSearch: true });
    if (cached) return cached;
    throw err;
  }
}

async function cacheFirst(req) {
  const cache = await caches.open(CACHE_VERSION);
  const cached = await cache.match(req);
  if (cached) return cached;
  const res = await fetch(req);
  if (res && res.ok) cache.put(req, res.clone());
  return res;
}

self.addEventListener("fetch", (event) => {
  const req = event.request;
  if (req.method !== "GET") return;
  const url = new URL(req.url);
  if (url.protocol !== "http:" && url.protocol !== "https:") return;

  // 1. Scores feed — network-first (fresh online, cached offline).
  if (req.url === SCORES_URL || url.pathname.endsWith("worldcup2026-results.json")) {
    event.respondWith(networkFirst(req));
    return;
  }
  // 2. Navigations / the HTML — network-first, fall back to cached shell.
  if (req.mode === "navigate" ||
      (url.origin === self.location.origin &&
       (url.pathname.endsWith("/") || url.pathname.endsWith("/index.html")))) {
    event.respondWith(
      networkFirst(req).catch(() =>
        caches.match("./index.html", { ignoreSearch: true })
          .then((r) => r || caches.match("./", { ignoreSearch: true }))
      )
    );
    return;
  }
  // 3. Same-origin static assets — cache-first.
  if (url.origin === self.location.origin) {
    event.respondWith(cacheFirst(req));
    return;
  }
  // 4. Everything else (e.g. fonts) — passthrough.
});
