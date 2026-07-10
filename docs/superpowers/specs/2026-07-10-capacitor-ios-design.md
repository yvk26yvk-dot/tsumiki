# Capacitor iOS化 設計書

日付: 2026-07-10
対象: 第二段階タスク4の前半「CapacitorでiOS化」。プッシュ通知は後続の別スペック。

## 決定事項(ユーザー承認済み)

| 論点 | 決定 |
|---|---|
| ゴール | シミュレーター+ユーザーのiPhone実機でフル機能(認証・同期・削除)が動くまで。TestFlightはプッシュ通知実装後にまとめて |
| Webコンテンツ | 案A: ローカル同梱(webDir方式)。リモートシェル(server.url)は審査リスクで不採用 |
| Bundle ID | `com.kouteichan.app`(変更不可の永久識別子) |
| アプリ名 | コウテイちゃん |
| リポジトリ | tsumikiリポジトリに同居(package.json / capacitor.config.json / ios/ を追加) |
| Apple Developer | 登録済み。署名チーム設定はXcode GUIでユーザーが実施 |
| PWA | GitHub Pages配信は従来通り併存。記録はSupabase経由で両者共有 |

## 1. リポジトリ構成とビルドフロー

- 追加ファイル:
  - `package.json` — @capacitor/core, @capacitor/cli, @capacitor/ios(バージョンは実装時の最新7.x固定)
  - `capacitor.config.json` — `{appId:'com.kouteichan.app', appName:'コウテイちゃん', webDir:'www'}`
  - `ios/` — `npx cap add ios` の生成物(コミット対象。Pods等の生成物はgitignore)
  - `scripts/sync-www.sh` 相当のnpm script — `www/` へアプリ資産をコピーして `cap sync ios`
- **`www/` は生成物**(gitignore)。コピー対象: `index.html` / `supabase.min.js` /
  `*.png`(kotei-4種+icon-192+icon-512) / `manifest.json`。
  **`sw.js` は除外**(WKWebView(capacitor://)はService Worker非対応・同梱物に
  キャッシュ層は不要。index.html側の登録コードはNATIVEガードで無効化する)
- GitHub Pages配信(リポジトリ直下)には影響なし。
  **「index.htmlはビルドなしで動く」原則はweb側で不変** — npm/Xcodeはネイティブの
  ガワにだけ関与する
- `.gitignore` 追加: `node_modules/`, `www/`, `ios/App/Pods/`, `ios/App/output/`,
  `ios/DerivedData/` 等
- CLAUDE.md更新: 開発フロー追記
  - web: これまで通りindex.htmlを直接編集 → main pushでPages反映
  - ネイティブ確認: `npm run sync` → `npx cap open ios` → Xcodeで実行
  - リリース時はweb反映とアプリ更新が独立である点を明記

## 2. index.htmlの最小変更(2箇所)

```js
const NATIVE = location.protocol === 'capacitor:';
```
を定数として追加した上で:

1. **パスワードリセットのredirectTo**: ネイティブ時は本番URL固定。
   `redirectTo: NATIVE ? 'https://yvk26yvk-dot.github.io/tsumiki/' : location.origin+location.pathname.replace(/index\.html$/,'')`
   ネイティブでのリセットの流れ: アプリで送信 → メールのリンクがSafariで
   本番PWAを開く → そこで新パスワードを設定 → アプリに戻り新パスワードで
   ログイン。(capacitor://はメールリンクの戻り先にできないため)
2. **SW登録のガード**: `if('serviceWorker' in navigator && !NATIVE)` に変更。

それ以外のWebコードは無変更(viewport-fit=cover+env()のセーフエリア対応済み、
認証・同期・uid照合・削除はcapacitor://ドメインのlocalStorageでそのまま動く)。
ネイティブとPWAはlocalStorageが別空間になるが、初回ログイン時のbootSyncプルで
クラウドから全件復元されるため問題ない(uid照合も通常通り機能)。

## 3. Xcodeプロジェクトと署名

- 前提確認済み: Xcode 26.6 / Node v25 / npm 11。CocoaPods未導入
- `npx cap add ios` — Capacitor 7のSwift Package Manager方式を優先し、
  不調ならCocoaPods(Homebrew経由でインストール)にフォールバック
- アイコン: `@capacitor/assets` で既存 `icon-512.png` から全サイズ生成
  (本来1024px推奨。イラスト発注後の差し替え前提の暫定)。
  スプラッシュ: 背景 `#FBF4EF` + アイコン中央配置
- Xcode GUI(ユーザー操作): Signing & Capabilities で登録済みDeveloper
  アカウントのチームを選択。Display Name「コウテイちゃん」を確認
- 追加権限なし(カメラ・位置情報等は使わない)。Info.plistはほぼ生成のまま

## 4. 検証(完了条件)

1. シミュレーター: 起動 → ログイン → 日次保存 → Table Editorに反映 → アプリ再起動で復元
2. シミュレーターまたは実機のオフライン(機内モード)で起動・保存 → 復帰で自動同期
3. 実機iPhone: 1と同様+ホーム画面アイコン・スプラッシュ・セーフエリア(ノッチ/ホームバー周りの見た目)
4. パスワードリセット一巡: アプリから送信 → メールリンクがSafariで本番PWAを開く → 再設定 → アプリで新パスワードログイン
5. ログアウト・アカウント削除がネイティブでも動く
6. PWA版と同一アカウントで記録が相互に見える(ネイティブで保存→PWAで表示、逆も)

## スコープ外

- プッシュ通知(次スペック。Capability追加・APNs・Supabase側の仕組みを含む)
- TestFlight配布・App Store Connect登録(プッシュ通知後にまとめて)
- Live Updates(Capgo等のOTA更新)— 必要になったら検討
- アイコン/スプラッシュの最終アセット(イラスト発注後)
- Sign in with Apple(提出前の認証拡張として別途)
