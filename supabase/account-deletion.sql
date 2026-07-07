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
