# db-schema-refactoring-sample

DBスキーマのリファクタリングとイミュータブルデータモデル導入を題材にした技術記事のサンプルプロジェクトです。

## 動作確認環境

MySQL 8.4 + Docker Compose で3つのDBを起動できます。

```bash
docker compose up -d
```

| コンテナ | ポート | DB名 | 内容 |
|---|---|---|---|
| db-before | 3506 | schema_before | リファクタリング前（問題のある構造） |
| db-after | 3507 | schema_after | リファクタリング後（イミュータブルモデル） |
| db-mutable-after | 3508 | schema_mutable_after | リファクタリング後（ミュータブルモデル） |

接続情報: `root` / `password`
