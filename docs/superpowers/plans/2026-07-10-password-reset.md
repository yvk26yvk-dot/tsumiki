# パスワードリセット+Confirm email ON化 実装計画

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** ログイン画面にパスワードリセット導線(forgot/recoveryモード)を追加し、Confirm emailをONに戻し、認証メール2種を日英併記テンプレートに差し替える。

**Architecture:** 既存の `authMode`(login/signup)を4モード(+forgot/recovery)に拡張し、`renderAuth`/`doAuth` をモード分岐で拡張する。リカバリは `sb.auth.onAuthStateChange` の `PASSWORD_RECOVERY` イベントで検知し、`updateUser({password})` 後はそのまま `enterApp()`。ページ追加なし・view-authで完結。

**Tech Stack:** Vanilla JS(index.html単一ファイル)/ supabase-js 2.110.0(同梱)/ Supabase Auth(resetPasswordForEmail / updateUser / Email Templates)

**Spec:** `docs/superpowers/specs/2026-07-10-password-reset-design.md`

## Global Constraints

- コウテイちゃんの人格: あたたかい母性・タメ口・責めない
- redirectToは動的: `location.origin+location.pathname`(本番固定にしない)
- forgot送信の成功文言は「メールを送ったよ。届いたリンクから、新しいパスワードを決めてね。」(存在しないメールでも同一=列挙対策)
- forgot送信のエラー文言は「すこし時間をおいて、もう一度ためしてみてね。」
- recovery成功トーストは「あたらしいパスワード、うけとったよ」
- 「パスワードを忘れた?」リンクは **loginモードのみ** 表示(signupでは出さない)
- sw.js の CACHE は `kotei-v6` に上げる
- コミットは各タスク末尾。**pushはしない**
- ブランチ: `feature/password-reset` を main から作成して作業

**検証方式:** 自動テスト基盤なし。各タスクでインラインスクリプト抽出+`node --check`、ブラウザ検証は最後にユーザーがまとめて実施。

**構文チェックコマンド(共通):**
```bash
python3 -c "import re; html=open('/Users/y/Desktop/kotei-workspace/tsumiki/index.html').read(); m=re.findall(r'<script>(.*?)</script>', html, re.S); open('/private/tmp/claude-501/-Users-y/56b9d1a3-0584-4e64-9390-82ab79c0306c/scratchpad/inline.js','w').write(m[0])" && node --check /private/tmp/claude-501/-Users-y/56b9d1a3-0584-4e64-9390-82ab79c0306c/scratchpad/inline.js
```

---

### Task 1: 認証4モード化(forgot/recovery)

**Files:**
- Modify: `index.html` — `renderAuth()`(504-526行付近)、`doAuth()`(535-553行付近)、起動IIFE(627-630行付近)

**Interfaces:**
- Consumes: 既存 `sb` / `esc()` / `mountFaces()` / `toast(msg)` / `authErrMsg(err)` / `enterApp()`
- Produces: `authMode` が `'login'|'signup'|'forgot'|'recovery'` の4値を取る。外部から使う関数のシグネチャは不変。

- [ ] **Step 1: renderAuthを4モード対応に置き換え**

既存の `function renderAuth(notice){...}` 全体(504-526行付近、`let authMode='login';` は残す)を次に置き換え:

