# にょわくじ2026

全力で抵抗するおみくじアプリにょわ．

→ **[docs/GAMEPLAY.md](docs/GAMEPLAY.md)** — アプリ仕様  
→ **[docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)** — 技術設計

---

## 開発環境

```sh
# 依存関係のインストール
gleam deps download

# テスト
gleam test

# ローカル開発サーバ
gleam run -m lustre/dev -- start
```

## ビルド (`dist/` に出力)

```sh
gleam run -m lustre/dev -- build
```

## デプロイ

`main` ブランチに push すると GitHub Actions がテスト → ビルド → Cloudflare Pages デプロイを実行します．

必要な GitHub シークレット / 変数:

| 名前                      | 種別     | 説明                     |
| ------------------------- | -------- | ------------------------ |
| `CLOUDFLARE_API_TOKEN`    | Secret   | Cloudflare API トークン  |
| `CLOUDFLARE_ACCOUNT_ID`   | Secret   | Cloudflare アカウント ID |
| `CLOUDFLARE_PROJECT_NAME` | Variable | Pages プロジェクト名     |
