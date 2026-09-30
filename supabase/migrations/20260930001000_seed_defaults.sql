-- 1000 · Seed: settings, feature flags (all OFF), categories, platforms, mapping presets, honours,
--        placeholder gates (draft), product skeletons (inactive), automations (disabled), venue, retention policies (disabled).
-- Every number here is a PLACEHOLDER the founder has not finalised; all are editable rows.

insert into settings (key, value, category, description) values
  ('festival.name',               '"Berlin Gate International Film Festival"', 'public',  'Festival name'),
  ('festival.short_name',         '"BGIFF"',                                   'public',  'Short name'),
  ('festival.edition',            '"2027"',                                    'public',  'Edition label'),
  ('festival.event_date',         '"2027-01-24"',                              'public',  'Berlin event date (placeholder, will change)'),
  ('festival.deadlines',          '[{"key":"regular","label":"Regular Deadline","date":"2026-10-05"},{"key":"late","label":"Late Deadline","date":"2026-11-01"},{"key":"extended","label":"Extended · Scripts & Photos","date":"2026-11-21"},{"key":"selection","label":"Official Selection","date":"2026-12-21"}]', 'public', 'Public deadlines (placeholders)'),
  ('festival.entry_target',       '5000',                                      'general', 'Entry target for cycle 1'),
  ('legal.operator',              '"Amira Pictures"',                          'legal',   'Trading name'),
  ('legal.owner',                 '"Amir Mahdi Morsali"',                      'legal',   'Owner / authorised representative'),
  ('legal.address',               '{"street":"Kantstraße 67","postal_code":"10627","city":"Berlin","country":"DE"}', 'legal', 'Registered address'),
  ('legal.email',                 '"info@bgiff.com"',                          'legal',   'Contact e-mail on Impressum and invoices'),
  ('legal.ust_idnr',              'null',                                      'legal',   'USt-IdNr — to be supplied by founder'),
  ('legal.vat_rate_bp',           '1900',                                      'legal',   'Default German VAT in basis points'),
  ('legal.oss_threshold_cents',   '1000000',                                   'legal',   'EU B2C distance-selling threshold (€10,000) for OSS monitor'),
  ('legal.invoice_prefix',        '"INV"',                                     'legal',   'Invoice number prefix'),
  ('legal.credit_note_prefix',    '"CN"',                                      'legal',   'Credit note prefix'),
  ('legal.order_prefix',          '"BG"',                                      'legal',   'Order number prefix'),
  ('contact.routing',             '{"hello":"info@bgiff.com","submissions":"info@bgiff.com","press":"info@bgiff.com","partners":"info@bgiff.com"}', 'general', 'All public addresses route to info@ until Workspace migration'),
  ('intake.distributor_threshold','10',                                        'intake',  'Films per submitter e-mail to be tagged distributor'),
  ('intake.dedup_runtime_tolerance_seconds', '120',                            'intake',  'Runtime tolerance when matching duplicates across platforms'),
  ('intake.dedup_fuzzy_threshold','0.85',                                      'intake',  'Trigram similarity above which a pair goes to dedup review'),
  ('intake.batch_size',           '1000',                                      'intake',  'Rows per import run'),
  ('gates.count',                 '5',                                         'gates',   'Planned number of gates (placeholder)'),
  ('gates.jury_pool_min',         '80',                                        'gates',   'Films entering jury stage, lower bound (placeholder)'),
  ('gates.jury_pool_max',         '120',                                       'gates',   'Films entering jury stage, upper bound (placeholder)'),
  ('gates.default_booking_fee_cents', '49',                                    'gates',   'Per-transaction booking fee (placeholder)'),
  ('gates.checkout_rate_limit',   '{"per_ip_per_10min":20,"per_email_per_10min":10}', 'gates', 'Checkout rate limits'),
  ('gates.max_qty_per_checkout',  '500',                                       'gates',   'Sanity cap per single checkout (no per-card limit by founder decision)'),
  ('email.transactional_domain',  '"mail.bgiff.com"',                          'email',   'Resend transactional sending domain'),
  ('email.marketing_domain',      '"news.bgiff.com"',                          'email',   'Resend marketing sending domain'),
  ('email.from_name',             '"Berlin Gate International Film Festival"', 'email',   'From name'),
  ('email.reply_to',              '"info@bgiff.com"',                          'email',   'Reply-to'),
  ('email.send_allowlist',        '[]',                                        'email',   'Non-production: only these addresses receive mail (empty = nobody)'),
  ('email.batch_size',            '500',                                       'email',   'Outbox rows per drain tick'),
  ('auth.magic_link_ttl_minutes', '15',                                        'auth',    'Magic link validity'),
  ('auth.magic_link_rate_limit',  '{"per_email_per_15min":5,"per_ip_per_15min":20}', 'auth', 'Magic link request limits'),
  ('media.max_upload_bytes',      '21474836480',                               'media',   '20 GB per full film file'),
  ('media.playback_token_ttl_seconds', '3600',                                 'media',   'Bunny signed playback URL TTL'),
  ('ai.default_model',            '"claude-fable-5-1"',                        'ai',      'Model for drafts and digest'),
  ('ai.cheap_model',              '"claude-haiku-4-5-20251001"',               'ai',      'Model for classification / pre-check'),
  ('ai.daily_digest_hour_utc',    '6',                                         'ai',      'Hour (UTC) the founder digest is generated'),
  ('brand.palette',               '{"gate_black":"#0B0B0D","screen_white":"#F5F4F0","concrete_grey":"#8A8A8E","signal_amber":"#E8A23A","ok":"#2E8B57","error":"#C0392B"}', 'public', 'Palette (proposal, not final)');

