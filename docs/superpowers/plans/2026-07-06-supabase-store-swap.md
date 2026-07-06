# Supabase store層差し替え 実装計画

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** localStorage専用のstore層を「ローカルファースト+アウトボックス同期」に差し替え、メール+パスワード認証と初回自動移行を追加する。

**Architecture:** localStorageを読み書きの主役(キャッシュ)として残し、Supabaseを同期先にする。保存はローカル即書き+未送信キュー(outbox)経由で非同期upsert。起動時にクラウドから全件プルしてローカルを更新(キュー内キーはローカル優先)。「ローカルにあってクラウドにないキーをキューに積む」規則で初回移行とオフライン復帰を同一コードで実現。UIから見えるstore APIは同期のまま完全互換。

**Tech Stack:** Vanilla JS(ビルドなし・index.html単一ファイル) / supabase-js v2 UMD(jsDelivr CDN) / Supabase Auth(メール+パスワード) / Postgres(schema.sql適用済み: profiles・daily・weekly、jsonb entry、RLS有効)

**Spec:** `docs/superpowers/specs/2026-07-06-supabase-store-design.md`

## Global Constraints

- 「store層の中身だけ差し替え、UIは触らない」— `getDaily`/`saveDaily`/`recentDaily`/`getWeekly`/`saveWeekly`/`_r`のシグネチャと同期挙動を変えない
- コウテイちゃんの人格: あたたかい母性・タメ口。エラー文もこのトーン(責めない)
- 配色は既存CSS変数(--rose, --leaf等)のみ使用。新しい色を持ち込まない
- Project URL: `https://zfntwysyrioqxznlhxhm.supabase.co`
- Publishable key: `sb_publishable_OKH_JjMgl8814Xye_3QhwQ_q4JBxa1K`(クライアント公開可。service_roleは使用禁止)
- localStorageキー: 既存 `kotei.daily.v1` / `kotei.weekly.v1` / `kotei.promise.v1` に加え、新設 `kotei.outbox.v1` / `kotei.migrated.v1`
- sw.js の CACHE は `kotei-v4` に1回だけ上げる(今回のリリース分。Task 1で実施)
- コミットは各タスク末尾で行う。**pushはしない**(main pushは本番デプロイ)

**検証方式について:** このプロジェクトには自動テスト基盤がない(単一HTML・ビルドなし・対象はブラウザ統合層)。本計画ではTDDの代わりに、各タスク末尾で「ローカルサーバー+実Supabaseプロジェクト」による手動検証を行う。検証コマンドと期待結果を各ステップに明記する。

**ローカルサーバー起動(全タスク共通):**
```bash
python3 -m http.server 8000 --directory /Users/y/Desktop/kotei-workspace/tsumiki
```
ブラウザで http://localhost:8000 を開く。コード変更後は「ハードリロード(Cmd+Shift+R)」で確認する。

---

### Task 1: sw.js — Supabase APIのキャッシュ除外とバージョン更新

**Files:**
- Modify: `sw.js:1`(CACHE定数)、`sw.js:15-17`(fetchハンドラ冒頭)

**Interfaces:**
- Produces: `*.supabase.co` へのリクエストはService Workerが関与しない(常に素のネットワーク)。以降のタスクのAPI通信が古いキャッシュを返さない前提を作る。

- [ ] **Step 1: fetchハンドラにsupabase.co素通しを追加し、CACHEをv4へ**

`sw.js` 1行目を変更:

```js
const CACHE = 'kotei-v4';
```

fetchハンドラの冒頭(`if (e.request.method !== 'GET') return;` の直後)に追加:

```js
self.addEventListener('fetch', e => {
  if (e.request.method !== 'GET') return;
  // Supabase(API/認証)はキャッシュしない。cache-firstに乗ると古いデータが返り続ける
  if (new URL(e.request.url).hostname.endsWith('.supabase.co')) return;
  const isHTML = e.request.mode === 'navigate' || (e.request.headers.get('accept')||'').includes('text/html');
```

