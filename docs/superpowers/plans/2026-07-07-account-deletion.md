# アカウント削除機能+設定画面 実装計画

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 設定画面(歯車アイコン→ログアウト/アカウント削除)を新設し、RPC関数による本人アカウントの完全削除(Apple審査要件)を実装する。あわせて前回持ち越しの軽微修正4件を直す。

**Architecture:** サーバー側は security definer の Postgres RPC `delete_user()` 1つ(`auth.uid()`本人のauth.users行を削除→cascadeで全記録が消える)。クライアントは新設の `view-settings` に配列駆動の設定項目リスト+控えめな削除リンクを置き、削除は「説明カード→confirm」の二段階。ログアウトはきろくページから設定画面へ移設。

**Tech Stack:** Vanilla JS(index.html単一ファイル・ビルドなし)/ supabase-js 2.110.0(同梱済み)/ Postgres RPC(security definer)

**Spec:** `docs/superpowers/specs/2026-07-07-account-deletion-design.md`

## Global Constraints

- コウテイちゃんの人格: あたたかい母性・タメ口・**責めない**。削除フローでも引き留めすぎない
- 配色は既存CSS変数のみ。新しい色を持ち込まない
- 設定項目は配列 `SETTINGS_ITEMS` 駆動(将来の通知設定は配列に1要素追加で済む構造)
- アカウント削除は目立たせない(`.linklike`・最下部)+二段階確認
- 歯車アイコンは**ログイン後のみ表示**(`body.noauth .header-gear{display:none}`)
- 削除はオンライン必須。RPC失敗時はローカルを一切消さない
- sw.js の CACHE は `kotei-v5` に上げる(本番は現在kotei-v4)
- コミットは各タスク末尾。**pushはしない**(main pushは本番デプロイ)
- ブランチ: `feature/account-deletion` を main から作成して作業

**検証方式:** 自動テスト基盤なし(単一HTML)。各タスクでインラインスクリプト抽出+`node --check` の構文検証を行い、ブラウザ検証は最後にユーザーがまとめて実施する。

**構文チェックコマンド(全タスク共通):**
```bash
python3 -c "import re; html=open('/Users/y/Desktop/kotei-workspace/tsumiki/index.html').read(); m=re.findall(r'<script>(.*?)</script>', html, re.S); open('/private/tmp/claude-501/-Users-y/56b9d1a3-0584-4e64-9390-82ab79c0306c/scratchpad/inline.js','w').write(m[0])" && node --check /private/tmp/claude-501/-Users-y/56b9d1a3-0584-4e64-9390-82ab79c0306c/scratchpad/inline.js
```

---

### Task 1: RPC関数のSQLファイル

**Files:**
- Create: `supabase/account-deletion.sql`

**Interfaces:**
- Produces: DB関数 `public.delete_user()`(クライアントからは `sb.rpc('delete_user')` で呼ぶ。戻り値 `{data,error}`)。実際のDB適用はユーザーがSQL Editorで実行(Task 5の検証手順に含む)。

- [ ] **Step 1: SQLファイルを作成**

`supabase/account-deletion.sql` を次の内容で新規作成:

```sql
-- =====================================================================
-- アカウント削除RPC。Supabase SQL Editor に貼り付けて Run する。
--
-- 本人のアカウントと全記録を削除する。呼べるのはログイン済みユーザーのみ。
-- auth.uid() = 本人のJWTでしか動かないため、他人を消すことは構造的に不可能。
-- schema.sql の on delete cascade により profiles/daily/weekly も同時に消える。
-- =====================================================================

create function public.delete_user()
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if auth.uid() is null then
    raise exception 'not authenticated';
  end if;
  delete from auth.users where id = auth.uid();
end;
$$;

revoke execute on function public.delete_user() from anon, public;
grant execute on function public.delete_user() to authenticated;
```

- [ ] **Step 2: コミット**

