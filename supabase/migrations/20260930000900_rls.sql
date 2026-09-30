-- 0900 · Row Level Security on EVERY table. Default deny.
-- Conventions:
--   * service_role (server-side only) bypasses RLS; the app calls decideAccess() before using it.
--   * founder/admin: full access everywhere (policy "admin_all").
--   * other staff roles: scoped policies below.
--   * filmmaker/distributor: rows where submitter_id = current_submitter_id().
--   * juror: BLIND — no policy at all on votes, gate_films, orders, order_lines, invoices, entitlements, submitters.
--   * anon: published/public content only; leaderboard only while flag('gates_public').

grant usage on schema public to anon, authenticated;
grant select, insert, update, delete on all tables in schema public to authenticated;
grant select, insert on all tables in schema public to anon;
grant usage, select on all sequences in schema public to anon, authenticated;
revoke insert on audit_log, settings, feature_flags, user_roles, invoices, votes, gates, gate_films from anon;
revoke update, delete on audit_log from anon, authenticated;
revoke delete on invoices, votes, orders, consents, audit_log, film_status_events, settings_history, gate_config_versions
  from anon, authenticated;

do $$
declare r record;
begin
  for r in select tablename from pg_tables where schemaname = 'public' loop
    execute format('alter table %I enable row level security', r.tablename);
    execute format('create policy admin_all on %I for all to authenticated using (is_admin()) with check (is_admin())', r.tablename);
  end loop;
end $$;

-- ---------- column guards for filmmakers (RLS is row-level; these keep non-staff from editing protected columns) ----------
create or replace function films_column_guard() returns trigger language plpgsql as $$
begin
  if auth.uid() is null or is_staff() or is_service() then return new; end if;  -- no JWT = server/trigger context
  if (new.submitter_id, new.status, new.public_visible, new.slug, new.deleted_at,
      new.screening_licence_at, new.gates_accepted_at)
     is distinct from
     (old.submitter_id, old.status, old.public_visible, old.slug, old.deleted_at,
      old.screening_licence_at, old.gates_accepted_at) then
    raise exception 'column not editable by filmmaker' using errcode = 'insufficient_privilege';
  end if;
  return new;
end $$;
create trigger films_column_guard before update on films for each row execute function films_column_guard();

create or replace function submitters_column_guard() returns trigger language plpgsql as $$
begin
  if auth.uid() is null or is_staff() or is_service() then return new; end if;  -- no JWT = server/trigger context
  if (new.email, new.email_hash, new.kind, new.auth_user_id, new.tags, new.films_count, new.notes, new.deleted_at, new.first_seen_platform)
     is distinct from
     (old.email, old.email_hash, old.kind, old.auth_user_id, old.tags, old.films_count, old.notes, old.deleted_at, old.first_seen_platform) then
    raise exception 'column not editable by filmmaker' using errcode = 'insufficient_privilege';
  end if;
  return new;
end $$;
create trigger submitters_column_guard before update on submitters for each row execute function submitters_column_guard();

-- [C-1] entries: a filmmaker may add a category only as pending_payment (it becomes active when the order is paid),
-- may switch the free primary only before confirming it, and can never touch paid_order_id/status directly.
create or replace function entries_column_guard() returns trigger language plpgsql as $$
declare v_confirmed timestamptz;
begin
  if auth.uid() is null or is_staff() or is_service() then return new; end if;
  if tg_op = 'INSERT' then
    if new.status <> 'pending_payment' or new.source <> 'dashboard' or new.paid_order_id is not null or new.is_primary then
      raise exception 'filmmaker may only add a pending additional category' using errcode = 'insufficient_privilege';
    end if;
    return new;
  end if;
  if (new.status, new.paid_order_id, new.source, new.submission_id, new.film_id) is distinct from
     (old.status, old.paid_order_id, old.source, old.submission_id, old.film_id) then
    raise exception 'column not editable by filmmaker' using errcode = 'insufficient_privilege';
  end if;
  if new.is_primary is distinct from old.is_primary or new.category_key is distinct from old.category_key then
    select primary_category_confirmed_at into v_confirmed from films where id = new.film_id;
    if v_confirmed is not null and not flag('filmmaker_category_change_after_confirm') then
      raise exception 'primary category already confirmed' using errcode = 'insufficient_privilege';
    end if;
  end if;
  return new;
