drop function if exists tag_distributors();
drop function if exists consents_stamp() cascade;
drop function if exists consents_apply() cascade;
drop table if exists consents, consent_texts, film_tags, tags, film_notes, film_status_events, dedup_candidates,
  upload_sessions, film_assets, film_people cascade;
drop table if exists entries, submissions cascade;
drop function if exists films_status_event() cascade;
drop function if exists submitters_films_count_sync() cascade;
drop table if exists films cascade;
drop function if exists normalize_title(text);
drop table if exists categories, people cascade;
drop function if exists current_submitter_id();
alter table if exists magic_link_tokens drop constraint if exists magic_link_tokens_submitter_fk;
drop table if exists submitters, import_errors, import_runs, webhook_events, import_mappings, platforms cascade;