insert into feature_flags (key, enabled, description, requires_founder) values
  ('admin_enabled',                        false, 'Serve the admin control centre routes',                     false),
  ('filmmaker_dashboard_enabled',          false, 'Serve the filmmaker dashboard + magic links',                true),
  ('emails_enabled',                       false, 'Outbox actually sends transactional mail (else drafts only)', true),
  ('marketing_enabled',                    false, 'Campaign sends allowed',                                     true),
  ('online_screening_open',                false, 'Public film pages show the player',                           true),
  ('payments_live',                        false, 'Stripe live mode allowed',                                    true),
  ('gates_open',                           false, 'Vote checkout enabled',                                       true),
  ('gates_public',                         false, 'Gate mechanics + leaderboard visible on public site',         true),
  ('faq_autoreply',                        false, 'AI may auto-send FAQ replies',                                true),
  ('batch_approve_screening',              false, 'Admin may batch-approve AI screening proposals',              true),
  ('filmmaker_category_change_after_confirm', false, 'Filmmaker may change category after confirming',           false),
  ('intake_filmfreeway_api',               false, 'Hourly FilmFreeway API sync',                                 false),
  ('intake_webhooks',                      false, 'Accept FilmFreeway/FestHome webhooks',                        false),
  ('locale_de',                            false, 'German site version',                                         false);

insert into platforms (key, name, kinds, config, sort) values
  ('filmfreeway',      'FilmFreeway',        '{api,webhook,csv}', '{"festival_slug":"BGIFF","url":"https://filmfreeway.com/BGIFF"}', 1),
  ('festhome',         'FestHome',           '{webhook,csv}',     '{"festival_id":"10633","url":"https://festhome.com/f/10633"}',   2),
  ('sfilmmaker',       'Sfilmmaker',         '{csv}', '{}', 10),
  ('toujiang',         'Toujiang',           '{csv}', '{}', 11),
  ('shortfilmdepot',   'ShortFilmDepot',     '{csv}', '{}', 12),
  ('movibeta',         'Movibeta',           '{csv}', '{}', 13),
  ('clickforfestivals','Click for Festivals','{csv}', '{}', 14),
  ('filmfestplatform', 'FilmFestPlatform',   '{csv}', '{}', 15),
  ('filmfestivallife', 'Film Festival Life', '{csv}', '{}', 16),
  ('docfilmdepot',     'DocFilmDepot',       '{csv}', '{}', 17),
  ('festagent',        'Festagent',          '{csv}', '{}', 18),
  ('wfcn',             'WFCN',               '{csv}', '{}', 19),
  ('direct',           'Direct / manual',    '{csv}', '{}', 90);

