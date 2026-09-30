-- 0300 · Platforms, intake, submitters, people, films, submissions, entries, assets, consents
-- STATUS: DRAFT for the parts marked [C-1] (categories/entries/consents/status model) — see docs/platform/DECISIONS_BUILD.md, Correction C-1.
-- Vocabulary after C-1:
--   submissions = one row per platform submission (FilmFreeway/FestHome/CSV) — the raw intake identity.
--   entries     = one row per (film, competition category); exactly one is_primary (free); extra ones may be paid (paid_order_id).

-- ---------- platforms & mapping presets (data, not code) ----------
create table platforms (
  key        text primary key,              -- filmfreeway, festhome, sfilmmaker, …
  name       text not null,
  kinds      text[] not null default '{csv}',   -- subset of {api,webhook,csv}
  enabled    boolean not null default true,
  config     jsonb not null default '{}'::jsonb, -- non-secret config (festival id, base url…)
  sort       integer not null default 100,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table import_mappings (
  id           uuid primary key default gen_random_uuid(),
  platform_key text not null references platforms(key),
  name         text not null,
  version      integer not null default 1,
  is_default   boolean not null default false,
  -- mapping: [{ "target": "films.title", "source": ["Project Title","Title"], "transform": "trim" }, …]
  mapping      jsonb not null,
  -- options: { "delimiter": ",", "raggedRowStrategy": "merge-overflow", "dateFormat": "…" }
  options      jsonb not null default '{}'::jsonb,
  created_by   uuid,
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now(),
  unique (platform_key, name, version)
);
create unique index import_mappings_one_default_idx on import_mappings (platform_key) where is_default;

-- ---------- raw inbound events (idempotent) ----------
create table webhook_events (
  id           uuid primary key default gen_random_uuid(),
  source       text not null,               -- filmfreeway | festhome | stripe | resend | bunny | csv
  external_id  text not null,               -- provider event id, or file_hash:row for csv
  event_type   text,
  signature_ok boolean,
  headers      jsonb,
  payload      jsonb not null,
  status       webhook_status not null default 'received',
  attempts     integer not null default 0,
  error        text,
  received_at  timestamptz not null default now(),
  processed_at timestamptz,
  unique (source, external_id)
);
create index webhook_events_pending_idx on webhook_events (source, received_at) where status = 'received';

create table import_runs (
  id            uuid primary key default gen_random_uuid(),
  platform_key  text not null references platforms(key),
  mapping_id    uuid references import_mappings(id),
  source_kind   text not null check (source_kind in ('webhook','csv','api','manual')),
  file_name     text,
  file_hash     bytea,
  status        import_status not null default 'running',
  rows_total    integer not null default 0,
  rows_created  integer not null default 0,
  rows_updated  integer not null default 0,
  rows_skipped  integer not null default 0,
  rows_failed   integer not null default 0,
  started_at    timestamptz not null default now(),
  finished_at   timestamptz,
  created_by    uuid,
  notes         text
);
create index import_runs_platform_idx on import_runs (platform_key, started_at desc);

create table import_errors (
  id          bigserial primary key,
  run_id      uuid not null references import_runs(id) on delete cascade,
  row_index   integer,
  external_id text,
  message     text not null,
  raw         jsonb,
  created_at  timestamptz not null default now()
);
create index import_errors_run_idx on import_errors (run_id);

-- ---------- submitters & people ----------
create table submitters (
  id                   uuid primary key default gen_random_uuid(),
  email                citext not null unique,
  email_hash           bytea not null,                       -- sha256(lower(email)) for analytics joins
  name                 text,
  organisation         text,
  kind                 submitter_kind not null default 'filmmaker',
  country              text,                                 -- ISO-3166-1 alpha-2
  phone                text,
  locale               text not null default 'en',
  timezone             text,
  auth_user_id         uuid unique,                          -- set on first magic-link login
  marketing_status     text not null default 'none' check (marketing_status in ('none','pending','subscribed','unsubscribed')),
  tags                 text[] not null default '{}',
  first_seen_platform  text references platforms(key),
  films_count          integer not null default 0,           -- maintained by trigger
  notes                text,
  created_at           timestamptz not null default now(),
  updated_at           timestamptz not null default now(),
  deleted_at           timestamptz
);
create index submitters_kind_idx on submitters (kind) where deleted_at is null;
create index submitters_country_idx on submitters (country);
create index submitters_name_trgm_idx on submitters using gin (name gin_trgm_ops);

alter table magic_link_tokens add constraint magic_link_tokens_submitter_fk
  foreign key (submitter_id) references submitters(id);

-- current filmmaker/distributor identity for RLS
create or replace function current_submitter_id() returns uuid language sql stable security definer set search_path = public as $$
  select id from submitters where auth_user_id = auth.uid() and deleted_at is null limit 1
$$;

create table people (
  id           uuid primary key default gen_random_uuid(),
  submitter_id uuid references submitters(id),
  full_name    text not null,
  email        citext,
  country      text,
  bio          text,
  external_ref text,
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now(),
  deleted_at   timestamptz
);
create index people_submitter_idx on people (submitter_id);
create index people_name_trgm_idx on people using gin (full_name gin_trgm_ops);

-- ---------- categories ----------
create table categories (
  key               text primary key,
  name              text not null,
  work_kind         work_kind not null default 'film',
  online_screening  boolean not null default true,   -- false for screenplay/photography
  active            boolean not null default true,
  sort              integer not null default 100,
  aliases           text[] not null default '{}',    -- platform category names that map here
  -- [C-1] which works may enter this category (used by the dashboard "add category" picker):
  -- {"work_kind":"film","min_runtime_seconds":null,"max_runtime_seconds":2400,"requires":["is_student"]}
  fit_rules         jsonb not null default '{}'::jsonb,
  description       text,
  created_at        timestamptz not null default now(),
  updated_at        timestamptz not null default now()
);

-- ---------- films ----------
create or replace function normalize_title(p text) returns text language sql immutable as $$
  select nullif(trim(regexp_replace(
    regexp_replace(lower(unaccent(coalesce(p,''))), '^(the|a|an|le|la|les|der|die|das|el|los|las)\s+', ''),
    '[^a-z0-9]+', ' ', 'g')), '')
$$;

create table films (
  id                 uuid primary key default gen_random_uuid(),
  submitter_id       uuid not null references submitters(id),
  title              text not null,
  original_title     text,
  normalized_title   text generated always as (normalize_title(title)) stored,
  slug               text unique,
  work_kind          work_kind not null default 'film',
  runtime_seconds    integer,
  completion_year    integer,
  country_of_origin  text,
  countries          text[] not null default '{}',
  languages          text[] not null default '{}',
  genres             text[] not null default '{}',
  logline            text,
  synopsis           text,
  premiere_status    text,
  ai_used            boolean,
  ai_declaration     text,
  is_student         boolean,
  is_first_film      boolean,
  has_subtitles      boolean,
  status             film_status not null default 'imported',
  status_changed_at  timestamptz not null default now(),
  public_visible     boolean not null default false,
  geo_restrictions   text[] not null default '{}',          -- ISO country codes blocked by filmmaker
  -- [C-1] three separate acts; set ONLY by the consents trigger, never by the app directly
  screening_licence_at          timestamptz,                -- L-03 online screening licence granted
  gates_accepted_at             timestamptz,                -- disclosed Gates rules accepted (private, versioned)
  primary_category_confirmed_at timestamptz,                -- entrant confirmed the free primary category
  withdrawn_at       timestamptz,
  withdraw_reason    text,
  search_tsv         tsvector generated always as (
                       setweight(to_tsvector('simple', coalesce(title,'')), 'A') ||
                       setweight(to_tsvector('simple', coalesce(original_title,'')), 'A') ||
                       setweight(to_tsvector('simple', coalesce(logline,'')), 'B') ||
                       setweight(to_tsvector('simple', coalesce(synopsis,'')), 'C')) stored,
  created_at         timestamptz not null default now(),
  updated_at         timestamptz not null default now(),
  deleted_at         timestamptz
);
create index films_submitter_idx on films (submitter_id);
create index films_status_idx on films (status) where deleted_at is null;
create index films_gate_ready_idx on films (status) where screening_licence_at is not null and gates_accepted_at is not null and deleted_at is null;
create index films_norm_title_idx on films (submitter_id, normalized_title);
create index films_norm_title_trgm_idx on films using gin (normalized_title gin_trgm_ops);
create index films_search_idx on films using gin (search_tsv);
create index films_created_idx on films (created_at desc, id desc);
create index films_public_idx on films (public_visible) where public_visible and deleted_at is null;

create table submissions (
  id              uuid primary key default gen_random_uuid(),
  film_id         uuid not null references films(id),
  submitter_id    uuid not null references submitters(id),
  platform_key    text not null references platforms(key),
  external_id     text not null,
  external_url    text,
  category_raw    text,                               -- category name as the platform sent it
  category_key    text references categories(key),   -- resolved via categories.aliases (may be null → intake review)
  submitted_at    timestamptz,
  platform_status text,
  judging_status  text,
  fee_cents       integer not null default 0,
  status          entry_status not null default 'active',
  import_run_id   uuid references import_runs(id),
  raw             jsonb not null default '{}'::jsonb,   -- full mapped+raw row for traceability
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now(),
  unique (platform_key, external_id)
);
create index submissions_film_idx on submissions (film_id);
create index submissions_submitter_idx on submissions (submitter_id);
create index submissions_submitted_idx on submissions (submitted_at desc);

-- [C-1] entries: one row per (film, competition category). Screening, gates and jury read THIS, not films.
create table entries (
  id             uuid primary key default gen_random_uuid(),
  film_id        uuid not null references films(id),
  category_key   text not null references categories(key),
  is_primary     boolean not null default false,       -- exactly one active primary per film (free)
  status         text not null default 'active' check (status in ('pending_payment','active','superseded','withdrawn','ineligible')),
  source         text not null default 'import' check (source in ('import','dashboard','festival')),
  submission_id  uuid references submissions(id),      -- the platform submission that created it (import)
  paid_order_id  uuid,                                 -- [C-1] fk to orders added in 0500; null for the free primary
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now(),
  unique (film_id, category_key)
);
create unique index entries_one_primary_idx on entries (film_id) where is_primary and status in ('active','pending_payment');
create index entries_category_idx on entries (category_key, status);
create index entries_film_idx on entries (film_id);

create table film_people (
  film_id   uuid not null references films(id) on delete cascade,
  person_id uuid not null references people(id) on delete cascade,
  credit    text not null,                            -- director, writer, producer, cast…
  sort      integer not null default 0,
  primary key (film_id, person_id, credit)
);
create index film_people_person_idx on film_people (person_id);

create table film_assets (
  id               uuid primary key default gen_random_uuid(),
  film_id          uuid not null references films(id),
  kind             asset_kind not null,
  provider         asset_provider not null default 'external',
  external_url     text,                              -- platform screener / Vimeo etc.
  external_password text,                             -- screener password as supplied by platform (needed for screening)
  storage_path     text,                              -- supabase storage or bunny storage path
  bunny_video_id   text,
  status           asset_status not null default 'ready',
  bytes            bigint,
  duration_seconds integer,
  mime             text,
  width            integer,
  height           integer,
  language         text,                              -- subtitles
  checksum         bytea,
  is_primary       boolean not null default false,
  uploaded_by      uuid,
  created_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now(),
  deleted_at       timestamptz
);
create index film_assets_film_idx on film_assets (film_id, kind) where deleted_at is null;

create table upload_sessions (
  id             uuid primary key default gen_random_uuid(),
  film_id        uuid not null references films(id),
  submitter_id   uuid not null references submitters(id),
  asset_kind     asset_kind not null,
  provider       asset_provider not null,
  provider_ref   text,                                -- tus upload id / bunny video id
  bytes_expected bigint,
  status         text not null default 'created' check (status in ('created','uploading','completed','failed','expired')),
  expires_at     timestamptz not null,
  asset_id       uuid references film_assets(id),
  created_at     timestamptz not null default now(),
  completed_at   timestamptz
);
create index upload_sessions_film_idx on upload_sessions (film_id, created_at desc);

create table dedup_candidates (
  id          uuid primary key default gen_random_uuid(),
  film_id_a   uuid not null references films(id),
  film_id_b   uuid not null references films(id),
  score       numeric(4,3) not null,
  reason      text not null,
  status      text not null default 'pending' check (status in ('pending','merged','distinct')),
  decided_by  uuid,
  decided_at  timestamptz,
  created_at  timestamptz not null default now(),
  check (film_id_a < film_id_b),
  unique (film_id_a, film_id_b)
);
create index dedup_candidates_pending_idx on dedup_candidates (created_at) where status = 'pending';

create table film_status_events (
  id          bigserial primary key,
  film_id     uuid not null references films(id),
  from_status film_status,
  to_status   film_status not null,
  actor_user_id uuid,
  reason      text,
  at          timestamptz not null default now()
);
create index film_status_events_film_idx on film_status_events (film_id, at desc);

create table film_notes (
  id             uuid primary key default gen_random_uuid(),
  film_id        uuid not null references films(id),
  author_user_id uuid,
  body           text not null,
  pinned         boolean not null default false,
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now(),
  deleted_at     timestamptz
);
create index film_notes_film_idx on film_notes (film_id, created_at desc);

create table tags (
  key   text primary key,
  label text not null,
  color text
);
create table film_tags (
  film_id uuid not null references films(id) on delete cascade,
  tag_key text not null references tags(key) on delete cascade,
  primary key (film_id, tag_key)
);

-- ---------- consents (versioned, with text snapshot) ----------
-- [C-1] exactly three consent kinds; each is a separate act, never bundled, never pre-ticked.
create table consent_texts (
  id             uuid primary key default gen_random_uuid(),
  kind           text not null check (kind in ('screening_licence','gates_rules','marketing')),
  version        text not null,
  locale         text not null default 'en',
  title          text not null,
  body_md        text not null,
  effective_from timestamptz not null default now(),
  created_at     timestamptz not null default now(),
  unique (kind, version, locale)
);

create table consents (
  id              uuid primary key default gen_random_uuid(),
  submitter_id    uuid not null references submitters(id),
  film_id         uuid references films(id),            -- required for screening_licence and gates_rules; null for marketing
  kind            text not null check (kind in ('screening_licence','gates_rules','marketing')),
  consent_text_id uuid not null references consent_texts(id),
  text_version    text not null,                        -- copied from consent_texts at grant time
  text_snapshot   text not null,                        -- full text the person saw, frozen
  granted_at      timestamptz not null default now(),
  confirmed_at    timestamptz,                          -- double opt-in confirmation (newsletter)
  revoked_at      timestamptz,
  source          text not null check (source in ('dashboard','email','import','admin')),
  ip_hash         bytea,
  ua_hash         bytea,
  created_at      timestamptz not null default now(),
  check ((kind = 'marketing') = (film_id is null))
);
create index consents_submitter_idx on consents (submitter_id, kind);
create index consents_film_idx on consents (film_id, kind) where film_id is not null;

-- [C-1] consents fill their snapshot from consent_texts and stamp the film / submitter
create or replace function consents_apply() returns trigger language plpgsql security definer set search_path = public as $$
declare t consent_texts%rowtype;
begin
  if tg_op = 'INSERT' then
    select * into t from consent_texts where id = new.consent_text_id;
    if t.kind <> new.kind then raise exception 'consent text % is for kind %, not %', t.id, t.kind, new.kind; end if;
    new.text_version := t.version;
    new.text_snapshot := t.body_md;
    return new;
  end if;
  return new;
end $$;
create trigger consents_apply before insert on consents for each row execute function consents_apply();

create or replace function consents_stamp() returns trigger language plpgsql security definer set search_path = public as $$
declare v_active boolean;
begin
  -- latest state for this (film|submitter, kind)
  select exists (select 1 from consents c where c.kind = new.kind and c.submitter_id = new.submitter_id
                   and c.film_id is not distinct from new.film_id and c.revoked_at is null) into v_active;
  if new.kind = 'screening_licence' then
    update films set screening_licence_at = case when v_active then coalesce(screening_licence_at, new.granted_at) else null end where id = new.film_id;
  elsif new.kind = 'gates_rules' then
    update films set gates_accepted_at = case when v_active then coalesce(gates_accepted_at, new.granted_at) else null end where id = new.film_id;
  elsif new.kind = 'marketing' then
    update submitters set marketing_status = case
        when v_active and new.confirmed_at is not null then 'subscribed'
        when v_active then 'pending'
        else 'unsubscribed' end
      where id = new.submitter_id;
  end if;
  return null;
end $$;
create trigger consents_stamp after insert or update of revoked_at, confirmed_at on consents for each row execute function consents_stamp();

-- ---------- derived counters & status machine ----------
create or replace function submitters_films_count_sync() returns trigger language plpgsql as $$
begin
  if tg_op = 'INSERT' then
    update submitters set films_count = films_count + 1 where id = new.submitter_id;
  elsif tg_op = 'DELETE' then
    update submitters set films_count = greatest(films_count - 1, 0) where id = old.submitter_id;
  elsif new.submitter_id is distinct from old.submitter_id then
    update submitters set films_count = greatest(films_count - 1, 0) where id = old.submitter_id;
    update submitters set films_count = films_count + 1 where id = new.submitter_id;
  end if;
  return null;
end $$;
create trigger films_count_sync after insert or update of submitter_id or delete on films
  for each row execute function submitters_films_count_sync();

create or replace function films_status_event() returns trigger language plpgsql as $$
begin
  if tg_op = 'INSERT' then
    insert into film_status_events (film_id, from_status, to_status, actor_user_id) values (new.id, null, new.status, auth.uid());
    return null;
  end if;
  if new.status is distinct from old.status then
    new.status_changed_at := now();
    insert into film_status_events (film_id, from_status, to_status, actor_user_id, reason)
    values (new.id, old.status, new.status, auth.uid(), nullif(current_setting('app.audit_reason', true), ''));
  end if;
  return new;
end $$;
create trigger films_status_event_insert after insert on films for each row execute function films_status_event();
create trigger films_status_event_update before update of status on films for each row execute function films_status_event();

-- nightly: tag bulk submitters as distributors (threshold is a setting)
create or replace function tag_distributors() returns integer language plpgsql security definer set search_path = public as $$
declare
  v_threshold integer := coalesce((setting('intake.distributor_threshold'))::integer, 10);
  v_n integer;
begin
  update submitters set kind = 'distributor'
   where kind = 'filmmaker' and films_count >= v_threshold and deleted_at is null;
  get diagnostics v_n = row_count;
  return v_n;
end $$;

select attach_updated_at(t) from unnest(array[
  'platforms','import_mappings','submitters','people','categories','films','submissions','entries','film_assets','film_notes'
]) as t;
select attach_audit(t) from unnest(array[
  'platforms','import_mappings','submitters','people','categories','films','submissions','entries','film_people','film_assets',
  'upload_sessions','dedup_candidates','film_notes','film_tags','consent_texts','consents'
]) as t;
