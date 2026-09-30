-- 0500 · Commerce: products, prices, coupons, orders, invoices, refunds, entitlements
-- STATUS: DRAFT — product catalogue follows Correction C-1 (additional categories vs honours vs services); prices NOT final.
-- Money is integer cents. Prices are stored GROSS (incl. VAT) as displayed to consumers (PAngV).
-- VAT rate in basis points (1900 = 19 %).

create table products (
  id            uuid primary key default gen_random_uuid(),
  key           text not null unique,
  kind          product_kind not null,
  name          text not null,
  description   text,
  requires_film boolean not null default true,
  work_kinds    work_kind[] not null default '{film,screenplay,photography}',
  active        boolean not null default false,
  sort          integer not null default 100,
  metadata      jsonb not null default '{}'::jsonb,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now()
);

create table prices (
  id                uuid primary key default gen_random_uuid(),
  product_id        uuid not null references products(id),
  gate_id           uuid,                                -- fk added in 0600 (vote prices per gate)
  currency          text not null default 'EUR',
  unit_amount_cents integer not null check (unit_amount_cents >= 0),  -- gross
  vat_rate_bp       integer not null default 1900 check (vat_rate_bp between 0 and 10000),
  valid_from        timestamptz not null default now(),
  valid_to          timestamptz,
  active            boolean not null default false,
  stripe_price_id   text unique,
  created_by        uuid,
  created_at        timestamptz not null default now(),
  updated_at        timestamptz not null default now()
);
create index prices_product_active_idx on prices (product_id, active, valid_from desc);

create table coupons (
  id          uuid primary key default gen_random_uuid(),
  code        citext not null unique,
  kind        text not null check (kind in ('percent','fixed')),
  value       integer not null check (value > 0),       -- percent (1-100) or cents
  currency    text not null default 'EUR',
  max_uses    integer,
  used_count  integer not null default 0,
  product_ids uuid[] not null default '{}',             -- empty = all products
  valid_from  timestamptz not null default now(),
  valid_to    timestamptz,
  active      boolean not null default true,
  created_by  uuid,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);

create table orders (
  id                          uuid primary key default gen_random_uuid(),
  number                      text unique,                -- BG-2026-000123 (assigned on paid)
  kind                        order_kind not null,
  status                      order_status not null default 'draft',
  submitter_id                uuid references submitters(id),
  film_id                     uuid references films(id),
  buyer_email                 citext not null,
  buyer_email_hash            bytea not null,
  buyer_name                  text,
  buyer_country               text,
  buyer_vat_id                text,
  buyer_address               jsonb,
  reverse_charge              boolean not null default false,
  currency                    text not null default 'EUR',
  net_cents                   integer not null default 0,
  vat_cents                   integer not null default 0,
  fee_cents                   integer not null default 0,   -- booking fee (gross) included in total
  total_cents                 integer not null default 0,   -- gross, what the buyer pays
  coupon_id                   uuid references coupons(id),
  discount_cents              integer not null default 0,
  stripe_checkout_session_id  text unique,
  stripe_payment_intent_id    text unique,
  payment_method              text,
  ip_hash                     bytea,
  metadata                    jsonb not null default '{}'::jsonb,
  paid_at                     timestamptz,
  refunded_cents              integer not null default 0,
  created_at                  timestamptz not null default now(),
  updated_at                  timestamptz not null default now()
);
create index orders_submitter_idx on orders (submitter_id, created_at desc);
create index orders_film_idx on orders (film_id);
create index orders_status_idx on orders (status, created_at desc);
create index orders_buyer_hash_idx on orders (buyer_email_hash, created_at desc);
create index orders_paid_idx on orders (paid_at desc) where status = 'paid';

create table order_lines (
  id                uuid primary key default gen_random_uuid(),
  order_id          uuid not null references orders(id) on delete cascade,
  product_id        uuid not null references products(id),
  price_id          uuid references prices(id),
  gate_id           uuid,                                  -- fk added in 0600
  film_id           uuid references films(id),
  description       text not null,
  qty               integer not null check (qty > 0),
  unit_amount_cents integer not null,                      -- gross unit price paid
  vat_rate_bp       integer not null,
  net_cents         integer not null,
  vat_cents         integer not null,
  gross_cents       integer not null,
  created_at        timestamptz not null default now()
);
create index order_lines_order_idx on order_lines (order_id);
create index order_lines_film_idx on order_lines (film_id);

