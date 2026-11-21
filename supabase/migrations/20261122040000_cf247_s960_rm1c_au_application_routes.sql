-- CF-247 s960 (Lane 2 S2-Data-Destination-Continuous; Platform Admin 21 Nov 2026 21:16 AEDT, first item "AU rules drafts": RM1C Australian application routes).
--
-- What was read (21 Nov 2026 21:40-22:10 AEDT, each page fetched as plain HTML and run through the loader's own htmlToText and extractFact):
--   Study Australia (Australian Government, Austrade) "How to apply to study": apply directly to the education provider; or use an education agent.
--   UAC: international students with an Australian Year 12, IB Diploma or NCEA Level 3 apply for undergraduate courses in NSW and the ACT through UAC;
--        all other international students apply directly to the institutions.
--   VTAC: only international Australian Year 12 students apply through VTAC (Victoria); others apply directly.
--   SATAC: international students with the listed Australian Year 12 or IB qualifications apply through SATAC (SA and the NT); others apply directly.
--   Not captured (gaps, no guess): QTAC (its international statement is not in the page's static HTML) and TISC (no official TISC page found).
--
-- What it changes (data in existing tables, one new nullable column, one md5-guarded edit of an existing function; G3 75/48 untouched):
--   1. destination.page_facts.state_codes: the states (ref.subdivisions codes) a fact's rule applies to; null = the whole country, as before.
--   2. Layer 1 Register › Australia: the four authorities (Study Australia, UAC, VTAC, SATAC), destination page-facts sources, monthly.
--   3. A draft study-rules edition "Australian application routes (Study Australia and admissions centres)", terms pending (the Platform Admin
--      sets terms and publishes; nothing is published here).
--   4. Five text facts (application_route, international students), each read directly (static, no Firecrawl).
--   5. security.destination_page_facts_load_v1: a rule from a fact that names one state carries it in study_rules.state_code; a rule whose fact
--      names states gets one proven 'state' applicability per state instead of the country one; copied rules keep their state.
-- The facts are read live on deploy by workflow "Destination page facts (static read)" (scope static: pages read directly only, so the
-- Home Affairs pages that need Firecrawl are not read, $0). Rules land as drafts in the draft edition for the Platform Admin to approve.
-- Nothing is dropped or deleted.
-- Replaces: nothing.
-- Retires: nothing.

do $g$ begin
  if (select (security.consumer_api_check_v1()->>'functions')::int) <> 75 or (select (security.consumer_api_check_v1()->>'relations')::int) <> 48
     or jsonb_array_length(security.consumer_api_check_v1()->'drift') <> 0 then raise exception 'pre-check: consumer API is not 75/48 without drift'; end if;
  if (select count(*) from pipeline.manual_locks) <> 7585 then raise exception 'pre-check: manual locks are not 7,585'; end if;
end $g$;

-- 1. the states a fact applies to
alter table destination.page_facts add column if not exists state_codes text[];
comment on column destination.page_facts.state_codes is
  'States (ref.subdivisions.code, for example AU-NSW) the rule read from this fact applies to; null = the whole country. 20261122040000 (s960, RM1C).';
do $c$ begin
  if not exists (select 1 from pg_constraint where conname = 'page_facts_state_codes_chk' and conrelid = 'destination.page_facts'::regclass) then
    alter table destination.page_facts add constraint page_facts_state_codes_chk
      check (state_codes is null or (cardinality(state_codes) > 0 and array_to_string(state_codes, ',') ~ '^[A-Z]{2}-[A-Z]{2,3}(,[A-Z]{2}-[A-Z]{2,3})*$'));
  end if;
end $c$;

-- 2. the sources, in the Layer 1 Register under Australia
with au as (select id from ref.countries where iso_alpha2 = 'AU'),
src(url, label, publisher, domains, licence, attribution) as (values
  ('https://www.studyaustralia.gov.au/en/plan-your-studies/how-to-apply-to-study', 'Study Australia: How to apply to study',
   'Australian Trade and Investment Commission (Austrade), Study Australia', array['studyaustralia.gov.au', 'www.studyaustralia.gov.au'],
   'Australian Government website; reuse terms to be confirmed by the Platform Admin',
   'Application routes: Study Australia, How to apply to study (studyaustralia.gov.au), Australian Government.'),
  ('https://uac.edu.au/future-applicants/international-year-12-students', 'UAC: Steps to uni for international Year 12 students',
   'Universities Admissions Centre (NSW and ACT)', array['uac.edu.au', 'www.uac.edu.au'],
   'Copyright UAC; short verbatim quotes of a factual rule; reuse terms to be confirmed by the Platform Admin',
   'NSW and ACT route: Universities Admissions Centre (uac.edu.au).'),
  ('https://vtac.edu.au/guides/quickstart/international', 'VTAC: Quick start guide for international students',
   'Victorian Tertiary Admissions Centre', array['vtac.edu.au', 'www.vtac.edu.au'],
   'Copyright VTAC; short verbatim quotes of a factual rule; reuse terms to be confirmed by the Platform Admin',
   'Victoria route: Victorian Tertiary Admissions Centre (vtac.edu.au).'),
  ('https://www.satac.edu.au/international-applicants', 'SATAC: International applicants',
   'South Australian Tertiary Admissions Centre (SA and NT)', array['satac.edu.au', 'www.satac.edu.au'],
   'Copyright SATAC; short verbatim quotes of a factual rule; reuse terms to be confirmed by the Platform Admin',
   'South Australia and Northern Territory route: South Australian Tertiary Admissions Centre (satac.edu.au).'))
insert into pipeline.sources(source_type, country_id, url, label, trust_rank, status, metadata)
select 'web', (select id from au), s.url, s.label, 1, 'active',
       jsonb_build_object('layer', 'layer1', 'source_system', 'DESTINATION', 'dataset_class', 'regulatory', 'destination_mode', 'facts',
         'destination_scope', 'pages', 'parser', 'Page-facts reader (static page; verbatim quotes)', 'publisher', s.publisher, 'licence', s.licence,
         'attribution', s.attribution, 'destination_edition', 'Australian application routes (Study Australia and admissions centres)',
         'operational_surface', 'Destination data', 'schedule_day_sydney', 3, 'authority_domains', to_jsonb(s.domains),
         'decision', 'Platform Admin 21 Nov 2026 21:16 AEDT (Lane 2, s960): RM1C application routes into a draft edition')
  from src s
 where not exists (select 1 from pipeline.sources x where x.url = s.url and x.metadata->>'source_system' = 'DESTINATION');

insert into pipeline.layer1_source_operations(source_id, authority_name, authority_domains, expected_format, expected_count_kind, active, paused,
       verification_cadence_days, ingestion_cadence_days, variance_warn_percent, variance_block_percent, auto_ingest, next_verification_at, change_reason)
select s.id, s.metadata->>'publisher', array(select jsonb_array_elements_text(s.metadata->'authority_domains')), 'Static HTML page', 'rules', true, false,
       30, 30, 20, 60, false, null,  -- monthly; variance warn 20%, block 60%; read by the page-facts load (3rd of the month) and the static-read workflow, not by Layer 1 auto-ingest
       'Registered 21 Nov 2026 (20261122040000, s960): RM1C application route for the draft Australian application routes edition'
  from pipeline.sources s
 where s.metadata->>'source_system' = 'DESTINATION' and s.metadata->>'destination_edition' = 'Australian application routes (Study Australia and admissions centres)'
   and not exists (select 1 from pipeline.layer1_source_operations o where o.source_id = s.id);

-- 3. the draft edition
insert into destination.editions(country_id, domain, edition_label, effective_from, status, source_url, source_owner, attribution_text, terms_status, last_checked_at)
select c.id, 'study_rules', 'Australian application routes (Study Australia and admissions centres)', current_date, 'draft',
       'https://www.studyaustralia.gov.au/en/plan-your-studies/how-to-apply-to-study',
       'Australian Government (Study Australia); Universities Admissions Centre; Victorian Tertiary Admissions Centre; South Australian Tertiary Admissions Centre',
       'Application routes: Study Australia, How to apply to study (studyaustralia.gov.au), Australian Government. NSW and ACT route: Universities Admissions Centre (uac.edu.au). Victoria route: Victorian Tertiary Admissions Centre (vtac.edu.au). South Australia and Northern Territory route: South Australian Tertiary Admissions Centre (satac.edu.au).',
       'pending', now()
  from ref.countries c
 where c.iso_alpha2 = 'AU'
   and not exists (select 1 from destination.editions e where e.edition_label = 'Australian application routes (Study Australia and admissions centres)');

-- 4. the facts (patterns tested 21 Nov 2026 against each page's static HTML with the loader's own text and match code)
insert into destination.page_facts(country_code, edition_label, page_url, kind, rule_category, title, applicant_scope, pattern, flags, anchor, status, read_mode, state_codes, note)
select 'AU', 'Australian application routes (Study Australia and admissions centres)', f.url, 'text', 'application_route', f.title, 'international student',
       f.pattern, 'i', f.anchor, 'active', 'static', f.states,
       'Seeded 21 Nov 2026 (20261122040000, s960, RM1C)'
  from (values
   ('https://www.studyaustralia.gov.au/en/plan-your-studies/how-to-apply-to-study', 'Apply directly to the education provider',
    'Applying directly\s*\.?\s*Once you decide which course you want to study[\s\S]{0,160}?you may be able to complete an application via the education provider', 'Applying directly', null::text[]),
   ('https://www.studyaustralia.gov.au/en/plan-your-studies/how-to-apply-to-study', 'Apply through an education agent',
    'An education agent can give you information about your options for studying and living in Australia and help you with your study application', 'Education Agent', null::text[]),
   ('https://uac.edu.au/future-applicants/international-year-12-students', 'Undergraduate in NSW and the ACT through UAC (Australian Year 12, IB Diploma or NCEA Level 3)',
    'International students undertaking one of the following qualifications in \d{4} or \d{4} can apply for undergraduate courses through UAC[\s\S]{0,400}?All other international students apply directly to the institutions, not through UAC', 'through UAC', array['AU-NSW', 'AU-ACT']),
   ('https://vtac.edu.au/guides/quickstart/international', 'Undergraduate in Victoria through VTAC (international Australian Year 12 students)',
    'The only international students that can apply for courses through VTAC are international Australian Year 12 students[\s\S]{0,300}?you must apply directly to the institutions', 'through VTAC', array['AU-VIC']),
   ('https://www.satac.edu.au/international-applicants', 'Undergraduate in South Australia and the Northern Territory through SATAC (listed Australian Year 12 or IB Diploma)',
    'International students studying one of the following qualifications in Australia may apply for undergraduate courses \(at the universities listed above\) through SATAC[\s\S]{0,700}?must apply directly to the relevant institutions, rather than through SATAC', 'through SATAC', array['AU-SA', 'AU-NT'])
  ) f(url, title, pattern, anchor, states)
 where not exists (select 1 from destination.page_facts g where g.page_url = f.url and g.title = f.title);

-- 5. the load function: state scope
create or replace function pg_temp.cf_edit_many(p_sig regprocedure, p_md5 text, p_old text[], p_new text[], p_marker text)
returns void language plpgsql as $f$
declare v_src text := (select p.prosrc from pg_proc p where p.oid = p_sig); v_def text; v_body text; v_c int; i int;
begin
  if position(p_marker in v_src) > 0 then raise notice '%: already applied', p_sig; return; end if;
  if md5(v_src) <> p_md5 then raise exception 'live % differs from the definition this change edits (body md5 %)', p_sig, md5(v_src); end if;
  v_def := replace(pg_get_functiondef(p_sig), chr(13), ''); v_body := v_src;
  for i in 1 .. array_length(p_old, 1) loop
    v_c := (length(v_def) - length(replace(v_def, p_old[i], ''))) / length(p_old[i]);
    if v_c <> 1 then raise exception '%: edit % must apply exactly once (found %)', p_sig, i, v_c; end if;
    v_def := replace(v_def, p_old[i], p_new[i]); v_body := replace(v_body, p_old[i], p_new[i]);
  end loop;
  execute v_def;
  if md5((select p.prosrc from pg_proc p where p.oid = p_sig)) <> md5(v_body) then raise exception '% after the edits is not the expected body', p_sig; end if;
end $f$;

select pg_temp.cf_edit_many('security.destination_page_facts_load_v1(jsonb)'::regprocedure, 'a81d0f62ec5443551fe191aa704415c4',
  array[
    $o1$          insert into destination.study_rules(edition_id, country_id, rule_category, title, summary, applicant_scope, numeric_threshold, currency_code,
                 application_fee_amount, fee_currency, work_hours_fortnight, financial_capacity_annual, post_study_work_years_max,
                 quote_on_page, evidence_id, evidence_date, source_url, last_checked_at, approval_status)$o1$,
    $o2$                  fd->>'quote', nullif(fd->>'evidence_id', '')::uuid, (v_read at time zone 'Australia/Sydney')::date, fd->>'page_url', v_read, 'draft');$o2$,
    $o3$               quote_on_page, evidence_id, evidence_date, source_url, last_checked_at, approval_status)
        select s.id, r.country_id, r.rule_category, r.title, r.summary, r.applicant_scope, r.numeric_threshold, r.currency_code,
               r.application_fee_amount, r.fee_currency, r.work_hours_fortnight, r.financial_capacity_annual, r.post_study_work_years_max,
               r.quote_on_page, r.evidence_id, r.evidence_date, r.source_url, r.last_checked_at, 'draft'$o3$,
    $o4$       where r.edition_id = e.id and r.country_id is not null and r.approval_status in ('draft', 'approved')
         and not exists (select 1 from destination.rule_applicability a where a.rule_id = r.id and a.entity_type = 'country');$o4$
  ],
  array[
    $n1$          insert into destination.study_rules(edition_id, country_id, rule_category, title, summary, applicant_scope, numeric_threshold, currency_code,
                 application_fee_amount, fee_currency, work_hours_fortnight, financial_capacity_annual, post_study_work_years_max,
                 quote_on_page, evidence_id, evidence_date, source_url, last_checked_at, approval_status, state_code)  -- 20261122040000 (s960): one state when the fact names one$n1$,
    $n2$                  fd->>'quote', nullif(fd->>'evidence_id', '')::uuid, (v_read at time zone 'Australia/Sydney')::date, fd->>'page_url', v_read, 'draft',
                  case when cardinality(f.state_codes) = 1 then f.state_codes[1] end);$n2$,
    $n3$               quote_on_page, evidence_id, evidence_date, source_url, last_checked_at, approval_status, state_code)
        select s.id, r.country_id, r.rule_category, r.title, r.summary, r.applicant_scope, r.numeric_threshold, r.currency_code,
               r.application_fee_amount, r.fee_currency, r.work_hours_fortnight, r.financial_capacity_annual, r.post_study_work_years_max,
               r.quote_on_page, r.evidence_id, r.evidence_date, r.source_url, r.last_checked_at, 'draft', r.state_code$n3$,
    $n4$       where r.edition_id = e.id and r.country_id is not null and r.approval_status in ('draft', 'approved')
         and not exists (select 1 from destination.rule_applicability a where a.rule_id = r.id and a.entity_type = 'country')
         -- 20261122040000 (s960): a rule whose fact names states (an admissions centre's route) applies to those states, not to the whole country
         and not exists (select 1 from destination.page_facts pf where pf.edition_label = e.edition_label and pf.status = 'active'
                           and pf.rule_category = r.rule_category and pf.title = r.title and pf.state_codes is not null);
      insert into destination.rule_applicability(rule_id, entity_type, entity_id, entity_code, applicability_status, evidence_url, quote_on_page, verified_at)
      select r.id, 'state', null, sc.code, 'proven', r.source_url, r.quote_on_page, coalesce(r.last_checked_at, now())
        from destination.study_rules r
        join destination.page_facts pf on pf.edition_label = e.edition_label and pf.status = 'active' and pf.rule_category = r.rule_category and pf.title = r.title
        cross join lateral unnest(pf.state_codes) sc(code)
       where r.edition_id = e.id and r.approval_status in ('draft', 'approved')
         and not exists (select 1 from destination.rule_applicability a where a.rule_id = r.id and a.entity_type = 'state' and a.entity_code = sc.code);$n4$
  ],
  '20261122040000 (s960)');

