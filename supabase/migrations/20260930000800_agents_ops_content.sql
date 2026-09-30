-- 0800 · AI agent runs & proposals, cron/health, retention, CMS-lite content

create table agent_runs (
  id            uuid primary key default gen_random_uuid(),
  agent         text not null,                    -- precheck | email_draft | founder_digest | faq_reply | critique_draft
  model         text not null,
  input_ref     jsonb not null default '{}'::jsonb,   -- {film_id | submitter_id | …}
  prompt        text,
  output        text,
  output_json   jsonb,
  input_tokens  integer,
  output_tokens integer,
  cost_cents    integer,
  status        text not null default 'running' check (status in ('running','succeeded','failed')),
  error         text,
  started_at    timestamptz not null default now(),
  finished_at   timestamptz,
  created_by    uuid
);
create index agent_runs_agent_idx on agent_runs (agent, started_at desc);
alter table screening_flags add constraint screening_flags_agent_run_fk foreign key (agent_run_id) references agent_runs(id);

create table agent_proposals (
  id            uuid primary key default gen_random_uuid(),
  agent_run_id  uuid references agent_runs(id),
  kind          text not null,                    -- screening_flag | email_draft | reply | critique | status_change
  target_table  text,
  target_id     uuid,
  payload       jsonb not null,
  status        proposal_status not null default 'proposed',
  decided_by    uuid,
  decided_at    timestamptz,
  decision_note text,
  expires_at    timestamptz,
  created_at    timestamptz not null default now()
);
create index agent_proposals_open_idx on agent_proposals (kind, created_at) where status = 'proposed';

create table cron_runs (
  id          bigserial primary key,
  job         text not null,                      -- intake | outbox | gates | digest | retention | backup_check | health
  started_at  timestamptz not null default now(),
  finished_at timestamptz,
  status      text not null default 'running' check (status in ('running','succeeded','failed')),
  stats       jsonb not null default '{}'::jsonb,
  error       text
);
create index cron_runs_job_idx on cron_runs (job, started_at desc);

create table retention_policies (
  id          uuid primary key default gen_random_uuid(),
  table_name  text not null,
  column_name text not null default 'created_at',
  days        integer not null check (days > 0),
  action      text not null check (action in ('anonymise','soft_delete')),
  enabled     boolean not null default false,
  note        text,
  unique (table_name, action)
);

-- ---------- CMS-lite ----------
create table site_pages (
  id           uuid primary key default gen_random_uuid(),
  path         text not null,                     -- '/legal/impressum'
  locale       text not null default 'en',
  title        text not null,
  blocks       jsonb not null default '[]'::jsonb,
  status       text not null default 'draft' check (status in ('draft','published')),
  published_at timestamptz,
  updated_by   uuid,
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now(),
  unique (path, locale)
);

create table faqs (
  id          uuid primary key default gen_random_uuid(),
  locale      text not null default 'en',
  question    text not null,
  answer_md   text not null,
  audience    text not null default 'public' check (audience in ('public','filmmaker','voter','press','internal')),
  sort        integer not null default 100,
  published   boolean not null default false,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);

create table journal_posts (
  id           uuid primary key default gen_random_uuid(),
  slug         text not null unique,
  locale       text not null default 'en',
  type         text not null default 'Festival News',
  title        text not null,
  excerpt      text,
  body_md      text,
  image_path   text,
  status       text not null default 'draft' check (status in ('draft','published')),
  published_at timestamptz,
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now()
);

create table venues (
  id       uuid primary key default gen_random_uuid(),
  name     text not null,
  address  text,
  city     text,
  country  text default 'DE',
  capacity integer,
  notes    text
);

create table programme_items (
  id          uuid primary key default gen_random_uuid(),
  title       text not null,
  kind        text not null default 'screening' check (kind in ('screening','talk','ceremony','other')),
  venue_id    uuid references venues(id),
  starts_at   timestamptz,
  ends_at     timestamptz,
  film_ids    uuid[] not null default '{}',
  description text,
  status      text not null default 'draft' check (status in ('draft','published')),
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);

select attach_updated_at(t) from unnest(array['site_pages','faqs','journal_posts','programme_items']) as t;
select attach_audit(t) from unnest(array[
  'agent_proposals','retention_policies','site_pages','faqs','journal_posts','venues','programme_items'
]) as t;
