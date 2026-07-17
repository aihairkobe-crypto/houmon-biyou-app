#!/usr/bin/env bash
# ============================================================
#  X（旧Twitter）自動投稿 セットアップ（iMac/MacBook用・ほぼ一発）
#  やること: Xのキーを登録 → Edge Function を配置。
#  事前に1回だけ: Supabaseダッシュボードで sql/supabase_step8_xposts.sql を実行。
#
#  使い方:  bash scripts/setup_x.sh
# ============================================================
set -euo pipefail

REF="dhgjaxhhdyxplnmubmvg"   # このプロジェクトのSupabase project-ref

echo "==============================================="
echo " X（旧Twitter）自動投稿 セットアップ"
echo "==============================================="

# 0) Supabase CLI があるか
if ! command -v supabase >/dev/null 2>&1; then
  echo "❌ Supabase CLI が見つかりません。先に入れてください:"
  echo "     brew install supabase/tap/supabase"
  exit 1
fi

# 1) ログイン確認（未ログインならブラウザでログイン）
if ! supabase projects list >/dev/null 2>&1; then
  echo "▶ Supabaseにログインします（ブラウザが開きます）…"
  supabase login
fi

# 2) テーブル作成の確認（DDLはダッシュボードでの実行が確実）
cat <<'NOTE'

［事前準備の確認］
  Supabase → SQL Editor で  sql/supabase_step8_xposts.sql  を実行しましたか？
  （x_settings と x_posts テーブルを作ります。まだなら、先に実行してください）
NOTE
read -r -p "  実行済みなら Enter で続行（未実行なら Ctrl+C で中断）: " _

# 3) Xの4つのキーを入力（入力は画面に表示されません）
echo
echo "▶ X Developer Portal で取得した4つのキーを入力してください（貼り付けOK・非表示）"
read -rs -p "  X API Key           : " XK;  echo
read -rs -p "  X API Key Secret    : " XS;  echo
read -rs -p "  X Access Token      : " XT;  echo
read -rs -p "  X Access Token Secret: " XTS; echo
if [ -z "${XK}" ] || [ -z "${XS}" ] || [ -z "${XT}" ] || [ -z "${XTS}" ]; then
  echo "❌ 4つすべて必要です。中断しました。"; exit 1
fi

# 4) cron用の合言葉を自動生成（毎日自動を裏で動かす時に使用）
CRON=$(openssl rand -hex 16)

# 5) シークレット登録
echo
echo "▶ キーをSupabaseに安全に登録します…"
supabase secrets set --project-ref "$REF" \
  X_API_KEY="$XK" \
  X_API_SECRET="$XS" \
  X_ACCESS_TOKEN="$XT" \
  X_ACCESS_SECRET="$XTS" \
  X_CRON_SECRET="$CRON" >/dev/null
echo "  ✅ 登録しました"

# 6) Edge Function を配置（cronが叩けるよう JWT検証はオフ。認可は関数内で実施）
echo "▶ 投稿窓口（x-post）を配置します…"
supabase functions deploy x-post --project-ref "$REF" --no-verify-jwt
echo "  ✅ 配置しました"

# 7) 仕上げ案内
cat <<DONE

===============================================
 ✅ 基本セットアップ完了！
===============================================
アプリ →「⚙️設定 → 📣 X（旧Twitter）自動投稿」→ 文例をタップ →「今すぐ投稿」で確認してください。

──［任意：アプリを閉じていても毎日自動投稿する］──
Supabase → SQL Editor に、下のSQLを貼って実行してください（合言葉は自動で埋めてあります）:

  create extension if not exists pg_cron;
  create extension if not exists pg_net;
  select cron.schedule('x-auto-post', '*/15 * * * *', \$\$
    select net.http_post(
      url     := 'https://${REF}.supabase.co/functions/v1/x-post',
      headers := jsonb_build_object('Content-Type','application/json','x-cron-secret','${CRON}'),
      body    := jsonb_build_object('action','run')
    );
  \$\$);

  ※この合言葉(${CRON})は今だけ表示されます。使わなければ気にしなくてOK。
  ※止めたいとき: select cron.unschedule('x-auto-post');
DONE
