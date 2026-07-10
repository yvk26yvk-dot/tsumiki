# Capacitor iOS化 実装計画

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** tsumikiをCapacitorでiOSアプリ化し、シミュレーターとユーザーのiPhone実機でフル機能(認証・同期・削除)が動く状態にする。

**Architecture:** Webコンテンツはローカル同梱(webDir=`www/`、生成物)。`npm run sync` でアプリ資産をwww/へコピーして `cap sync ios`。web側のビルドなし原則とGitHub Pages配信は無傷。index.htmlの変更は `NATIVE` 分岐2箇所のみ。

**Tech Stack:** Capacitor 7(@capacitor/core・cli・ios)/ Swift Package Manager優先(不調時CocoaPods)/ @capacitor/assets(アイコン生成)/ Xcode 26.6(確認済み)/ Node v25(確認済み)

**Spec:** `docs/superpowers/specs/2026-07-10-capacitor-ios-design.md`

## Global Constraints

- Bundle ID: `com.kouteichan.app` / アプリ名: `コウテイちゃん`
- webDir: `www`(生成物・gitignore)。**sw.jsはwww/に含めない**
- index.htmlのweb挙動(PWA)を一切変えない — NATIVE分岐はネイティブでのみ効く
- ネイティブのredirectTo固定値: `https://yvk26yvk-dot.github.io/tsumiki/`(ドメイン移行時の更新はCLAUDE.mdにTODO済み)
- 追加権限なし(Info.plistに使用目的文言の追加をしない)
- コミットは各タスク末尾。**pushしない**
- ブランチ: `feature/capacitor-ios` を main から作成
- 作業ディレクトリ: `/Users/y/Desktop/kotei-workspace/tsumiki`

**検証方式:** Task 1-4はCLI検証(コマンド+期待結果を明記)。ブラウザ相当の操作検証はTask 5でユーザーがシミュレーター/実機で実施。

---

### Task 1: Capacitor導入とiOSプロジェクト生成

**Files:**
- Create: `capacitor.config.json` / `scripts/sync-www.sh` / `package.json`(npm installが生成) / `ios/`(cap addが生成)
- Modify: `.gitignore`

**Interfaces:**
- Produces: `npm run sync`(www/生成+cap sync ios)、`ios/App/` のXcodeプロジェクト。Task 3/4はこの上で動く。

- [ ] **Step 1: npm初期化と依存導入**

```bash
cd /Users/y/Desktop/kotei-workspace/tsumiki
npm init -y
npm install @capacitor/core@7 @capacitor/ios@7
npm install -D @capacitor/cli@7 @capacitor/assets
```
Expected: `package.json` と `node_modules/` が生成され、エラーなし(EACCESSやネットワークエラーが出たらBLOCKED報告)。

- [ ] **Step 2: capacitor.config.json を作成**

```json
{
  "appId": "com.kouteichan.app",
  "appName": "コウテイちゃん",
  "webDir": "www",
  "ios": {
    "contentInset": "automatic"
  }
}
```

- [ ] **Step 3: 同期スクリプトを作成**

`scripts/sync-www.sh`:

```bash
#!/bin/bash
# アプリ資産を www/ に集めて cap sync する。
# sw.js は除外(WKWebViewはService Worker非対応。index.html側もNATIVEガード済み)
set -e
cd "$(dirname "$0")/.."
rm -rf www && mkdir www
cp index.html supabase.min.js manifest.json www/
cp kotei-normal.png kotei-care.png kotei-cheer.png kotei-body.png icon-192.png icon-512.png www/
npx cap sync ios
```

```bash
chmod +x scripts/sync-www.sh
```

`package.json` の scripts に追加(npm init -y が作った"test"行は削除してよい):

```json
  "scripts": {
    "sync": "bash scripts/sync-www.sh"
  }
```

- [ ] **Step 4: .gitignoreに生成物を追加**

既存 `.gitignore` の末尾に追加:

```
# Capacitor / ネイティブ生成物
node_modules/
www/
ios/App/Pods/
ios/App/output/
ios/DerivedData/
```

- [ ] **Step 5: iOSプロジェクト生成(SPM優先)**

```bash
npx cap add ios --packagemanager SPM
```
Expected: `ios/` ディレクトリが生成され "✔ Adding native Xcode project" 等の成功表示。
`--packagemanager SPM` が未対応・失敗の場合のフォールバック:
```bash
brew --version || echo "BREW_MISSING"   # brewがなければBLOCKED報告(ユーザーにHomebrew導入を依頼)
brew install cocoapods
npx cap add ios
```
生成後、`ios/.gitignore` が `App/Pods` や `App/public` を無視しているか確認し、なければ手元の `.gitignore` に `ios/App/App/public/` を追加。