-- Column presets are BEST-EFFORT guesses at the export formats (see DECISIONS_BUILD D-B07);
-- headers match case-insensitively after trimming; admin can edit these rows and re-run an import.
insert into import_mappings (platform_key, name, is_default, mapping, options) values
('filmfreeway', 'FilmFreeway CSV export (default)', true, '[
  {"target":"entry.external_id",     "source":["Submission ID","Tracking Number","ID"], "required":true},
  {"target":"entry.submitted_at",    "source":["Submission Date","Date Submitted"], "transform":"date"},
  {"target":"entry.category_raw",    "source":["Category","Categories","Submission Category"], "required":true},
  {"target":"entry.platform_status", "source":["Submission Status","Status"]},
  {"target":"entry.judging_status",  "source":["Judging Status"]},
  {"target":"entry.fee_cents",       "source":["Entry Fee","Submission Fee"], "transform":"money_cents"},
  {"target":"entry.external_url",    "source":["Project Link","Submission URL","URL"]},
  {"target":"submitter.email",       "source":["Submitter Email","Contact Email","Email"], "transform":"email", "required":true},
  {"target":"submitter.name",        "source":["Submitter Name","Contact Name"]},
  {"target":"submitter.country",     "source":["Country","Contact Country"], "transform":"country"},
  {"target":"submitter.phone",       "source":["Contact Phone","Phone"]},
  {"target":"film.title",            "source":["Project Title","Title","English Title"], "required":true},
  {"target":"film.original_title",   "source":["Original Title","Native Title"]},
  {"target":"film.runtime_seconds",  "source":["Runtime","Duration","Running Time"], "transform":"runtime"},
  {"target":"film.completion_year",  "source":["Completion Date","Year of Completion","Year"], "transform":"year"},
  {"target":"film.country_of_origin","source":["Country of Origin","Origin Country"], "transform":"country"},
  {"target":"film.countries",        "source":["Country of Filming","Countries of Production"], "transform":"country_list"},
  {"target":"film.languages",        "source":["Language","Languages"], "transform":"list"},
  {"target":"film.genres",           "source":["Genres","Genre"], "transform":"list"},
  {"target":"film.synopsis",         "source":["Synopsis","Logline / Synopsis"]},
  {"target":"film.logline",          "source":["Logline"]},
  {"target":"film.premiere_status",  "source":["Premiere Status"]},
  {"target":"film.is_student",       "source":["Student Project","Student"], "transform":"bool"},
  {"target":"film.is_first_film",    "source":["First-time Filmmaker","First Film"], "transform":"bool"},
  {"target":"film.ai_declaration",   "source":["AI Disclosure","AI Declaration","Use of AI"]},
  {"target":"people.directors",      "source":["Directors","Director"], "transform":"list"},
  {"target":"people.writers",        "source":["Writers","Writer"], "transform":"list"},
  {"target":"people.producers",      "source":["Producers","Producer"], "transform":"list"},
  {"target":"people.cast",           "source":["Key Cast","Cast"], "transform":"list"},
  {"target":"assets.screener_url",   "source":["Screener","Screener URL","Online Screener"]},
  {"target":"assets.screener_password","source":["Screener Password","Password"]},
  {"target":"assets.poster_url",     "source":["Poster","Poster URL"]},
  {"target":"assets.trailer_url",    "source":["Trailer","Trailer URL"]}
]', '{"delimiter":",","raggedRowStrategy":"error","dateFormats":["MMM d, yyyy","yyyy-MM-dd","MM/dd/yyyy"]}'),
('festhome', 'FestHome CSV/XLSX export (default)', true, '[
  {"target":"entry.external_id",     "source":["ID","Submission ID","Film ID","Id"], "required":true},
  {"target":"entry.submitted_at",    "source":["Submission date","Date","Registered"], "transform":"date"},
  {"target":"entry.category_raw",    "source":["Section","Category","Sections"], "required":true},
  {"target":"entry.platform_status", "source":["Status","State"]},
  {"target":"entry.external_url",    "source":["Link","URL","Festhome link"]},
  {"target":"submitter.email",       "source":["Email","E-mail","Contact email"], "transform":"email", "required":true},
  {"target":"submitter.name",        "source":["Contact","Contact name","Submitter"]},
  {"target":"submitter.country",     "source":["Contact country","Country of contact"], "transform":"country"},
  {"target":"submitter.phone",       "source":["Phone","Telephone"]},
  {"target":"film.title",            "source":["Title","English title","Film title"], "required":true},
  {"target":"film.original_title",   "source":["Original title","Original Title"]},
  {"target":"film.runtime_seconds",  "source":["Duration","Runtime","Length"], "transform":"runtime"},
  {"target":"film.completion_year",  "source":["Year","Production year"], "transform":"year"},
  {"target":"film.country_of_origin","source":["Country","Production country","Countries"], "transform":"country"},
  {"target":"film.languages",        "source":["Language","Languages","Original language"], "transform":"list"},
  {"target":"film.genres",           "source":["Genre","Genres"], "transform":"list"},
  {"target":"film.synopsis",         "source":["Synopsis","Short synopsis"]},
  {"target":"film.has_subtitles",    "source":["Subtitles","English subtitles"], "transform":"bool"},
  {"target":"people.directors",      "source":["Director","Directors","Director(s)"], "transform":"list"},
  {"target":"people.producers",      "source":["Producer","Producers"], "transform":"list"},
  {"target":"assets.screener_url",   "source":["Screener","Online screener","Video link","Link to film"]},
  {"target":"assets.screener_password","source":["Password","Screener password"]},
  {"target":"assets.poster_url",     "source":["Poster","Poster URL"]}
]', '{"delimiter":",","raggedRowStrategy":"merge-overflow","dateFormats":["yyyy-MM-dd","dd/MM/yyyy","dd-MM-yyyy"]}');