- [ ] **Step 2: 動作確認**

ローカルサーバーで http://localhost:8000 を開き、DevTools → Application → Service Workers で新しいSWが activated になること(必要なら "Update" を押す)。Application → Cache Storage に `kotei-v4` だけが残ること(古い `kotei-v3` は消える)。

- [ ] **Step 3: コミット**

```bash
git add sw.js
git commit -m "sw: Supabase APIをキャッシュ対象から除外、CACHEをkotei-v4へ"
```

---

### Task 2: 認証基盤 — supabase-js読み込み・ログイン画面・起動分岐

**Files:**
- Modify: `index.html`
  - `<head>`のCSS(セレクタ拡張+新規クラス)
  - `<body>`タグと`.app`内(view-auth追加)
  - `<script>`冒頭(定数+クライアント)
  - スクリプト末尾の起動処理(renderDaily直呼びを認証分岐へ)

**Interfaces:**
- Consumes: 既存の `mountFaces()` / `esc()` / `switchView(view)` / CSSクラス(`speech`/`deck`/`slide`/`field-label`/`btn`/`deck-nav`)
- Produces:
  - `const sb` — supabase-jsクライアント(グローバル)。以降の全タスクが使う
  - `async function enterApp()` — 認証済みでアプリ本体へ入る(Task 4がbootSync呼び出しを足す)
  - `function renderAuth(notice?: string)` — ログイン/新規登録画面を描画
  - body class `noauth` — 未認証時にナビと通常viewを隠す

- [ ] **Step 1: Supabaseダッシュボードの設定(手動・ブラウザ)**

1. Authentication → Sign In / Providers → Email → **Confirm email をOFF**(開発中のみ。**リリース前にONへ戻す** — Day 13-14品質日のパスワードリセット実装と同時に)
2. Authentication → URL Configuration → Site URL に `https://yvk26yvk-dot.github.io/tsumiki/` を設定、Redirect URLs に `http://localhost:8000` を追加

- [ ] **Step 2: CDNスクリプトと定数・クライアント初期化を追加**

`index.html` の `</nav>` の直後、既存 `<script>` の前に:

```html
<script src="https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2/dist/umd/supabase.min.js"></script>
```

既存 `<script>` の先頭(`const store = {` の前)に:

```js
const SUPABASE_URL='https://zfntwysyrioqxznlhxhm.supabase.co';
const SUPABASE_KEY='sb_publishable_OKH_JjMgl8814Xye_3QhwQ_q4JBxa1K';
const sb=window.supabase.createClient(SUPABASE_URL,SUPABASE_KEY);
```

- [ ] **Step 3: HTMLとCSSを追加**

`<body>` → `<body class="noauth">` に変更。

`.app` 内、`<section id="view-record" ...>` の直後に:

```html
<section id="view-auth" class="view"></section>
```

CSSの `textarea,input[type=text]` セレクタ2箇所(定義とfocus)を拡張:

```css
textarea,input[type=text],input[type=email],input[type=password]{ /* 既存の定義そのまま */ }
textarea:focus,input[type=text]:focus,input[type=email]:focus,input[type=password]:focus{border-color:var(--rose);}
```

`</style>` の前に新規クラスを追加:

```css
body.noauth nav{display:none;}
body.noauth .view:not(#view-auth){display:none!important;}
.linklike{background:none;border:none;font-family:inherit;font-size:13px;color:var(--ink-faint);text-decoration:underline;cursor:pointer;padding:2px;}
.toast{position:fixed;left:50%;bottom:90px;transform:translate(-50%,16px);background:var(--ink);color:#fff;font-size:13.5px;line-height:1.5;padding:11px 18px;border-radius:999px;opacity:0;transition:all .35s;z-index:20;max-width:88%;text-align:center;}
.toast.show{opacity:.95;transform:translate(-50%,0);}
```

(`.toast` はTask 4の移行報告で使う。ここでまとめて入れる)

