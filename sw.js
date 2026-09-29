const CACHE_NAME = "mzad-phone-v1";

const APP_SHELL = [
  "./",
  "./index.html",
  "./home.html",
  "./market.html",
  "./device.html",
  "./direct.html",
  "./favorites.html",
  "./profile.html",
  "./my-listings.html",
  "./sell.html",
  "./sell-auction.html",
  "./auctions.html",
  "./forgot.html",
  "./signup.html",
  "./manifest.json"
];

self.addEventListener("install", event => {
  event.waitUntil(
    caches.open(CACHE_NAME)
      .then(cache => {
        return cache.addAll(APP_SHELL);
      })
      .catch(error => {
        console.warn(
          "MZAD PHONE CACHE INSTALL ERROR:",
          error
        );
      })
  );

  self.skipWaiting();
});


self.addEventListener("activate", event => {
  event.waitUntil(
    caches.keys()
      .then(keys => {
        return Promise.all(
          keys
            .filter(key => key !== CACHE_NAME)
            .map(key => caches.delete(key))
        );
      })
  );

  self.clients.claim();
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

          const responseClone = response.clone();

          caches.open(CACHE_NAME)
            .then(cache => {
              cache.put(
                request,
                responseClone
              );
            });

        }

        return response;

      })

      .catch(() => {

        return caches.match(request)
          .then(cachedResponse => {

            if (cachedResponse) {
              return cachedResponse;
            }

            return caches.match("./index.html");

          });

      })

  );

});
