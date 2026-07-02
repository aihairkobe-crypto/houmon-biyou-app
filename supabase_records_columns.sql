-- ============================================================
--  施術記録(records)に必要な列をまとめて追加（まだの分をここで一括）
--  Supabase の SQL Editor に貼り付けて Run（1回・既にあってもOK）
--   - member_name : 利用者/お客様の名前（施設の名簿が変わっても実績に名前を残す）
--   - place_kind  : 訪問区分（在宅／施設／病院）
-- ============================================================

alter table public.records add column if not exists member_name text;
alter table public.records add column if not exists place_kind  text;

-- PostgREST のスキーマキャッシュを即時更新
notify pgrst, 'reload schema';