insert into categories (key, name, work_kind, online_screening, sort, aliases) values
  ('narrative_feature',   'Narrative Feature',                   'film', true, 10, '{"Narrative Feature","Feature Film","Feature Narrative"}'),
  ('narrative_short',     'Narrative Short',                     'film', true, 20, '{"Narrative Short","Short Film","Short Narrative"}'),
  ('low_budget_feature',  'Low-Budget Feature',                  'film', true, 30, '{"Low-Budget Feature","Low Budget Feature","Micro-Budget Feature"}'),
  ('feature_documentary', 'Feature Documentary',                 'film', true, 40, '{"Feature Documentary","Documentary Feature"}'),
  ('short_documentary',   'Short Documentary',                   'film', true, 50, '{"Short Documentary","Documentary Short"}'),
  ('animation',           'Animation',                           'film', true, 60, '{"Animation","Animated Film","Animated Short"}'),
  ('experimental',        'Experimental',                        'film', true, 70, '{"Experimental","Experimental Film"}'),
  ('music_video',         'Music Video',                         'film', true, 80, '{"Music Video"}'),
  ('student',             'Student',                             'film', true, 90, '{"Student","Student Film","Student Short"}'),
  ('first_film',          'First Film',                          'film', true, 100, '{"First Film","First-Time Filmmaker","Debut Film"}'),
  ('web_new_media',       'Web / New Media',                     'film', true, 110, '{"Web/New Media","Web / New Media","New Media","Web Series","Episodic"}'),
  ('ai_film',             'AI Film',                             'film', true, 120, '{"AI Film","AI-Assisted Film","AI Generated Film"}'),
  ('underground',         'Underground',                         'film', true, 130, '{"Underground","Underground Film"}'),
  ('lgbtq',               'LGBTQ+',                              'film', true, 140, '{"LGBTQ+","LGBTQ","LGBTQ+ Film","Queer Cinema"}'),
  ('feature_screenplay',  'Feature Screenplay',                  'screenplay', false, 150, '{"Feature Screenplay","Feature Script"}'),
  ('short_screenplay',    'Short Screenplay',                    'screenplay', false, 160, '{"Short Screenplay","Short Script"}'),
  ('cinematic_photography','Cinematic Photography',              'photography', false, 170, '{"Cinematic Photography"}'),
  ('documentary_photography','Documentary Photography',          'photography', false, 180, '{"Documentary Photography"}'),
  ('fine_art_photography','Conceptual & Fine-Art Photography',   'photography', false, 190, '{"Conceptual & Fine-Art Photography","Conceptual Photography","Fine Art Photography","Fine-Art Photography"}');