end $$;
create trigger entries_column_guard before insert or update on entries for each row execute function entries_column_guard();

-- ---------- reference data readable by everyone ----------
create policy public_read on categories for select to anon, authenticated using (active);
create policy public_read on honours for select to anon, authenticated using (active);
create policy public_read on platforms for select to authenticated using (true);
create policy public_read on settings for select to anon, authenticated using (category = 'public');
create policy public_read on site_pages for select to anon, authenticated using (status = 'published');
create policy public_read on faqs for select to anon, authenticated using (published and audience in ('public','voter','press'));
create policy public_read on journal_posts for select to anon, authenticated using (status = 'published');
create policy public_read on programme_items for select to anon, authenticated using (status = 'published');
create policy public_read on venues for select to anon, authenticated using (true);
create policy public_read on results for select to anon, authenticated using (public_at is not null and public_at <= now());
-- [C-1] Gates rules are shown privately (dashboard, behind login) — never to anon while the model is unannounced.
create policy public_read on consent_texts for select to anon using (kind <> 'gates_rules');
create policy auth_read on consent_texts for select to authenticated using (kind <> 'gates_rules' or current_submitter_id() is not null or is_staff());

-- ---------- public films & leaderboard ----------
create policy public_read on films for select to anon, authenticated using (public_visible and deleted_at is null);
create policy public_read on film_assets for select to anon, authenticated
  using (kind in ('poster','still','trailer') and deleted_at is null
         and exists (select 1 from films f where f.id = film_assets.film_id and f.public_visible and f.deleted_at is null));
create policy public_read on gates for select to anon, authenticated
  using (flag('gates_public') and status in ('open','closing','closed'));
create policy public_read on gate_films for select to anon, authenticated
  using (flag('gates_public') and exists (select 1 from gates g where g.id = gate_films.gate_id and g.status in ('open','closing','closed')));
create policy public_read on laurels for select to anon, authenticated
  using (revoked_at is null and exists (select 1 from films f where f.id = laurels.film_id and f.public_visible));
create policy public_insert on events for insert to anon, authenticated with check (actor_kind = 'anonymous' and submitter_id is null);

-- ---------- staff (non-admin) ----------
create policy staff_read on submitters for select to authenticated using (is_staff());
create policy staff_read on people for select to authenticated using (is_staff());
create policy staff_read on films for select to authenticated using (is_staff());
create policy staff_read on submissions for select to authenticated using (is_staff());
create policy staff_read on entries for select to authenticated using (is_staff());
create policy staff_read on film_people for select to authenticated using (is_staff());
create policy staff_read on film_assets for select to authenticated using (is_staff());
create policy staff_read on consents for select to authenticated using (is_staff());
create policy staff_read on film_status_events for select to authenticated using (is_staff());
create policy staff_read on tags for select to authenticated using (is_staff());
create policy staff_read on film_tags for select to authenticated using (is_staff());
create policy staff_read on decisions for select to authenticated using (is_staff());
create policy staff_read on documents for select to authenticated using (is_staff());
create policy staff_read on feature_flags for select to authenticated using (is_staff());
create policy staff_read on settings for select to authenticated using (is_staff());
create policy staff_all on film_notes for all to authenticated using (is_staff()) with check (is_staff());
create policy staff_all on tasks for all to authenticated using (is_staff()) with check (is_staff());
create policy staff_all on crm_activities for all to authenticated using (is_staff()) with check (is_staff());
create policy staff_read on laurels for select to authenticated using (is_staff());

-- support
create policy support_read on outbox for select to authenticated using (has_role('support'));
create policy support_read on email_events for select to authenticated using (has_role('support'));
create policy support_read on suppressions for select to authenticated using (has_role('support'));
create policy support_read on orders for select to authenticated using (has_role('support'));
create policy support_update on submitters for update to authenticated using (has_role('support')) with check (has_role('support'));

