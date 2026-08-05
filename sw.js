const CACHE = 'portal-lc-v1';
const SHELL = [
  'app.html',
  'confirmacao.html',
  'r.html',
  'manifest.json',
];

self.addEventListener('install', e => {
  e.waitUntil(
    caches.open(CACHE).then(c => c.addAll(SHELL)).then(() => self.skipWaiting())
  );
});

self.addEventListener('activate', e => {
  e.waitUntil(
    caches.keys()
      .then(keys => Promise.all(keys.filter(k => k !== CACHE).map(k => caches.delete(k))))
      .then(() => self.clients.claim())
  );
});

self.addEventListener('fetch', e => {
  // Não intercepta chamadas ao Supabase ou CDNs externos
  if(!e.request.url.startsWith(self.location.origin)) return;
  // Estratégia: Network First com fallback para cache
  e.respondWith(
    fetch(e.request)
      .then(res => {
        if(res.ok){
          const clone = res.clone();
          caches.open(CACHE).then(c => c.put(e.request, clone));
        }
        return res;
      })
      .catch(() => caches.match(e.request).then(cached => cached || caches.match('app.html')))
  );
});
