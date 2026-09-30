-- 0600 · Gates engine: gates, gate_films, votes, laurels, fraud alerts
-- All numbers (threshold, capacity, price, fee, dates) are ROWS, never constants.

create table gates (
  id                 uuid primary key default gen_random_uuid(),
  n                  integer not null unique check (n > 0),
  name               text not null,
  threshold          integer not null check (threshold > 0),          -- votes a film needs to be "through"
  capacity           integer not null check (capacity > 0),           -- max films that pass this gate
  vote_price_cents   integer not null check (vote_price_cents >= 0),  -- gross incl. VAT
  booking_fee_cents  integer not null default 0 check (booking_fee_cents >= 0),
  currency           text not null default 'EUR',
  vat_rate_bp        integer not null default 1900,
  opens_at           timestamptz,
  closes_at          timestamptz,
  closed_at          timestamptz,
  status             gate_status not null default 'draft',
  captcha_mode       text not null default 'off' check (captcha_mode in ('off','auto','on')),
  config_version     integer not null default 1,
  notes              text,
  created_at         timestamptz not null default now(),
  updated_at         timestamptz not null default now(),
  check (closes_at is null or opens_at is null or closes_at > opens_at)
);
create unique index gates_single_open_idx on gates (status) where status in ('open','closing');

create table gate_config_versions (
  id         bigserial primary key,
  gate_id    uuid not null references gates(id),
  version    integer not null,
  snapshot   jsonb not null,
  changed_by uuid,
  reason     text,
  changed_at timestamptz not null default now(),
  unique (gate_id, version)
);

create or replace function gates_version_snapshot() returns trigger language plpgsql as $$
begin
  if tg_op = 'INSERT' then
    insert into gate_config_versions (gate_id, version, snapshot, changed_by, reason)
    values (new.id, 1, to_jsonb(new), auth.uid(), 'created');
    return null;
  end if;
  if (new.threshold, new.capacity, new.vote_price_cents, new.booking_fee_cents, new.opens_at, new.closes_at, new.vat_rate_bp)
        is distinct from
        (old.threshold, old.capacity, old.vote_price_cents, old.booking_fee_cents, old.opens_at, old.closes_at, old.vat_rate_bp) then
    if old.status in ('closing','closed') then
      raise exception 'gate % is %; its parameters are frozen', old.n, old.status;
    end if;
    new.config_version := old.config_version + 1;
    insert into gate_config_versions (gate_id, version, snapshot, changed_by, reason)
    values (new.id, new.config_version, to_jsonb(new), auth.uid(), nullif(current_setting('app.audit_reason', true), ''));
  end if;
  return new;
end $$;
create trigger gates_version_snapshot_insert after insert on gates for each row execute function gates_version_snapshot();
create trigger gates_version_snapshot_update before update on gates for each row execute function gates_version_snapshot();

alter table prices add constraint prices_gate_fk foreign key (gate_id) references gates(id);
alter table order_lines add constraint order_lines_gate_fk foreign key (gate_id) references gates(id);

create table gate_films (
  id              uuid primary key default gen_random_uuid(),
  gate_id         uuid not null references gates(id),
  film_id         uuid not null references films(id),
  votes           integer not null default 0 check (votes >= 0),   -- materialised counter of counted votes
  status          gate_film_status not null default 'active',
  through_at      timestamptz,
  eliminated_at   timestamptz,
  rank_at_close   integer,
  last_vote_at    timestamptz,
  override_by     uuid,
  override_reason text,
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now(),
  unique (gate_id, film_id)
);
create index gate_films_leaderboard_idx on gate_films (gate_id, status, votes desc, last_vote_at asc);
create index gate_films_film_idx on gate_films (film_id);