- [ ] **Step 4: 認証画面とフローを実装**

スクリプト末尾の起動処理の直前に追加:

```js
/* ===== 認証 ===== */
let authMode='login';
function renderAuth(notice){
  document.body.classList.add('noauth');
  document.querySelectorAll('.view').forEach(s=>s.classList.remove('active'));
  const v=document.getElementById('view-auth');
  v.classList.add('active');
  const isUp=authMode==='signup';
  v.innerHTML='<div class="speech"><div class="row"><span class="kotei" data-kotei></span><div class="msg"><div class="name">コウテイちゃん</div>'
    +(isUp?'はじめまして。あなたの記録、わたしが大事に預かるね。':'おかえり。あなたの記録、ここで待ってるよ。')
    +'</div></div></div>'
    +'<div class="deck" style="min-height:auto"><div class="slide">'
    +(notice?'<p class="sub" style="color:var(--rose-deep);margin:0 0 14px">'+esc(notice)+'</p>':'')
    +'<div class="field-label">メールアドレス</div><input type="email" id="auth-email" autocomplete="email">'
    +'<div class="field-label" style="margin-top:12px">パスワード</div><input type="password" id="auth-pw" autocomplete="'+(isUp?'new-password':'current-password')+'">'
    +'</div><div class="deck-nav"><button class="btn primary" id="auth-go">'+(isUp?'はじめる':'ログイン')+'</button></div>'
    +'<p style="text-align:center;margin:14px 0 0"><button class="linklike" id="auth-toggle">'+(isUp?'アカウントがある人はこちら':'はじめての人はこちら')+'</button></p></div>';
  mountFaces();
  document.getElementById('auth-toggle').onclick=()=>{authMode=isUp?'login':'signup';renderAuth();};
  document.getElementById('auth-go').onclick=doAuth;
  document.getElementById('auth-pw').onkeydown=e=>{if(e.key==='Enter')doAuth();};
}
function authErrMsg(err){
  const m=(err&&err.message)||'';
  if(m.includes('Invalid login credentials'))return 'メールかパスワードが違うみたい。もう一度みてくれる?';
  if(m.includes('already registered'))return 'そのメールはもう登録されてるよ。ログインしてみてね。';
  if(m.includes('at least 6'))return 'パスワードは6文字以上にしてね。';
  if(m.includes('valid email'))return 'メールアドレスの形が違うみたい。';
  return 'うまくいかなかったみたい。すこし待ってもう一度ためしてみてね。('+m+')';
}
async function doAuth(){
  const email=document.getElementById('auth-email').value.trim();
  const pw=document.getElementById('auth-pw').value;
  if(!email||!pw){renderAuth('メールとパスワード、両方入れてね。');document.getElementById('auth-email').value=email;return;}
  const btn=document.getElementById('auth-go');btn.disabled=true;btn.textContent='ちょっと待ってね…';
  const res=authMode==='signup'
    ?await sb.auth.signUp({email,password:pw})
    :await sb.auth.signInWithPassword({email,password:pw});
  if(res.error){renderAuth(authErrMsg(res.error));document.getElementById('auth-email').value=email;return;}
  if(authMode==='signup'&&!res.data.session){
    authMode='login';
    renderAuth('確認メールを送ったよ。メールの中のリンクを押してから、ここでログインしてね。');
    document.getElementById('auth-email').value=email;
    return;
  }
  enterApp();
}
async function enterApp(){
  document.body.classList.remove('noauth');
  switchView('daily');
}
```

- [ ] **Step 5: 起動処理を認証分岐に差し替え**

末尾の

```js
mountFaces();
renderDaily();
```

を次に置き換え(`nav button` のonclick設定行と serviceWorker 登録行はそのまま):

```js
mountFaces();
(async()=>{
  const {data:{session}}=await sb.auth.getSession();
  if(session){enterApp();}else{renderAuth();}
})();
```

- [ ] **Step 6: 動作確認**

