drop table if exists programme_items, venues, journal_posts, faqs, site_pages, retention_policies, cron_runs, agent_proposals cascade;
alter table if exists screening_flags drop constraint if exists screening_flags_agent_run_fk;
drop table if exists agent_runs cascade;
