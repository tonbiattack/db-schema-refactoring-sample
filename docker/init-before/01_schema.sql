SET
  NAMES utf8mb4;

SET
  character_set_client = utf8mb4;

-- ============================================================
-- イミュータブルデータモデル: リファクタリング前
--
-- 【問題点】
--   1. import_ 系と alert_ 系に同一データが二重存在する
--   2. 自動検知ルートと手動登録ルートで同種テーブルが2系統ある
--   3. 登録経路（自動/手動）がテーブル構造に埋め込まれている
--   4. 結合キーが不統一（user_profiles だけ業務キーで結合）
-- ============================================================
-- ------------------------------------------------------------
-- マスタ: ユーザー種別
-- ------------------------------------------------------------
CREATE TABLE user_types (
  id INT NOT NULL AUTO_INCREMENT COMMENT 'ユーザー種別ID',
  name VARCHAR(50) NOT NULL COMMENT 'ユーザー種別名（例: 個人, 法人）',
  created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '作成日時',
  updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP COMMENT '更新日時',
  PRIMARY KEY (id)
) COMMENT = 'ユーザー種別マスタ';

-- ------------------------------------------------------------
-- ルートエンティティ: ユーザー
-- ------------------------------------------------------------
CREATE TABLE users (
  id INT NOT NULL AUTO_INCREMENT COMMENT 'ユーザーID',
  external_code VARCHAR(50) NOT NULL COMMENT '外部システムの識別コード（業務キー）',
  user_type_id INT NOT NULL COMMENT 'ユーザー種別ID（user_types.id）',
  name VARCHAR(100) NOT NULL COMMENT 'ユーザー名',
  created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '作成日時',
  updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP COMMENT '更新日時',
  PRIMARY KEY (id),
  UNIQUE KEY uq_users_external_code (external_code),
  CONSTRAINT fk_users_user_type FOREIGN KEY (user_type_id) REFERENCES user_types(id)
) COMMENT = 'ユーザー';

-- 問題: 他の子テーブルは user_id（FK）で結合しているのに、ここだけ external_code（業務キー）で結合
CREATE TABLE user_profiles (
  id INT NOT NULL AUTO_INCREMENT COMMENT 'プロフィールID',
  external_code VARCHAR(50) NOT NULL COMMENT '外部システムの識別コード（users.external_code を参照。問題: FK ではなく業務キーで結合）',
  address VARCHAR(255) NOT NULL COMMENT '住所',
  phone VARCHAR(50) NOT NULL COMMENT '電話番号',
  created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '作成日時',
  updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP COMMENT '更新日時',
  PRIMARY KEY (id),
  UNIQUE KEY uq_user_profiles_external_code (external_code)
) COMMENT = 'ユーザープロフィール（問題: external_code という業務キーで users と結合している）';

-- ============================================================
-- インポート系テーブル（外部システムから取り込んだ生データ）
-- ============================================================
CREATE TABLE import_transactions (
  id INT NOT NULL AUTO_INCREMENT COMMENT '取引インポートID',
  user_id INT NOT NULL COMMENT 'ユーザーID（users.id）',
  amount DECIMAL(15, 2) NOT NULL COMMENT '取引金額',
  transacted_at DATETIME NOT NULL COMMENT '取引日時（外部システム上）',
  created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '取り込み日時',
  PRIMARY KEY (id),
  CONSTRAINT fk_import_transactions_user FOREIGN KEY (user_id) REFERENCES users(id)
) COMMENT = '取引インポート（外部システムから取り込んだ生データ）';

CREATE TABLE import_logs (
  id INT NOT NULL AUTO_INCREMENT COMMENT 'ログインポートID',
  user_id INT NOT NULL COMMENT 'ユーザーID（users.id）',
  action VARCHAR(100) NOT NULL COMMENT '操作内容（例: ログイン, パスワード変更）',
  occurred_at DATETIME NOT NULL COMMENT '操作日時（外部システム上）',
  created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '取り込み日時',
  PRIMARY KEY (id),
  CONSTRAINT fk_import_logs_user FOREIGN KEY (user_id) REFERENCES users(id)
) COMMENT = '操作ログインポート（外部システムから取り込んだ生データ）';

CREATE TABLE import_account_update_histories (
  id INT NOT NULL AUTO_INCREMENT COMMENT 'アカウント更新履歴インポートID',
  user_id INT NOT NULL COMMENT 'ユーザーID（users.id）',
  changed_column VARCHAR(100) NOT NULL COMMENT '変更されたカラム名',
  before_value TEXT NULL COMMENT '変更前の値',
  after_value TEXT NULL COMMENT '変更後の値',
  updated_at_external DATETIME NOT NULL COMMENT '外部システム上の更新日時',
  created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '取り込み日時',
  PRIMARY KEY (id),
  CONSTRAINT fk_import_account_update_histories_user FOREIGN KEY (user_id) REFERENCES users(id)
) COMMENT = 'アカウント更新履歴インポート（外部システムから取り込んだ生データ）';