ハードリロードして:
1. 未ログイン → ログイン画面が出る。ナビ(下タブ)が隠れている
2. 「はじめての人はこちら」→ 新規登録。メール `yvk26.yvk@gmail.com` + パスワードで「はじめる」→ そのままアプリ本体(きょうのスライド)に入る
3. Supabase Table Editor → `profiles` に1行できている(トリガー確認)
4. リロード → ログイン画面を経由せず直接アプリに入る(セッション永続)
5. わざと違うパスワードでログイン → 「メールかパスワードが違うみたい。」が出る

- [ ] **Step 7: コミット**

```bash
git add index.html
git commit -m "auth: メール+パスワード認証とログイン画面を追加、起動を認証分岐に"
```

---

### Task 3: store層 — アウトボックスとバックグラウンド同期

**Files:**
- Modify: `index.html` の `const store = {...}`(139-148行相当)、`setPromiseVal`、スクリプト末尾(onlineリスナー)

**Interfaces:**
- Consumes: `sb`(Task 2)
- Produces:
  - `store.OKEY = 'kotei.outbox.v1'` — 未送信キュー。形式は `{"daily|2026-07-06":1, "weekly|W2026-06-29":1, "profile|promise":1}`
  - `store._enq(t,k)` — キューに積む(flushはしない)。Task 4のbootSyncが使う
  - `store.flush()` — キューを全送信(async・多重起動ガード付き)。Task 4・5が使う
  - `setPromiseLocal(v)` — localStorageのみ更新(同期なし)。Task 4のプルが使う

- [ ] **Step 1: storeオブジェクトを差し替え**

既存の `const store = {...}` を丸ごと次に置き換え(`getDaily`/`recentDaily`/`getWeekly`/`_r`/`_w` は無変更のまま含む):

```js
const store = {
  DKEY:'kotei.daily.v1', WKEY:'kotei.weekly.v1', OKEY:'kotei.outbox.v1',
  _r(k){ try{return JSON.parse(localStorage.getItem(k))||{};}catch(e){return {};} },
  _w(k,o){ try{localStorage.setItem(k,JSON.stringify(o));return true;}catch(e){return false;} },
  getDaily(d){ return this._r(this.DKEY)[d]||null; },
  saveDaily(d,e){ const a=this._r(this.DKEY); a[d]={...e,savedAt:new Date().toISOString()}; const ok=this._w(this.DKEY,a); this._enq('daily',d); this.flush(); return ok; },
  recentDaily(n){ const o=[]; for(let i=n-1;i>=0;i--){const dt=new Date();dt.setDate(dt.getDate()-i);const k=key(dt);o.push({key:k,date:dt,entry:this._r(this.DKEY)[k]||null});} return o; },
  getWeekly(w){ return this._r(this.WKEY)[w]||null; },
  saveWeekly(w,e){ const a=this._r(this.WKEY); a[w]={...e,savedAt:new Date().toISOString()}; const ok=this._w(this.WKEY,a); this._enq('weekly',w); this.flush(); return ok; },

  /* --- ここからSupabase同期。UIから見えるAPIは上と同じ・同期のまま --- */
  _enq(t,k){ const q=this._r(this.OKEY); q[t+'|'+k]=1; this._w(this.OKEY,q); },
  _flushing:false,
  async flush(){
    if(this._flushing) return; this._flushing=true;
    try{
      const {data:{session}}=await sb.auth.getSession();
      if(!session) return;
      const uid=session.user.id, failed=new Set();
      /* 毎回キューを読み直す: 送信中に新しい保存が入っても取りこぼさない */
      while(true){
        const q=this._r(this.OKEY);
        const id=Object.keys(q).find(x=>!failed.has(x));
        if(!id) break;
        const sep=id.indexOf('|'), t=id.slice(0,sep), k=id.slice(sep+1);
        let error=null;
        if(t==='daily'){ const e=this._r(this.DKEY)[k]; if(e){({error}=await sb.from('daily').upsert({user_id:uid,date_key:k,entry:e,saved_at:e.savedAt})); } }
        else if(t==='weekly'){ const e=this._r(this.WKEY)[k]; if(e){({error}=await sb.from('weekly').upsert({user_id:uid,week_key:k,entry:e,saved_at:e.savedAt})); } }
        else if(t==='profile'){ ({error}=await sb.from('profiles').upsert({id:uid,promise:getPromise(),updated_at:new Date().toISOString()})); }
        if(error){ failed.add(id); continue; }  /* キューに残して次の機会に再送 */
        const cur=this._r(this.OKEY); delete cur[id]; this._w(this.OKEY,cur);
      }
    }catch(e){ /* オフライン等。キューに残っているので次のflushで再送される */ }
    finally{ this._flushing=false; }
  }
};
```

