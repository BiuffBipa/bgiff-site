-- Gates engine behaviour test (runs in CI after migrations; plain SQL assertions, no pgTAP needed)
begin;
set local search_path = public;

do $$
declare
  s uuid; g1 uuid; g2 uuid;
  fa uuid; fb uuid; fc uuid; fd uuid; fe uuid;
  o uuid; res jsonb; v_status gate_film_status; v_votes int; v_cnt int; v_vote uuid;
begin
  insert into submitters (email, email_hash, name) values ('gatetest@example.com', digest('gatetest@example.com','sha256'), 'Gate Tester') returning id into s;
  insert into films (submitter_id, title, status) values (s, 'Alpha', 'eligible') returning id into fa;
  insert into films (submitter_id, title, status) values (s, 'Bravo', 'eligible') returning id into fb;
  insert into films (submitter_id, title, status) values (s, 'Charlie', 'eligible') returning id into fc;
  insert into films (submitter_id, title, status) values (s, 'Delta (no gates consent, must be excluded)', 'eligible') returning id into fd;
  insert into films (submitter_id, title, status) values (s, 'Echo (screenplay, must be excluded)', 'eligible') returning id into fe;
  insert into entries (film_id, category_key, is_primary) values
    (fa, 'narrative_short', true), (fb, 'narrative_short', true), (fc, 'narrative_short', true),
    (fd, 'animation', true), (fe, 'short_screenplay', true);
  -- [C-1] a paid additional category for alpha (does not affect gates)
  insert into entries (film_id, category_key, is_primary, status, source) values (fa, 'experimental', false, 'active', 'dashboard');
  begin
    insert into entries (film_id, category_key, is_primary) values (fa, 'animation', true);
    raise exception 'second primary entry must be rejected';
  exception when unique_violation then null;
  end;

  -- [C-1] three separate consents: licence + gates rules per film (Delta gets licence only)
  insert into consent_texts (kind, version, title, body_md) values
    ('screening_licence', 'test-1', 'Licence', 'licence text'), ('gates_rules', 'test-1', 'Gates rules', 'rules text'), ('marketing', 'test-1', 'News', 'marketing text');
  insert into consents (submitter_id, film_id, kind, consent_text_id, source)
    select s, f, 'screening_licence', (select id from consent_texts where kind = 'screening_licence'), 'dashboard' from unnest(array[fa, fb, fc, fd, fe]) as f;
  insert into consents (submitter_id, film_id, kind, consent_text_id, source)
    select s, f, 'gates_rules', (select id from consent_texts where kind = 'gates_rules'), 'dashboard' from unnest(array[fa, fb, fc, fe]) as f;
  assert (select gates_accepted_at from films where id = fa) is not null, 'gates_rules consent stamps the film';
  assert (select text_snapshot from consents where film_id = fa and kind = 'gates_rules') = 'rules text', 'consent keeps a text snapshot';
  assert (select gates_accepted_at from films where id = fd) is null, 'delta has no gates acceptance';
  begin
    insert into consents (submitter_id, film_id, kind, consent_text_id, source) values (s, fa, 'marketing', (select id from consent_texts where kind = 'marketing'), 'dashboard');
    raise exception 'marketing consent must not be film-scoped';
  exception when check_violation then null;
  end;
  begin
    insert into consents (submitter_id, film_id, kind, consent_text_id, source) values (s, fa, 'gates_rules', (select id from consent_texts where kind = 'marketing'), 'dashboard');
    raise exception 'kind/text mismatch must be rejected';
  exception when raise_exception then null;
  end;

  -- reconfigure the placeholder gates for the test: gate 1 threshold 3, capacity 2
  update gates set threshold = 3, capacity = 2, closes_at = now() + interval '1 day', opens_at = now() where n = 1 returning id into g1;
  select id into g2 from gates where n = 2;
  assert (select config_version from gates where id = g1) = 2, 'config version bumps on parameter change';
  assert (select count(*) from gate_config_versions where gate_id = g1) = 2, 'config history kept';

  -- votes before opening must fail
  insert into orders (kind, status, buyer_email, buyer_email_hash, total_cents) values ('vote','paid','buyer@example.com', digest('buyer@example.com','sha256'), 349) returning id into o;
  begin
    insert into votes (gate_id, film_id, order_id, qty, buyer_email_hash, stripe_event_id) values (g1, fa, o, 1, digest('x','sha256'), 'evt_pre');
    raise exception 'vote on a draft gate must be rejected';
  exception when check_violation then null;
  end;

  perform open_gate(g1);
  assert (select count(*) from gate_films where gate_id = g1) = 3, 'gate 1 receives only films with licence + gates acceptance in an online category';
  assert (select count(*) from gate_films where gate_id = g1 and film_id = fd) = 0, 'no gates acceptance → not in gate';
  assert (select status from films where id = fa) = 'in_gates', 'film status moves to in_gates';
  assert (select status from films where id = fe) = 'eligible', 'screenplay stays out of gates';

  -- idempotency: same stripe event twice
  insert into votes (gate_id, film_id, order_id, qty, buyer_email_hash, stripe_event_id) values (g1, fa, o, 2, digest('x','sha256'), 'evt_1');
  begin
    insert into votes (gate_id, film_id, order_id, qty, buyer_email_hash, stripe_event_id) values (g1, fa, o, 2, digest('x','sha256'), 'evt_1');
    raise exception 'duplicate stripe event must be rejected';
  exception when unique_violation then null;
  end;
  select votes, status into v_votes, v_status from gate_films where gate_id = g1 and film_id = fa;
  assert v_votes = 2 and v_status = 'active', format('alpha has 2 votes, active (got %s %s)', v_votes, v_status);

  -- threshold reached → through
  insert into votes (gate_id, film_id, order_id, qty, buyer_email_hash, stripe_event_id) values (g1, fa, o, 1, digest('x','sha256'), 'evt_2') returning id into v_vote;
  select votes, status into v_votes, v_status from gate_films where gate_id = g1 and film_id = fa;
  assert v_votes = 3 and v_status = 'through', 'alpha through at threshold';

  -- late vote after through is stored but reversed, counter unchanged
  insert into votes (gate_id, film_id, order_id, qty, buyer_email_hash, stripe_event_id) values (g1, fa, o, 5, digest('x','sha256'), 'evt_late');
  assert (select status from votes where stripe_event_id = 'evt_late') = 'reversed', 'late vote reversed';
  assert (select votes from gate_films where gate_id = g1 and film_id = fa) = 3, 'late vote not counted';

  -- refund while open drops film back to active
  update votes set status = 'reversed', reversed_reason = 'refund' where id = v_vote;
  -- (reversal audit) 
  select votes, status into v_votes, v_status from gate_films where gate_id = g1 and film_id = fa;
  assert v_votes = 2 and v_status = 'active', 'refund reverses through';
  begin
    update votes set status = 'counted' where id = v_vote;
    raise exception 'reversed vote must not be re-counted';
  exception when raise_exception then null;
  end;
  insert into votes (gate_id, film_id, order_id, qty, buyer_email_hash, stripe_event_id) values (g1, fa, o, 1, digest('x','sha256'), 'evt_3');

  -- bravo 2, charlie 1
  insert into votes (gate_id, film_id, order_id, qty, buyer_email_hash, stripe_event_id) values (g1, fb, o, 2, digest('y','sha256'), 'evt_4');
  insert into votes (gate_id, film_id, order_id, qty, buyer_email_hash, stripe_event_id) values (g1, fc, o, 1, digest('y','sha256'), 'evt_5');
  begin
    insert into votes (gate_id, film_id, order_id, qty, buyer_email_hash, stripe_event_id) values (g1, fd, o, 1, digest('y','sha256'), 'evt_delta');
    raise exception 'vote for a film outside the gate must be rejected';
  exception when check_violation then null;
  end;

  -- not due yet (1 through < capacity 2, time not over)
  res := close_gate(g1);
  assert (res ->> 'noop')::boolean, 'close is a no-op when not due';

  -- time window ends → close: remaining slot goes to bravo, charlie eliminated with a laurel
  update gates set opens_at = now() - interval '1 hour', closes_at = now() - interval '1 second' where id = g1;
  assert gate_should_close(g1), 'gate is due after closes_at';
  res := close_gate(g1);
  assert (res ->> 'through')::int = 2, format('2 films through (%s)', res);
  assert (select status from gate_films where gate_id = g1 and film_id = fb) = 'through', 'bravo promoted by rank';
  assert (select status from gate_films where gate_id = g1 and film_id = fc) = 'eliminated', 'charlie eliminated';
  assert (select rank_at_close from gate_films where gate_id = g1 and film_id = fa) = 1, 'alpha rank 1';
  assert (select rank_at_close from gate_films where gate_id = g1 and film_id = fb) = 2, 'bravo rank 2';
  assert (select rank_at_close from gate_films where gate_id = g1 and film_id = fc) = 3, 'charlie rank 3';
  select count(*) into v_cnt from laurels where gate_id = g1 and kind = 'gate';
  assert v_cnt = 1, format('1 gate laurel issued (%s)', v_cnt);
  assert (select status from films where id = fc) = 'eliminated', 'film status eliminated';
  assert (select status from gates where id = g1) = 'closed', 'gate closed';
  assert (close_gate(g1) ->> 'noop')::boolean, 'closing twice is a no-op';

  -- frozen parameters after close
  begin
    update gates set threshold = 99 where id = g1;
    raise exception 'closed gate parameters must be frozen';
  exception when raise_exception then null;
  end;

  -- post-close reversal raises a fraud alert, does not change outcome
  update votes set status = 'reversed', reversed_reason = 'chargeback' where stripe_event_id = 'evt_4';
  assert (select status from gate_films where gate_id = g1 and film_id = fb) = 'through', 'outcome unchanged after close';
  assert (select count(*) from fraud_alerts where kind = 'post_close_reversal' and film_id = fb) = 1, 'fraud alert raised';

  -- gate 2 opens with only the films that went through gate 1, votes reset to 0
  perform open_gate(g2);
  assert (select count(*) from gate_films where gate_id = g2) = 2, 'gate 2 has 2 films';
  assert (select max(votes) from gate_films where gate_id = g2) = 0, 'votes reset to zero';

  -- audit log captured the manual gate edit and the votes
  assert (select count(*) from audit_log where table_name = 'votes') >= 6, 'votes audited';
  raise notice 'gates.sql: all assertions passed';
end $$;

rollback;
