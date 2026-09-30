-- 0200 · Identity, roles, settings, feature flags, audit log, decisions, documents, magic links

-- ---------- helper: updated_at ----------
create or replace function set_updated_at() returns trigger language plpgsql as $$
begin
  new.updated_at := now();
  return new;
end $$;

-- ---------- roles ----------
create table user_roles (
  auth_user_id uuid not null,
  role         role_key not null,
  granted_by   uuid,
  created_at   timestamptz not null default now(),
  primary key (auth_user_id, role)
);
create index user_roles_role_idx on user_roles (role);

-- Roles are read from the JWT (app_metadata.roles, set by an auth hook) with a DB fallback.
create or replace function current_roles() returns role_key[] language sql stable security definer set search_path = public as $$
  select coalesce(
    (select array_agg(r.role) from user_roles r where r.auth_user_id = auth.uid()),
    '{}'::role_key[]
  )
$$;

create or replace function has_role(r role_key) returns boolean language sql stable as $$
  select r = any (current_roles())
$$;

create or replace function has_any_role(rs role_key[]) returns boolean language sql stable as $$
  select current_roles() && rs
$$;

create or replace function is_staff() returns boolean language sql stable as $$
  select has_any_role(array['founder','admin','support','finance','screener','programmer']::role_key[])
$$;

create or replace function is_admin() returns boolean language sql stable as $$
  select has_any_role(array['founder','admin']::role_key[])
$$;

create or replace function is_service() returns boolean language sql stable as $$
  select coalesce(auth.role() = 'service_role', false)
$$;

-- ---------- settings (versioned key/value, editable by admin) ----------
create table settings (
  key         text primary key,
  value       jsonb not null,
  category    text not null default 'general',
  description text,
  version     integer not null default 1,
  is_secret   boolean not null default false,   -- secrets never live here; flag exists to block accidental use
  updated_by  uuid,
  updated_at  timestamptz not null default now(),
  check (is_secret = false)
);
create index settings_category_idx on settings (category);

create table settings_history (
  id         bigserial primary key,
  key        text not null,
  value      jsonb not null,
  version    integer not null,
  changed_by uuid,
  changed_at timestamptz not null default now()
);
create index settings_history_key_idx on settings_history (key, version desc);

create or replace function settings_version_bump() returns trigger language plpgsql as $$
begin
  if tg_op = 'UPDATE' and new.value is distinct from old.value then
    new.version := old.version + 1;
    new.updated_at := now();
    insert into settings_history (key, value, version, changed_by) values (old.key, old.value, old.version, old.updated_by);
  end if;
  return new;
end $$;
create trigger settings_version_bump before update on settings for each row execute function settings_version_bump();

-- security definer: server-side helpers (tag_distributors etc.) read settings regardless of caller
create or replace function setting(p_key text) returns jsonb language sql stable security definer set search_path = public as $$
  select value from settings where key = p_key
$$;

-- ---------- feature flags (every live switch defaults to off) ----------
create table feature_flags (
  key         text primary key,
  enabled     boolean not null default false,
  description text,
  requires_founder boolean not null default true,  -- only founder may flip
  updated_by  uuid,
  updated_at  timestamptz not null default now()
);

-- security definer: policies call flag() for roles that cannot read feature_flags themselves
create or replace function flag(p_key text) returns boolean language sql stable security definer set search_path = public as $$
  select coalesce((select enabled from feature_flags where key = p_key), false)
$$;

-- ---------- audit log (append-only) ----------
create table audit_log (
  id            bigserial primary key,
  at            timestamptz not null default now(),
  actor_user_id uuid,
  actor_roles   role_key[],
  action        text not null,            -- insert | update | delete | custom verbs
  table_name    text not null,
  row_id        text,
  before        jsonb,
  after         jsonb,
  reason        text,
  request_id    text,
  ip_hash       bytea
);
create index audit_log_table_row_idx on audit_log (table_name, row_id, at desc);
create index audit_log_actor_idx on audit_log (actor_user_id, at desc);
create index audit_log_at_idx on audit_log (at desc);

revoke update, delete, truncate on audit_log from public, anon, authenticated;
-- service_role bypasses grants; the rule below makes the table append-only for everyone.
create rule audit_log_no_update as on update to audit_log do instead nothing;
create rule audit_log_no_delete as on delete to audit_log do instead nothing;

create or replace function audit_row() returns trigger language plpgsql security definer set search_path = public as $$
declare
  v_row_id text;
  v_reason text := nullif(current_setting('app.audit_reason', true), '');
