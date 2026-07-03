-- ============================================================
--  訪問美容アプリ クラウド版 STEP1：組織・役割・権限の土台
--  Supabase の SQL Editor に貼り付けて「Run」してください
-- ============================================================

create extension if not exists pgcrypto;

-- 組織
create table if not exists public.orgs (
  id uuid primary key default gen_random_uuid(),
  name text,
  created_at timestamptz default now()
);

-- プロフィール（auth.users と1:1。役割と所属組織）
create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  org_id uuid references public.orgs(id),
  name text,
  role text not null default 'member',   -- 'owner'（運営）| 'member'（メンバー）
  created_at timestamptz default now()
);

-- デモ用データ（売上の「見え方」を確認するための簡易テーブル）
create table if not exists public.entries (
  id uuid primary key default gen_random_uuid(),
  org_id uuid references public.orgs(id),
  owner_uid uuid references auth.users(id) default auth.uid(),  -- 担当（作成者）
  label text,
  amount int default 0,
  created_at timestamptz default now()
);

-- 自分の org_id / role を返す（security definer で RLS を回避して参照）
create or replace function public.my_org() returns uuid
  language sql stable security definer set search_path = public as $$
  select org_id from public.profiles where id = auth.uid()
$$;
create or replace function public.my_role() returns text
  language sql stable security definer set search_path = public as $$
  select role from public.profiles where id = auth.uid()
$$;

-- RLS（行レベル権限）を有効化
alter table public.orgs     enable row level security;
alter table public.profiles enable row level security;
alter table public.entries  enable row level security;

-- orgs：自分の組織は閲覧可 / 認証ユーザは組織作成可
drop policy if exists orgs_select on public.orgs;
create policy orgs_select on public.orgs for select using (id = public.my_org());
drop policy if exists orgs_insert on public.orgs;
create policy orgs_insert on public.orgs for insert to authenticated with check (true);

-- profiles：自分のは全操作可 / 同じ組織のプロフィールは閲覧可
drop policy if exists profiles_self on public.profiles;
create policy profiles_self on public.profiles for all using (id = auth.uid()) with check (id = auth.uid());
drop policy if exists profiles_org_read on public.profiles;
create policy profiles_org_read on public.profiles for select using (org_id = public.my_org());

-- entries：運営＝組織の全件 / メンバー＝自分のものだけ
drop policy if exists entries_select on public.entries;
create policy entries_select on public.entries for select using (
  org_id = public.my_org() and (public.my_role() = 'owner' or owner_uid = auth.uid())
);
drop policy if exists entries_insert on public.entries;
create policy entries_insert on public.entries for insert to authenticated with check (
  org_id = public.my_org() and owner_uid = auth.uid()
);
drop policy if exists entries_delete on public.entries;
create policy entries_delete on public.entries for delete using (
  org_id = public.my_org() and (public.my_role() = 'owner' or owner_uid = auth.uid())
);
