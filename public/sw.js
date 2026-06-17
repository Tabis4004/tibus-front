const CACHE_VERSION = "tibus-static-v4";
const STATIC_ASSETS = ["/icon/tibus-mark.png", "/icon/icon-192.png", "/icon/icon-512.png"];

self.addEventListener("install", (event) => {
  event.waitUntil(
    caches
      .open(CACHE_VERSION)
      .then((cache) => cache.addAll(STATIC_ASSETS))
      .then(() => self.skipWaiting()),
  );
});

self.addEventListener("message", (event) => {
  if (event.data?.type === "SKIP_WAITING") {
    void self.skipWaiting();
  }
});

self.addEventListener("activate", (event) => {
  event.waitUntil(
    caches
      .keys()
      .then((cacheNames) =>
        Promise.all(
          cacheNames.map((cacheName) => {
            if (cacheName !== CACHE_VERSION) {
              return caches.delete(cacheName);
            }
          }),
        ),
      )
      .then(() => self.clients.claim()),
  );
});

self.addEventListener("fetch", (event) => {
  if (event.request.method !== "GET") return;

  let url;
  try {
    url = new URL(event.request.url);
  } catch {
    return;
  }

  if (url.origin !== self.location.origin) return;
  if (url.pathname.startsWith("/auth")) return;

  // Never cache the app shell or hashed bundles — stale files break SPA navigation in Chrome.
  if (
    event.request.mode === "navigate" ||
    url.pathname.startsWith("/assets/") ||
    url.pathname === "/" ||
    url.pathname.endsWith(".html") ||
    url.pathname.endsWith(".js") ||
    url.pathname.endsWith(".css")
  ) {
    return;
  }

  // Offline fallback for icons only.
  if (url.pathname.startsWith("/icon/")) {
    event.respondWith(
      fetch(event.request).catch(() => caches.match(event.request).then((r) => r ?? caches.match("/icon/icon-192.png"))),
    );
  }
});

self.addEventListener("push", (event) => {
  const data = event.data?.json() ?? {};

  event.waitUntil(
    clients.matchAll({ type: "window", includeUncontrolled: true }).then((clientList) => {
      const isAppInFocus = clientList.some((client) => client.focused);

      if (!isAppInFocus) {
        return self.registration.showNotification(data.title, data.options);
      }
    }),
  );
});

self.addEventListener("notificationclick", (event) => {
  event.notification.close();

  event.waitUntil(
    clients.matchAll({ type: "window" }).then((clientList) => {
      for (const client of clientList) {
        if ("focus" in client) return client.focus();
      }
      if (clients.openWindow) return clients.openWindow("/");
    }),
  );
});
