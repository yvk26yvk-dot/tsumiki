# Supabase store層差し替え 設計書

日付: 2026-07-06
対象: 第二段階タスク2「store層の差し替え + localStorageからのデータ移行導線」

## 決定事項(ユーザー承認済み)

| 論点 | 決定 |
|---|---|
| ログイン方針 | ログイン必須(未ログインなら認証画面) |
| 認証方式 | メール+パスワード(Sign in with AppleはCapacitor化の段階で追加) |
| 移行導線 | 初回ログイン時に自動移行。完了時にコウテイちゃんが一度だけ報告 |
| オフライン | ローカル即保存+アウトボックス経由でバックグラウンド同期 |
| 実現方式 | 案A: ローカルファースト(localStorage=キャッシュ、Supabase=同期先) |

## 前提

- DBスキーマは `supabase/schema.sql` で作成済み(profiles / daily / weekly、jsonb entry、RLS有効)。
- Project URL: `https://zfntwysyrioqxznlhxhm.supabase.co`
- Publishable key: `sb_publishable_OKH_JjMgl8814Xye_3QhwQ_q4JBxa1K`
  (RLS前提でクライアント公開が正規の使い方。service_roleキーは使わない)
- 「store層の中身だけ差し替え、UIは触らない」原則を厳守する。UIから見える
  API(`getDaily`/`saveDaily`/`recentDaily`/`getWeekly`/`saveWeekly`/`_r`直読み)は
  同期のまま完全互換。

## アーキテクチャ

```
UI(無変更) ──同期呼び出し──> store層
                              ├─ localStorage (kotei.daily.v1 / kotei.weekly.v1)  ← 読み書きの主役
                              └─ outbox (kotei.outbox.v1) ──非同期upsert──> Supabase
起動時: Supabase ──全件プル──> localStorage を更新(キュー内キーはローカル優先)
```

## 1. 起動フローと認証UI

- supabase-js v2 UMD を jsDelivr からバージョン固定の `<script>` 1本で読み込む
  (ビルド工程なし維持。sw.jsのcache-firstで2回目以降はオフラインでも読める)。
- URL/キーは index.html に定数として直書き。
- 起動シーケンス:
  1. `sb.auth.getSession()` でセッション確認
  2. なし → 新設 `view-auth` を表示。ナビ(タブバー)は隠す
  3. あり → `bootSync()`: クラウド全件プル → localStorage更新 → outboxをflush
     → 従来どおり `renderDaily()`
  4. プル失敗(オフライン起動)はローカルキャッシュのまま起動
- `view-auth`: コウテイちゃん画像+「おかえり。あなたの記録、ここで待ってるよ」
  トーン。メール・パスワード入力、「新規登録/ログイン」切り替え。
  認証エラーもコウテイちゃん口調(例:「メールかパスワードが違うみたい」)。
  メール確認が有効な場合は「確認メールを送ったよ」状態を表示。
- ログアウト: 「きろく」ページ最下部に小さなリンク。実行時はsignOutと同時に
  koteiのlocalStorageキャッシュを消去(共有端末対策)。outboxに未送信が残って
  いれば警告してから。
- Supabase側設定: Authentication → URL Configuration の Site URL に
  `https://yvk26yvk-dot.github.io/tsumiki/` を設定。開発用に
  `http://localhost:8000` をRedirect URLsへ追加。

## 2. store層の差し替え・同期・移行

- **書き**: `saveDaily(d,e)` → localStorage即保存(現行同様) → outboxにキー
  `{t:'daily', k:d}` を積む → `flush()` を非同期で呼ぶ。weekly・約束も同型。
- **outbox** (`kotei.outbox.v1`): 未送信キーの配列。flushは各キーの現在の
  ローカル値を読んでupsert(`onConflict: user_id,date_key` / `user_id,week_key`)、
  成功したら除去。値でなくキーを積むので、同じキーへの連続保存は自然に
  最後の値だけが送られる。
- **flushのタイミング**: 保存直後 / `window`の`online`イベント / 起動時プル後。
  失敗は静かにキューへ残す(次の機会に再送)。
- **プル時のマージ規則**: outboxにあるキーはローカル優先(未送信=最新)。
  それ以外はクラウド値でローカルを上書き。
- **移行**: プル後、「ローカルにあってクラウドにないキー」をoutboxへ積む。
  この規則だけで初回移行と日常のオフライン復帰が同じコードで動く。
  初回アップロード完了時のみ(`kotei.migrated.v1`フラグで一度だけ)
  コウテイちゃんが「これまでの記録、クラウドでちゃんと預かったよ」と報告。
- **約束**: `setPromiseVal` → ローカル即書き+outbox `{t:'profile'}` →
  `profiles.promise` へupsert。プル時は `profiles.promise` からローカルへ。
- 複数端末の同時使用は現時点で対象外(1ユーザー1端末)。将来は`savedAt`比較で
  新しい方優先に拡張。

## 3. sw.js・エラー処理

- fetchハンドラ冒頭で、リクエスト先ホストが `*.supabase.co` なら素通し
  (キャッシュしない)。これを怠るとAPI応答がcache-firstで永久キャッシュされる。
- `CACHE` を `kotei-v4` に上げる(index.html更新のため)。
- エラー処理方針: 同期失敗はサイレント(キュー残留で自動リトライ)。
  認証失敗のみユーザーに見せる(コウテイちゃん口調)。

## 4. 検証手順(完了条件)

ローカルHTTPサーバー(`python3 -m http.server 8000`)+実プロジェクトで:

1. 新規登録 → ログインできる
2. 日次保存 → Supabase Table Editor に行が現れる
3. リロード → 記録が復元される
4. DevToolsオフライン → 保存できる → オンライン復帰で自動同期される
5. localStorage全消去+再ログイン → クラウドから全件復元される
6. 2つ目のテストアカウントで他人のデータが見えない(RLS確認)

本番の実データ移行: 実記録は本番PWA(GitHub Pages)のlocalStorageにあるため、
mainへpush後、本番でログインした時点で自動移行が走る。

## スコープ外(このタスクではやらない)

- Sign in with Apple(Capacitor化の段階)
- アカウント削除機能(次タスク。DBはon delete cascade済みで土台あり)
- パスワードリセット導線(必要になったら追加)
- kotei層のAI化
