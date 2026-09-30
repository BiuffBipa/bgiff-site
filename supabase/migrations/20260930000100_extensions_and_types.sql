-- 0100 · Extensions and enum types
-- All BGIFF platform objects live in the `public` schema of the dedicated project.
-- (For the shared-project option see supabase/scripts/set-schema.sh.)

create extension if not exists pgcrypto;
create extension if not exists citext;
create extension if not exists pg_trgm;
create extension if not exists unaccent;

create type role_key as enum (
  'founder','admin','screener','programmer','juror','support','finance','filmmaker','distributor'
);

create type submitter_kind as enum ('filmmaker','distributor','school','agency','other');

create type work_kind as enum ('film','screenplay','photography');

create type film_status as enum (
  'imported','precheck','in_screening','needs_info','eligible','ineligible',
  'in_gates','jury','honoured','eliminated','withdrawn'
);

create type entry_status as enum ('active','superseded','withdrawn');

create type asset_kind as enum (
  'poster','still','trailer','screener','full_file','subtitles','script_pdf','photo','laurel','other'
);
create type asset_provider as enum ('bunny','supabase','external');
create type asset_status as enum ('pending','uploading','processing','ready','failed','removed');

create type flag_severity as enum ('info','warning','blocker');
create type screening_decision as enum ('eligible','ineligible','needs_info');

create type gate_status as enum ('draft','scheduled','open','closing','closed','cancelled');
create type gate_film_status as enum ('active','through','eliminated','withdrawn');
create type vote_status as enum ('counted','reversed');

-- [C-1] additional_category = paid consideration of the SAME work in another main category (bought before screening);
--       honour_consideration  = craft/technical/identity/special honours — separate products, timing/pricing NOT final.
create type product_kind as enum (
  'vote','additional_category','honour_consideration','laurel_print','feedback','promo',
  'table_read','b2b_package','ticket','other'
);
create type order_kind as enum ('vote','addon','b2b','ticket');
create type order_status as enum ('draft','pending','paid','failed','refunded','partially_refunded','cancelled');
create type refund_kind as enum ('refund','chargeback');
create type invoice_status as enum ('issued','credited','void');

create type email_kind as enum ('transactional','marketing');
create type outbox_status as enum ('queued','sending','sent','failed','suppressed','cancelled');
create type suppression_reason as enum ('bounce','complaint','unsubscribe','manual');
create type campaign_status as enum ('draft','scheduled','sending','sent','cancelled');

create type proposal_status as enum ('proposed','approved','rejected','expired');
create type task_status as enum ('open','in_progress','done','cancelled');
create type webhook_status as enum ('received','processed','failed','ignored');
create type import_status as enum ('running','succeeded','partial','failed');
create type honour_kind as enum ('category','craft','identity','special','grand','gate','selection');