```bash
git add supabase/account-deletion.sql
git commit -m "db: アカウント削除RPC(delete_user)を追加"
```

---

### Task 2: 設定画面の骨格(歯車・view-settings・ログアウト移設)

**Files:**
- Modify: `index.html`
  - CSS: `header` ルール(28行目付近)に `position:relative` 追加、`</style>` 前に新規クラス追加
  - HTML: header内に歯車ボタン、`view-auth` の後に `view-settings` セクション
  - JS: `KOTEI_KEYS` 定数、`SETTINGS_ITEMS`/`renderSettings`/`doLogout` 新設、`switchView` に settings 分岐、歯車の配線、きろくページのログアウト撤去(`logoutHtml`・`wireLogout` 削除)

**Interfaces:**
- Consumes: 既存 `mountFaces()` / `switchView(view)` / `store.OKEY` / `store._r` / `sb.auth.signOut` / CSSクラス(`speech`/`deck-nav`/`btn`/`linklike`)
- Produces:
  - `const KOTEI_KEYS` — localStorageの全koteiキー配列(logout/削除で共用)
  - `let delMode` — 設定画面が削除確認モードかのフラグ(Task 3の `renderDeleteConfirm()` が使う)
  - `function renderSettings()` — delMode=trueなら `renderDeleteConfirm()`(Task 3で実装)に委譲
  - `async function doLogout()` — signOutは `{scope:'local'}`(軽微修正2を含む)
  - `switchView('settings')` が動く(delMode=falseにリセットして描画)
  - Task 3はrenderSettings内の `#open-delete` ボタンから起動される

- [ ] **Step 1: CSSを追加**

28行目付近の `header{padding:24px 0 4px;text-align:center;}` を:

```css
header{padding:24px 0 4px;text-align:center;position:relative;}
```

`</style>` の直前に追加:

```css
  .header-gear{position:absolute;top:28px;right:2px;background:none;border:none;cursor:pointer;color:var(--ink-faint);padding:6px;line-height:0;}
  .header-gear svg{width:21px;height:21px;}
  body.noauth .header-gear{display:none;}
  .settings-item{display:flex;justify-content:space-between;align-items:center;background:var(--card);border:1px solid var(--line);border-radius:var(--radius-sm);padding:15px 16px;margin-bottom:10px;cursor:pointer;}
  .settings-item .lbl{font-weight:600;font-size:15px;}
  .settings-item .sub{font-size:12px;color:var(--ink-soft);margin-top:2px;}
  .settings-item .chev{color:var(--ink-faint);font-size:18px;}
  .linklike:disabled{opacity:.5;cursor:default;}
```

- [ ] **Step 2: HTMLを追加**

header内(`<p class="tagline">...</p>` の直後、`</header>` の前)に:

```html
    <button id="header-gear" class="header-gear" aria-label="設定">
      <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.9" stroke-linecap="round" stroke-linejoin="round"><circle cx="12" cy="12" r="3"/><path d="M19.4 15a1.65 1.65 0 0 0 .33 1.82l.06.06a2 2 0 1 1-2.83 2.83l-.06-.06a1.65 1.65 0 0 0-1.82-.33 1.65 1.65 0 0 0-1 1.51V21a2 2 0 1 1-4 0v-.09a1.65 1.65 0 0 0-1-1.51 1.65 1.65 0 0 0-1.82.33l-.06.06a2 2 0 1 1-2.83-2.83l.06-.06a1.65 1.65 0 0 0 .33-1.82 1.65 1.65 0 0 0-1.51-1H3a2 2 0 1 1 0-4h.09a1.65 1.65 0 0 0 1.51-1 1.65 1.65 0 0 0-.33-1.82l-.06-.06a2 2 0 1 1 2.83-2.83l.06.06a1.65 1.65 0 0 0 1.82.33h.01a1.65 1.65 0 0 0 1-1.51V3a2 2 0 1 1 4 0v.09a1.65 1.65 0 0 0 1 1.51h.01a1.65 1.65 0 0 0 1.82-.33l.06-.06a2 2 0 1 1 2.83 2.83l-.06.06a1.65 1.65 0 0 0-.33 1.82v.01a1.65 1.65 0 0 0 1.51 1H21a2 2 0 1 1 0 4h-.09a1.65 1.65 0 0 0-1.51 1z"/></svg>
    </button>
```

