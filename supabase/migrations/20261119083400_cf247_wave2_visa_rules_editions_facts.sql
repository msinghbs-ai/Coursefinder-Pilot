-- CF-247 s716: next-wave visa-rules editions and facts, first runs through the Layer 1 schedule (S2-Build; Platform Admin 19 Nov 2026 06:45 and
-- 06:50: "execute initial Storage → Evidence → Edition runs, approve open-licence terms, and publish verified editions").
--
-- What was read (19 Nov 2026 07:45 AEDT): GOV.UK "Money you need" states "£1,529 per month (for up to 9 months) for courses in London" and
-- "£1,171 per month (for up to 9 months) for courses outside London", and "All content is available under the Open Government Licence v3.0";
-- USCIS states "up to 12 months of OPT employment authorization"; Immigration New Zealand's student fund page states "NZD $20,000 for each year"
-- (client-rendered; no reuse statement was readable).
-- What it changes (rows in existing tables; no new table or function; G3 75/48):
--   * Three draft study-rules editions: United Kingdom (terms approved: Open Government Licence v3.0), United States (terms approved: U.S.
--     Government work, public domain), New Zealand (terms pending until the site's reuse terms are confirmed; read and held, not published).
--   * Facts (destination.page_facts):
--       - NZ: the annual living-cost amount (visa_funds, NZD a year; read rendered).
--       - GB: the two monthly maintenance amounts as quoted text facts (London, outside London). They are monthly for up to 9 months, so they are
--         not written as an annual living cost (the loader's annual field would misstate them).
--       - US: the OPT length as a quoted text fact (months, not years, so not written to the years field).
--   * The NZ, GB and US visa-rules sources are due 55 minutes after this change, after the LIN 19/198 run of the same hour, so the two runs
--     never open a successor edition at the same time; the hourly destination-open-licence-publish publishes editions whose terms are approved.
-- Nothing is dropped or deleted.
-- Replaces: nothing.
-- Retires: nothing.

insert into destination.editions(country_id, domain, edition_label, effective_from, status, source_url, source_owner, attribution_text, terms_status, last_checked_at)
select c.id, 'study_rules', v.label, current_date, 'draft', v.url, v.owner, v.attr, v.terms, now()
  from (values
    ('GB', 'UKVI Student visa pages (GOV.UK)', 'https://www.gov.uk/student-visa/money', 'UK Visas and Immigration (Home Office)',
     'Source: GOV.UK (UK Visas and Immigration). Contains public sector information licensed under the Open Government Licence v3.0.', 'approved'),
    ('US', 'USCIS F-1 Optional Practical Training pages', 'https://www.uscis.gov/node/50597', 'U.S. Citizenship and Immigration Services',
     'Source: U.S. Citizenship and Immigration Services, uscis.gov (U.S. Government work, public domain).', 'approved'),
    ('NZ', 'Immigration New Zealand Student visa pages', 'https://immigration.govt.nz/process-to-apply/applying-for-a-visa/providing-evidence-and-documents-to-support-your-visa-application/student-fund-requirements/',
     'Immigration New Zealand (MBIE)', 'Source: Immigration New Zealand, immigration.govt.nz. Reuse terms to be confirmed.', 'pending')
  ) v(cc, label, url, owner, attr, terms)
  join ref.countries c on c.iso_alpha2 = v.cc
 where not exists (select 1 from destination.editions e where e.edition_label = v.label);

insert into destination.page_facts(country_code, edition_label, page_url, kind, rule_category, title, applicant_scope, pattern, flags, unit, currency_code,
       min_value, max_value, anchor, status, read_mode, note)
select v.cc, v.edition, v.url, v.kind, v.cat, v.title, 'student', v.pattern, 'i', v.unit, v.cur, v.mn, v.mx, v.anchor, 'active', v.mode,
       'Seeded 19 Nov 2026 (20261119083400, s716): next-wave visa rules'
  from (values
    ('NZ', 'Immigration New Zealand Student visa pages',
     'https://immigration.govt.nz/process-to-apply/applying-for-a-visa/providing-evidence-and-documents-to-support-your-visa-application/student-fund-requirements/',
     'amount', 'visa_funds', 'Student visa annual living cost (tertiary study, 1 year or more)', 'NZD\s?\$?\s?([0-9]{2},[0-9]{3})\s+for each year', 'NZD a year', 'NZD',
     15000::numeric, 40000::numeric, 'for each year|NZD', 'rendered'),
    ('GB', 'UKVI Student visa pages (GOV.UK)', 'https://www.gov.uk/student-visa/money', 'text', 'visa_funds', 'Student visa maintenance, courses in London (per month, up to 9 months)',
     '£\s?[0-9],[0-9]{3} per month \(for up to 9 months\) for courses in London', null, 'GBP', null, null, 'per month', 'static'),
    ('GB', 'UKVI Student visa pages (GOV.UK)', 'https://www.gov.uk/student-visa/money', 'text', 'visa_funds', 'Student visa maintenance, courses outside London (per month, up to 9 months)',
     '£\s?[0-9],[0-9]{3} per month \(for up to 9 months\) for courses outside London', null, 'GBP', null, null, 'per month', 'static'),
    ('US', 'USCIS F-1 Optional Practical Training pages', 'https://www.uscis.gov/node/50597', 'text', 'post_study_work', 'F-1 Optional Practical Training (OPT) length',
     'up to 12 months of (?:OPT )?employment authorization', null, null, null, null, 'months of', 'static')
  ) v(cc, edition, url, kind, cat, title, pattern, unit, cur, mn, mx, anchor, mode)
 where not exists (select 1 from destination.page_facts f where f.page_url = v.url and f.title = v.title);

-- the three visa-rules sources: due within the hour, after the LIN 19/198 run (the standard Layer 1 scheduler runs hourly at :05)
update pipeline.layer1_source_operations o
   set next_verification_at = now() + interval '55 minutes', updated_at = now(),  -- fixed: one scheduler hour apart from the LIN 19/198 run
       change_reason = 'Due 19 Nov 2026 (20261119083400, s716): first run through the standard Layer 1 scheduler'
  from pipeline.sources s
 where s.id = o.source_id and s.metadata->>'wave' = 'next-wave 19 Nov 2026'
   and s.label in ('Immigration New Zealand Student and Post-Study Work Visa rules', 'UKVI Student visa and Graduate route (GOV.UK)', 'USCIS and Department of State F-1 and OPT rules')
   and o.last_verified_at is null;

-- post-checks (rolled back with the dry run if any fails)
do $chk$
declare v_n int; v_drift jsonb;
begin
  select count(*) into v_n from destination.page_facts where note like 'Seeded 19 Nov 2026 (20261119083400, s716)%' and status = 'active';
  if v_n <> 4 then raise exception 'post-check: expected 4 next-wave facts, found %', v_n; end if;
  if exists (select 1 from destination.editions where edition_label = 'Immigration New Zealand Student visa pages' and terms_status = 'approved') then
    raise exception 'post-check: NZ terms must stay pending until confirmed';
  end if;
  select count(*) into v_n from pipeline.layer1_source_operations o join pipeline.sources s on s.id = o.source_id
   where s.metadata->>'wave' = 'next-wave 19 Nov 2026' and o.next_verification_at is not null and o.active and not o.paused;
  if v_n <> 3 then raise exception 'post-check: expected the three visa-rules sources due, found %', v_n; end if;
  v_drift := security.consumer_api_check_v1();
  if jsonb_typeof(v_drift) = 'array' then
    if jsonb_array_length(v_drift) > 0 then raise exception 'consumer API drift %', v_drift; end if;
  elsif jsonb_array_length(coalesce(v_drift->'drift', '[]'::jsonb)) > 0 then raise exception 'consumer API drift %', v_drift->'drift';
  end if;
end $chk$;
