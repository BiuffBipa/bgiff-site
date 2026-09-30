drop table if exists events, tasks, crm_activities, automations cascade;
alter table if exists outbox drop constraint if exists outbox_campaign_send_fk;
drop table if exists campaign_sends, campaigns, segment_members, segments, suppressions, email_events, outbox, email_templates cascade;