```js
function renderAuth(notice){
  document.body.classList.add('noauth');
  document.querySelectorAll('.view').forEach(s=>s.classList.remove('active'));
  const v=document.getElementById('view-auth');
  v.classList.add('active');
  const m=authMode;
  const GREET={
    login:'おかえり。あなたの記録、ここで待ってるよ。',
    signup:'はじめまして。あなたの記録、わたしが大事に預かるね。',
    forgot:'だいじょうぶ、いっしょに入り直そう。メールアドレスを教えてね。',
    recovery:'おかえり。あたらしいパスワードを決めよう。'
  };
  const BTN={login:'ログイン',signup:'はじめる',forgot:'リセットメールを送る',recovery:'これにする'};
  const showEmail=(m!=='recovery');
  const showPw=(m!=='forgot');
  v.innerHTML='<div class="speech"><div class="row"><span class="kotei" data-kotei></span><div class="msg"><div class="name">コウテイちゃん</div>'+GREET[m]+'</div></div></div>'
    +'<div class="deck" style="min-height:auto"><div class="slide">'
    +(notice?'<p class="sub" style="color:var(--rose-deep);margin:0 0 14px">'+esc(notice)+'</p>':'')
    +(showEmail?'<div class="field-label">メールアドレス</div><input type="email" id="auth-email" autocomplete="email">':'')
    +(showPw?'<div class="field-label"'+(showEmail?' style="margin-top:12px"':'')+'>'+(m==='recovery'?'あたらしいパスワード':'パスワード')+'</div><input type="password" id="auth-pw" autocomplete="'+(m==='login'?'current-password':'new-password')+'">':'')
    +'</div><div class="deck-nav"><button class="btn primary" id="auth-go">'+BTN[m]+'</button></div>'
    +(m==='login'?'<p style="text-align:center;margin:14px 0 0"><button class="linklike" id="auth-forgot">パスワードを忘れた?</button></p>':'')
    +(m!=='recovery'?'<p style="text-align:center;margin:'+(m==='login'?'8px':'14px')+' 0 0"><button class="linklike" id="auth-toggle">'+(m==='signup'?'アカウントがある人はこちら':(m==='forgot'?'ログインにもどる':'はじめての人はこちら'))+'</button></p>':'')
    +'</div>';
  mountFaces();
  const tg=document.getElementById('auth-toggle');
  if(tg)tg.onclick=()=>{authMode=(m==='signup'||m==='forgot')?'login':'signup';renderAuth();};
  const fg=document.getElementById('auth-forgot');
  if(fg)fg.onclick=()=>{authMode='forgot';renderAuth();};
  document.getElementById('auth-go').onclick=doAuth;
  const authEnter=e=>{if(e.key==='Enter'&&!document.getElementById('auth-go').disabled)doAuth();};
  const em=document.getElementById('auth-email');if(em)em.onkeydown=authEnter;
  const pw=document.getElementById('auth-pw');if(pw)pw.onkeydown=authEnter;
}
```

- [ ] **Step 2: doAuthを4モード対応に置き換え**

既存の `async function doAuth(){...}` 全体を次に置き換え:

```js
async function doAuth(){
  const mode=authMode;
  const emEl=document.getElementById('auth-email'), pwEl=document.getElementById('auth-pw');
  const email=emEl?emEl.value.trim():'';
  const pw=pwEl?pwEl.value:'';
  if((mode==='login'||mode==='signup')&&(!email||!pw)){renderAuth('メールとパスワード、両方入れてね。');document.getElementById('auth-email').value=email;return;}
  if(mode==='forgot'&&!email){renderAuth('メールアドレスを入れてね。');return;}
  if(mode==='recovery'&&!pw){renderAuth('あたらしいパスワードを入れてね。');return;}
  const btn=document.getElementById('auth-go');btn.disabled=true;btn.textContent='ちょっと待ってね…';
  ['auth-toggle','auth-forgot'].forEach(id=>{const b=document.getElementById(id);if(b)b.disabled=true;});
  let res;
  if(mode==='signup')res=await sb.auth.signUp({email,password:pw});
  else if(mode==='login')res=await sb.auth.signInWithPassword({email,password:pw});
  else if(mode==='forgot')res=await sb.auth.resetPasswordForEmail(email,{redirectTo:location.origin+location.pathname});
  else res=await sb.auth.updateUser({password:pw});
  if(res.error){
    renderAuth(mode==='forgot'?'すこし時間をおいて、もう一度ためしてみてね。':authErrMsg(res.error));
    const em2=document.getElementById('auth-email');if(em2)em2.value=email;
    return;
  }
  if(mode==='forgot'){
    authMode='login';
    renderAuth('メールを送ったよ。届いたリンクから、新しいパスワードを決めてね。');
    document.getElementById('auth-email').value=email;
    return;
  }
  if(mode==='signup'&&!res.data.session){
    authMode='login';
    renderAuth('確認メールを送ったよ。メールの中のリンクを押してから、ここでログインしてね。');
    document.getElementById('auth-email').value=email;
    return;
  }
  if(mode==='recovery'){authMode='login';toast('あたらしいパスワード、うけとったよ');}
  enterApp();
}
```

- [ ] **Step 3: リカバリイベント購読と起動ガード**

起動IIFE(現在の以下のコード):

```js
(async()=>{
  const {data:{session}}=await sb.auth.getSession();
  if(session){enterApp();}else{renderAuth();}
})();
```

を次に置き換え:

