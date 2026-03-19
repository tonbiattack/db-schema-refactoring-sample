SET
  NAMES utf8mb4;

SET
  character_set_client = utf8mb4;

-- マスタデータ初期投入
INSERT INTO
  user_types (id, name)
VALUES
  (1, '個人'),
  (2, '法人');

INSERT INTO
  detection_statuses (id, name)
VALUES
  (1, '未検知'),
  (2, '検知済み'),
  (3, '除外');

INSERT INTO
  registration_types (id, name)
VALUES
  (1, '自動検知'),
  (2, '手動登録');

INSERT INTO
  investigation_statuses (id, name)
VALUES
  (1, '調査中'),
  (2, '完了'),
  (3, '取り消し');