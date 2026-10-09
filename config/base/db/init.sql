create extension if not exists pg_trgm;

create table if not exists users (
  key serial primary key,
  username text not null unique constraint users_username_len check (char_length(username) <= 100),
  password text constraint users_password_len check (char_length(password) <= 256),
  method text,
  verified jsonb,
  displayname text, constraint users_displayname_length check (char_length(displayname) <= 64),
  description text, constraint users_description_length check (char_length(description) <= 1024),
  title text, constraint  users_title_length check (char_length(title) <= 100),
  tags text, constraint users_tags_length check (char_length(tags) <= 256),
  createdtime timestamp not null default now(),
  modifiedtime timestamp,
  lastactive timestamp,
  detail jsonb,
  plan jsonb,
  config jsonb,
  staff int,
  deleted boolean
);

create index if not exists idx_user_displayname on users (lower(displayname) varchar_pattern_ops);

create table if not exists password (
  key serial primary key,
  owner int references users(key),
  hash text constraint password_hash_len check (char_length(hash) <= 256),
  createdtime timestamp default now(),
  snooze timestamp default now()
);

create index if not exists idx_password_owner on password (owner);
create index if not exists idx_password_createdtime on password (createdtime);

create table if not exists session (
  key text not null unique primary key,
  owner int references users(key),
  ip text,
  ttl timestamp,
  detail jsonb
);

create index if not exists idx_sessions_user on session (owner);
create index if not exists idx_sessions_ttl on session (ttl);

create table if not exists mailverifytoken (
  owner int references users(key) on delete cascade,
  token text not null,
  time timestamp not null default now()
);

create index if not exists idx_mailverifytoken on mailverifytoken (token);

create table if not exists pwresettoken (
  owner int references users(key) on delete cascade,
  token text not null,
  time timestamp default now()
);

create index if not exists idx_pwresettoken on pwresettoken (token);

-- 2FA: 每個已啟用的第二因素一列. secret 不能放 users, 因為 users 整列會被寫進 session.
--  - method: totp ( 之後可加 email / sms / webauthn ).
--  - secret: totp secret, 用 config.auth.mfa 的金鑰加密後存放.
--  - target: 寄送對象 ( sms 手機號碼等 ), totp 不用.
--  - detail: 各方法自己的狀態, 如 totp 的 laststep ( 防 replay ).
create table if not exists mfa (
  key serial primary key,
  owner int not null references users(key) on delete cascade,
  method text not null,
  secret text,
  target text,
  detail jsonb,
  createdtime timestamp not null default now(),
  lastused timestamp
);

create index if not exists idx_mfa_owner on mfa (owner);

-- 2FA 復原碼, 只存雜湊. 用過的留著 used 時間, 重新產生時整批換掉.
create table if not exists mfarecovery (
  key serial primary key,
  owner int not null references users(key) on delete cascade,
  hash text not null,
  createdtime timestamp not null default now(),
  used timestamp
);

create index if not exists idx_mfarecovery_owner on mfarecovery (owner);

create table if not exists invitetoken (
  key serial primary key,
  owner int, -- no cascade and foreign key since we should keep it even if owner is gone.
  scope text,
  token text unique not null,
  createdtime timestamp default now(),
  ttl timestamp,
  domain text,
  detail jsonb,
  deleted boolean default false
);

create table if not exists auditlog (
  key serial primary key,
  action text,
  option jsonb,
  owner int, -- no cascade and foreign key since we should keep it even if owner is gone.
  session text,
  ip text,
  detail jsonb,
  createdtime timestamp default now()
);
