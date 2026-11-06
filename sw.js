// Ferrum: la app abre sin conexión. La página se pide primero a la red para recibir actualizaciones.
const CACHE = 'ferrum-v47';
const ARCHIVOS = ['./', './index.html', './manifest.webmanifest', './ferrum-f-180.png', './ferrum-f-192.png', './ferrum-f-512.png'];

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
  e.respondWith(fetch(req.url, {cache: 'no-cache'}).then(res => {
    const copia = res.clone(); caches.open(CACHE).then(c => c.put(req, copia)); return res;
  }).catch(() => caches.match(req).then(hit => hit || caches.match('./index.html'))));
});

self.addEventListener('push', e => {
  const d = e.data ? e.data.json() : {};
  e.waitUntil(self.registration.showNotification(d.titulo || 'Ferrum', {body: d.cuerpo || '', icon: './ferrum-f-192.png', badge: './ferrum-f-192.png'}));
});

self.addEventListener('notificationclick', e => {
  e.notification.close();
  e.waitUntil(self.clients.matchAll({type: 'window'}).then(cs => cs[0] ? cs[0].focus() : self.clients.openWindow('./')));
});
