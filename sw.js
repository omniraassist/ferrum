// Ferrum: la app abre sin conexión. La página se pide primero a la red para recibir actualizaciones.
const CACHE = 'ferrum-v11';
const ARCHIVOS = ['./', './index.html', './manifest.webmanifest', './ferrum-trazo-180.png', './ferrum-trazo-192.png', './ferrum-trazo-512.png'];

self.addEventListener('install', e => {
  e.waitUntil(caches.open(CACHE).then(c => c.addAll(ARCHIVOS)).then(() => self.skipWaiting()));
});

self.addEventListener('activate', e => {
  e.waitUntil(caches.keys()
    .then(ks => Promise.all(ks.filter(k => k !== CACHE).map(k => caches.delete(k))))
    .then(() => self.clients.claim()));
});

self.addEventListener('fetch', e => {
  const req = e.request;
  if (req.method !== 'GET') return;
  const url = new URL(req.url);
  if (url.hostname.endsWith('fonts.googleapis.com') || url.hostname.endsWith('fonts.gstatic.com')) {
    e.respondWith(caches.match(req).then(hit => hit || fetch(req).then(res => {
      const copia = res.clone(); caches.open(CACHE).then(c => c.put(req, copia)); return res;
    })));
    return;
  }
  if (url.origin !== location.origin) return;
  e.respondWith(fetch(req).then(res => {
    const copia = res.clone(); caches.open(CACHE).then(c => c.put(req, copia)); return res;
  }).catch(() => caches.match(req).then(hit => hit || caches.match('./index.html'))));
});