-- [C-1] placeholder fit rules for the "add category" picker (DRAFT; runtime cut-offs to be confirmed by founder)
update categories set fit_rules = jsonb_build_object('work_kind', 'film', 'min_runtime_seconds', 2400) where key in ('narrative_feature','low_budget_feature','feature_documentary');
update categories set fit_rules = jsonb_build_object('work_kind', 'film', 'max_runtime_seconds', 2399) where key in ('narrative_short','short_documentary');
update categories set fit_rules = jsonb_build_object('work_kind', 'film') where key in ('animation','experimental','music_video','web_new_media','ai_film','underground','lgbtq');
update categories set fit_rules = jsonb_build_object('work_kind', 'film', 'requires', array['is_student']) where key = 'student';
update categories set fit_rules = jsonb_build_object('work_kind', 'film', 'requires', array['is_first_film']) where key = 'first_film';
update categories set fit_rules = jsonb_build_object('work_kind', 'screenplay') where key in ('feature_screenplay','short_screenplay');
update categories set fit_rules = jsonb_build_object('work_kind', 'photography') where key in ('cinematic_photography','documentary_photography','fine_art_photography');

insert into honours (key, name, kind, category_key, sort)
  select 'best_' || key, 'Best ' || name, 'category', key, sort from categories;
insert into honours (key, name, kind, sort) values
  ('official_selection',   'Official Selection',          'selection', 1),
  ('grand_prize',          'Berlin Gate Grand Prize',     'grand',     2),
  ('special_jury',         'Special Jury Award',          'special',   3),
  ('craft_cinematography', 'Best Cinematography',         'craft',     300),
  ('craft_editing',        'Best Editing',                'craft',     310),
  ('craft_sound',          'Best Sound',                  'craft',     320),
  ('craft_score',          'Best Original Score',         'craft',     330),
  ('craft_performance',    'Best Performance',            'craft',     340),
  ('craft_production_design','Best Production Design',    'craft',     350),
  ('identity_human_rights','Human Rights Spotlight',      'identity',  400),
  ('identity_diaspora',    'Diaspora Voices',             'identity',  410),
  ('identity_emerging',    'Emerging Voice',              'identity',  420),
  ('gate_laurel',          'Gate Laurel',                 'gate',      900);

-- Placeholder gates: DRAFT, numbers are the brief's examples, founder has NOT finalised them.
insert into gates (n, name, threshold, capacity, vote_price_cents, booking_fee_cents, status, notes) values
  (1, 'Gate 1', 10, 1500, 100, 49, 'draft', 'PLACEHOLDER numbers from Build Brief v1 §3.5 — edit before scheduling'),
  (2, 'Gate 2', 15,  750, 200, 49, 'draft', 'PLACEHOLDER'),
  (3, 'Gate 3', 20,  375, 300, 49, 'draft', 'PLACEHOLDER'),
  (4, 'Gate 4', 25,  190, 500, 49, 'draft', 'PLACEHOLDER'),
  (5, 'Gate 5', 30,  100, 700, 49, 'draft', 'PLACEHOLDER');