- [ ] **Step 2: 約束の同期を追加**

既存の `setPromiseVal` を次の2関数に置き換え:

```js
function setPromiseLocal(v){try{localStorage.setItem(PKEY,v);}catch(e){}}
function setPromiseVal(v){setPromiseLocal(v);store._enq('profile','promise');store.flush();}
```

- [ ] **Step 3: オンライン復帰時の再送を追加**

スクリプト末尾(serviceWorker登録行の手前)に:

```js
window.addEventListener('online',()=>store.flush());
```

- [ ] **Step 4: 動作確認**

1. ログイン済みで日次チェックを保存 → Table Editor の `daily` に行が現れ、`entry` に q1〜q6 が入っている。DevTools → Application → Local Storage の `kotei.outbox.v1` が `{}` に戻っている
2. 週次チェックを保存 → `weekly` に行が現れる(`week_key` は `W2026-06-29` 形式)
3. 約束を変更して保存 → `profiles.promise` が更新される
4. DevTools → Network → Offline にして日次を書き直し保存 → いつも通り完了画面が出る(ローカル即保存)。`kotei.outbox.v1` にキーが残る
5. Offline解除 →(onlineイベントで)数秒内に `daily` の該当行が更新され、outboxが空になる

- [ ] **Step 5: コミット**

```bash
git add index.html
git commit -m "store: アウトボックス方式でSupabase同期を追加(ローカル即保存+裏で再送)"
```

---

### Task 4: bootSync — 起動時プル・マージ・自動移行

**Files:**
- Modify: `index.html`(`enterApp` の更新、`bootSync`/`toast` の新設)

**Interfaces:**
- Consumes: `sb` / `store._enq` / `store.flush` / `store._r` / `setPromiseLocal` / `getPromise` / `.toast` CSS(Task 2)
- Produces: `async function bootSync(): boolean` — 変更があったらtrue。`function toast(msg)` — 一時通知。

- [ ] **Step 1: bootSyncとtoastを実装**

`enterApp` の直前に追加:

