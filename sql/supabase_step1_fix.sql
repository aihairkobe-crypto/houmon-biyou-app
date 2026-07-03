-- ============================================================
--  STEP1 修正：組織作成/参加を「関数」で安全に行う（RLSの初期化問題を回避）
--  Supabase の SQL Editor に貼り付けて Run してください
-- ============================================================

-- 組織を作って、自分を運営(owner)として登録（security definer で安全に一括処理）
create or replace function public.create_org_and_join(org_name text, display_name text)
returns uuid language plpgsql security definer set search_path = public as $$
declare new_org uuid;
begin
  insert into public.orgs(name) values (coalesce(nullif(org_name,''),'組織')) returning id into new_org;
  insert into public.profiles(id, org_id, name, role)
    values (auth.uid(), new_org, display_name, 'owner')
    on conflict (id) do update set org_id = excluded.org_id, name = excluded.name, role = 'owner';
  return new_org;
end $$;

-- 組織コードで参加して、自分をメンバー(member)として登録
create or replace function public.join_org(code uuid, display_name text)
returns void language plpgsql security definer set search_path = public as $$
begin
  insert into public.profiles(id, org_id, name, role)
    values (auth.uid(), code, display_name, 'member')
    on conflict (id) do update set org_id = excluded.org_id, name = excluded.name;
end $$;

grant execute on function public.create_org_and_join(text,text) to authenticated;
grant execute on function public.join_org(uuid,text) to authenticated;