`<section id="view-auth" class="view"></section>` の直後に:

```html
  <section id="view-settings" class="view"></section>
```

- [ ] **Step 3: JSを追加(設定画面+ログアウト移設)**

`const store = {` の直前に:

```js
const KOTEI_KEYS=['kotei.daily.v1','kotei.weekly.v1','kotei.promise.v1','kotei.outbox.v1','kotei.migrated.v1','kotei.migrating.v1'];
```

`/* ===== 認証 ===== */` セクションの直前に:

```js
/* ===== 設定 ===== */
const SETTINGS_ITEMS=[
  {id:'logout', label:'ログアウト', sub:'記録はクラウドにちゃんと残るよ', fn:doLogout}
  /* Capacitor化で通知設定などをここに追加 */
];
let delMode=false;
function renderSettings(){
  const v=document.getElementById('view-settings');
  if(delMode){renderDeleteConfirm();return;}
  v.innerHTML='<div class="speech"><div class="row"><span class="kotei" data-kotei></span><div class="msg"><div class="name">コウテイちゃん</div>設定だよ。ゆっくりどうぞ。</div></div></div>'
    +'<div style="margin-top:10px">'
    +SETTINGS_ITEMS.map(it=>'<div class="settings-item" data-set="'+it.id+'"><div><div class="lbl">'+it.label+'</div>'+(it.sub?'<div class="sub">'+it.sub+'</div>':'')+'</div><span class="chev">›</span></div>').join('')
    +'</div>'
    +'<div class="deck-nav" style="margin-top:18px"><button class="btn ghost" id="settings-back" style="flex:1">もどる</button></div>'
    +'<p style="text-align:center;margin:28px 0 0"><button class="linklike" id="open-delete">アカウントの削除について</button></p>';
  mountFaces();
  document.getElementById('settings-back').onclick=()=>switchView('daily');
  document.querySelectorAll('[data-set]').forEach(el=>{el.onclick=()=>{const it=SETTINGS_ITEMS.find(x=>x.id===el.dataset.set);if(it)it.fn();};});
  document.getElementById('open-delete').onclick=()=>{delMode=true;renderSettings();};
}
async function doLogout(){
  const pending=Object.keys(store._r(store.OKEY)).length;
  if(pending>0 && !confirm('まだクラウドに送れていない記録が'+pending+'件あるよ。ログアウトすると、この端末からは消えちゃう。それでもログアウトする?')) return;
  if(pending===0 && !confirm('ログアウトする? 記録はクラウドにちゃんと残ってるから、安心してね。')) return;
  await sb.auth.signOut({scope:'local'});
  KOTEI_KEYS.forEach(k=>localStorage.removeItem(k));
  location.reload();
}
```

(この時点では `renderDeleteConfirm` は未定義だが、delModeの初期値がfalseなので到達しない。Task 3で実装する)

- [ ] **Step 4: switchViewと配線を更新**

`switchView` 内の `if(view==='record'){renderRecord();}` の直後に:

```js
  if(view==='settings'){delMode=false;renderSettings();}
```

`document.querySelectorAll('nav button').forEach(...)` の行の直後に:

```js
document.getElementById('header-gear').onclick=()=>switchView('settings');
```

- [ ] **Step 5: きろくページのログアウトを撤去**

