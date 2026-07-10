# パスワードリセット導線 + Confirm email ON化 設計書

日付: 2026-07-10
対象: Day 13-14品質日タスク(リリース要件)。Capacitor化の前段。

## 決定事項(ユーザー承認済み)

| 論点 | 決定 |
|---|---|
| 実現方式 | 案A: index.html内で完結(reset.html等の別ページは作らない) |
| リセット手段 | Supabase標準: resetPasswordForEmail → メール内リンク → PASSWORD_RECOVERYイベント → updateUser |
| Confirm email | ONに戻す(リリース要件)。新規登録の「確認メールを送ったよ」表示は実装済み |
| 段取り | この作業と並行してユーザーがXcodeをDL(次フェーズ=Capacitor化の前提) |

## 1. 「パスワードを忘れた?」導線

- ログイン画面(authMode='login'のみ。signupでは非表示)のパスワード欄の下に
  `.linklike` で「パスワードを忘れた?」を追加。タップで `authMode='forgot'`。
- forgotモード: メール入力+「リセットメールを送る」ボタンのみ。
  「ログインにもどる」でloginに戻れる。
- 送信: `sb.auth.resetPasswordForEmail(email, {redirectTo: location.origin+location.pathname.replace(/index\.html$/,'')})`
  ※redirectToは動的に自分自身へ。本番固定にするとローカル検証でメールリンクが
  本番に飛んでしまい検証できないため。ローカル/本番どちらで送っても
  「送った環境の自分」に戻る。`index.html` 末尾の正規化は、インストール済みPWA
  (start_url=./index.html)から送ってもRedirect URLsの登録値と完全一致させるため。
  使用するオリジンはSupabaseのRedirect URLsへの登録が必要(セクション3)。
- エラー文言の例外: メール形式エラー(登録有無と無関係)のみ
  「メールアドレスの形が違うみたい。」を出す。それ以外は一律の汎用文言(列挙対策)。
- 成功時文言: 「メールを送ったよ。届いたリンクから、新しいパスワードを決めてね。」
  ※存在しないメールでもSupabaseは成功を返す仕様のため、この文言のままで
  メール列挙攻撃対策になる(登録有無を推測させない)。
- エラー時(レート制限等): 「すこし時間をおいて、もう一度ためしてみてね。」

## 2. リカバリ着地と新パスワード設定

- 起動時に `sb.auth.onAuthStateChange((event,session)=>{...})` を購読し、
  `PASSWORD_RECOVERY` イベントで view-auth を「新しいパスワード」モードで表示。
- recoveryモード: パスワード入力1つ+「これにする」ボタン。
  `sb.auth.updateUser({password})` 成功 → トースト「あたらしいパスワード、うけとったよ」
  → `enterApp()`(リカバリリンクがセッションを張るため再ログイン不要)。
- エラー(6文字未満等)は既存 `authErrMsg` を流用して表示。
- リカバリセッションからのenterAppは通常ログインと同一経路
  (uid照合ガード・bootSyncは追加対応不要)。
- 堅牢化(最終レビュー反映): 起動時のリカバリ判定は `access_token` と
  `type=recovery` の両方を要求し、イベントが来ない場合は3秒後に通常bootへ
  フォールバック(白画面防止)。リセットリンクの期限切れ
  (`error_code=otp_expired`)はforgotモードで「リンクの期限が切れちゃったみたい。
  もう一度、リセットメールを送ろうね。」を表示。旧パスワードと同一のエラーは
  「まえと同じパスワードみたい。あたらしいのを決めてね。」。

## 3. Supabase設定(ユーザー操作)

- Authentication → Sign In / Providers → Email → **Confirm email をON**
- URL Configuration → Redirect URLs に本番URL
  `https://yvk26yvk-dot.github.io/tsumiki/` があることを確認、
  ローカル検証用に `http://localhost:8080` と `http://127.0.0.1:8080` を追加
  (redirectToが動的なため、検証で使うオリジンはすべて登録が必要)
- 既知事項(スコープ外・メモ): Supabase内蔵メールは時間あたり数通の送信制限が
  ある。App Store公開前に独自SMTP(Resend等)への切り替えを検討する。

### メールテンプレート(日英併記)

標準テンプレートは英語のみのため、Authentication → Email Templates で
**Reset Password(recovery)** と **Confirm signup(confirmation)** の2種を
日英併記に差し替える(ユーザー操作。文面は実装計画に完全版を記載):

- 方針: 本文上段に日本語(コウテイちゃんのトーン・責めない)、下段に英語。
  件名も併記(例: 「【コウテイちゃん】パスワードの再設定 / Reset your password」)。
  リンクは `{{ .ConfirmationURL }}` を使用。
- ユーザーごとの言語出し分けは標準機能に存在しないため、併記が現実解。
  言語別配信は第三段階(多言語対応)で独自SMTP+Send Email Hookとともに検討。

## 4. 検証(完了条件)

sw.jsのCACHEを `kotei-v6` へ上げる。

1. ログイン画面に「パスワードを忘れた?」が出る。signup画面では出ない
2. 送信 → メール受信 → リンク → 新しいパスワード画面 → 設定 → そのままアプリに入る
3. 新パスワードでログインできる。旧パスワードは弾かれる
4. Confirm email ON後、新規登録で確認メールが届き、確認後にログインできる
5. 存在しないメールアドレスでリセット送信 → 同じ成功文言(登録有無が分からない)
6. リセット・確認の両メールが日英併記の文面で届く

## スコープ外

- Capacitor iOS化(次スペック。XcodeのDL完了後)
- 独自SMTP / 言語別の出し分け配信(公開前に別途。文面自体は本スペックで日英併記化する)
- メールアドレス変更機能
