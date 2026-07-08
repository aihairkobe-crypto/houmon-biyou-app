-- ============================================================
-- 設定のクラウド同期（屋号/振込先/登録番号/料金表/枠/色/時間単位）
-- profiles.settings(jsonb) に保存 → どの端末でも同じ設定・請求書の発行者欄が出る
-- Supabase → SQL Editor に貼って1回だけ実行してください（何度実行しても安全）
-- ============================================================

-- ① 設定を入れる列を追加（無ければ作る）
alter table public.profiles
  add column if not exists settings jsonb;

-- ② 自分のprofileを更新できるように（設定の書き込みに必要）。既にあれば作り直し
drop policy if exists profiles_self_update on public.profiles;
create policy profiles_self_update on public.profiles
  for update
  using (id = auth.uid())
  with check (id = auth.uid());

-- 確認：実行後、profiles に settings 列があればOK
-- select column_name from information_schema.columns
--   where table_schema='public' and table_name='profiles' and column_name='settings';