`renderRecord()` から次を削除:
- `const logoutHtml=...` の行(374行目付近)
- 空状態パスの `+logoutHtml` と `wireLogout();`(377-378行目付近)— `v.innerHTML=html; mountFaces(); return;` に戻す
- 通常パスの `html+=logoutHtml;` と `wireLogout();`(426・429行目付近)
- `function wireLogout(){...}` 全体(432-443行目付近)

- [ ] **Step 6: 構文チェック**

共通コマンドを実行。Expected: エラーなし。

- [ ] **Step 7: コミット**

```bash
git add index.html
git commit -m "feat: 設定画面(歯車・配列駆動)を新設しログアウトを移設"
```

---

### Task 3: アカウント削除フロー(二段階確認)

**Files:**
- Modify: `index.html`(`renderSettings` の直後に `renderDeleteConfirm`/`doDeleteAccount` を追加)

**Interfaces:**
- Consumes: `sb.rpc('delete_user')`(Task 1)/ `KOTEI_KEYS`・`delMode`・`renderSettings`(Task 2)/ 既存 `toast(msg)`・`esc()`・`mountFaces()`
- Produces: `function renderDeleteConfirm(err?)` / `async function doDeleteAccount()`

- [ ] **Step 1: 削除フローを実装**

`doLogout` の直後に追加:

```js
function renderDeleteConfirm(err){
  const v=document.getElementById('view-settings');
  v.innerHTML='<div class="speech"><div class="row"><span class="kotei" data-kotei="care"></span><div class="msg"><div class="name">コウテイちゃん</div>アカウントを消すと、いままでの記録はぜんぶ消えて、元に戻せないよ。それでもいいか、ゆっくり考えてね。</div></div></div>'
    +(err?'<p style="color:var(--rose-deep);font-size:13.5px;text-align:center;margin:12px 0 0">'+esc(err)+'</p>':'')
    +'<div class="deck-nav" style="margin-top:18px"><button class="btn primary" id="del-cancel" style="flex:2">やめておく</button><button class="btn ghost" id="del-go" style="flex:1">削除にすすむ</button></div>';
  mountFaces();
  document.getElementById('del-cancel').onclick=()=>{delMode=false;renderSettings();};
  document.getElementById('del-go').onclick=doDeleteAccount;
}
async function doDeleteAccount(){
  if(!confirm('ほんとうに削除する? 記録はすべて消えて、元に戻せないよ。')) return;
  const btn=document.getElementById('del-go');btn.disabled=true;
  const {error}=await sb.rpc('delete_user');
  if(error){renderDeleteConfirm('いまは削除できないみたい。電波のあるところで、もう一度ためしてみてね。');return;}
  await sb.auth.signOut({scope:'local'}).catch(()=>{});
  KOTEI_KEYS.forEach(k=>localStorage.removeItem(k));
  toast('ここまで一緒に歩いてくれてありがとう。またいつでも、待ってるね');
  setTimeout(()=>location.reload(),2500);
}
```

- [ ] **Step 2: 構文チェック**

共通コマンドを実行。Expected: エラーなし。

- [ ] **Step 3: コミット**

```bash
git add index.html
git commit -m "feat: アカウント削除フロー(二段階確認+RPC)を追加"
```

---

### Task 4: 軽微修正(エスケープ3箇所・移行トースト)

**Files:**
- Modify: `index.html`(renderRecord 394行目付近・417行目付近、renderWeeklyForm 346行目付近、bootSync 551-559行目付近)

**Interfaces:**
- Consumes: 既存 `esc()` / `toast()` / `store.flush()` / `kotei.migrating.v1`(KOTEI_KEYSに定義済み)
- Produces: なし(挙動修正のみ)

- [ ] **Step 1: エスケープ3箇所**

renderRecord(394行目付近):
`e.q2_tags.join('・')` → `e.q2_tags.map(esc).join('・')`

renderRecord(417行目付近):
`'<span class="rec-note">'+k+'：'` → `'<span class="rec-note">'+esc(k)+'：'`