-- post-checks
do $p$ declare v_bad text; begin
  if (select md5(prosrc) from pg_proc where oid = 'security.destination_page_facts_load_v1(jsonb)'::regprocedure) <> 'c34e7946cb96daa41f6195398d9385e7' then
    raise exception 'post-check: the load function is not the expected body'; end if;
  if (select count(*) from destination.page_facts where edition_label = 'Australian application routes (Study Australia and admissions centres)' and status = 'active') <> 5 then
    raise exception 'post-check: expected 5 application-route facts'; end if;
  select string_agg(distinct c, ', ') into v_bad from destination.page_facts f cross join lateral unnest(f.state_codes) c
   where not exists (select 1 from ref.subdivisions s where s.code = c);
  if v_bad is not null then raise exception 'post-check: state codes not in ref.subdivisions: %', v_bad; end if;
  if (select count(*) from destination.editions where edition_label = 'Australian application routes (Study Australia and admissions centres)' and status = 'draft' and terms_status = 'pending') <> 1 then
    raise exception 'post-check: the draft edition is missing'; end if;
  if (select count(*) from pipeline.layer1_source_operations o join pipeline.sources s on s.id = o.source_id
       where s.metadata->>'destination_edition' = 'Australian application routes (Study Australia and admissions centres)') <> 4 then
    raise exception 'post-check: expected 4 registered sources'; end if;
  if (select (security.consumer_api_check_v1()->>'functions')::int) <> 75 or (select (security.consumer_api_check_v1()->>'relations')::int) <> 48
     or jsonb_array_length(security.consumer_api_check_v1()->'drift') <> 0 then raise exception 'post-check: consumer API is not 75/48 without drift'; end if;
  if (select count(*) from pipeline.manual_locks) <> 7585 then raise exception 'post-check: manual locks are not 7,585'; end if;
  if (select count(*) from cron.job where active) > 140 then raise exception 'post-check: more than 140 active jobs'; end if;
  raise notice 's960: 5 facts, 4 sources, draft edition; loader md5 c34e7946; G3 75/48; locks 7,585';
end $p$;