-- finance
create policy finance_all on products for all to authenticated using (has_role('finance')) with check (has_role('finance'));
create policy finance_all on prices for all to authenticated using (has_role('finance')) with check (has_role('finance'));
create policy finance_all on coupons for all to authenticated using (has_role('finance')) with check (has_role('finance'));
create policy finance_all on orders for all to authenticated using (has_role('finance')) with check (has_role('finance'));
create policy finance_read on order_lines for select to authenticated using (has_role('finance'));
create policy finance_all on invoices for all to authenticated using (has_role('finance')) with check (has_role('finance'));
create policy finance_all on refunds for all to authenticated using (has_role('finance')) with check (has_role('finance'));
create policy finance_read on entitlements for select to authenticated using (has_role('finance'));
create policy finance_read on number_counters for select to authenticated using (has_role('finance'));

-- screener
create policy screener_read on screening_assignments for select to authenticated
  using (has_role('screener') and screener_user_id = auth.uid());
create policy screener_update on screening_assignments for update to authenticated
  using (has_role('screener') and screener_user_id = auth.uid()) with check (screener_user_id = auth.uid());
create policy screener_read on screening_flags for select to authenticated
  using (has_role('screener') and exists (select 1 from screening_assignments a where a.film_id = screening_flags.film_id and a.screener_user_id = auth.uid()));
create policy screener_all on screening_decisions for all to authenticated
  using (has_role('screener') and decided_by = auth.uid())
  with check (has_role('screener') and decided_by = auth.uid()
              and exists (select 1 from screening_assignments a where a.film_id = screening_decisions.film_id and a.screener_user_id = auth.uid() and a.status = 'open'));

-- programmer
create policy programmer_all on programme_items for all to authenticated using (has_role('programmer')) with check (has_role('programmer'));
create policy programmer_all on venues for all to authenticated using (has_role('programmer')) with check (has_role('programmer'));

-- ---------- juror (blind) ----------
create policy juror_self on jurors for select to authenticated using (auth_user_id = auth.uid());
create policy juror_read on jury_assignments for select to authenticated using (juror_id = current_juror_id());
create policy juror_read on films for select to authenticated
  using (has_role('juror') and exists (select 1 from jury_assignments a where a.film_id = films.id and a.juror_id = current_juror_id()));
create policy juror_read on entries for select to authenticated
  using (has_role('juror') and exists (select 1 from jury_assignments a where a.film_id = entries.film_id and a.juror_id = current_juror_id()));
create policy juror_read on film_assets for select to authenticated
  using (has_role('juror') and kind in ('poster','still','trailer','screener','subtitles','script_pdf','photo') and deleted_at is null
         and exists (select 1 from jury_assignments a where a.film_id = film_assets.film_id and a.juror_id = current_juror_id()));
create policy juror_read on film_people for select to authenticated
  using (has_role('juror') and exists (select 1 from jury_assignments a where a.film_id = film_people.film_id and a.juror_id = current_juror_id()));
create policy juror_read on people for select to authenticated
  using (has_role('juror') and exists (select 1 from film_people fp join jury_assignments a on a.film_id = fp.film_id where fp.person_id = people.id and a.juror_id = current_juror_id()));
create policy juror_all on conflicts for all to authenticated using (juror_id = current_juror_id()) with check (juror_id = current_juror_id());
create policy juror_all on scores for all to authenticated
  using (juror_id = current_juror_id())
  with check (juror_id = current_juror_id() and exists (select 1 from jury_assignments a where a.film_id = scores.film_id and a.juror_id = current_juror_id() and a.round = scores.round));
create policy juror_read on scoring_rubrics for select to authenticated using (has_role('juror') and active);
-- NOTE: intentionally NO juror policy on votes, gate_films, gates, orders, order_lines, invoices, entitlements, submitters, results.

