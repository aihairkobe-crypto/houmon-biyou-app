# MacBookで作業を続ける手順（2台運用）

コードは全部 GitHub（`aihairkobe-crypto/houmon-biyou-app`）にあります。
どちらのMacでも「pull → 作業 → push」を回せば、いつでも最新を触れます。

---

## ① MacBook 初回だけ（1回きり）

```bash
# 1. GitHubにログイン（未ログインなら）
gh auth login          # github.com / HTTPS / ブラウザ認証 を選ぶ

# 2. リポジトリを取ってくる（置き場所はホーム直下がおすすめ）
cd ~
git clone https://github.com/aihairkobe-crypto/houmon-biyou-app.git

# 3. Claude Code をこのフォルダで起動
cd ~/houmon-biyou-app
claude
```

Claude Code が未インストールなら先に入れる → https://claude.com/claude-code

---

## ② 毎回の作業（両方のMac共通）

作業を **始める前に必ず** 最新を取り込む：

```bash
cd ~/houmon-biyou-app
git pull
```

作業が **終わったら** 保存して送る（Claudeに「コミットしてpushして」でもOK）：

```bash
git add -A
git commit -m "作業内容"
git push
```

push すれば GitHub Pages（本番URL）にも自動反映されます。
https://aihairkobe-crypto.github.io/houmon-biyou-app/

---

## ③ 大事なルール（2台でデータを壊さないため）

1. **作業前は必ず `git pull`**。これを忘れると、もう片方で直した内容と衝突します。
2. **1つのファイルを両方のMacで同時に編集しない**。片方で終えて push → もう片方で pull、の順番を守る。
3. もし `git pull` で「conflict（衝突）」が出たら、無理に進めずClaudeに貼って相談する。

> アプリのデータ（顧客・予約・売上）は Supabase（クラウド）にあるので、
> どのMac・どのスマホからログインしても同じデータが見えます。
> このリポジトリで同期するのは「アプリ本体のコード」だけです。
