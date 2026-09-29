const CACHE_NAME = "mzad-phone-v2";

const APP_SHELL = [
  "/",
  "/index.html",
  "/home.html",
  "/market.html",
  "/device.html",
  "/direct.html",
  "/favorites.html",
  "/profile.html",
  "/my-listings.html",
  "/sell.html",
  "/sell-auction.html",
  "/auctions.html",
  "/forgot.html",
  "/signup.html",
  "/manifest.json"
];

self.addEventListener("install", event => {
  event.waitUntil(
    caches.open(CACHE_NAME)
      .then(cache => cache.addAll(APP_SHELL))
      .then(() => self.skipWaiting())
  );
});

self.addEventListener("activate", event => {
  event.waitUntil(
    caches.keys()
      .then(keys =>
        Promise.all(
          keys
            .filter(key => key !== CACHE_NAME)
            .map(key => caches.delete(key))
        )
      )
      .then(() => self.clients.claim())
  );
});

self.addEventListener("fetch", event => {
  const request = event.request;

  if (request.method !== "GET") {
    return;
  }

  event.respondWith(
    fetch(request)
      .then(response => {
        if (
          response &&
          response.status === 200 &&
          response.type === "basic"
        ) {
          const copy = response.clone();

          caches.open(CACHE_NAME)
            .then(cache => {
              cache.put(request, copy);
            });
        }

        return response;
      })
      .catch(() => {
        return caches.match(request)
          .then(cached => {
            return cached || caches.match("/index.html");
          });
      })
  );
});
