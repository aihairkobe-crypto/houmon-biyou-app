-- ============================================================
--  STEP8：X（旧Twitter）自動投稿
--  x_settings（毎日の自動投稿の設定）と x_posts（投稿キュー・履歴）
--  Supabase → SQL Editor に貼って「Run」を1回。何度実行しても安全です。
-- ============================================================

create extension if not exists pgcrypto;

-- 毎日の自動投稿の設定（1組織につき1行）
create table if not exists public.x_settings (
  org_id     uuid primary key references public.orgs(id) on delete cascade,
  enabled    boolean not null default false,          -- 毎日の自動投稿ON/OFF
  post_time  time    not null default '09:00',         -- 何時に投稿するか（tzの時刻）
  tz         text    not null default 'Asia/Tokyo',
  templates  jsonb   not null default '[]'::jsonb,      -- 文例（この中から順番に投稿）
  next_index int     not null default 0,                -- 次に使う文例の番号
  last_auto_date date,                                  -- 最後に自動投稿した日（二重投稿防止）
  updated_at timestamptz default now()
);

-- 投稿キュー＆履歴（今すぐ投稿・予約投稿・自動投稿すべてここに残る）
create table if not exists public.x_posts (
  id           uuid primary key default gen_random_uuid(),
  org_id       uuid references public.orgs(id) on delete cascade,
  body         text not null,
  status       text not null default 'queued',   -- queued（予約待ち）| posted（投稿済）| failed（失敗）| canceled（取消）
  source       text not null default 'manual',   -- manual（手動）| scheduled（予約）| auto（毎日自動）
  scheduled_at timestamptz,                       -- 予約投稿の予定時刻
  posted_at    timestamptz,
  tweet_id     text,
  error        text,
  created_at   timestamptz default now()
);
create index if not exists x_posts_org_idx on public.x_posts(org_id, created_at desc);
create index if not exists x_posts_due_idx on public.x_posts(status, scheduled_at);

-- 行レベル権限（自分の組織の分だけ見える・触れる）
alter table public.x_settings enable row level security;
alter table public.x_posts    enable row level security;

drop policy if exists x_settings_all on public.x_settings;
create policy x_settings_all on public.x_settings for all
  using (org_id = public.my_org()) with check (org_id = public.my_org());

drop policy if exists x_posts_all on public.x_posts;
create policy x_posts_all on public.x_posts for all
  using (org_id = public.my_org()) with check (org_id = public.my_org());


-- ============================================================
--  （任意）毎日の自動投稿を「アプリを閉じていても」動かす設定
--  Edge Function「x-post」をデプロイし、下の <PROJECT_REF> と
--  <CRON_SECRET> を自分の値に置き換えてから、この2文を実行します。
--  ・<PROJECT_REF>  … SupabaseのURL https://xxxx.supabase.co の xxxx 部分
--  ・<CRON_SECRET>  … Edge Functionに設定した X_CRON_SECRET と同じ文字列
--  ※置き換えずにそのまま実行しても、上のテーブル作成には影響しません。
-- ============================================================
-- create extension if not exists pg_cron;
-- create extension if not exists pg_net;
--
-- select cron.schedule('x-auto-post', '*/15 * * * *', $$
--   select net.http_post(
--     url     := 'https://<PROJECT_REF>.supabase.co/functions/v1/x-post',
--     headers := jsonb_build_object('Content-Type','application/json','x-cron-secret','<CRON_SECRET>'),
--     body    := jsonb_build_object('action','run')
--   );
-- $$);
--
-- 停止したいとき： select cron.unschedule('x-auto-post');


-- 確認：実行後、テーブルができていればOK
-- select table_name from information_schema.tables
--   where table_schema='public' and table_name in ('x_settings','x_posts');