```js
function toast(msg){
  const t=document.createElement('div');t.className='toast';t.textContent=msg;
  document.body.appendChild(t);
  requestAnimationFrame(()=>t.classList.add('show'));
  setTimeout(()=>{t.classList.remove('show');setTimeout(()=>t.remove(),400);},4500);
}
/* 起動時同期: クラウド→ローカルにプル。未送信キーはローカル優先。
   ローカルだけにあるキーはキューへ(初回移行もオフライン復帰もこの1規則) */
async function bootSync(){
  const {data:{session}}=await sb.auth.getSession();
  if(!session) return false;
  const uid=session.user.id;
  let changed=false, toMigrate=0;
  try{
    const [dRes,wRes,pRes]=await Promise.all([
      sb.from('daily').select('date_key,entry'),
      sb.from('weekly').select('week_key,entry'),
      sb.from('profiles').select('promise').eq('id',uid).maybeSingle()
    ]);
    const q=store._r(store.OKEY);
    const merge=(res,storageKey,keyCol,type)=>{
      if(res.error) return;
      const local=store._r(storageKey), cloud={};
      (res.data||[]).forEach(r=>{cloud[r[keyCol]]=r.entry;});
      Object.keys(cloud).forEach(k=>{
        if(!q[type+'|'+k] && JSON.stringify(local[k])!==JSON.stringify(cloud[k])){local[k]=cloud[k];changed=true;}
      });
      Object.keys(local).forEach(k=>{
        if(!cloud[k] && !q[type+'|'+k]){store._enq(type,k);toMigrate++;}
      });
      store._w(storageKey,local);
    };
    merge(dRes,store.DKEY,'date_key','daily');
    merge(wRes,store.WKEY,'week_key','weekly');
    if(!pRes.error && !q['profile|promise']){
      const cp=(pRes.data&&pRes.data.promise)||'';
      if(cp && cp!==getPromise()){setPromiseLocal(cp);changed=true;}
      else if(!cp && getPromise()){store._enq('profile','promise');toMigrate++;}
    }
    if(toMigrate>0){
      await store.flush();
      if(!localStorage.getItem('kotei.migrated.v1') && Object.keys(store._r(store.OKEY)).length===0){
        localStorage.setItem('kotei.migrated.v1','1');
        toast('これまでの記録、クラウドでちゃんと預かったよ');
      }
    } else {
      store.flush();
    }
  }catch(e){ /* オフライン起動: ローカルキャッシュのまま使える */ }
  return changed;
}
```

- [ ] **Step 2: enterAppにbootSyncを組み込む**

`enterApp` を次に置き換え:

```js
async function enterApp(){
  document.body.classList.remove('noauth');
  switchView('daily');            /* まずローカルキャッシュで即表示 */
  const changed=await bootSync(); /* 裏でプル */
  const cur=document.querySelector('.view.active');
  /* プルで変わったときだけ再描画。入力途中(スライド操作中)は邪魔しない */
  if(changed && cur && cur.id==='view-daily' && Object.keys(dstate).length===0) renderDaily();
}
```

- [ ] **Step 3: 動作確認**

1. **復元**: DevTools → Application → Local Storage で `kotei.daily.v1` 等を全削除(セッションの `sb-` キーは残す)→ リロード → クラウドから記録が復元され、きろくページに過去分が見える
2. **移行**: `kotei.outbox.v1` と `kotei.migrated.v1` を削除し、`kotei.daily.v1` に手でダミー日付を足す(コンソールで
   `const a=JSON.parse(localStorage.getItem('kotei.daily.v1'));a['2026-07-01']={q4_note:'移行テスト',savedAt:new Date().toISOString()};localStorage.setItem('kotei.daily.v1',JSON.stringify(a));`
   )→ リロード → トースト「これまでの記録、クラウドでちゃんと預かったよ」が出て、Table Editorの `daily` に `2026-07-01` の行が現れる
3. **オフライン起動**: Network → Offline のままリロード → ログイン画面にならず、ローカルの記録で普通に使える

- [ ] **Step 4: コミット**

```bash
git add index.html
git commit -m "sync: 起動時プルとローカル→クラウド自動移行(bootSync)を追加"
```

---

### Task 5: ログアウト導線

**Files:**
- Modify: `index.html` の `renderRecord()`(きろくページ末尾にリンク追加、空状態にも)

**Interfaces:**
- Consumes: `sb.auth.signOut()` / `store._r(store.OKEY)` / `.linklike` CSS(Task 2)
- Produces: きろくページ最下部の「ログアウト」リンク

- [ ] **Step 1: renderRecordにログアウトを追加**

`renderRecord()` 内で、ログアウトHTMLを両方の描画パスに入れる。関数冒頭付近に:

```js
const logoutHtml='<div style="text-align:center;margin:30px 0 6px"><button class="linklike" id="logout">ログアウト</button></div>';
```

早期return側(記録ゼロの空状態)を:

