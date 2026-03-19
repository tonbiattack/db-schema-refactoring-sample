SET NAMES utf8mb4;
SET character_set_client = utf8mb4;

-- ============================================================
-- イミュータブルデータモデル: リファクタリング後
--
-- 【解決した問題】
--   1. import_ 系を唯一の生データ置き場にし、二重管理を解消
--   2. alert_investigations に一本化し、登録経路を registration_type_id カラムで表現
--   3. user_profiles の結合キーを user_id FK に統一
--   4. valid_from / valid_to で状態変化の履歴を保全（イミュータブル）
-- ============================================================

-- ------------------------------------------------------------
-- マスタ: ユーザー種別
-- ------------------------------------------------------------
CREATE TABLE user_types (
  id         INT         NOT NULL AUTO_INCREMENT COMMENT 'ユーザー種別ID',
  name       VARCHAR(50) NOT NULL                COMMENT 'ユーザー種別名（例: 個人, 法人）',
  created_at DATETIME    NOT NULL DEFAULT CURRENT_TIMESTAMP                    COMMENT '作成日時',
  updated_at DATETIME    NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP COMMENT '更新日時',
  PRIMARY KEY (id)
) COMMENT = 'ユーザー種別マスタ';

-- ------------------------------------------------------------
-- マスタ: 検知ステータス
-- ------------------------------------------------------------
CREATE TABLE detection_statuses (
  id         INT         NOT NULL AUTO_INCREMENT COMMENT '検知ステータスID',
  name       VARCHAR(50) NOT NULL                COMMENT '検知ステータス名（例: 未検知, 検知済み, 除外）',
  created_at DATETIME    NOT NULL DEFAULT CURRENT_TIMESTAMP                    COMMENT '作成日時',
  updated_at DATETIME    NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP COMMENT '更新日時',
  PRIMARY KEY (id)
) COMMENT = '検知ステータスマスタ（import_ 系テーブルの検知状態を管理）';

-- ------------------------------------------------------------
-- マスタ: 登録種別
-- ------------------------------------------------------------
CREATE TABLE registration_types (
  id         INT         NOT NULL AUTO_INCREMENT COMMENT '登録種別ID',
  name       VARCHAR(50) NOT NULL                COMMENT '登録種別名（例: 自動検知, 手動登録）',
  created_at DATETIME    NOT NULL DEFAULT CURRENT_TIMESTAMP                    COMMENT '作成日時',
  updated_at DATETIME    NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP COMMENT '更新日時',
  PRIMARY KEY (id)
) COMMENT = '登録種別マスタ（alert_investigations の登録経路を管理）';

-- ------------------------------------------------------------
-- マスタ: 調査ステータス
-- ------------------------------------------------------------
CREATE TABLE investigation_statuses (
  id         INT         NOT NULL AUTO_INCREMENT COMMENT '調査ステータスID',
  name       VARCHAR(50) NOT NULL                COMMENT '調査ステータス名（例: 調査中, 完了, 取り消し）',
  created_at DATETIME    NOT NULL DEFAULT CURRENT_TIMESTAMP                    COMMENT '作成日時',
  updated_at DATETIME    NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP COMMENT '更新日時',
  PRIMARY KEY (id)
) COMMENT = '調査ステータスマスタ（alert_investigations の調査状態を管理）';

-- ------------------------------------------------------------
-- ルートエンティティ: ユーザー（通常モデルを維持）
-- ------------------------------------------------------------
CREATE TABLE users (
  id            INT          NOT NULL AUTO_INCREMENT COMMENT 'ユーザーID',
  external_code VARCHAR(50)  NOT NULL               COMMENT '外部システムの識別コード（業務キー）',
  user_type_id  INT          NOT NULL               COMMENT 'ユーザー種別ID（user_types.id）',
  name          VARCHAR(100) NOT NULL               COMMENT 'ユーザー名',
  created_at    DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP                    COMMENT '作成日時',
  updated_at    DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP COMMENT '更新日時',
  PRIMARY KEY (id),
  UNIQUE KEY uq_users_external_code (external_code),
  CONSTRAINT fk_users_user_type
    FOREIGN KEY (user_type_id) REFERENCES user_types(id)
) COMMENT = 'ユーザー（通常モデル。可変データのため UPDATE を許容）';

