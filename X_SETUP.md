# X（旧Twitter）自動投稿 セットアップ手順

作成: 2026-07-17 ／ 対象アカウント: **@ihair_kobe**

このアプリから **X（旧Twitter）へ自動で投稿**できるようにする手順です。
むずかしいプログラムの知識は要りません。**コピペ**でできます（合計30〜40分）。

---

## この機能でできること

- アプリの「⚙️設定 → 📣 X（旧Twitter）自動投稿」から
  - **今すぐ投稿**（文例をタップ → ボタン1つ）
  - **日時を決めて予約投稿**
  - **毎日決まった時刻に自動投稿**（文例を上から順番に）
- 文章は、いまの @ihair_kobe のテイスト（温かい一言＋ハッシュタグ）の**文例をあらかじめ用意**済み。編集も自由。

> 投稿にはお客様の名前など個人情報は一切含みません（実績は「本日◯名さま」の件数だけ）。

---

## 準備は3つ（＋任意で1つ）

| | やること | 場所 | 目安 |
|--|----------|------|------|
| A | XのAPIキーを取る | X Developer Portal | 15分 |
| B | 保存用のテーブルを作る | Supabase（SQL） | 3分 |
| C | 投稿の窓口（関数）を置く＋キーを登録 | Supabase（Edge Functions） | 15分 |
| D | （任意）閉じてても自動投稿する | Supabase（SQL） | 5分 |

---

## STEP A：XのAPIキーを取る

1. https://developer.x.com/ に @ihair_kobe でログイン
2. **「Sign up for Free Account」**（無料。月1,500投稿まで）を作成。用途の説明欄には英語で数百文字必要です。例:
   > I use the X API to post updates about my mobile hair salon business (schedules, announcements) automatically from my own management app. Only my own account will post. No data collection.
3. 作成できたら **Projects & Apps** → 自分のApp を開く
4. **User authentication settings** を開き、
   - **App permissions** を **「Read and write」** に変更（← ここ重要。投稿に必須）
   - Type of App は「Web App / Automated App or bot」でOK
   - Callback URL / Website URL は自分のサイト（無ければ `https://ihair-kobe.example.com` など仮でも可）
   - 保存
5. **Keys and tokens** タブで、次の**4つ**を発行してメモ（画面を離れると再表示できないので必ずコピー）:
   - **API Key**（＝Consumer Key）
   - **API Key Secret**（＝Consumer Secret）
   - **Access Token**
   - **Access Token Secret**

> ⚠️ 権限を「Read and write」にする前に発行したAccess Tokenは「読み取り専用」です。権限を変えたら、Access Token / Secret を**作り直して（Regenerate）**ください。

---

## STEP B：保存用テーブルを作る（Supabase）

1. Supabase のプロジェクトを開く → 左メニュー **SQL Editor**
2. このリポジトリの **`sql/supabase_step8_xposts.sql`** の中身を全部貼り付け
3. **Run** を押す（`x_settings` と `x_posts` ができます。何度実行しても安全）

---

## STEP C：投稿の窓口（Edge Function）を置く

キーをブラウザに出さず安全に投稿するため、Supabase側に小さな関数を1つ置きます。

### C-1. 関数を作る
1. Supabase 左メニュー **Edge Functions** → **Create a function**
2. 名前を **`x-post`** にする
3. コード欄に、このリポジトリの **`supabase/functions/x-post/index.ts`** の中身を全部貼り付け
4. **Deploy**

> CLIが使える方は `supabase functions deploy x-post` でもOKです。

### C-2. キー（Secrets）を登録
Edge Functions → **x-post** → **Secrets（環境変数）** に、STEP Aの4つ＋合言葉を登録:

| 名前 | 値 |
|------|-----|
| `X_API_KEY` | API Key |
| `X_API_SECRET` | API Key Secret |
| `X_ACCESS_TOKEN` | Access Token |
| `X_ACCESS_SECRET` | Access Token Secret |
| `X_CRON_SECRET` | 自分で決める長い文字列（例: `ihair-9f3k2j...`）※STEP Dで使う |

> `SUPABASE_URL` と `SUPABASE_SERVICE_ROLE_KEY` は最初から入っています（登録不要）。

### C-3. 動作確認
アプリ →「⚙️設定 → 📣 X（旧Twitter）自動投稿」→ 文例をタップ →**「今すぐ投稿」**。
@ihair_kobe に投稿されれば成功です 🎉

---

## STEP D：（任意）アプリを閉じていても自動投稿する

STEP CまででもOKですが、その場合 **毎日自動・予約投稿は「アプリを開いた時」に処理**されます。
アプリを開かなくても投稿したい場合は、Supabaseに15分ごとの見張り番を置きます。

1. Supabase **SQL Editor** を開く
2. `sql/supabase_step8_xposts.sql` の下半分にある **コメントアウトされた cron 設定**を使います。
   `--` を外し、次の2か所を自分の値に置き換えて実行:
   - `<PROJECT_REF>` … あなたのSupabase URL `https://xxxx.supabase.co` の **xxxx** の部分
   - `<CRON_SECRET>` … STEP C-2で決めた **X_CRON_SECRET と同じ文字列**

```sql
create extension if not exists pg_cron;
create extension if not exists pg_net;

select cron.schedule('x-auto-post', '*/15 * * * *', $$
  select net.http_post(
    url     := 'https://<PROJECT_REF>.supabase.co/functions/v1/x-post',
    headers := jsonb_build_object('Content-Type','application/json','x-cron-secret','<CRON_SECRET>'),
    body    := jsonb_build_object('action','run')
  );
$$);
```

- 止めたいとき: `select cron.unschedule('x-auto-post');`

---

## アプリの使い方

**⚙️設定 → 📣 X（旧Twitter）自動投稿**

- **投稿する文章**: 直接入力、または下の**テイスト文例をタップ**。「📊 本日の実績から文章を作る」で件数入りの文章も作れます。
- **今すぐ投稿** / **日時を決めて予約**
- **毎日の自動投稿**: チェックを入れて時刻を決め「保存」。文例を上から順番に、毎日1回投稿します。
- **文例を編集**: 1行＝1つの文例。自由に追加・書き換えできます。
- **最近の投稿**: 状態（投稿済／予約待ち／失敗）と履歴が見えます。予約は取消も可能。

---

## うまくいかない時

| 症状 | 原因と対処 |
|------|-----------|
| 「投稿窓口に接続できません」 | STEP C（関数のデプロイ）が未完了。関数名が `x-post` か確認 |
| 「X API 401」/ 403 | キーの打ち間違い、または権限が「Read」のまま。**Read and write** にしてAccess Tokenを再発行 |
| 「X API 403 ...duplicate...」 | 同じ本文は連続投稿できません（Xの仕様）。文面を変えてください |
| 「本文が空です」 | 文章を入力してください |
| 毎日自動が動かない | 時刻を過ぎているか／その日は投稿済みか確認。閉じていても投稿したいなら STEP D を設定 |

分からないところは、板谷までこの画面のスクショを送ってください。