```js
if(dates.length===0 && Object.keys(weeks).length===0){
  html+='<div class="empty"><span class="kotei" data-kotei="care"></span>まだ記録がないよ。<br>きょうのタブから、はじめてみよう。</div>'+logoutHtml;
  v.innerHTML=html; mountFaces(); wireLogout(); return;
}
```

通常パスの末尾 `v.innerHTML=html; mountFaces();` の前に `html+=logoutHtml;` を追加し、`mountFaces();` の後に `wireLogout();` を呼ぶ。

関数の外に:

```js
function wireLogout(){
  const lo=document.getElementById('logout');
  if(!lo) return;
  lo.onclick=async()=>{
    const pending=Object.keys(store._r(store.OKEY)).length;
    if(pending>0 && !confirm('まだクラウドに送れていない記録が'+pending+'件あるよ。ログアウトすると、この端末からは消えちゃう。それでもログアウトする?')) return;
    if(pending===0 && !confirm('ログアウトする? 記録はクラウドにちゃんと残ってるから、安心してね。')) return;
    await sb.auth.signOut();
    ['kotei.daily.v1','kotei.weekly.v1','kotei.promise.v1','kotei.outbox.v1','kotei.migrated.v1'].forEach(k=>localStorage.removeItem(k));
    location.reload();
  };
}
```

- [ ] **Step 2: 動作確認**

1. きろくページ最下部に「ログアウト」が出る(記録あり・なし両方の状態で)
2. 押す → 確認ダイアログ → OK → ログイン画面に戻り、Local Storageの `kotei.*` が消えている
3. 再ログイン → クラウドから全記録が復元される(Task 4のプル)

- [ ] **Step 3: コミット**

```bash
git add index.html
git commit -m "auth: きろくページにログアウト導線を追加(未送信データは警告)"
```

---

### Task 6: 総合検証(RLS含む・スペックの完了条件6項目)

**Files:** 変更なし(検証のみ)。問題が見つかった場合のみ修正+コミット。

- [ ] **Step 1: スペックの検証手順を通しで実行**

1. 新規登録→ログインできる(Task 2で確認済みだが通しで再確認)
2. 日次保存 → Table Editorに行が現れる
3. リロード → 記録が復元される
4. DevToolsオフライン → 保存できる → オンライン復帰で自動同期
5. localStorage全消去+再ログイン → クラウドから全件復元
6. **RLS確認**: 2つ目のテストアカウント(例: `yvk26.yvk+test@gmail.com`)で新規登録・ログインし、(a)きろくページが空であること、(b)コンソールで `await sb.from('daily').select('*')` を実行して**自分の行だけ**(この時点では0件)が返ることを確認

- [ ] **Step 2: SWキャッシュの最終確認**

DevTools → Network で supabase.co へのリクエストの Size 列が `(ServiceWorker)` になっていないこと(=素のネットワークで飛んでいること)。

- [ ] **Step 3: テストアカウントの掃除**

Supabase Dashboard → Authentication → Users で `+test` アカウントを削除 → Table Editorで該当ユーザーの行がcascade削除されていることを確認(アカウント削除機能の土台の実証にもなる)。

- [ ] **Step 4: 完了報告**

全項目の結果(成功/失敗と証拠)をユーザーに報告。**pushはユーザーの指示を待つ**(main pushは本番デプロイ=実データの自動移行が走るため)。

---

## 備考

- **本番反映時の注意**: mainへpushすると1〜2分でGitHub Pagesに反映され、本番PWAで次回開いたときにログイン画面になる。ログイン後、実記録の自動移行が走る。push前にこの計画の全検証が通っていること。
- **リリース前TODO(このプランのスコープ外だが忘れないこと)**: Confirm emailをONに戻す / パスワードリセット導線(Day 13-14品質日・リリース要件) / アカウント削除機能(次タスク)
- **既知の制限**: bootSyncの全件プルはSupabaseの1リクエスト上限(既定1000行)まで。日次1000件=約3年分なので当面問題ないが、超える前にページング(`.range()`ループ)に変える。
