-- ============================================================
--  STEP2：本番データ（顧客・利用者・予約・実績・予約不可・設定）＋権限
--  Supabase の SQL Editor に貼り付けて Run してください
--  ※ STEP1 の orgs / profiles / my_org() / my_role() が前提です
-- ============================================================

-- 顧客先（個人/施設/病院）— 組織で共有
create table if not exists public.clients (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null references public.orgs(id) on delete cascade,
  kind text, name text, address text, phone text, billing text, rules text, memo text,
  price_list jsonb default '[]'::jsonb,
  lat double precision, lng double precision,
  geo_approx boolean default false, geo_fail boolean default false,
  created_at timestamptz default now()
);

-- 利用者（施設の入居者など）— 組織で共有
create table if not exists public.members_t (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null references public.orgs(id) on delete cascade,
  client_id uuid references public.clients(id) on delete cascade,
  name text, kana text, default_menu text, default_price int, staff_id uuid, memo text,
  created_at timestamptz default now()
);

-- 予約（シフト）
create table if not exists public.bookings (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null references public.orgs(id) on delete cascade,
  client_id uuid references public.clients(id) on delete cascade,
  date text, "time" text, duration int, travel_min int default 0, travel int default 0,
  staff_ids uuid[] default '{}'::uuid[],
  source text, memo text, status text default '予定',
  created_at timestamptz default now()
);

-- 実績（売上・カルテ）
create table if not exists public.records (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null references public.orgs(id) on delete cascade,
  booking_id uuid references public.bookings(id) on delete cascade,
  client_id uuid references public.clients(id) on delete cascade,
  member_id uuid,
  staff_id uuid,
  menu text, amount int default 0, note text, photos jsonb default '[]'::jsonb,
  date text, created_at timestamptz default now()
);

-- 予約不可枠（時間単位）
create table if not exists public.time_blocks (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null references public.orgs(id) on delete cascade,
  date text, "time" text, duration int, label text,
  created_at timestamptz default now()
);

-- 組織設定（屋号・営業時間など）1組織1行
create table if not exists public.org_settings (
  org_id uuid primary key references public.orgs(id) on delete cascade,
  biz_name text, reg_number text,
  open_hour numeric default 9, close_hour numeric default 18, slot_min int default 60,
  updated_at timestamptz default now()
);

-- ===== RLS 有効化 =====
alter table public.clients      enable row level security;
alter table public.members_t    enable row level security;
alter table public.bookings     enable row level security;
alter table public.records      enable row level security;
alter table public.time_blocks  enable row level security;
alter table public.org_settings enable row level security;

-- ===== 共有（組織のメンバーは読み書きできる）：顧客・利用者・予約不可 =====
drop policy if exists clients_all on public.clients;
create policy clients_all on public.clients for all using (org_id = public.my_org()) with check (org_id = public.my_org());

drop policy if exists members_all on public.members_t;
create policy members_all on public.members_t for all using (org_id = public.my_org()) with check (org_id = public.my_org());

drop policy if exists tb_all on public.time_blocks;
create policy tb_all on public.time_blocks for all using (org_id = public.my_org()) with check (org_id = public.my_org());

-- ===== 組織設定：閲覧は全員 / 変更は運営のみ =====
drop policy if exists os_read on public.org_settings;
create policy os_read on public.org_settings for select using (org_id = public.my_org());
drop policy if exists os_write on public.org_settings;
create policy os_write on public.org_settings for all
  using (org_id = public.my_org() and public.my_role() = 'owner')
  with check (org_id = public.my_org() and public.my_role() = 'owner');

-- ===== 予約（シフト）：運営=全件 / メンバー=自分が担当の予約だけ =====
drop policy if exists bk_select on public.bookings;
create policy bk_select on public.bookings for select using (
  org_id = public.my_org() and (public.my_role() = 'owner' or auth.uid() = any(staff_ids))
);
drop policy if exists bk_insert on public.bookings;
create policy bk_insert on public.bookings for insert with check (org_id = public.my_org());
drop policy if exists bk_update on public.bookings;
create policy bk_update on public.bookings for update
  using (org_id = public.my_org() and (public.my_role() = 'owner' or auth.uid() = any(staff_ids)))
  with check (org_id = public.my_org());
drop policy if exists bk_delete on public.bookings;
create policy bk_delete on public.bookings for delete
  using (org_id = public.my_org() and (public.my_role() = 'owner' or auth.uid() = any(staff_ids)));

-- ===== 実績（売上・カルテ）：運営=全件 / メンバー=自分の担当分だけ =====
drop policy if exists rc_select on public.records;
create policy rc_select on public.records for select using (
  org_id = public.my_org() and (public.my_role() = 'owner' or staff_id = auth.uid())
);
drop policy if exists rc_insert on public.records;
create policy rc_insert on public.records for insert with check (org_id = public.my_org());
drop policy if exists rc_update on public.records;
create policy rc_update on public.records for update
  using (org_id = public.my_org() and (public.my_role() = 'owner' or staff_id = auth.uid()))
  with check (org_id = public.my_org());
drop policy if exists rc_delete on public.records;
create policy rc_delete on public.records for delete
  using (org_id = public.my_org() and (public.my_role() = 'owner' or staff_id = auth.uid()));