create table votes (
  id               uuid primary key default gen_random_uuid(),
  gate_id          uuid not null references gates(id),
  film_id          uuid not null references films(id),
  order_id         uuid not null references orders(id),
  order_line_id    uuid references order_lines(id),
  qty              integer not null check (qty > 0),
  buyer_email_hash bytea not null,
  country          text,
  status           vote_status not null default 'counted',
  stripe_event_id  text not null unique,           -- payment_intent.succeeded event id → idempotent
  reversed_reason  text,
  reversed_at      timestamptz,
  created_at       timestamptz not null default now()
);
create index votes_gate_film_idx on votes (gate_id, film_id, created_at);
create index votes_order_idx on votes (order_id);
create index votes_buyer_idx on votes (buyer_email_hash, created_at desc);

-- Guard: votes can only be inserted while the gate is open and the film is active in it.
-- Counter maintenance and "through" detection happen here, atomically, per vote row.
create or replace function votes_apply() returns trigger language plpgsql security definer set search_path = public as $$
declare
  v_gate gates%rowtype;
  v_gf   gate_films%rowtype;
begin
  select * into v_gate from gates where id = new.gate_id for share;
  if v_gate.status <> 'open' then
    raise exception 'gate % is not open (status %)', v_gate.n, v_gate.status using errcode = 'check_violation';
  end if;
  select * into v_gf from gate_films where gate_id = new.gate_id and film_id = new.film_id for update;
  if not found then
    raise exception 'film % is not in gate %', new.film_id, v_gate.n using errcode = 'check_violation';
  end if;
  if v_gf.status <> 'active' then
    -- Late arrival after the film went through: keep the row for reconciliation, but do not count it.
    new.status := 'reversed';
    new.reversed_reason := 'film_not_active:' || v_gf.status::text;
    new.reversed_at := now();
    return new;
  end if;
  update gate_films
     set votes = votes + new.qty,
         last_vote_at = new.created_at,
         status = case when votes + new.qty >= v_gate.threshold then 'through'::gate_film_status else status end,
         through_at = case when votes + new.qty >= v_gate.threshold then new.created_at else through_at end
   where id = v_gf.id;
  return new;
end $$;
create trigger votes_apply before insert on votes for each row execute function votes_apply();

-- Reversal (refund / chargeback): decrement, and drop the film back to active if the gate is still open.
create or replace function votes_reverse() returns trigger language plpgsql security definer set search_path = public as $$
declare
  v_gate gates%rowtype;
begin
  if old.status = 'counted' and new.status = 'reversed' then
    new.reversed_at := coalesce(new.reversed_at, now());
    select * into v_gate from gates where id = new.gate_id;
    update gate_films
       set votes = greatest(votes - new.qty, 0),
           status = case
                      when v_gate.status = 'open' and status = 'through' and votes - new.qty < v_gate.threshold then 'active'::gate_film_status
                      else status
                    end,
           through_at = case
                      when v_gate.status = 'open' and status = 'through' and votes - new.qty < v_gate.threshold then null
                      else through_at
                    end
     where gate_id = new.gate_id and film_id = new.film_id;
    if v_gate.status <> 'open' then
      insert into fraud_alerts (gate_id, film_id, order_id, kind, severity, details)
      values (new.gate_id, new.film_id, new.order_id, 'post_close_reversal', 'warning',
              jsonb_build_object('vote_id', new.id, 'qty', new.qty, 'reason', new.reversed_reason));
    end if;
  elsif old.status = 'reversed' and new.status = 'counted' then
    raise exception 'a reversed vote cannot be counted again';
  end if;
  return new;
end $$;
create trigger votes_reverse before update of status on votes for each row execute function votes_reverse();

create table laurels (
  id         uuid primary key default gen_random_uuid(),
  film_id    uuid not null references films(id),
  kind       honour_kind not null,             -- selection | gate | category | craft | identity | special | grand
  honour_key text references honours(key),
  gate_id    uuid references gates(id),
  label      text not null,                    -- e.g. "Gate 2 · BGIFF 2027"
  file_path  text,                             -- generated PNG/SVG in storage
  issued_at  timestamptz not null default now(),
  revoked_at timestamptz,
  created_at timestamptz not null default now(),
  unique (film_id, kind, gate_id, honour_key)
);
create index laurels_film_idx on laurels (film_id) where revoked_at is null;