-- sequential order/invoice numbering per year (gapless within a year)
create table number_counters (
  kind text not null check (kind in ('order','invoice','credit_note')),
  year integer not null,
  last integer not null default 0,
  primary key (kind, year)
);

create or replace function next_number(p_kind text, p_prefix text) returns text language plpgsql security definer set search_path = public as $$
declare
  v_year integer := extract(year from now() at time zone 'UTC')::integer;
  v_last integer;
begin
  insert into number_counters (kind, year, last) values (p_kind, v_year, 1)
  on conflict (kind, year) do update set last = number_counters.last + 1
  returning last into v_last;
  return format('%s-%s-%s', p_prefix, v_year, lpad(v_last::text, 6, '0'));
end $$;

create table invoices (
  id              uuid primary key default gen_random_uuid(),
  number          text not null unique,                    -- INV-2026-000001
  order_id        uuid not null references orders(id),
  status          invoice_status not null default 'issued',
  issued_at       timestamptz not null default now(),
  seller          jsonb not null,                          -- snapshot of settings.legal.* at issue time
  buyer           jsonb not null,                          -- snapshot of buyer data
  lines           jsonb not null,                          -- snapshot of order_lines
  currency        text not null,
  net_cents       integer not null,
  vat_cents       integer not null,
  gross_cents     integer not null,
  vat_rate_bp     integer not null,
  reverse_charge  boolean not null default false,
  vat_note        text,                                    -- e.g. reverse-charge wording
  pdf_path        text,
  credit_note_of  uuid references invoices(id),
  created_at      timestamptz not null default now()
);
create index invoices_order_idx on invoices (order_id);
create index invoices_issued_idx on invoices (issued_at desc);

-- invoices are immutable except pdf_path and status
create or replace function invoices_immutable() returns trigger language plpgsql as $$
begin
  if to_jsonb(new) - 'pdf_path' - 'status' is distinct from to_jsonb(old) - 'pdf_path' - 'status' then
    raise exception 'invoices are immutable; issue a credit note instead';
  end if;
  return new;
end $$;
create trigger invoices_immutable before update on invoices for each row execute function invoices_immutable();
create rule invoices_no_delete as on delete to invoices do instead nothing;

create table refunds (
  id               uuid primary key default gen_random_uuid(),
  order_id         uuid not null references orders(id),
  kind             refund_kind not null,
  stripe_refund_id text unique,
  stripe_dispute_id text unique,
  amount_cents     integer not null check (amount_cents > 0),
  reason           text,
  status           text not null default 'pending' check (status in ('pending','succeeded','failed','lost','won')),
  created_by       uuid,
  created_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now()
);
create index refunds_order_idx on refunds (order_id);

create table entitlements (
  id           uuid primary key default gen_random_uuid(),
  submitter_id uuid not null references submitters(id),
  film_id      uuid references films(id),
  product_id   uuid not null references products(id),
  order_id     uuid references orders(id),
  key          text not null,                 -- e.g. award_consideration:craft, laurel_print, feedback
  granted_at   timestamptz not null default now(),
  expires_at   timestamptz,
  revoked_at   timestamptz,
  revoke_reason text,
  metadata     jsonb not null default '{}'::jsonb,
  created_at   timestamptz not null default now()
);
create index entitlements_film_idx on entitlements (film_id, key) where revoked_at is null;

-- [C-1] a paid additional-category entry points at the order that paid for it
alter table entries add constraint entries_paid_order_fk foreign key (paid_order_id) references orders(id);
alter table order_lines add column entry_id uuid references entries(id);
create index order_lines_entry_idx on order_lines (entry_id) where entry_id is not null;
create index entitlements_submitter_idx on entitlements (submitter_id);

select attach_updated_at(t) from unnest(array['products','prices','coupons','orders','refunds']) as t;
select attach_audit(t) from unnest(array[
  'products','prices','coupons','orders','order_lines','invoices','refunds','entitlements'
]) as t;
