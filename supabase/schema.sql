-- =====================================================================
-- コウテイちゃん (tsumiki) — Supabase スキーマ v1
-- Supabase ダッシュボードの SQL Editor に全文貼り付けて Run する。
--
-- 設計方針:
--   * daily / weekly のエントリ本体は jsonb 1カラムに保存する。
--     localStorage の形 (q1_done, q2_tags, pillars, goods...) をそのまま
--     入れられるので、store層の差し替えが最小になり、UIは無変更で済む。
--     質問項目を将来変えてもテーブル定義の変更が不要。
--   * キーは localStorage と同じ: daily は 'YYYY-MM-DD'、weekly は 'WYYYY-MM-DD'。
--   * 約束 (kotei.promise.v1) は profiles.promise に持つ。
--   * すべて on delete cascade。auth のユーザーを消せば記録も消える
--     (アカウント削除機能=Apple審査要件 の土台)。
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. profiles — 1行 = 1ユーザー。約束と作成日時。
-- ---------------------------------------------------------------------
create table public.profiles (
  id         uuid primary key references auth.users (id) on delete cascade,
  promise    text not null default '',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- サインアップと同時に profiles 行を自動作成する
create function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.profiles (id) values (new.id);
  return new;
end;
$$;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- ---------------------------------------------------------------------
-- 2. daily — 日次チェック。1行 = 1ユーザー × 1日。
--    entry 例: {"q1_done":true,"q2_tags":["優しかった"],"q3_pick":0,
--               "q4_note":"料理した","q5_done":false,"q6_done":true}
-- ---------------------------------------------------------------------
create table public.daily (
  user_id  uuid not null references auth.users (id) on delete cascade,
  date_key date not null,                -- 'YYYY-MM-DD' がそのまま入る
  entry    jsonb not null,
  saved_at timestamptz not null default now(),
  primary key (user_id, date_key)
);

-- ---------------------------------------------------------------------
-- 3. weekly — 週次チェック。1行 = 1ユーザー × 1週。
--    week_key は既存キーそのまま 'W' + 週の月曜日 (例 'W2026-06-29')。
--    entry 例: {"pillars":{"仕事":4,...},"pmemos":{...},"goods":["..."]}
-- ---------------------------------------------------------------------
create table public.weekly (
  user_id  uuid not null references auth.users (id) on delete cascade,
  week_key text not null check (week_key ~ '^W\d{4}-\d{2}-\d{2}$'),
  entry    jsonb not null,
  saved_at timestamptz not null default now(),
  primary key (user_id, week_key)
);

-- ---------------------------------------------------------------------
-- 4. Row Level Security — 「本人しか自分の記録を読めない」
--    anon キーはクライアントに公開されるが、RLS があるので
--    ログイン済み本人の行にしかアクセスできない。
-- ---------------------------------------------------------------------
alter table public.profiles enable row level security;
alter table public.daily    enable row level security;
alter table public.weekly   enable row level security;

create policy "own profile"
  on public.profiles for all
  using ((select auth.uid()) = id)
  with check ((select auth.uid()) = id);

create policy "own daily"
  on public.daily for all
  using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);

create policy "own weekly"
  on public.weekly for all
  using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);