create table fraud_alerts (
  id          uuid primary key default gen_random_uuid(),
  gate_id     uuid references gates(id),
  film_id     uuid references films(id),
  order_id    uuid references orders(id),
  kind        text not null,                   -- velocity | same_card_many_films | post_close_reversal | geo_anomaly | manual
  severity    flag_severity not null default 'warning',
  details     jsonb not null default '{}'::jsonb,
  status      text not null default 'open' check (status in ('open','dismissed','actioned')),
  resolved_by uuid,
  resolved_at timestamptz,
  created_at  timestamptz not null default now()
);
create index fraud_alerts_open_idx on fraud_alerts (created_at desc) where status = 'open';

-- ---------- gate lifecycle ----------

-- Open gate N: create gate_films rows for every film that passed gate N-1 (or every eligible, online-screenable film for gate 1).
create or replace function open_gate(p_gate_id uuid) returns integer language plpgsql security definer set search_path = public as $$
declare
  v_gate gates%rowtype;
  v_prev gates%rowtype;
  v_n integer;
begin
  select * into v_gate from gates where id = p_gate_id for update;
  if v_gate.status not in ('draft','scheduled') then
    raise exception 'gate % cannot be opened from status %', v_gate.n, v_gate.status;
  end if;
  if v_gate.n = 1 then
    -- [C-1] a film enters gate 1 only if: screening said eligible, its PRIMARY entry is in an online-screening category,
    -- the online-screening licence was granted AND the disclosed Gates rules were accepted privately in the dashboard.
    insert into gate_films (gate_id, film_id)
    select v_gate.id, f.id
      from films f
      join entries e on e.film_id = f.id and e.is_primary and e.status = 'active'
      join categories c on c.key = e.category_key
     where f.status = 'eligible' and f.deleted_at is null and f.withdrawn_at is null
       and c.online_screening and f.screening_licence_at is not null and f.gates_accepted_at is not null
    on conflict do nothing;
  else
    select * into v_prev from gates where n = v_gate.n - 1;
    if v_prev.status <> 'closed' then
      raise exception 'gate % must be closed before gate % opens', v_prev.n, v_gate.n;
    end if;
    insert into gate_films (gate_id, film_id)
    select v_gate.id, gf.film_id
      from gate_films gf join films f on f.id = gf.film_id
     where gf.gate_id = v_prev.id and gf.status = 'through' and f.withdrawn_at is null and f.deleted_at is null
    on conflict do nothing;
  end if;
  get diagnostics v_n = row_count;
  update gates set status = 'open', opens_at = coalesce(opens_at, now()) where id = p_gate_id;
  update films set status = 'in_gates' where id in (select film_id from gate_films where gate_id = p_gate_id) and status <> 'in_gates';
  return v_n;
end $$;

-- Should the gate close now? capacity reached OR time window ended.
create or replace function gate_should_close(p_gate_id uuid) returns boolean language sql stable as $$
  select g.status = 'open' and (
           (select count(*) from gate_films gf where gf.gate_id = g.id and gf.status = 'through') >= g.capacity
           or (g.closes_at is not null and now() >= g.closes_at))
    from gates g where g.id = p_gate_id
$$;

-- Close gate: fill remaining capacity with highest-voted active films, eliminate the rest, issue gate laurels.
-- Idempotent: calling it on a closed gate is a no-op. Ties: earliest last vote, then earliest entry (created_at).
create or replace function close_gate(p_gate_id uuid, p_force boolean default false) returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_gate gates%rowtype;
  v_through integer;
  v_slots integer;
  v_promoted integer := 0;
  v_eliminated integer := 0;
