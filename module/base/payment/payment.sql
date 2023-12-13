create table if not exists payment (
  key serial primary key,
  owner int references users(key), -- user who creates this recrod.
  scope text, -- slug of scope this payment is in.
  slug text, -- slug of this payment.
  payload jsonb, -- data sent to gateway.
  gateway jsonb, -- data collected from gateway.
  invoice jsonb, -- invoice information
  createdtime timestamp default now(),
  paidtime timestamp,
  state text, -- either pending, complete, refunded, dispute
  deleted boolean default false
);

create index if not exists idx_payment_owner on payment (owner);
create index if not exists idx_payment_slug on payment (slug);
create index if not exists idx_payment_createdtime on payment (createdtime);
