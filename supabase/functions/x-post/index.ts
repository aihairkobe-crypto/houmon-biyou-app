// ============================================================
//  Supabase Edge Function: x-post
//  X（旧Twitter）へOAuth 1.0aで投稿する窓口。
//  APIキーはブラウザに出さず、ここ（サーバー側）で秘密に保管します。
//
//  必要なシークレット（Supabase → Edge Functions → x-post → Secrets）:
//    X_API_KEY / X_API_SECRET / X_ACCESS_TOKEN / X_ACCESS_SECRET
//    X_CRON_SECRET               … 毎日自動の定期実行を守る合言葉（任意の長い文字列）
//    SUPABASE_URL / SUPABASE_SERVICE_ROLE_KEY … 自動で入っています
//
//  受け付ける動作（POST JSON）:
//    { "action":"post", "text":"本文" }  … 今すぐ投稿（アプリのログインが必要）
//    { "action":"run" }                  … 予約投稿＋毎日自動の処理（cronが叩く）
// ============================================================
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

// --- OAuth 1.0a 署名（HMAC-SHA1）---
function pe(s: string): string {
  return encodeURIComponent(s).replace(/[!*'()]/g, (c) => "%" + c.charCodeAt(0).toString(16).toUpperCase());
}
async function hmacSha1(key: string, msg: string): Promise<string> {
  const k = await crypto.subtle.importKey(
    "raw",
    new TextEncoder().encode(key),
    { name: "HMAC", hash: "SHA-1" },
    false,
    ["sign"],
  );
  const sig = await crypto.subtle.sign("HMAC", k, new TextEncoder().encode(msg));
  return btoa(String.fromCharCode(...new Uint8Array(sig)));
}

async function postTweet(text: string): Promise<any> {
  const ck = Deno.env.get("X_API_KEY");
  const cs = Deno.env.get("X_API_SECRET");
  const tk = Deno.env.get("X_ACCESS_TOKEN");
  const ts = Deno.env.get("X_ACCESS_SECRET");
  if (!ck || !cs || !tk || !ts) {
    throw new Error("XのAPIキーが未設定です（Edge FunctionのSecretsを確認してください）");
  }
  const url = "https://api.twitter.com/2/tweets";
  const oauth: Record<string, string> = {
    oauth_consumer_key: ck,
    oauth_nonce: crypto.randomUUID().replace(/-/g, ""),
    oauth_signature_method: "HMAC-SHA1",
    oauth_timestamp: Math.floor(Date.now() / 1000).toString(),
    oauth_token: tk,
    oauth_version: "1.0",
  };
  // JSONボディの投稿では、署名対象はoauth_*パラメータのみ（クエリ・フォーム値なし）
  const paramStr = Object.keys(oauth).sort().map((k) => pe(k) + "=" + pe(oauth[k])).join("&");
  const base = "POST&" + pe(url) + "&" + pe(paramStr);
  const signingKey = pe(cs) + "&" + pe(ts);
  oauth.oauth_signature = await hmacSha1(signingKey, base);
  const header = "OAuth " + Object.keys(oauth).sort().map((k) => pe(k) + '="' + pe(oauth[k]) + '"').join(", ");

  const res = await fetch(url, {
    method: "POST",
    headers: { "Authorization": header, "Content-Type": "application/json" },
    body: JSON.stringify({ text }),
  });
  const data = await res.json().catch(() => ({}));
  if (!res.ok) {
    const detail = data?.detail || data?.title || JSON.stringify(data);
    throw new Error("X API " + res.status + ": " + detail);
  }
  return data; // { data: { id, text } }
}

// --- tz の現在の日付/時刻（"YYYY-MM-DD" / "HH:MM"）---
function localParts(tz: string): { date: string; hm: string } {
  const fmt = new Intl.DateTimeFormat("en-CA", {
    timeZone: tz,
    year: "numeric", month: "2-digit", day: "2-digit",
    hour: "2-digit", minute: "2-digit", hour12: false,
  });
  const p: Record<string, string> = {};
  for (const part of fmt.formatToParts(new Date())) p[part.type] = part.value;
  return { date: `${p.year}-${p.month}-${p.day}`, hm: `${p.hour}:${p.minute}` };
}

const SB_URL = Deno.env.get("SUPABASE_URL")!;
const SB_SERVICE = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const CRON_SECRET = Deno.env.get("X_CRON_SECRET") || "";

const cors: Record<string, string> = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type, x-cron-secret",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};
function json(obj: unknown, status = 200): Response {
  return new Response(JSON.stringify(obj), { status, headers: { ...cors, "Content-Type": "application/json" } });
}

// 予約投稿＋毎日自動の処理。scopeOrg 指定時はその組織だけ（アプリからの手動キック用）
async function runQueueAndAuto(admin: any, scopeOrg: string | null) {
  const nowIso = new Date().toISOString();
  let posted = 0, failed = 0, autoPosted = 0;

  // ① 予約投稿：期限が来た queued を投稿
  let dueQ = admin.from("x_posts").select("*").eq("status", "queued").lte("scheduled_at", nowIso);
  if (scopeOrg) dueQ = dueQ.eq("org_id", scopeOrg);
  const { data: due } = await dueQ;
  for (const row of (due || [])) {
    try {
      const r = await postTweet(row.body);
      await admin.from("x_posts").update({
        status: "posted", posted_at: new Date().toISOString(), tweet_id: r?.data?.id ?? null,
      }).eq("id", row.id);
      posted++;
    } catch (e) {
      await admin.from("x_posts").update({ status: "failed", error: String(e) }).eq("id", row.id);
      failed++;
    }
  }

  // ② 毎日自動：時刻を過ぎていて、まだ今日投稿していない組織
  let setQ = admin.from("x_settings").select("*").eq("enabled", true);
  if (scopeOrg) setQ = setQ.eq("org_id", scopeOrg);
  const { data: sets } = await setQ;
  for (const s of (sets || [])) {
    const tpls: string[] = Array.isArray(s.templates) ? s.templates.filter((t: string) => (t || "").trim()) : [];
    if (!tpls.length) continue;
    const { date, hm } = localParts(s.tz || "Asia/Tokyo");
    const target = String(s.post_time || "09:00").slice(0, 5);
    if (hm < target) continue;                 // まだ時刻前
    if (s.last_auto_date === date) continue;    // 今日はもう投稿済み
    const idx = ((s.next_index || 0) % tpls.length + tpls.length) % tpls.length;
    const body = tpls[idx];
    try {
      const r = await postTweet(body);
      await admin.from("x_posts").insert({
        org_id: s.org_id, body, status: "posted", source: "auto",
        posted_at: new Date().toISOString(), tweet_id: r?.data?.id ?? null,
      });
      await admin.from("x_settings").update({
        next_index: idx + 1, last_auto_date: date, updated_at: new Date().toISOString(),
      }).eq("org_id", s.org_id);
      autoPosted++;
    } catch (e) {
      await admin.from("x_posts").insert({
        org_id: s.org_id, body, status: "failed", source: "auto", error: String(e),
      });
      failed++;
    }
  }
  return { posted, autoPosted, failed };
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (req.method !== "POST") return json({ error: "POSTのみ対応です" }, 405);

  try {
    const body = await req.json().catch(() => ({}));
    const action = body.action || "post";
    const admin = createClient(SB_URL, SB_SERVICE);

    if (action === "post") {
      const jwt = (req.headers.get("Authorization") || "").replace("Bearer ", "");
      const { data: { user } } = await admin.auth.getUser(jwt);
      if (!user) return json({ error: "ログインが必要です" }, 401);
      const { data: prof } = await admin.from("profiles").select("org_id").eq("id", user.id).single();
      const org_id = prof?.org_id ?? null;

      const text = (body.text ?? "").toString().trim();
      if (!text) return json({ ok: false, error: "本文が空です" });
      if ([...text].length > 280) return json({ ok: false, error: "280文字を超えています" });

      try {
        const r = await postTweet(text);
        const id = r?.data?.id ?? null;
        await admin.from("x_posts").insert({
          org_id, body: text, status: "posted", source: "manual",
          posted_at: new Date().toISOString(), tweet_id: id,
        });
        return json({ ok: true, tweet_id: id, url: id ? ("https://x.com/i/web/status/" + id) : null });
      } catch (e) {
        // 投稿失敗（XのAPIキー未設定・権限不足など）も履歴に残し、原因をアプリへ返す
        await admin.from("x_posts").insert({ org_id, body: text, status: "failed", source: "manual", error: String(e) });
        return json({ ok: false, error: String(e) });
      }
    }

    if (action === "run") {
      // cronの合言葉が一致すれば全組織を処理。無ければユーザーの組織だけ（アプリからのキック）
      let scopeOrg: string | null = null;
      const secret = req.headers.get("x-cron-secret") || "";
      if (!(CRON_SECRET && secret === CRON_SECRET)) {
        const jwt = (req.headers.get("Authorization") || "").replace("Bearer ", "");
        const { data: { user } } = await admin.auth.getUser(jwt);
        if (!user) return json({ error: "unauthorized" }, 401);
        const { data: prof } = await admin.from("profiles").select("org_id").eq("id", user.id).single();
        scopeOrg = prof?.org_id ?? null;
        if (!scopeOrg) return json({ error: "組織が見つかりません" }, 400);
      }
      const summary = await runQueueAndAuto(admin, scopeOrg);
      return json({ ok: true, ...summary });
    }

    return json({ error: "不明なaction: " + action }, 400);
  } catch (e) {
    return json({ error: String(e) }, 500);
  }
});
