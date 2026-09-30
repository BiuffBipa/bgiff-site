-- 0700 · Outbox (all email), email events, suppressions, templates, segments, campaigns, automations, CRM, tasks, analytics events

create table email_templates (
  key              text not null,
  locale           text not null default 'en',
  version          integer not null default 1,
  kind             email_kind not null,
  subject          text not null,
  body_md          text not null,                 -- markdown with {{variables}}
  variables_schema jsonb not null default '{}'::jsonb,
  active           boolean not null default false,
  approved_by      uuid,                          -- founder/admin approval before first send
  approved_at      timestamptz,
  created_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now(),
  primary key (key, locale, version)
);

create table outbox (
  id                  uuid primary key default gen_random_uuid(),
  kind                email_kind not null,
  to_email            citext not null,
  to_submitter_id     uuid references submitters(id),
  template_key        text not null,
  locale              text not null default 'en',
  subject             text,                       -- rendered at send time if null
  variables           jsonb not null default '{}'::jsonb,
  idempotency_key     text unique,                -- e.g. 'film_ready:<film_id>'
  scheduled_for       timestamptz not null default now(),
  status              outbox_status not null default 'queued',
  attempts            integer not null default 0,
  next_attempt_at     timestamptz not null default now(),
  provider            text not null default 'resend',
  provider_message_id text unique,
  error               text,
  campaign_send_id    uuid,                        -- fk below
  created_by          uuid,
  created_at          timestamptz not null default now(),
  sent_at             timestamptz
);
create index outbox_drain_idx on outbox (next_attempt_at) where status in ('queued','failed');
create index outbox_recipient_idx on outbox (to_email, created_at desc);
create index outbox_submitter_idx on outbox (to_submitter_id, created_at desc);

create table email_events (
  id                bigserial primary key,
  provider          text not null default 'resend',
  provider_event_id text not null unique,
  provider_message_id text,
  outbox_id         uuid references outbox(id),
  event_type        text not null,                -- sent | delivered | delivery_delayed | bounced | complained | opened | clicked
  payload           jsonb not null,
  occurred_at       timestamptz not null default now()
);
create index email_events_outbox_idx on email_events (outbox_id, occurred_at desc);

create table suppressions (
  email      citext primary key,
  reason     suppression_reason not null,
  source     text,
  note       text,
  created_at timestamptz not null default now()
);

create table segments (
  id          uuid primary key default gen_random_uuid(),
  key         text not null unique,
  name        text not null,
  kind        text not null default 'dynamic' check (kind in ('dynamic','static')),
  definition  jsonb not null default '{}'::jsonb,  -- filter DSL evaluated by lib/platform/crm/segments.ts
  member_count integer,
  created_by  uuid,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);
create table segment_members (
  segment_id   uuid not null references segments(id) on delete cascade,
  submitter_id uuid not null references submitters(id) on delete cascade,
  added_at     timestamptz not null default now(),
  primary key (segment_id, submitter_id)
);

create table campaigns (
  id             uuid primary key default gen_random_uuid(),
  name           text not null,
  kind           email_kind not null default 'marketing',
  segment_id     uuid references segments(id),
  template_key   text not null,
  locale         text not null default 'en',
  subject_a      text,
  subject_b      text,
  ab_split_bp    integer not null default 0 check (ab_split_bp between 0 and 10000),
  scheduled_for  timestamptz,
  status         campaign_status not null default 'draft',
  approved_by    uuid,
  approved_at    timestamptz,
  stats          jsonb not null default '{}'::jsonb,
  created_by     uuid,
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now(),
  sent_at        timestamptz
);
create index campaigns_status_idx on campaigns (status, scheduled_for);

create table campaign_sends (
  id           uuid primary key default gen_random_uuid(),
  campaign_id  uuid not null references campaigns(id) on delete cascade,
  submitter_id uuid not null references submitters(id),
  email        citext not null,
  variant      text not null default 'a',
  outbox_id    uuid references outbox(id),
  created_at   timestamptz not null default now(),
  unique (campaign_id, submitter_id)
);
alter table outbox add constraint outbox_campaign_send_fk foreign key (campaign_send_id) references campaign_sends(id);

create table automations (
  id             uuid primary key default gen_random_uuid(),
  key            text not null unique,            -- welcome | consent_reminder | gate_open | film_advanced | film_eliminated | cart_abandon | invoice
  trigger_event  text not null,                   -- events.name that fires it
  delay_minutes  integer not null default 0,
  template_key   text not null,
  kind           email_kind not null default 'transactional',
  segment_guard_id uuid references segments(id),  -- recipient must be in this segment (e.g. not distributor)
  enabled        boolean not null default false,
  updated_by     uuid,
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now()
);

create table crm_activities (
  id            uuid primary key default gen_random_uuid(),
  submitter_id  uuid not null references submitters(id),
  film_id       uuid references films(id),
  kind          text not null,                    -- note | call | email_in | email_out | meeting | status | system
  body          text,
  actor_user_id uuid,
  metadata      jsonb not null default '{}'::jsonb,
  occurred_at   timestamptz not null default now(),
  created_at    timestamptz not null default now()
);
create index crm_activities_submitter_idx on crm_activities (submitter_id, occurred_at desc);

create table tasks (
  id               uuid primary key default gen_random_uuid(),
  title            text not null,
  body             text,
  submitter_id     uuid references submitters(id),
  film_id          uuid references films(id),
  assignee_user_id uuid,
  due_at           timestamptz,
  priority         integer not null default 3 check (priority between 1 and 5),
  status           task_status not null default 'open',
  created_by       uuid,
  created_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now(),
  completed_at     timestamptz
);
create index tasks_assignee_idx on tasks (assignee_user_id, status, due_at);

-- internal analytics + event bus (film views, votes, checkout funnel, automation triggers)
create table events (
  id            bigserial primary key,
  name          text not null,                    -- film.viewed | checkout.started | vote.counted | film.status_changed …
  actor_kind    text not null default 'anonymous' check (actor_kind in ('anonymous','submitter','staff','system')),
  submitter_id  uuid,
  film_id       uuid,
  gate_id       uuid,
  order_id      uuid,
  session_hash  bytea,
  country       text,
  properties    jsonb not null default '{}'::jsonb,
  processed_at  timestamptz,                      -- automations consumed it
  occurred_at   timestamptz not null default now()
);
create index events_name_time_idx on events (name, occurred_at desc);
create index events_film_idx on events (film_id, occurred_at desc) where film_id is not null;
create index events_unprocessed_idx on events (occurred_at) where processed_at is null;

select attach_updated_at(t) from unnest(array['email_templates','segments','campaigns','automations','tasks']) as t;
select attach_audit(t) from unnest(array[
  'email_templates','outbox','suppressions','segments','campaigns','campaign_sends','automations','crm_activities','tasks'
]) as t;
