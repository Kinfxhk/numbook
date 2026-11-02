// Numbook's own service worker. Flutter's generated one unregisters itself,
// and a notepad that needs the network to open is not offline.
//
// Online, the worker deliberately does not answer anything: a response the
// worker builds itself is parsed from scratch on every open, while the same file
// from the browser's HTTP cache comes back with its compiled-code cache too
// (measured on this app: 168 ms to first frame without the worker in the path,
// ~2.1 s with it). GitHub Pages only allows max-age=600, so the worker is what
// keeps the app openable when the network is gone: offline it serves everything
// from the precache.
//
// A deploy is still live on the next open: after the first frame the page asks
// for `tn-check`, and if version.json has moved on the worker refetches the whole
// shell and asks for a single reload.
//
// The precache list must cover what a cold boot asks for: Chrome loads
// canvaskit/chromium/*, not canvaskit/*, and the app dies on the missing module
// (a real offline boot failed on exactly that file). Bump CACHE whenever
// PRECACHE changes.
const CACHE = 'numbook-v1';

// Best effort: one missing file must not fail the whole install.
const PRECACHE = [
  './',
  './index.html',
  './manifest.json',
  './version.json',
  './flutter_bootstrap.js',
  './main.dart.js',
  './canvaskit/canvaskit.js',
  './canvaskit/canvaskit.wasm',
  './canvaskit/chromium/canvaskit.js',
  './canvaskit/chromium/canvaskit.wasm',
  // Flutter refuses to start without its asset manifest, so this one is not
  // optional even though a missing file is otherwise ignored.
  './assets/AssetManifest.bin.json',
  './assets/AssetManifest.json',
  './assets/FontManifest.json',
  // The UI's own faces: a boot without them renders boxes.
  './assets/fonts/MaterialIcons-Regular.otf',
  './assets/fonts/fallback/Roboto-Regular.ttf',
  './assets/packages/cupertino_icons/assets/CupertinoIcons.ttf',
  './icons/Icon-192.png',
];

const refresh = (url) => new Request(url, { cache: 'reload' });

self.addEventListener('install', (event) => {
  event.waitUntil(
    (async () => {
      const cache = await caches.open(CACHE);
      await Promise.all(PRECACHE.map((url) => cache.add(refresh(url)).catch(() => {})));
      await self.skipWaiting();
    })()
  );
});

self.addEventListener('activate', (event) => {
  event.waitUntil(
    (async () => {
      const keys = await caches.keys();
      await Promise.all(
        keys.filter((k) => k !== CACHE).map((k) => caches.delete(k))
      );
      await self.clients.claim();
    })()
  );
});

// Has the deploy changed under us? If so refill the whole shell, then let the
// page reload once — after this the cache and the site agree, so no loop.
self.addEventListener('message', (event) => {
  if (event.data !== 'tn-check') return;
  event.waitUntil(
    (async () => {
      try {
        const res = await fetch('./version.json?t=' + Date.now(), { cache: 'no-store' });
        if (!res.ok) return;
        const fresh = await res.clone().json();
        const hit = await caches.match('./version.json');
        const held = hit ? await hit.json() : null;
        if (held && held.version === fresh.version && held.build_number === fresh.build_number) return;

        const cache = await caches.open(CACHE);
        await cache.put('./version.json', res);
        await Promise.all(
          PRECACHE.filter((u) => !u.endsWith('version.json'))
            .map((u) => cache.add(refresh(u)).catch(() => {}))
        );
        const clients = await self.clients.matchAll();
        clients.forEach((client) => client.postMessage('tn-reload'));
      } catch (_) {
        // Offline, or a reload in flight: try again on the next open.
      }
    })()
  );
});

self.addEventListener('fetch', (event) => {
  const request = event.request;
  if (request.method !== 'GET') return;

  const url = new URL(request.url);
  // Exchange rates are the one thing that may leave the app; never cache them.
  if (url.origin !== self.location.origin) return;
  // Online the browser's own caches are faster than this worker; see the top.
  if (navigator.onLine) return;

  event.respondWith(
    (async () => {
      const hit = await caches.match(request);
      if (hit) return hit;
      // Only a navigation may fall back to the shell document; a missing script
      // must fail as itself.
      if (request.mode === 'navigate') {
        const shell = await caches.match('./index.html');
        if (shell) return shell;
      }
      return fetch(request);
    })()
  );
});
