# コウテイちゃん (tsumiki)

自己肯定感を育てる日記アプリ。ペンギンのキャラクター「コウテイちゃん」が、
毎日の記録にあたたかくフィードバックする。個人開発、日本語UI。

## 現在地とゴール
- 第一段階(完了間近): localStorage + PWA。GitHub Pagesで公開中
  - 公開URL: https://yvk26yvk-dot.github.io/tsumiki/
- 第二段階(いまここ): Supabase移行 → Capacitor iOS化 → 課金 → App Store提出
- ポジショニング: 「日記アプリ」(App Storeカテゴリ=ライフスタイル。医療・ヘルスケアにしない)

## アーキテクチャの絶対原則
index.html 内に、意図的に隔離された2つの層がある。**この隔離を壊さないこと。**

1. **store層** (データアクセス): 現在は localStorage。
   Supabase移行時はこのオブジェクトの中身だけを差し替え、UIコードは触らない。
   - `store.getDaily(dateKey)` / `store.saveDaily(dateKey, entry)`
   - `store.recentDaily(n)` / `store.getWeekly(weekKey)` / `store.saveWeekly(weekKey, entry)`
2. **kotei層** (フィードバック生成): 現在はルールベース。
   AI化するときは `kotei.daily(entry)` / `kotei.weekly(weekly, days)` の中身だけを
   API呼び出しに差し替える。呼び出し側は変更しない。
   - AI APIキーは絶対にクライアントに置かない。Supabase Edge Functions を中継する。

## コウテイちゃんの人格(変更禁止の資産)
- あたたかい母性、タメ口
- **できなかった日を絶対に責めない**。全部未入力でも「来ただけで満点だよ」
- タグライン: 「今日のあなたを、ぎゅっと抱きしめる」
- AI化するときは、この人格定義をそのままシステムプロンプトに移植する

## UI/UX原則
- シンプル維持。機能を足すときも画面を複雑にしない
- 日次チェックはスライド式(1問ずつ)。全6問
- ふりかえりタブは「ながめる場所」。週次チェックのフォームはユーザーが
  ボタンを押したときだけ出す(勝手にフォームを出さない)
- 配色: 背景 #FBF4EF / ローズ #E0907F / 若葉 #8FA079 / 金茶 #D8A85E
- キャラ画像: kotei-normal(通常) / kotei-cheer(結果画面) / kotei-care(空状態) / kotei-body(ヘッダー)

## 技術的な決まりごと
- 静的サイト(ビルド工程なし)。index.html にHTML/CSS/JSが同居
- Service Worker (sw.js): HTMLはnetwork-first。**index.htmlを更新したら
  sw.js の CACHE バージョン(kotei-vN)を上げる**
- main への push で GitHub Pages に自動デプロイ(反映まで1〜2分)
- データを保存する localStorage キー: kotei.daily.v1 / kotei.weekly.v1 / kotei.promise.v1
  スキーマを変えるときは必ず既存データの移行処理を書く(ユーザーの記録を消さない)
- ネイティブ(Capacitor)の開発フロー:
  - web側はこれまで通り index.html を直接編集(ビルドなし)。main push で Pages に反映
  - ネイティブ確認は `npm run sync`(www/へ資産コピー+cap sync)→ `npx cap open ios` → Xcodeで実行
  - www/ と node_modules/ は生成物(コミットしない)。ios/ はコミット対象
  - webの更新はPagesに即反映されるが、アプリ内のWebは**アプリ更新まで変わらない**(反映が2系統で独立)
  - sw.js はネイティブに同梱しない(WKWebViewはSW非対応。index.htmlのNATIVEガードで登録もスキップ)

## コミットしてはいけないもの
- APIキー、シークレット類(.env は .gitignore に入れる)
- 事業戦略・マネタイズ関連の文書(ROADMAP等はこのリポジトリの外で管理。ここはPublic)

## 第二段階のタスク順序
1. Supabase セットアップ(Auth: メール + Sign in with Apple / DB / RLS)
2. store層の差し替え + localStorage からのデータ移行導線
3. アカウント削除機能(Apple審査の必須要件)
4. Capacitor で iOS 化 → プッシュ通知
5. IAP(RevenueCat) + AIコウテイちゃん(kotei層のAPI化)
6. App Store 提出

※認証メール(パスワードリセット/確認)は、Supabase無料構成ではテンプレート編集が
  できない(独自SMTPまたはProが必要)ため、**デフォルトの英語文面のまま**。
  App Store提出前に独自SMTP(Resend等)を導入し、日英併記化とあわせて実施する。
  文面案は docs/superpowers/plans/2026-07-10-password-reset.md のTask 3に保存済み。

※将来 app.kouteichan.com へ移すときの更新箇所: index.html内の**NATIVE分岐の
  本番URL固定値**(パスワードリセットのredirectTo)、SupabaseのSite URL /
  Redirect URLs、manifest/OGP類。GitHub PagesのURLをハードコードしている箇所を
  `grep "yvk26yvk-dot.github.io"` で洗い出して一括更新すること。
