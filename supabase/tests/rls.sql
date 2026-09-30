-- RLS behaviour test per role (plain SQL assertions). Runs as a superuser that switches role.
begin;
set local search_path = public;

-- fixtures ------------------------------------------------------------------
insert into auth.users (id, email) values
  ('00000000-0000-0000-0000-000000000001', 'admin@bgiff.test'),
  ('00000000-0000-0000-0000-000000000002', 'juror@bgiff.test'),
  ('00000000-0000-0000-0000-000000000003', 'maker1@bgiff.test'),
  ('00000000-0000-0000-0000-000000000004', 'maker2@bgiff.test'),
  ('00000000-0000-0000-0000-000000000005', 'screener@bgiff.test'),
  ('00000000-0000-0000-0000-000000000006', 'finance@bgiff.test');
insert into user_roles (auth_user_id, role) values
  ('00000000-0000-0000-0000-000000000001', 'admin'),
  ('00000000-0000-0000-0000-000000000002', 'juror'),
  ('00000000-0000-0000-0000-000000000003', 'filmmaker'),
  ('00000000-0000-0000-0000-000000000004', 'filmmaker'),
  ('00000000-0000-0000-0000-000000000005', 'screener'),
  ('00000000-0000-0000-0000-000000000006', 'finance');
insert into submitters (id, email, email_hash, name, auth_user_id) values
  ('10000000-0000-0000-0000-000000000001', 'maker1@bgiff.test', digest('maker1@bgiff.test','sha256'), 'Maker One', '00000000-0000-0000-0000-000000000003'),
  ('10000000-0000-0000-0000-000000000002', 'maker2@bgiff.test', digest('maker2@bgiff.test','sha256'), 'Maker Two', '00000000-0000-0000-0000-000000000004');
insert into films (id, submitter_id, title, status) values
  ('20000000-0000-0000-0000-000000000001', '10000000-0000-0000-0000-000000000001', 'Film One', 'eligible'),
  ('20000000-0000-0000-0000-000000000002', '10000000-0000-0000-0000-000000000002', 'Film Two', 'eligible');
insert into entries (id, film_id, category_key, is_primary) values
  ('50000000-0000-0000-0000-000000000001', '20000000-0000-0000-0000-000000000001', 'narrative_short', true),
  ('50000000-0000-0000-0000-000000000002', '20000000-0000-0000-0000-000000000002', 'narrative_short', true);
insert into consent_texts (id, kind, version, title, body_md) values
  ('60000000-0000-0000-0000-000000000001', 'screening_licence', 'rls-1', 'Licence', 'licence'),
  ('60000000-0000-0000-0000-000000000002', 'gates_rules', 'rls-1', 'Gates rules', 'CONFIDENTIAL rules'),
  ('60000000-0000-0000-0000-000000000003', 'marketing', 'rls-1', 'News', 'news');
insert into consents (submitter_id, film_id, kind, consent_text_id, source) values
  ('10000000-0000-0000-0000-000000000001', '20000000-0000-0000-0000-000000000001', 'screening_licence', '60000000-0000-0000-0000-000000000001', 'dashboard'),
  ('10000000-0000-0000-0000-000000000001', '20000000-0000-0000-0000-000000000001', 'gates_rules', '60000000-0000-0000-0000-000000000002', 'dashboard'),
  ('10000000-0000-0000-0000-000000000002', '20000000-0000-0000-0000-000000000002', 'screening_licence', '60000000-0000-0000-0000-000000000001', 'dashboard'),
  ('10000000-0000-0000-0000-000000000002', '20000000-0000-0000-0000-000000000002', 'gates_rules', '60000000-0000-0000-0000-000000000002', 'dashboard');
insert into jurors (id, auth_user_id, name, email) values ('30000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000002', 'Jury Member', 'juror@bgiff.test');
insert into jury_assignments (juror_id, film_id) values ('30000000-0000-0000-0000-000000000001', '20000000-0000-0000-0000-000000000001');
update gates set opens_at = now(), closes_at = now() + interval '1 day' where n = 1;
select open_gate(id) from gates where n = 1;
insert into orders (id, kind, status, submitter_id, buyer_email, buyer_email_hash, total_cents) values
  ('40000000-0000-0000-0000-000000000001', 'vote', 'paid', null, 'voter@bgiff.test', digest('voter@bgiff.test','sha256'), 149),
  ('40000000-0000-0000-0000-000000000002', 'addon', 'paid', '10000000-0000-0000-0000-000000000001', 'maker1@bgiff.test', digest('maker1@bgiff.test','sha256'), 4900);