- [ ] **Step 6: 初回同期と検証**

```bash
npm run sync
ls www/ && ls ios/App/App/public/index.html
grep -c "sw.js" <(ls www/) || echo "sw.js excluded OK"
```
Expected: www/ に index.html・supabase.min.js・manifest.json・png6点(sw.jsなし)。`ios/App/App/public/index.html` が存在。cap syncが "Sync finished" を表示。

- [ ] **Step 7: コミット**

```bash
git add package.json package-lock.json capacitor.config.json scripts/sync-www.sh .gitignore ios/
git commit -m "feat: Capacitor導入とiOSプロジェクト生成(SPM/webDir=www)"
```

---

### Task 2: index.htmlのNATIVE分岐とCLAUDE.md更新

**Files:**
- Modify: `index.html`(定数追加+2箇所)、`CLAUDE.md`(開発フロー追記)

**Interfaces:**
- Consumes: 既存 `SUPABASE_URL` 定数付近 / doAuthのforgot分岐 / 末尾のSW登録行
- Produces: `const NATIVE`(グローバル)。webの挙動は不変。

- [ ] **Step 1: NATIVE定数を追加**

`const SUPABASE_URL=...` の直前に:

```js
const NATIVE=location.protocol==='capacitor:';
```

- [ ] **Step 2: forgotのredirectToをネイティブ分岐**

doAuth内の

```js
  else if(mode==='forgot')res=await sb.auth.resetPasswordForEmail(email,{redirectTo:location.origin+location.pathname.replace(/index\.html$/,'')});
```

を次に置き換え:

```js
  /* ネイティブ: capacitor://はメールリンクの戻り先にできないため本番PWAへ。
     Safariで再設定→アプリに戻って新パスワードでログインする流れ */
  else if(mode==='forgot')res=await sb.auth.resetPasswordForEmail(email,{redirectTo:NATIVE?'https://yvk26yvk-dot.github.io/tsumiki/':location.origin+location.pathname.replace(/index\.html$/,'')});
```

- [ ] **Step 3: SW登録をNATIVEガード**

末尾の

```js
if('serviceWorker' in navigator){window.addEventListener('load',()=>navigator.serviceWorker.register('sw.js').catch(()=>{}));}
```

を次に置き換え:

```js
if('serviceWorker' in navigator && !NATIVE){window.addEventListener('load',()=>navigator.serviceWorker.register('sw.js').catch(()=>{}));}
```

- [ ] **Step 4: CLAUDE.mdに開発フローを追記**

「## 技術的な決まりごと」セクションの末尾に追加:

```markdown
- ネイティブ(Capacitor)の開発フロー:
  - web側はこれまで通り index.html を直接編集(ビルドなし)。main push で Pages に反映
  - ネイティブ確認は `npm run sync`(www/へ資産コピー+cap sync)→ `npx cap open ios` → Xcodeで実行
  - www/ と node_modules/ は生成物(コミットしない)。ios/ はコミット対象
  - webの更新はPagesに即反映されるが、アプリ内のWebは**アプリ更新まで変わらない**(反映が2系統で独立)
  - sw.js はネイティブに同梱しない(WKWebViewはSW非対応。index.htmlのNATIVEガードで登録もスキップ)
```

- [ ] **Step 5: 構文チェックとwebの無変化確認**

```bash
python3 -c "import re; html=open('/Users/y/Desktop/kotei-workspace/tsumiki/index.html').read(); m=re.findall(r'<script>(.*?)</script>', html, re.S); open('/private/tmp/claude-501/-Users-y/56b9d1a3-0584-4e64-9390-82ab79c0306c/scratchpad/inline.js','w').write(m[0])" && node --check /private/tmp/claude-501/-Users-y/56b9d1a3-0584-4e64-9390-82ab79c0306c/scratchpad/inline.js
grep -c "NATIVE" /Users/y/Desktop/kotei-workspace/tsumiki/index.html
```
Expected: 構文OK。NATIVE出現は3(定義+redirectTo+SWガード)。
※http(s)では `location.protocol` は 'capacitor:' にならないため、web挙動は完全に不変。sw.jsのCACHEは**上げない**(web側に配信される差分はNATIVE分岐のみで、既存のnetwork-first配信で次回反映される。バンプは実機検証後のリリースコミットでまとめて判断)。

- [ ] **Step 6: コミット**

