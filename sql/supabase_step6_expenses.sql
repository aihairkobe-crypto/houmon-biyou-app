-- ============================================================
--  訪問美容アプリ STEP6：経費（軽めの経費ログ）
--  Supabase の SQL Editor に貼り付けて「Run」してください
--  ※ STEP1 の orgs / my_org() と STEP2 の clients が前提です
-- ============================================================

create table if not exists public.expenses (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null references public.orgs(id) on delete cascade,
  staff_id uuid references auth.users(id) default auth.uid(),
  date date not null,
  amount int default 0,
  category text,                                                   -- 費目（駐車場/ガソリン/備品/その他 など・自由）
  note text,
  client_id uuid references public.clients(id) on delete set null, -- 任意：どの仕事/顧客に紐づくか
  lane text,                                                       -- 任意：枠（訪問枠/サロン枠 など）
  created_at timestamptz default now()
);

alter table public.expenses enable row level security;

-- 自分の組織の経費だけ 全操作可
drop policy if exists expenses_all on public.expenses;
create policy expenses_all on public.expenses for all
  using (org_id = public.my_org())
  with check (org_id = public.my_org());