```js
/* リカバリリンクで戻ってきたら、新しいパスワード画面へ */
sb.auth.onAuthStateChange((event)=>{
  if(event==='PASSWORD_RECOVERY'){authMode='recovery';renderAuth();}
});
(async()=>{
  /* リカバリ着地時はアプリを開かず、上のイベントに任せる(画面のちらつき防止) */
  if(location.hash.includes('type=recovery'))return;
  const {data:{session}}=await sb.auth.getSession();
  if(session){enterApp();}else{renderAuth();}
})();
```

- [ ] **Step 4: 構文チェック**

共通コマンドを実行。Expected: エラーなし。
追加チェック: `grep -c "PASSWORD_RECOVERY\|resetPasswordForEmail\|auth-forgot" index.html` が4以上。

- [ ] **Step 5: コミット**

```bash
git add index.html
git commit -m "feat: パスワードリセット導線(forgot/recoveryモード)を追加"
```

---

### Task 2: sw.jsバージョン更新

**Files:**
- Modify: `sw.js:1`

- [ ] **Step 1: CACHEをv6へ変更しコミット**

```js
const CACHE = 'kotei-v6';
```

```bash
node --check sw.js
git add sw.js
git commit -m "sw: CACHEをkotei-v6へ(パスワードリセットリリース)"
```

---

### Task 3: Supabase設定+メールテンプレート(ユーザー操作)+検証

**Files:** 変更なし(ダッシュボード操作と検証のみ)

- [ ] **Step 1: ダッシュボード設定(ユーザー)**

1. Authentication → Sign In / Providers → Email → **Confirm email をON**
2. Authentication → URL Configuration → Redirect URLs に以下があることを確認/追加:
   - `https://yvk26yvk-dot.github.io/tsumiki/`
   - `http://localhost:8080`
   - `http://127.0.0.1:8080`

- [ ] **Step 2: メールテンプレート差し替え(ユーザー)**

Authentication → Email Templates で2種を差し替え:

**Reset Password** — Subject:
```
【コウテイちゃん】パスワードの再設定 / Reset your password
```
Message body:
```html
<h2>パスワードの再設定</h2>
<p>コウテイちゃんだよ。パスワードを新しくするお手伝いをするね。<br>
下のリンクを押して、あたらしいパスワードを決めてね。</p>
<p><a href="{{ .ConfirmationURL }}">あたらしいパスワードを決める / Set a new password</a></p>
<p>心当たりがないときは、このメールはそのまま捨てて大丈夫だよ。</p>
<hr>
<p>Hi, this is Kotei-chan. Tap the link above to set a new password.<br>
If you didn't request this, you can safely ignore this email.</p>
```

**Confirm signup** — Subject:
```
【コウテイちゃん】メールアドレスの確認 / Confirm your email
```
Message body:
```html
<h2>メールアドレスの確認</h2>
<p>はじめまして、コウテイちゃんだよ。登録ありがとう。<br>
下のリンクを押して、メールアドレスの確認を済ませてね。</p>
<p><a href="{{ .ConfirmationURL }}">メールアドレスを確認する / Confirm your email</a></p>
<hr>
<p>Welcome! Tap the link above to confirm your email address and start your journey with Kotei-chan.</p>
```

- [ ] **Step 3: 検証(ユーザー実施)**

ローカルサーバー: `python3 -m http.server 8080 --directory /Users/y/Desktop/kotei-workspace/tsumiki`
※メール送信レート制限(数通/時)があるので、項目2と4は時間を空けるか別アドレスで。

1. ログイン画面に「パスワードを忘れた?」が出る。signup画面では出ない
2. 忘れた?→メール入力→送信→「メールを送ったよ〜」→メール受信(日英併記)→リンク→「あたらしいパスワードを決めよう」画面→設定→トースト→そのままアプリ
3. 新パスワードでログインできる。旧パスワードは「メールかパスワードが違うみたい」
4. 新規登録(テストアドレス)→確認メール(日英併記)が届く→「確認メールを送ったよ〜」表示→リンク確認後にログインできる
5. 存在しないメールでリセット送信→同じ「メールを送ったよ〜」文言
6. リセット・確認メールの文面が日英併記になっている

---

## 備考

- リカバリリンクの着地はURLハッシュ(`#...type=recovery`)で起動ガードしている。
  supabase-jsのフロー設定が将来PKCE(`?code=`)に変わるとガードが効かず一瞬アプリが
  見えてから recovery 画面に切り替わるが、フロー自体は `PASSWORD_RECOVERY` イベントで
  成立する(機能は壊れない)
- 本番push前チェック: Task 3 Step 1-2(ダッシュボード設定)が本番にも効いていること
  (プロジェクトは1つなのでローカル検証と共通)