-- Product skeletons, all INACTIVE and without prices (prices are not final).
-- [C-1] three product families, kept apart: additional competition categories (before screening),
-- honour consideration (craft/technical/identity/special — timing & pricing NOT final), and services.
insert into products (key, kind, name, requires_film, work_kinds, active, sort, metadata) values
  ('vote',                       'vote',                 'Audience vote',                                   true,  '{film}', false, 1,  '{}'),
  ('additional_category',        'additional_category',  'Additional competition category (same work)',     true,  '{film,screenplay,photography}', false, 10, '{"window":"before_initial_screening","guarantee":"none"}'),
  ('honour_consideration_craft', 'honour_consideration', 'Honour consideration: craft & technical',         true,  '{film}', false, 20, '{"status":"not_final"}'),
  ('honour_consideration_identity','honour_consideration','Honour consideration: identity & thematic',      true,  '{film,screenplay,photography}', false, 21, '{"status":"not_final"}'),
  ('honour_consideration_special','honour_consideration', 'Honour consideration: special jury',             true,  '{film,screenplay,photography}', false, 22, '{"status":"not_final"}'),
  ('laurel_print',               'laurel_print',         'Printed laurel & certificate',                    true,  '{film,screenplay,photography}', false, 30, '{}'),
  ('written_feedback',           'feedback',             'Professional written feedback',                   true,  '{film,screenplay,photography}', false, 31, '{}'),
  ('promo_package',              'promo',                'Promotion package',                               true,  '{film,screenplay,photography}', false, 32, '{}'),
  ('table_read',                 'table_read',           'Table read (screenplays)',                        true,  '{screenplay}', false, 33, '{}'),
  ('b2b_distributor_package',    'b2b_package',          'Distributor package',                             false, '{film}', false, 40, '{}');

-- [C-1] consent reminders are per kind; none bundles the three acts.
insert into automations (key, trigger_event, delay_minutes, template_key, kind, enabled) values
  ('welcome',                            'film.imported',   0,    'film_ready',                        'transactional', false),
  ('primary_category_confirm_reminder',  'film.imported',   4320, 'primary_category_confirm_reminder', 'transactional', false),
  ('consent_reminder_screening_licence', 'film.eligible',   4320, 'consent_reminder_screening_licence','transactional', false),
  ('consent_reminder_gates_rules',       'film.eligible',   7200, 'consent_reminder_gates_rules',      'transactional', false),
  ('marketing_double_optin',             'consent.marketing_requested', 0, 'marketing_confirm',        'transactional', false),
  ('gate_open',        'gate.opened',              0,    'gate_open',         'transactional', false),
  ('film_advanced',    'gate_film.through',        0,    'film_advanced',     'transactional', false),
  ('film_eliminated',  'gate_film.eliminated',     0,    'film_eliminated',   'transactional', false),
  ('cart_abandon',     'checkout.abandoned',       120,  'cart_abandon',      'marketing',     false),
  ('invoice',          'order.paid',               0,    'invoice',           'transactional', false);

insert into venues (name, address, city, country) values
  ('Regenbogenkino', 'Lausitzer Str. 21a, 10999 Berlin', 'Berlin', 'DE');

insert into retention_policies (table_name, column_name, days, action, enabled, note) values
  ('magic_link_tokens', 'created_at', 30,  'soft_delete', false, 'R-06: tokens are useless after expiry'),
  ('rate_limits',       'window_start', 2, 'soft_delete', false, 'housekeeping'),
  ('events',            'occurred_at', 400, 'anonymise',  false, 'strip session_hash after 13 months'),
  ('webhook_events',    'received_at', 400, 'anonymise',  false, 'strip raw payload PII after 13 months');

insert into tags (key, label, color) values
  ('distributor', 'Distributor', '#8A8A8E'), ('iran', 'Iran', '#E8A23A'), ('press_pick', 'Press pick', '#2E8B57'), ('watch', 'Watch', '#C0392B');