```bash
git add index.html CLAUDE.md
git commit -m "feat: NATIVE分岐(リセットredirectTo/SWガード)とネイティブ開発フローを追記"
```

---

### Task 3: アプリアイコンとスプラッシュ生成

**Files:**
- Create: `assets/logo.png`(1024px・icon-512から拡大の暫定)
- Modify: `ios/App/App/Assets.xcassets/`(@capacitor/assetsが生成)

**Interfaces:**
- Consumes: 既存 `icon-512.png`
- Produces: iOSの全サイズアイコン+スプラッシュ(logo.png+背景色から自動生成)。イラスト発注後は `assets/logo.png` を差し替えて再生成するだけ。

- [ ] **Step 1: 元画像を準備(sipsで拡大)**

```bash
cd /Users/y/Desktop/kotei-workspace/tsumiki
mkdir -p assets
sips -z 1024 1024 icon-512.png --out assets/logo.png
sips -g pixelWidth -g pixelHeight assets/logo.png
```
Expected: `assets/logo.png` が 1024x1024。
※splash.pngは作らない — @capacitor/assets は logo.png を背景色の中央に配置した
スプラッシュを自動生成する。

- [ ] **Step 2: iOSアセット生成**

```bash
npx @capacitor/assets generate --ios --iconBackgroundColor '#FBF4EF' --splashBackgroundColor '#FBF4EF'
```
Expected: "Generated N assets" 等の成功表示。`ios/App/App/Assets.xcassets/AppIcon.appiconset/` に生成物。

- [ ] **Step 3: コミット**

```bash
git add assets/ ios/App/App/Assets.xcassets/
git commit -m "feat: アプリアイコンとスプラッシュを生成(icon-512からの暫定)"
```

---

### Task 4: シミュレータービルドのCLI検証

**Files:** 変更なし(ビルド検証のみ。失敗時の修正はあり得る)

- [ ] **Step 1: ビルド**

SPM構成の場合:
```bash
xcodebuild -project /Users/y/Desktop/kotei-workspace/tsumiki/ios/App/App.xcodeproj -scheme App -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' build 2>&1 | tail -5
```
CocoaPods構成の場合(workspaceを使う):
```bash
xcodebuild -workspace /Users/y/Desktop/kotei-workspace/tsumiki/ios/App/App.xcworkspace -scheme App -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' build 2>&1 | tail -5
```
Expected: `** BUILD SUCCEEDED **`。失敗したらエラー全文を報告(BLOCKED)。

- [ ] **Step 2: コミット(ビルドで生成物が出た場合のみ.gitignore調整)**

ビルドが green であること自体が成果物。作業ツリーに意図しない差分(DerivedData等)が出ていたら .gitignore に追加してコミット、差分ゼロならコミット不要。

---

### Task 5: ユーザー検証(Xcode GUI+シミュレーター+実機)

**Files:** 変更なし

- [ ] **Step 1: 署名設定(ユーザー・Xcode GUI)**

```bash
npx cap open ios
```
Xcodeで: App target → Signing & Capabilities → Team に登録済みDeveloperアカウントを選択。Bundle Identifier が `com.kouteichan.app` であることを確認。

- [ ] **Step 2: シミュレーター検証(ユーザー)**

Xcodeの実行ボタン(▶)でシミュレーター起動:
1. 起動→ログイン→日次保存→Table Editorに反映→アプリ再起動で復元
2. スプラッシュとアイコンの表示確認

- [ ] **Step 3: 実機検証(ユーザー)**

iPhoneをMacに接続し、実行先を実機にして▶:
1. Task 5-2の1と同様
2. 機内モードで起動・保存→解除で自動同期
3. セーフエリア(ノッチ/ホームバー)の見た目
4. パスワードリセット一巡(アプリ→メール→Safariで本番PWA→再設定→アプリで新PWログイン)
5. ネイティブから新規登録一巡(登録→確認メールのリンクがSafariで開く→確認後アプリでログイン)
6. ログアウト・アカウント削除
7. PWA版と同一アカウントで記録が相互に見える

---

## 備考

- Task 1 Step 1/5 と Task 3 Step 2 はネットワーク・環境依存。エラー時は自己判断で回り道せずBLOCKEDで報告する(コーディネーターが対処)
- 実機検証後のmainマージ・pushは従来通りユーザー指示で。push時のweb側変更はNATIVE分岐のみ(PWAに実質影響なし)なのでsw.jsバンプは不要と判断するが、最終レビューの指摘があれば従う
- プッシュ通知(Capability追加・APNs)は次スペック。今回のXcodeプロジェクトに手を入れない
