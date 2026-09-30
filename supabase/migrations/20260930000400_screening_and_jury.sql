-- 0400 · Screening (AI pre-check + human decisions) and jury
-- STATUS: DRAFT — entry-level (per category) scoping follows Correction C-1; see DECISIONS_BUILD.md.

create table screening_flags (
  id            uuid primary key default gen_random_uuid(),
  film_id       uuid not null references films(id),
  kind          text not null check (kind in ('format','runtime','subtitles','duplicate','category_fit','ai_declaration','rights','other')),
  severity      flag_severity not null default 'warning',
  note          text,
  agent_run_id  uuid,                              -- fk added in 0800
  resolved_at   timestamptz,
  resolved_by   uuid,
  created_at    timestamptz not null default now()
);
create index screening_flags_film_idx on screening_flags (film_id) where resolved_at is null;
create index screening_flags_open_idx on screening_flags (severity, created_at) where resolved_at is null;

create table screening_assignments (
  id               uuid primary key default gen_random_uuid(),
  film_id          uuid not null references films(id),
  screener_user_id uuid not null,
  assigned_by      uuid,
  assigned_at      timestamptz not null default now(),
  due_at           timestamptz,
  status           text not null default 'open' check (status in ('open','done','released')),
  unique (film_id, screener_user_id)
);
create index screening_assignments_screener_idx on screening_assignments (screener_user_id, status);

create table screening_decisions (
  id            uuid primary key default gen_random_uuid(),
  film_id       uuid not null references films(id),
  entry_id      uuid references entries(id),         -- [C-1] null = decision about the work as a whole; set = category fit for that entry
  decision      screening_decision not null,
  reason_key    text,                                -- e.g. 'no_subtitles', 'runtime_exceeds'
  reason_text   text,                                -- shown to filmmaker (approved template)
  internal_note text,
  decided_by    uuid not null,
  decided_at    timestamptz not null default now(),
  is_current    boolean not null default true
);
create index screening_decisions_film_idx on screening_decisions (film_id, decided_at desc);
create unique index screening_decisions_current_idx on screening_decisions (film_id, coalesce(entry_id, '00000000-0000-0000-0000-000000000000'::uuid)) where is_current;

create or replace function screening_decisions_supersede() returns trigger language plpgsql as $$
begin
  update screening_decisions set is_current = false
   where film_id = new.film_id and entry_id is not distinct from new.entry_id and is_current and id <> new.id;
  return new;
end $$;
create trigger screening_decisions_supersede before insert on screening_decisions
  for each row execute function screening_decisions_supersede();

-- ---------- jury ----------
create table honours (
  key         text primary key,
  name        text not null,
  kind        honour_kind not null,
  category_key text references categories(key),
  sort        integer not null default 100,
  active      boolean not null default true,
  description text
);

create table jurors (
  id            uuid primary key default gen_random_uuid(),
  auth_user_id  uuid unique,
  name          text not null,
  email         citext not null unique,
  bio           text,
  category_keys text[] not null default '{}',
  active        boolean not null default true,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now()
);

create or replace function current_juror_id() returns uuid language sql stable security definer set search_path = public as $$
  select id from jurors where auth_user_id = auth.uid() and active limit 1
$$;

create table jury_assignments (
  id          uuid primary key default gen_random_uuid(),
  juror_id    uuid not null references jurors(id),
  film_id     uuid not null references films(id),
  entry_id    uuid references entries(id),           -- [C-1] the (film, category) being judged; null only for cross-category honours
  round       integer not null default 1,
  assigned_by uuid,
  assigned_at timestamptz not null default now(),
  status      text not null default 'open' check (status in ('open','scored','released','conflict')),
  unique (juror_id, film_id, round)
);
create index jury_assignments_juror_idx on jury_assignments (juror_id, status);

create table conflicts (
  id          uuid primary key default gen_random_uuid(),
  juror_id    uuid not null references jurors(id),
  film_id     uuid not null references films(id),
  note        text,
  declared_at timestamptz not null default now(),
  unique (juror_id, film_id)
);

create table scoring_rubrics (
  id         uuid primary key default gen_random_uuid(),
  version    text not null unique,
  work_kind  work_kind not null default 'film',
  criteria   jsonb not null,                  -- [{key,label,weight,max}]
  active     boolean not null default false,
  created_at timestamptz not null default now()
);

create table scores (
  id           uuid primary key default gen_random_uuid(),
  juror_id     uuid not null references jurors(id),
  film_id      uuid not null references films(id),
  entry_id     uuid references entries(id),          -- [C-1]
  round        integer not null default 1,
  rubric_id    uuid not null references scoring_rubrics(id),
  values       jsonb not null,                -- {criterionKey: number}
  total        numeric(8,3),
  comment      text,
  submitted_at timestamptz,
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now(),
  unique (juror_id, film_id, round)
);
create index scores_film_idx on scores (film_id, round);

create table rankings (
  id           uuid primary key default gen_random_uuid(),
  category_key text references categories(key),
  round        integer not null,
  film_id      uuid not null references films(id),
  rank         integer not null,
  method       text not null,                 -- e.g. 'mean_total_v1'
  computed_at  timestamptz not null default now(),
  unique (category_key, round, film_id)
);

create table results (
  id             uuid primary key default gen_random_uuid(),
  film_id        uuid not null references films(id),
  honour_key     text not null references honours(key),
  category_key   text references categories(key),
  decided_at     timestamptz not null default now(),
  signed_off_by  uuid,
  signed_off_at  timestamptz,
  public_at      timestamptz,
  note           text,
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now(),
  unique (film_id, honour_key)
);

select attach_updated_at(t) from unnest(array['jurors','scores','results']) as t;
select attach_audit(t) from unnest(array[
  'screening_flags','screening_assignments','screening_decisions','honours','jurors','jury_assignments',
  'conflicts','scoring_rubrics','scores','rankings','results'
]) as t;
