// Network only: every page is signed-in admin data, so nothing is cached
// that could outlive the session. The worker exists so the app is
// installable and a dropped connection shows a message, not a browser error.
const OFFLINE_PAGE = `<!doctype html><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>Offline</title>
<body style="font-family:system-ui;display:grid;place-items:center;min-height:100vh;margin:0;background:#f8fafc;color:#0f172a;text-align:center">
<div><h1>You're offline</h1><p>Reconnect and try again.</p></div>`

self.addEventListener("install", () => self.skipWaiting())
self.addEventListener("activate", (event) => event.waitUntil(self.clients.claim()))

self.addEventListener("fetch", (event) => {
  if (event.request.mode !== "navigate") return

  event.respondWith(
    fetch(event.request).catch(() =>
      new Response(OFFLINE_PAGE, {status: 503, headers: {"Content-Type": "text/html; charset=utf-8"}})
    )
  )
})