insert into votes (gate_id, film_id, order_id, qty, buyer_email_hash, stripe_event_id)
  select id, '20000000-0000-0000-0000-000000000001', '40000000-0000-0000-0000-000000000001', 1, digest('v','sha256'), 'evt_rls_1' from gates where n = 1;
insert into screening_assignments (film_id, screener_user_id) values ('20000000-0000-0000-0000-000000000002', '00000000-0000-0000-0000-000000000005');

create or replace function pg_temp.as_user(p_uid text, p_role text default 'authenticated') returns void language plpgsql as $$
begin
  perform set_config('request.jwt.claims', json_build_object('sub', p_uid, 'role', p_role)::text, true);
  execute format('set local role %I', p_role);
end $$;
create or replace function pg_temp.as_admin() returns void language plpgsql as $$
begin
  perform set_config('request.jwt.claims', '', true);
  reset role;
end $$;

-- anon ---------------------------------------------------------------------------
select pg_temp.as_user('', 'anon');
do $$ begin
  assert (select count(*) from films) = 0, 'anon sees no non-public films';
  assert (select count(*) from submitters) = 0, 'anon sees no submitters';
  assert (select count(*) from gate_films) = 0, 'anon sees no leaderboard while gates_public is off';
  assert (select count(*) from categories) = 19, 'anon sees categories';
  assert (select count(*) from settings where category <> 'public') = 0, 'anon sees only public settings';
  assert (select count(*) from settings) > 0, 'anon sees public settings';
  assert (select count(*) from consent_texts where kind = 'gates_rules') = 0, 'anon never sees the gates rules text';
  assert (select count(*) from consent_texts) = 2, 'anon sees licence + marketing texts';
end $$;
select pg_temp.as_admin();
update feature_flags set enabled = true where key = 'gates_public';
update films set public_visible = true where id = '20000000-0000-0000-0000-000000000001';
select pg_temp.as_user('', 'anon');
do $$ begin
  assert (select count(*) from films) = 1, 'anon sees the public film';
  assert (select count(*) from gate_films) = 2, 'anon sees leaderboard once gates_public is on';
  assert (select count(*) from gate_leaderboard) = 1, 'leaderboard view (security_invoker) shows only public films to anon';
  assert (select count(*) from votes) = 0, 'anon never sees vote rows';
  assert (select count(*) from orders) = 0, 'anon never sees orders';
end $$;
select pg_temp.as_admin();
update feature_flags set enabled = false where key = 'gates_public';

-- juror (blind) ------------------------------------------------------------------
select pg_temp.as_user('00000000-0000-0000-0000-000000000002');
do $$ begin
  assert (select count(*) from films) = 1, 'juror sees only assigned film';
  assert (select count(*) from entries) = 1, 'juror sees entries of assigned film only';
  assert (select count(*) from consents) = 0, 'juror cannot see consents';
  assert (select count(*) from votes) = 0, 'juror cannot see votes';
  assert (select count(*) from gate_films) = 0, 'juror cannot see gate standings';
  assert (select count(*) from orders) = 0, 'juror cannot see orders';
  assert (select count(*) from entitlements) = 0, 'juror cannot see entitlements';
  assert (select count(*) from submitters) = 0, 'juror cannot see submitter identities';
  assert (select count(*) from jury_assignments) = 1, 'juror sees own assignment';
end $$;
do $$ begin
  insert into scores (juror_id, film_id, rubric_id, values)
  values ('30000000-0000-0000-0000-000000000001', '20000000-0000-0000-0000-000000000002', gen_random_uuid(), '{}');
  raise exception 'juror scored an unassigned film';
exception when insufficient_privilege or foreign_key_violation then null;
end $$;

