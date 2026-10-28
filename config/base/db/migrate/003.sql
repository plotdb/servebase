-- migrate-003: users.system ( 系統狀態, 不送到前端 ) 與 activatetoken ( 啟用管理員代建的帳號 ). see init.sql.

ALTER TABLE users ADD COLUMN IF NOT EXISTS system jsonb;

-- config.authinfo.renewpw 搬到 system.renewpw
UPDATE users
  SET system = coalesce(system, '{}'::jsonb) || '{"renewpw": true}'::jsonb,
  config = config #- '{authinfo,renewpw}'
  WHERE config #> '{authinfo,renewpw}' = 'true'::jsonb;

CREATE TABLE IF NOT EXISTS activatetoken (
  key serial primary key,
  owner int not null references users(key) on delete cascade,
  hash text not null,
  createdtime timestamp not null default now(),
  ttl timestamp not null,
  used timestamp,
  deleted boolean
);

CREATE INDEX IF NOT EXISTS idx_activatetoken_hash ON activatetoken (hash);
CREATE INDEX IF NOT EXISTS idx_activatetoken_owner ON activatetoken (owner);
