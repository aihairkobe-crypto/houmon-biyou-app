-- ============================================================
--  STEP3-A：リアルタイム自動更新（他端末の変更を即反映）
--  Supabase の SQL Editor に貼り付けて Run してください（1回だけ）
--  ※ 既に追加済みでもエラーにならないよう、存在チェック付き
--  ※ RLS が効くので、各メンバーは「自分が見てよい変更」だけ受け取ります
-- ============================================================

do $$
begin
  if not exists (select 1 from pg_publication_tables
      where pubname='supabase_realtime' and schemaname='public' and tablename='bookings') then
    alter publication supabase_realtime add table public.bookings;
  end if;
  if not exists (select 1 from pg_publication_tables
      where pubname='supabase_realtime' and schemaname='public' and tablename='records') then
    alter publication supabase_realtime add table public.records;
  end if;
  if not exists (select 1 from pg_publication_tables
      where pubname='supabase_realtime' and schemaname='public' and tablename='clients') then
    alter publication supabase_realtime add table public.clients;
  end if;
end $$;
