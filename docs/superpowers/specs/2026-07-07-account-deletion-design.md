# アカウント削除機能 + 設定画面 設計書

日付: 2026-07-07
対象: 第二段階タスク3「アカウント削除機能(Apple審査 5.1.1(v) の必須要件)」

## 決定事項(ユーザー承認済み)

| 論点 | 決定 |
|---|---|
| 導線 | 簡易設定画面を新設(ヘッダー右上の歯車アイコン) |
| 設定画面の項目 | 今回はログアウトとアカウント削除の2つのみ。項目を後から増やしやすい配列駆動の構造にする(通知設定はCapacitor化のとき追加) |
| ログアウト | きろく最下部から設定画面へ移設(きろく側のリンクは削除) |
| 削除の見せ方 | 目立たせない(最下部に小さく淡いリンク)+二段階確認 |
| サーバー側方式 | 案A: Postgres RPC関数(security definer)。Edge Functionは導入しない |
| 同梱修正 | 前回レビュー持ち越しの軽微4件を同じブランチで直す |

## 1. DB: RPC関数

`supabase/account-deletion.sql` を新規作成し、SQL Editorで1回実行する。

```sql
-- 本人のアカウントと全記録を削除する。
-- 呼べるのはログイン済みユーザーのみ。auth.uid()=本人のJWTでしか動かないため、
-- 他人を消すことは構造的に不可能。cascadeで profiles/daily/weekly も消える。
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

クライアントからは `await sb.rpc('delete_user')`。
将来kotei層AI化でEdge Functionsを導入したら、公式Admin API経由に移行してもよい(任意)。

## 2. 設定画面

- ヘッダー右上に歯車アイコンの小ボタンを追加(既存navの3タブは不変)。
  タップで `view-settings` を表示。設定画面には「もどる」ボタンがあり
  「きょう」タブ(`switchView('daily')`)へ戻る。
- 項目は配列駆動:
  ```js
  const SETTINGS_ITEMS=[
    {id:'logout', label:'ログアウト', sub:'記録はクラウドにちゃんと残るよ', fn:doLogout},
    /* Capacitor化で通知設定などをここに追加 */
  ];
  ```
  `renderSettings()` がこの配列をループしてカード行(label+sub+タップ領域)を描画。
- **アカウント削除は配列に入れない**。画面最下部に `.linklike`(小さく・淡色)で
  「アカウントの削除について」を別置きする。
- ログアウト処理は既存 `wireLogout` の中身を `doLogout()` として設定画面へ移設。
  確認ダイアログの文言・未送信警告は現行のまま。きろく最下部のログアウトHTML/配線は削除。

## 3. 削除フロー(二段階確認)

1. **1段目: 説明カード**(view-settings内で切り替え表示)。コウテイちゃんのトーンで
   事実を静かに伝える:
   「アカウントを消すと、いままでの記録はぜんぶ消えて、元に戻せないよ。
   それでもいいか、ゆっくり考えてね。」
   ボタン: 「やめておく」(btn primary・目立つ) / 「削除にすすむ」(btn ghost・控えめ)
2. **2段目: 最終確認** — `confirm('ほんとうに削除する? 記録はすべて消えて、元に戻せないよ。')`
3. 実行: `await sb.rpc('delete_user')` → 成功時:
   - `await sb.auth.signOut({scope:'local'})`(サーバー側セッションはユーザー削除で無効化済み)
   - localStorageの kotei.* 全キー削除(daily/weekly/promise/outbox/migrated/migrating)
   - お別れトースト「ここまで一緒に歩いてくれてありがとう。またいつでも、待ってるね」
   - 2.5秒後 `location.reload()` → ログイン画面
4. エラー時(オフライン・RPC失敗): 説明カード上にコウテイちゃん口調で表示:
   「いまは削除できないみたい。電波のあるところで、もう一度ためしてみてね。」
   **削除はオンライン必須**(ローカルだけ消えてクラウドに記録が残る事故を防ぐ)。
   未送信キューが残っていても削除意思を優先し、追加警告はしない(全削除するため)。

## 4. 同梱する軽微修正(前回最終レビュー持ち越し)

1. **エスケープ3箇所**: renderRecordの `e.q2_tags.join('・')` → `e.q2_tags.map(esc).join('・')`、
   週次柱メモのキー `k` → `esc(k)`、renderWeeklyFormの `sp[p]`(range/val出力) → `esc(...)`
2. **オフラインsignOut**: ログアウト(および削除フロー)の `sb.auth.signOut()` を
   `sb.auth.signOut({scope:'local'})` に変更。オフラインでも確実にローカルセッションを破棄
3. **移行トーストの取り逃し**: bootSyncで移行キーを投入した時点で `kotei.migrating.v1` を
   セットし、トースト条件を「migratingフラグあり・outbox空・migrated未セット」に変更。
   表示後に migrated をセットし migrating を削除。新規ユーザー(移行なし)には出ない
4. **CSS**: `.linklike:disabled{opacity:.5;cursor:default;}` を追加

## 5. 検証(完了条件)

ローカルサーバー+テストアカウント(`yvk26.yvk+del@gmail.com` 等)で:

1. 歯車 → 設定画面が開き、「もどる」で戻れる
2. 設定画面からログアウトできる(未送信警告も従来どおり)。きろく最下部にリンクがないこと
3. テストアカウントで記録を数件保存 → 削除フロー実行 → ログイン画面に戻る
4. Dashboard確認: auth.users から該当ユーザーが消え、daily/weekly/profiles の行もcascade削除
5. 削除済みメールで再度新規登録できる(再入会が塞がれていないこと)
6. オフラインで削除を試みる → エラーメッセージが出て何も消えないこと
7. エスケープ修正: コンソールでdailyのentryに `<b>x</b>` を含むタグ/メモを注入し、
   きろくページで太字にならず文字列として表示されること
8. sw.jsのCACHEを `kotei-v5` に上げる(本番リリース済みv4からの更新のため)

## スコープ外

- Sign in with Apple / パスワードリセット(Day 13-14・リリース要件) / 通知設定 / kotei層AI化
- Edge Functionsの導入(AI化のときに検討)