renderWeeklyForm(346行目付近)の2箇所:
`'">'+(sp[p]!=null?sp[p]:3)+'</span>'` → `'">'+esc(sp[p]!=null?sp[p]:3)+'</span>'`
`value="'+(sp[p]!=null?sp[p]:3)+'" data-pillar=` → `value="'+esc(sp[p]!=null?sp[p]:3)+'" data-pillar=`

- [ ] **Step 2: 移行トーストをフラグ方式に**

bootSyncの次のブロック:

```js
    if(toMigrate>0){
      await store.flush();
      if(!localStorage.getItem('kotei.migrated.v1') && Object.keys(store._r(store.OKEY)).length===0){
        localStorage.setItem('kotei.migrated.v1','1');
        toast('これまでの記録、クラウドでちゃんと預かったよ');
      }
    } else {
      store.flush();
    }
```

を次に置き換え:

```js
    if(toMigrate>0) localStorage.setItem('kotei.migrating.v1','1');
    await store.flush();
    /* 移行の完送を見届けてから一度だけ報告(部分失敗した回はフラグが残り、次回完送時に出る) */
    if(localStorage.getItem('kotei.migrating.v1') && !localStorage.getItem('kotei.migrated.v1') && Object.keys(store._r(store.OKEY)).length===0){
      localStorage.setItem('kotei.migrated.v1','1');
      localStorage.removeItem('kotei.migrating.v1');
      toast('これまでの記録、クラウドでちゃんと預かったよ');
    }
```

- [ ] **Step 3: 構文チェック**

共通コマンドを実行。Expected: エラーなし。

- [ ] **Step 4: コミット**

```bash
git add index.html
git commit -m "fix: 記録描画のエスケープ3箇所と移行トーストの取り逃しを修正"
```

---

### Task 5: sw.jsバージョン更新+総合検証

**Files:**
- Modify: `sw.js:1`(CACHE)

- [ ] **Step 1: CACHEをv5へ**

```js
const CACHE = 'kotei-v5';
```

- [ ] **Step 2: 構文チェックとコミット**

```bash
node --check sw.js
git add sw.js
git commit -m "sw: CACHEをkotei-v5へ(設定画面・アカウント削除リリース)"
```

- [ ] **Step 3: 検証(ユーザー実施)**

事前準備: Supabase SQL Editor で `supabase/account-deletion.sql` を実行(Success. No rows returned)。
ローカルサーバー: `python3 -m http.server 8080 --directory /Users/y/Desktop/kotei-workspace/tsumiki`

1. 歯車 → 設定画面が開き「もどる」で戻れる。**ログイン画面では歯車が見えない**
2. 設定画面からログアウトできる。きろく最下部にログアウトがないこと
3. テストアカウント(`yvk26.yvk+del@gmail.com`等)で記録を数件保存 → 設定 → 削除フロー(説明カード→confirm)→ お別れトースト → ログイン画面
4. Dashboard: auth.users から該当ユーザーが消え、daily/weekly/profiles もcascade削除
5. 同じメールで再度新規登録できる
6. オフライン(DevTools)で削除 → エラー文言が出て、ローカルの記録が残っている
7. エスケープ: コンソールで `const a=JSON.parse(localStorage.getItem('kotei.daily.v1'));a['2026-07-01']={q2_tags:['<b>x</b>'],q2_note:'t',savedAt:new Date().toISOString()};localStorage.setItem('kotei.daily.v1',JSON.stringify(a));` → きろくページで `<b>x</b>` が文字列のまま表示(太字にならない)
8. 検証後、注入したダミーデータを削除(該当キーを消すか、テストアカウントごと削除)

---

## 備考

- 本番反映(main push)後、既存セッションのユーザーは次回オンライン起動でsw.js更新(v5)が届く
- リリース前TODO(スコープ外・忘れないこと): Confirm emailをON / パスワードリセット(Day 13-14) / Sign in with Apple(Capacitor時)