CREATE TABLE user_profiles (
  id         INT          NOT NULL AUTO_INCREMENT COMMENT 'プロフィールID',
  user_id    INT          NOT NULL               COMMENT 'ユーザーID（users.id。変更前は external_code で結合していたが FK に統一）',
  address    VARCHAR(255) NOT NULL               COMMENT '住所',
  phone      VARCHAR(50)  NOT NULL               COMMENT '電話番号',
  created_at DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP                    COMMENT '作成日時',
  updated_at DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP COMMENT '更新日時',
  PRIMARY KEY (id),
  UNIQUE KEY uq_user_profiles_user_id (user_id),
  CONSTRAINT fk_user_profiles_user
    FOREIGN KEY (user_id) REFERENCES users(id)
) COMMENT = 'ユーザープロフィール（変更: external_code 結合 → user_id FK に統一）';

CREATE TABLE user_change_histories (
  id             INT          NOT NULL AUTO_INCREMENT COMMENT 'ユーザー変更履歴ID',
  user_id        INT          NOT NULL               COMMENT 'ユーザーID（users.id）',
  changed_column VARCHAR(100) NOT NULL               COMMENT '変更されたカラム名',
  before_value   TEXT         NULL                   COMMENT '変更前の値',
  after_value    TEXT         NULL                   COMMENT '変更後の値',
  changed_at     DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '変更日時',
  PRIMARY KEY (id),
  CONSTRAINT fk_user_change_histories_user
    FOREIGN KEY (user_id) REFERENCES users(id)
) COMMENT = 'ユーザー変更履歴（イミュータブル。users 本体は通常モデルのまま、変更履歴を別テーブルで管理）';

-- ============================================================
-- インポート系テーブル（イミュータブル）
-- valid_from / valid_to で状態変化の履歴を保全
-- detection_status_id で検知状態を管理（alert_ 系コピーを廃止）
-- ============================================================

CREATE TABLE import_transactions (
  id                  INT            NOT NULL AUTO_INCREMENT COMMENT '取引インポートID',
  user_id             INT            NOT NULL               COMMENT 'ユーザーID（users.id）',
  amount              DECIMAL(15, 2) NOT NULL               COMMENT '取引金額',
  transacted_at       DATETIME       NOT NULL               COMMENT '取引日時（外部システム上）',
  detection_status_id INT            NOT NULL DEFAULT 1     COMMENT '検知ステータスID（detection_statuses.id。状態変化は新行 INSERT で記録）',
  valid_from          DATETIME       NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT 'この行が有効になった日時',
  valid_to            DATETIME       NULL                   COMMENT 'この行が無効になった日時（NULL = 現在有効）',
  created_at          DATETIME       NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '行作成日時',
  PRIMARY KEY (id),
  CONSTRAINT fk_import_transactions_user
    FOREIGN KEY (user_id) REFERENCES users(id),
  CONSTRAINT fk_import_transactions_detection_status
    FOREIGN KEY (detection_status_id) REFERENCES detection_statuses(id)
) COMMENT = '取引インポート（イミュータブル。検知状態の変化は valid_to を閉じて新行 INSERT で記録）';

CREATE TABLE import_logs (
  id                  INT          NOT NULL AUTO_INCREMENT COMMENT 'ログインポートID',
  user_id             INT          NOT NULL               COMMENT 'ユーザーID（users.id）',
  action              VARCHAR(100) NOT NULL               COMMENT '操作内容（例: ログイン, パスワード変更）',
  occurred_at         DATETIME     NOT NULL               COMMENT '操作日時（外部システム上）',
  detection_status_id INT          NOT NULL DEFAULT 1     COMMENT '検知ステータスID（detection_statuses.id。状態変化は新行 INSERT で記録）',
  valid_from          DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT 'この行が有効になった日時',
  valid_to            DATETIME     NULL                   COMMENT 'この行が無効になった日時（NULL = 現在有効）',
  created_at          DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '行作成日時',
  PRIMARY KEY (id),
  CONSTRAINT fk_import_logs_user
    FOREIGN KEY (user_id) REFERENCES users(id),
  CONSTRAINT fk_import_logs_detection_status
    FOREIGN KEY (detection_status_id) REFERENCES detection_statuses(id)
) COMMENT = '操作ログインポート（イミュータブル。検知状態の変化は valid_to を閉じて新行 INSERT で記録）';

CREATE TABLE import_account_update_histories (
  id                  INT          NOT NULL AUTO_INCREMENT COMMENT 'アカウント更新履歴インポートID',
  user_id             INT          NOT NULL               COMMENT 'ユーザーID（users.id）',
  changed_column      VARCHAR(100) NOT NULL               COMMENT '変更されたカラム名',
  before_value        TEXT         NULL                   COMMENT '変更前の値',
  after_value         TEXT         NULL                   COMMENT '変更後の値',
  updated_at_external DATETIME     NOT NULL               COMMENT '外部システム上の更新日時',
  detection_status_id INT          NOT NULL DEFAULT 1     COMMENT '検知ステータスID（detection_statuses.id。状態変化は新行 INSERT で記録）',
  valid_from          DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT 'この行が有効になった日時',
  valid_to            DATETIME     NULL                   COMMENT 'この行が無効になった日時（NULL = 現在有効）',
  created_at          DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '行作成日時',
  PRIMARY KEY (id),
  CONSTRAINT fk_import_account_update_histories_user
    FOREIGN KEY (user_id) REFERENCES users(id),
  CONSTRAINT fk_import_acc_upd_hist_detection_status
    FOREIGN KEY (detection_status_id) REFERENCES detection_statuses(id)
) COMMENT = 'アカウント更新履歴インポート（イミュータブル。検知状態の変化は valid_to を閉じて新行 INSERT で記録）';