begin
  select * into v_gate from gates where id = p_gate_id for update;
  if v_gate.status = 'closed' then
    return jsonb_build_object('gate', v_gate.n, 'noop', true);
  end if;
  if v_gate.status <> 'open' then
    raise exception 'gate % is not open', v_gate.n;
  end if;
  if not p_force and not gate_should_close(p_gate_id) then
    return jsonb_build_object('gate', v_gate.n, 'noop', true, 'reason', 'not_due');
  end if;

  update gates set status = 'closing' where id = p_gate_id;

  select count(*) into v_through from gate_films where gate_id = p_gate_id and status = 'through';
  v_slots := greatest(v_gate.capacity - v_through, 0);

  with ranked as (
    select gf.id, row_number() over (order by gf.votes desc, gf.last_vote_at asc nulls last, gf.created_at asc) as rn
      from gate_films gf where gf.gate_id = p_gate_id and gf.status = 'active'
  )
  update gate_films gf
     set status = 'through', through_at = now(), rank_at_close = v_through + r.rn
    from ranked r where r.id = gf.id and r.rn <= v_slots;
  get diagnostics v_promoted = row_count;

  with ranked as (
    select gf.id, row_number() over (order by gf.votes desc, gf.last_vote_at asc nulls last, gf.created_at asc) as rn
      from gate_films gf where gf.gate_id = p_gate_id and gf.status = 'active'
  )
  update gate_films gf
     set status = 'eliminated', eliminated_at = now(), rank_at_close = v_through + v_slots + r.rn
    from ranked r where r.id = gf.id;
  get diagnostics v_eliminated = row_count;

  -- rank the films that were already through by the moment they got through
  with ranked as (
    select id, row_number() over (order by through_at asc) as rn
      from gate_films where gate_id = p_gate_id and status = 'through' and rank_at_close is null
  )
  update gate_films gf set rank_at_close = r.rn from ranked r where r.id = gf.id;

  -- free digital laurel for every eliminated film
  insert into laurels (film_id, kind, gate_id, label)
  select gf.film_id, 'gate', v_gate.id, format('%s · BGIFF', v_gate.name)
    from gate_films gf where gf.gate_id = p_gate_id and gf.status = 'eliminated'
  on conflict do nothing;

  update films set status = 'eliminated'
   where id in (select film_id from gate_films where gate_id = p_gate_id and status = 'eliminated') and status = 'in_gates';

  update gates set status = 'closed', closed_at = now() where id = p_gate_id;
  return jsonb_build_object('gate', v_gate.n, 'through', v_through + v_promoted, 'promoted_by_rank', v_promoted, 'eliminated', v_eliminated);
end $$;

-- called by pg_cron every minute (see runbook); harmless on plain Postgres
create or replace function close_due_gates() returns integer language plpgsql security definer set search_path = public as $$
declare v_n integer := 0; r record;
begin
  for r in select id from gates where status = 'open' loop
    if gate_should_close(r.id) then perform close_gate(r.id); v_n := v_n + 1; end if;
  end loop;
  return v_n;
end $$;

-- Public leaderboard (only exposed when flag gates_public is on; see RLS)
create view gate_leaderboard with (security_invoker = true) as
  select gf.gate_id, g.n as gate_n, gf.film_id, f.title, f.slug, e.category_key, gf.votes, gf.status, gf.through_at,
         rank() over (partition by gf.gate_id order by gf.votes desc, gf.last_vote_at asc nulls last) as position
    from gate_films gf
    join gates g on g.id = gf.gate_id
    join films f on f.id = gf.film_id
    left join entries e on e.film_id = f.id and e.is_primary and e.status = 'active'
   where f.deleted_at is null;

select attach_updated_at(t) from unnest(array['gates','gate_films']) as t;
select attach_audit(t) from unnest(array['gates','gate_films','votes','laurels','fraud_alerts']) as t;
