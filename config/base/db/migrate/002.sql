-- migrate-002: 2FA ( totp ). see mfa / mfarecovery in init.sql.

CREATE TABLE IF NOT EXISTS mfa (
  key serial primary key,
  owner int not null references users(key) on delete cascade,
  method text not null,
  secret text,
  target text,
  detail jsonb,
  createdtime timestamp not null default now(),
  lastused timestamp
);

CREATE INDEX IF NOT EXISTS idx_mfa_owner ON mfa (owner);

CREATE TABLE IF NOT EXISTS mfarecovery (
  key serial primary key,
  owner int not null references users(key) on delete cascade,
  hash text not null,
  createdtime timestamp not null default now(),
  used timestamp
);

CREATE INDEX IF NOT EXISTS idx_mfarecovery_owner ON mfarecovery (owner);