-- ---------- filmmaker / distributor (own rows) ----------
create policy owner_read on submitters for select to authenticated using (id = current_submitter_id());
create policy owner_update on submitters for update to authenticated using (id = current_submitter_id()) with check (id = current_submitter_id());
create policy owner_read on films for select to authenticated using (submitter_id = current_submitter_id() and deleted_at is null);
create policy owner_update on films for update to authenticated using (submitter_id = current_submitter_id()) with check (submitter_id = current_submitter_id());
create policy owner_read on submissions for select to authenticated using (submitter_id = current_submitter_id());
create policy owner_read on entries for select to authenticated
  using (exists (select 1 from films f where f.id = entries.film_id and f.submitter_id = current_submitter_id()));
create policy owner_write on entries for insert to authenticated
  with check (exists (select 1 from films f where f.id = entries.film_id and f.submitter_id = current_submitter_id()));
create policy owner_update on entries for update to authenticated
  using (exists (select 1 from films f where f.id = entries.film_id and f.submitter_id = current_submitter_id()))
  with check (exists (select 1 from films f where f.id = entries.film_id and f.submitter_id = current_submitter_id()));
create policy owner_all on people for all to authenticated using (submitter_id = current_submitter_id()) with check (submitter_id = current_submitter_id());
create policy owner_all on film_people for all to authenticated
  using (exists (select 1 from films f where f.id = film_people.film_id and f.submitter_id = current_submitter_id()))
  with check (exists (select 1 from films f where f.id = film_people.film_id and f.submitter_id = current_submitter_id()));
create policy owner_read on film_assets for select to authenticated
  using (exists (select 1 from films f where f.id = film_assets.film_id and f.submitter_id = current_submitter_id()));
create policy owner_write on film_assets for insert to authenticated
  with check (exists (select 1 from films f where f.id = film_assets.film_id and f.submitter_id = current_submitter_id()));
create policy owner_update on film_assets for update to authenticated
  using (exists (select 1 from films f where f.id = film_assets.film_id and f.submitter_id = current_submitter_id()))
  with check (exists (select 1 from films f where f.id = film_assets.film_id and f.submitter_id = current_submitter_id()));
create policy owner_read on upload_sessions for select to authenticated using (submitter_id = current_submitter_id());
create policy owner_read on consents for select to authenticated using (submitter_id = current_submitter_id());
create policy owner_insert on consents for insert to authenticated with check (submitter_id = current_submitter_id() and source = 'dashboard');
create policy owner_read on film_status_events for select to authenticated
  using (exists (select 1 from films f where f.id = film_status_events.film_id and f.submitter_id = current_submitter_id()));
create policy owner_read on screening_decisions for select to authenticated
  using (is_current and exists (select 1 from films f where f.id = screening_decisions.film_id and f.submitter_id = current_submitter_id()));
create policy owner_read on gate_films for select to authenticated
  using (exists (select 1 from films f where f.id = gate_films.film_id and f.submitter_id = current_submitter_id()));
-- (no join back to gate_films here: it would recurse with gate_films.public_read → gates)
create policy owner_read on gates for select to authenticated
  using (status in ('open','closing','closed') and current_submitter_id() is not null);
create policy owner_read on laurels for select to authenticated
  using (revoked_at is null and exists (select 1 from films f where f.id = laurels.film_id and f.submitter_id = current_submitter_id()));
create policy owner_read on orders for select to authenticated using (submitter_id = current_submitter_id());
create policy owner_read on order_lines for select to authenticated
  using (exists (select 1 from orders o where o.id = order_lines.order_id and o.submitter_id = current_submitter_id()));
create policy owner_read on invoices for select to authenticated
  using (exists (select 1 from orders o where o.id = invoices.order_id and o.submitter_id = current_submitter_id()));
create policy owner_read on entitlements for select to authenticated using (submitter_id = current_submitter_id());
create policy owner_read on outbox for select to authenticated using (to_submitter_id = current_submitter_id());
create policy owner_read on results for select to authenticated
  using (exists (select 1 from films f where f.id = results.film_id and f.submitter_id = current_submitter_id()));
create policy owner_read on faqs for select to authenticated using (published and audience = 'filmmaker');
create policy owner_insert on events for insert to authenticated with check (actor_kind = 'submitter' and submitter_id = current_submitter_id());