-- filmmaker 1 ----------------------------------------------------------------------
select pg_temp.as_user('00000000-0000-0000-0000-000000000003');
do $$ begin
  assert current_submitter_id() = '10000000-0000-0000-0000-000000000001', 'current_submitter_id resolves';
  assert (select count(*) from films) = 1 and (select title from films) = 'Film One', 'filmmaker sees only own film';
  assert (select count(*) from submitters) = 1, 'filmmaker sees only self';
  assert (select count(*) from orders) = 1, 'filmmaker sees own order only';
  assert (select count(*) from votes) = 0, 'filmmaker cannot see vote rows';
  assert (select count(*) from gate_films) = 1, 'filmmaker sees own gate position';
  assert (select votes from gate_films) = 1, 'filmmaker sees own vote count';
  update films set logline = 'edited by owner' where id = '20000000-0000-0000-0000-000000000001';
  assert (select logline from films where id = '20000000-0000-0000-0000-000000000001') = 'edited by owner', 'filmmaker may edit own logline';
  update films set logline = 'hack' where id = '20000000-0000-0000-0000-000000000002';
  assert (select count(*) from films where logline = 'hack') = 0, 'filmmaker cannot edit other film (0 rows)';
  assert (select count(*) from consent_texts where kind = 'gates_rules') = 1, 'logged-in filmmaker can read the gates rules privately';
  assert (select count(*) from entries) = 1, 'filmmaker sees own entries';
  assert (select count(*) from consents) = 2, 'filmmaker sees own consents';
  -- [C-1] add an additional category as pending payment
  insert into entries (film_id, category_key, source, status) values ('20000000-0000-0000-0000-000000000001', 'experimental', 'dashboard', 'pending_payment');
  assert (select count(*) from entries where film_id = '20000000-0000-0000-0000-000000000001') = 2, 'pending additional category created';
  -- [C-1] grant marketing consent (double opt-in pending until confirmed)
  insert into consents (submitter_id, kind, consent_text_id, source) values ('10000000-0000-0000-0000-000000000001', 'marketing', '60000000-0000-0000-0000-000000000003', 'dashboard');
  assert (select marketing_status from submitters where id = '10000000-0000-0000-0000-000000000001') = 'pending', 'marketing consent is pending until confirmed';
end $$;
do $$ begin
  insert into entries (film_id, category_key, source, status) values ('20000000-0000-0000-0000-000000000001', 'animation', 'dashboard', 'active');
  raise exception 'filmmaker activated a category without paying';
exception when insufficient_privilege then null;
end $$;
do $$ begin
  update films set gates_accepted_at = now() + interval '1 day' where id = '20000000-0000-0000-0000-000000000001';
  raise exception 'filmmaker set gates_accepted_at directly';
exception when insufficient_privilege then null;
end $$;
do $$ begin
  insert into consents (submitter_id, film_id, kind, consent_text_id, source) values ('10000000-0000-0000-0000-000000000001', '20000000-0000-0000-0000-000000000001', 'screening_licence', '60000000-0000-0000-0000-000000000001', 'import');
  raise exception 'filmmaker inserted a consent with a non-dashboard source';
exception when insufficient_privilege then null;
end $$;
do $$ begin
  update films set status = 'honoured' where id = '20000000-0000-0000-0000-000000000001';
  raise exception 'filmmaker changed status';
exception when insufficient_privilege then null;
end $$;
do $$ begin
  update submitters set kind = 'distributor' where id = '10000000-0000-0000-0000-000000000001';
  raise exception 'filmmaker changed own kind';
exception when insufficient_privilege then null;
end $$;

-- screener --------------------------------------------------------------------------
select pg_temp.as_user('00000000-0000-0000-0000-000000000005');
do $$ begin
  assert (select count(*) from films) = 2, 'screener (staff) can read films';
  assert (select count(*) from votes) = 0, 'screener cannot see votes';
  assert (select count(*) from orders) = 0, 'screener cannot see orders';
  insert into screening_decisions (film_id, decision, decided_by) values ('20000000-0000-0000-0000-000000000002', 'eligible', '00000000-0000-0000-0000-000000000005');
end $$;
do $$ begin
  insert into screening_decisions (film_id, decision, decided_by) values ('20000000-0000-0000-0000-000000000001', 'eligible', '00000000-0000-0000-0000-000000000005');
  raise exception 'screener decided on unassigned film';
exception when insufficient_privilege then null;
end $$;

-- finance -----------------------------------------------------------------------------
select pg_temp.as_user('00000000-0000-0000-0000-000000000006');
do $$ begin
  assert (select count(*) from orders) = 2, 'finance sees all orders';
  assert (select count(*) from films) = 2, 'finance (staff) reads films';
  assert (select count(*) from scores) = 0, 'finance cannot see jury scores';
end $$;

-- admin ---------------------------------------------------------------------------------
select pg_temp.as_user('00000000-0000-0000-0000-000000000001');
do $$ begin
  assert (select count(*) from votes) = 1, 'admin sees votes';
  assert (select count(*) from audit_log) > 0, 'admin reads audit log';
  update audit_log set reason = 'tamper' where id = (select min(id) from audit_log);
  assert (select count(*) from audit_log where reason = 'tamper') = 0, 'audit log is append-only';
  delete from audit_log;
  assert (select count(*) from audit_log) > 0, 'audit log cannot be deleted';
end $$;

select pg_temp.as_admin();
do $$ begin raise notice 'rls.sql: all assertions passed'; end $$;
rollback;