-- ============================================================
-- 自動検知系テーブル
-- 問題: import_ 系からコピーされた二重管理データ
-- ============================================================
CREATE TABLE alert_transactions (
  id INT NOT NULL AUTO_INCREMENT COMMENT '検知取引ID',
  user_id INT NOT NULL COMMENT 'ユーザーID（users.id を直接参照・1段）',
  amount DECIMAL(15, 2) NOT NULL COMMENT '取引金額（import_transactions からコピー。問題: 二重管理）',
  transacted_at DATETIME NOT NULL COMMENT '取引日時（import_transactions からコピー。問題: 二重管理）',
  created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '作成日時',
  updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP COMMENT '更新日時',
  PRIMARY KEY (id),
  CONSTRAINT fk_alert_transactions_user FOREIGN KEY (user_id) REFERENCES users(id)
) COMMENT = '自動検知取引（問題: import_transactions と同一データが二重存在する）';

CREATE TABLE alert_logs (
  id INT NOT NULL AUTO_INCREMENT COMMENT '検知ログID',
  user_id INT NOT NULL COMMENT 'ユーザーID（users.id を直接参照・1段）',
  action VARCHAR(100) NOT NULL COMMENT '操作内容（import_logs からコピー。問題: 二重管理）',
  occurred_at DATETIME NOT NULL COMMENT '操作日時（import_logs からコピー。問題: 二重管理）',
  created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '作成日時',
  updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP COMMENT '更新日時',
  PRIMARY KEY (id),
  CONSTRAINT fk_alert_logs_user FOREIGN KEY (user_id) REFERENCES users(id)
) COMMENT = '自動検知操作ログ（問題: import_logs と同一データが二重存在する）';

-- ============================================================
-- 手動登録系テーブル
-- 問題: 自動検知系と同種データを別テーブルで管理（2系統の並存）
--       参照階層が自動検知系より2段深い
-- ============================================================
CREATE TABLE alert_users (
  id INT NOT NULL AUTO_INCREMENT COMMENT 'アラートユーザーID',
  user_id INT NOT NULL COMMENT 'ユーザーID（users.id を参照・1段）',
  reason TEXT NOT NULL COMMENT '手動登録の理由',
  registered_at DATETIME NOT NULL COMMENT '手動登録日時',
  created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '作成日時',
  updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP COMMENT '更新日時',
  PRIMARY KEY (id),
  CONSTRAINT fk_alert_users_user FOREIGN KEY (user_id) REFERENCES users(id)
) COMMENT = '手動登録アラートユーザー（問題: 自動検知には対応するテーブルがなく非対称）';

CREATE TABLE alert_user_comments (
  id INT NOT NULL AUTO_INCREMENT COMMENT 'コメントID',
  alert_user_id INT NOT NULL COMMENT 'アラートユーザーID（alert_users.id を参照・2段）',
  comment TEXT NOT NULL COMMENT 'コメント本文',
  created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '作成日時',
  updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP COMMENT '更新日時',
  PRIMARY KEY (id),
  CONSTRAINT fk_alert_user_comments_alert_user FOREIGN KEY (alert_user_id) REFERENCES alert_users(id)
) COMMENT = '手動登録アラートユーザーへのコメント';

CREATE TABLE alert_user_investigations (
  id INT NOT NULL AUTO_INCREMENT COMMENT '調査情報ID',
  alert_user_id INT NOT NULL COMMENT 'アラートユーザーID（alert_users.id を参照・2段）',
  status VARCHAR(50) NOT NULL COMMENT '調査ステータス（問題: マスタ参照ではなく文字列で直接管理）',
  investigated_at DATETIME NOT NULL COMMENT '調査実施日時',
  created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '作成日時',
  updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP COMMENT '更新日時',
  PRIMARY KEY (id),
  CONSTRAINT fk_alert_user_investigations_alert_user FOREIGN KEY (alert_user_id) REFERENCES alert_users(id)
) COMMENT = '手動登録の調査情報（問題: 自動検知系と非対称で参照が2段深い）';

CREATE TABLE alert_investigation_transactions (
  id INT NOT NULL AUTO_INCREMENT COMMENT '調査取引明細ID',
  alert_user_investigation_id INT NOT NULL COMMENT '調査情報ID（alert_user_investigations.id を参照・3段）',
  amount DECIMAL(15, 2) NOT NULL COMMENT '取引金額',
  transacted_at DATETIME NOT NULL COMMENT '取引日時',
  created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '作成日時',
  updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP COMMENT '更新日時',
  PRIMARY KEY (id),
  CONSTRAINT fk_alert_inv_transactions_investigation FOREIGN KEY (alert_user_investigation_id) REFERENCES alert_user_investigations(id)
) COMMENT = '手動登録の調査取引明細（問題: alert_transactions と同種データ・参照が3段深い）';

CREATE TABLE alert_investigation_logs (
  id INT NOT NULL AUTO_INCREMENT COMMENT '調査操作ログID',
  alert_user_investigation_id INT NOT NULL COMMENT '調査情報ID（alert_user_investigations.id を参照・3段）',
  action VARCHAR(100) NOT NULL COMMENT '操作内容',
  occurred_at DATETIME NOT NULL COMMENT '操作日時',
  created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '作成日時',
  updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP COMMENT '更新日時',
  PRIMARY KEY (id),
  CONSTRAINT fk_alert_inv_logs_investigation FOREIGN KEY (alert_user_investigation_id) REFERENCES alert_user_investigations(id)
) COMMENT = '手動登録の調査操作ログ（問題: alert_logs と同種データ・参照が3段深い）';