-- ============================================================
-- 調査情報テーブル（イミュータブル）
-- 自動検知・手動登録の共通テーブルとして一本化
-- registration_type_id で登録経路を区別
-- valid_from / valid_to で調査状態の変遷を保全
-- ============================================================

CREATE TABLE alert_investigations (
  id                      INT      NOT NULL AUTO_INCREMENT COMMENT '調査情報ID',
  user_id                 INT      NOT NULL               COMMENT 'ユーザーID（users.id を直接参照・1段に統一）',
  registration_type_id    INT      NOT NULL               COMMENT '登録種別ID（registration_types.id。自動検知/手動登録をカラムで区別）',
  investigation_status_id INT      NOT NULL DEFAULT 1     COMMENT '調査ステータスID（investigation_statuses.id。状態変化は新行 INSERT で記録）',
  reason                  TEXT     NULL                   COMMENT '検知・登録の理由',
  valid_from              DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT 'この行が有効になった日時',
  valid_to                DATETIME NULL                   COMMENT 'この行が無効になった日時（NULL = 現在有効）',
  created_at              DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '行作成日時',
  PRIMARY KEY (id),
  CONSTRAINT fk_alert_investigations_user
    FOREIGN KEY (user_id) REFERENCES users(id),
  CONSTRAINT fk_alert_investigations_registration_type
    FOREIGN KEY (registration_type_id) REFERENCES registration_types(id),
  CONSTRAINT fk_alert_investigations_investigation_status
    FOREIGN KEY (investigation_status_id) REFERENCES investigation_statuses(id)
) COMMENT = '調査情報（イミュータブル。自動検知・手動登録を一本化。調査状態の変化は valid_to を閉じて新行 INSERT で記録）';

CREATE TABLE alert_investigation_comments (
  id                     INT      NOT NULL AUTO_INCREMENT COMMENT 'コメントID',
  alert_investigation_id INT      NOT NULL               COMMENT '調査情報ID（alert_investigations.id）',
  comment                TEXT     NOT NULL               COMMENT 'コメント本文',
  created_at             DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP                    COMMENT '作成日時',
  updated_at             DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP COMMENT '更新日時',
  PRIMARY KEY (id),
  CONSTRAINT fk_alert_inv_comments_investigation
    FOREIGN KEY (alert_investigation_id) REFERENCES alert_investigations(id)
) COMMENT = '調査コメント（ミュータブル。編集・削除が業務上発生するため UPDATE を許容）';

CREATE TABLE alert_investigation_transactions (
  id                     INT            NOT NULL AUTO_INCREMENT COMMENT '調査取引明細ID',
  alert_investigation_id INT            NOT NULL               COMMENT '調査情報ID（alert_investigations.id）',
  amount                 DECIMAL(15, 2) NOT NULL               COMMENT '取引金額',
  transacted_at          DATETIME       NOT NULL               COMMENT '取引日時',
  created_at             DATETIME       NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '作成日時',
  PRIMARY KEY (id),
  CONSTRAINT fk_alert_inv_transactions_investigation
    FOREIGN KEY (alert_investigation_id) REFERENCES alert_investigations(id)
) COMMENT = '調査取引明細（追記のみ。自動検知・手動登録で1系統に統一）';

CREATE TABLE alert_investigation_logs (
  id                     INT          NOT NULL AUTO_INCREMENT COMMENT '調査操作ログID',
  alert_investigation_id INT          NOT NULL               COMMENT '調査情報ID（alert_investigations.id）',
  action                 VARCHAR(100) NOT NULL               COMMENT '操作内容',
  occurred_at            DATETIME     NOT NULL               COMMENT '操作日時',
  created_at             DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '作成日時',
  PRIMARY KEY (id),
  CONSTRAINT fk_alert_inv_logs_investigation
    FOREIGN KEY (alert_investigation_id) REFERENCES alert_investigations(id)
) COMMENT = '調査操作ログ（追記のみ。自動検知・手動登録で1系統に統一）';