begin
  if tg_op = 'DELETE' then
    v_row_id := (to_jsonb(old) ->> 'id');
    insert into audit_log (actor_user_id, actor_roles, action, table_name, row_id, before, after, reason, request_id)
    values (auth.uid(), current_roles(), 'delete', tg_table_name, v_row_id, to_jsonb(old), null, v_reason,
            nullif(current_setting('app.request_id', true), ''));
    return old;
  elsif tg_op = 'UPDATE' then
    v_row_id := (to_jsonb(new) ->> 'id');
    if to_jsonb(new) - 'updated_at' is distinct from to_jsonb(old) - 'updated_at' then
      insert into audit_log (actor_user_id, actor_roles, action, table_name, row_id, before, after, reason, request_id)
      values (auth.uid(), current_roles(), 'update', tg_table_name, v_row_id, to_jsonb(old), to_jsonb(new), v_reason,
              nullif(current_setting('app.request_id', true), ''));
    end if;
    return new;
  else
    v_row_id := (to_jsonb(new) ->> 'id');
    insert into audit_log (actor_user_id, actor_roles, action, table_name, row_id, before, after, reason, request_id)
    values (auth.uid(), current_roles(), 'insert', tg_table_name, v_row_id, null, to_jsonb(new), v_reason,
            nullif(current_setting('app.request_id', true), ''));
    return new;
  end if;
end $$;

-- attach audit + updated_at triggers to a table by name (used by later migrations)
create or replace function attach_audit(p_table regclass) returns void language plpgsql as $$
begin
  execute format('create trigger audit_%1$s after insert or update or delete on %1$s for each row execute function audit_row()', p_table);
end $$;

create or replace function attach_updated_at(p_table regclass) returns void language plpgsql as $$
begin
  execute format('create trigger touch_%1$s before update on %1$s for each row execute function set_updated_at()', p_table);
end $$;

-- ---------- decisions log mirror & governance documents ----------
create table decisions (
  id         uuid primary key default gen_random_uuid(),
  code       text not null unique,          -- e.g. D-132, D-B01
  title      text not null,
  body_md    text,
  decided_at date,
  decided_by text,
  source     text,                          -- e.g. "02_DECISIONS_LOG.md", "Build Brief v1"
  supersedes text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table documents (
  id           uuid primary key default gen_random_uuid(),
  key          text not null,               -- e.g. R-04, L-03
  version      text not null,
  locale       text not null default 'en',
  title        text not null,
  body_md      text,
  status       text not null default 'draft' check (status in ('draft','approved','published','retired')),
  published_at timestamptz,
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now(),
  unique (key, version, locale)
);

-- ---------- magic links & rate limits ----------
create table magic_link_tokens (
  id           uuid primary key default gen_random_uuid(),
  email        citext not null,
  submitter_id uuid,                        -- fk added in 0300
  token_hash   bytea not null unique,       -- sha256(token); raw token never stored
  purpose      text not null default 'dashboard' check (purpose in ('dashboard','jury','admin')),
  expires_at   timestamptz not null,
  used_at      timestamptz,
  ip_hash      bytea,
  ua_hash      bytea,
  created_at   timestamptz not null default now()
);
create index magic_link_tokens_email_idx on magic_link_tokens (email, created_at desc);
create index magic_link_tokens_expires_idx on magic_link_tokens (expires_at) where used_at is null;

create table rate_limits (
  bucket       text not null,               -- e.g. 'magic_link:email:<hash>'
  window_start timestamptz not null,
  count        integer not null default 0,
  primary key (bucket, window_start)
);

-- sliding-window counter; returns true when allowed
create or replace function rate_limit_hit(p_bucket text, p_limit integer, p_window interval) returns boolean
language plpgsql security definer set search_path = public as $$
declare
  v_window_start timestamptz := date_trunc('minute', now());
  v_total integer;
begin
  insert into rate_limits (bucket, window_start, count) values (p_bucket, v_window_start, 1)
  on conflict (bucket, window_start) do update set count = rate_limits.count + 1;
  select coalesce(sum(count), 0) into v_total from rate_limits
   where bucket = p_bucket and window_start > now() - p_window;
  return v_total <= p_limit;
end $$;

select attach_updated_at('settings'), attach_updated_at('decisions'), attach_updated_at('documents');
select attach_audit('user_roles'), attach_audit('settings'), attach_audit('feature_flags'),
       attach_audit('decisions'), attach_audit('documents');
