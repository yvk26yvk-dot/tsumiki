const CACHE = 'kotei-v6';
const ASSETS = ['./index.html','./manifest.json','./kotei-normal.png','./kotei-care.png','./kotei-cheer.png','./kotei-body.png','./icon-192.png','./supabase.min.js'];

self.addEventListener('install', e => {
  e.waitUntil(caches.open(CACHE).then(c => c.addAll(ASSETS)).then(() => self.skipWaiting()));
});

self.addEventListener('activate', e => {
  e.waitUntil(
    caches.keys().then(keys => Promise.all(keys.filter(k => k !== CACHE).map(k => caches.delete(k))))
      .then(() => self.clients.claim())
  );
});

self.addEventListener('fetch', e => {
  if (e.request.method !== 'GET') return;
  // Supabase(API/認証)はキャッシュしない。cache-firstに乗ると古いデータが返り続ける
  if (new URL(e.request.url).hostname.endsWith('.supabase.co')) return;
  const isHTML = e.request.mode === 'navigate' || (e.request.headers.get('accept')||'').includes('text/html');
  if (isHTML) {
    // network-first: 更新がすぐ届く。オフライン時のみキャッシュ
    e.respondWith(
      fetch(e.request).then(res => {
        const copy = res.clone();
        caches.open(CACHE).then(c => c.put(e.request, copy)).catch(()=>{});
        return res;
      }).catch(() => caches.match(e.request).then(m => m || caches.match('./index.html')))
    );
    return;
  }
  e.respondWith(
    caches.match(e.request).then(cached =>
      cached || fetch(e.request).then(res => {
        const copy = res.clone();
        caches.open(CACHE).then(c => c.put(e.request, copy)).catch(() => {});
        return res;
      })
    )
  );
});
