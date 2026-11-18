-- CF-247 RM1I / RM1C / RM1H / RM1D destination page facts (S2-Build; Platform Admin 18 Nov 2026 14:23 and 15:32: "Build and run the page-facts
-- loader ... extracts each figure or rule from official pages with verbatim quotes and as_at timestamps ... then record open-data licence terms,
-- approve verified attributed rows, and publish the editions so API v3 /destination serves them"; QILT stays gated until written permission).
--
-- What it builds
--   * destination.page_facts: each figure or rule read from an official page, as data: the page, the edition it belongs to, the rule category
--     and title, a pattern whose first group is the value (amount, number or text), its unit and currency, a plausible range and an anchor word.
--     Kind workbook names a data page and the link text of the workbook to read (JSA OSCA occupation data). A Platform Admin changes a pattern
--     or adds a fact without a code change; the last read of each fact (value, quote, time, or why it was not found) is kept on the row.
--   * layer1-destination-geo-loader v1.2.0 mode facts: reads each page, stores it as evidence, applies the patterns to the page's visible
--     text (supabase/functions/_shared/cf247-page-facts.js) and returns each value with its verbatim quote; a miss returns what the page says
--     around the anchor word and writes nothing. The JSA workbook is found by its link text, stored, and loaded only from the columns its
--     header names (occupation code, title, median weekly earnings, employed persons); nothing is guessed.
--   * security.destination_page_facts_load_v1: writes draft study rules (rule category, title, value, unit, currency, verbatim quote, evidence,
--     source link and the time read as last_checked_at and evidence_date) and draft OSCA career rows with attribution. A rule already approved
--     is never changed: a different value on the page is reported (differs_from_approved) for a person to decide. Editions whose terms are
--     restricted are not read.
--   * Terms recorded, from each owner's copyright page (read 18 Nov 2026):
--       - Department of Home Affairs: CC BY 3.0 AU, attributed to the Australian Government Department of Home Affairs (homeaffairs.gov.au
--         copyright and disclaimer). Approved.
--       - Jobs and Skills Australia: CC BY 4.0, © Commonwealth of Australia (jobsandskills.gov.au/copyright). Approved.
--       - Fair Work Ombudsman: CC BY-NC 4.0 (fairwork.gov.au copyright statement), a non-commercial licence, and its robots rules refuse automated
--         reading. Recorded as restricted: nothing is read or loaded (the national minimum wage waits for written permission).
--     Study Australia's living-costs page holds no figure (it points to the Cost of Living Calculator and the Home Affairs checklist; its own
--     note says the costs were last updated November 2023) and no Study Tasmania page with an official figure was found, so no edition is made
--     for either; the 12-month living cost is read from Home Affairs instead. The TAC and direct application routes need a source whose terms
--     are known (Study Australia's are not published on its site); recorded as a gap, not loaded. QILT is not touched.
--   * Job destination-page-facts-load (3rd of the month, 05:30 Sydney) and Run now; the first load is asked for by a follow-up migration once
--     the v1.2.0 edge function is deployed. The hourly target
--     destination-open-licence-publish approves the attributed drafts with evidence and a quote for owners on destination.open_licence_owners
--     and publishes the edition, so API v3 /destination serves them (public.website_v3_destination reads; nothing in the consumer API changes).
-- Nothing is dropped or deleted. G3 untouched (75 functions, 48 tables).
-- Replaces: nothing (no page-facts loader existed).
-- Retires: nothing.

-- 1. the facts
create table if not exists destination.page_facts (
  id uuid primary key default gen_random_uuid(),
  country_code text not null check (country_code = upper(country_code) and length(country_code) = 2),
  edition_label text not null,
  page_url text not null check (page_url ~ '^https://'),
  kind text not null check (kind in ('amount', 'number', 'text', 'workbook')),
  rule_category text,
  title text not null,
  applicant_scope text,
  pattern text not null,
  flags text not null default 'i' check (flags ~ '^[gimsuy]*$'),
  unit text,
  currency_code text check (currency_code is null or currency_code ~ '^[A-Z]{3}$'),
  min_value numeric,
  max_value numeric,
  anchor text,
  status text not null default 'active' check (status in ('active', 'retired')),
  last_read_at timestamptz,
  last_status text check (last_status is null or last_status in ('found', 'not_found', 'page_failed', 'differs_from_approved', 'held')),
  last_value text,
  last_quote text,
  last_reason text,
  last_windows jsonb,
  note text,
  created_at timestamptz not null default now(),
  updated_by uuid,
  updated_at timestamptz not null default now(),
  check (kind = 'workbook' or rule_category is not null)
);
comment on table destination.page_facts is 'CF-247 RM1I/RM1C/RM1H/RM1D (18 Nov 2026): each figure or rule read from an official page (page, edition, rule category, title, pattern whose first group is the value, unit, currency, plausible range, anchor word), or a workbook found by its link text; data changed by a Platform Admin, read by layer1-destination-geo-loader mode facts. The last read (value, verbatim quote, time, or why not found) is kept on the row.';
create unique index if not exists page_facts_active_uq on destination.page_facts(edition_label, page_url, title) where status = 'active';
alter table destination.page_facts enable row level security;
revoke all on destination.page_facts from anon, authenticated;

-- 2. editions (draft) and their terms
insert into destination.editions(country_id, domain, edition_label, effective_from, status, source_url, source_owner, attribution_text, terms_status, last_checked_at)
select c.id, v.domain, v.label, current_date, 'draft', v.url, v.owner, v.attr, 'pending', now()
  from ref.countries c
  cross join (values
    ('study_rules', 'Home Affairs Student visa (subclass 500) and Temporary Graduate visa (subclass 485) pages',
     'https://immi.homeaffairs.gov.au/visas/getting-a-visa/visa-listing/student-500', 'Department of Home Affairs',
     'Source: Australian Government Department of Home Affairs, immi.homeaffairs.gov.au. © Commonwealth of Australia, licensed under Creative Commons Attribution 3.0 Australia (CC BY 3.0 AU); the Coat of Arms and the Department''s logo are excluded.'),
    ('career_outcomes', 'JSA OSCA Occupation data (2021 Census)',
     'https://www.jobsandskills.gov.au/data/labour-market-insights', 'Jobs and Skills Australia',
     'Source: Jobs and Skills Australia, OSCA Occupation data - 2021 Census (Labour Market Insights), jobsandskills.gov.au. © Commonwealth of Australia, licensed under Creative Commons Attribution 4.0 International (CC BY 4.0).'),
    ('study_rules', 'Fair Work Ombudsman National Minimum Wage',
     'https://www.fairwork.gov.au/minimum-wages', 'Fair Work Ombudsman',
     '© Fair Work Ombudsman www.fairwork.gov.au, licensed under Creative Commons Attribution-NonCommercial 4.0 International (CC BY-NC 4.0).')
  ) v(domain, label, url, owner, attr)
 where c.iso_alpha2 = 'AU'
   and not exists (select 1 from destination.editions e where e.country_id = c.id and e.domain = v.domain and e.edition_label = v.label);

do $e$
declare v_admin constant uuid := '63ba56cb-48d4-4169-98c2-7c4d1f72925b';  -- the Platform Admin who gave the direction (15:32)
        t record; v_res jsonb;
begin
  for t in select * from (values
      ('Home Affairs Student visa (subclass 500) and Temporary Graduate visa (subclass 485) pages', 'approved', 'CC BY 3.0 AU', 'homeaffairs.gov.au/access-and-accountability/using-our-website/copyright-and-disclaimer, 18 Nov 2026'),
      ('JSA OSCA Occupation data (2021 Census)', 'approved', 'CC BY 4.0', 'jobsandskills.gov.au/copyright, 18 Nov 2026'),
      ('Fair Work Ombudsman National Minimum Wage', 'restricted', 'CC BY-NC 4.0 (non-commercial); robots rules refuse automated reading', 'fairwork.gov.au/website-information/copyright-statement, 18 Nov 2026')
    ) x(label, terms, licence, checked)
  loop
    if (select terms_status from destination.editions where edition_label = t.label) = t.terms then continue; end if;
    v_res := security.destination_edition_set_terms_v1((select id from destination.editions where edition_label = t.label), t.terms, v_admin);
    insert into pipeline.admin_control_events(area, action, target, detail, actor)
    values ('destination', 'edition_terms', t.label, jsonb_build_object('terms', t.terms, 'licence', t.licence, 'checked', t.checked,
            'reason', 'Platform Admin 18 Nov 2026 15:32 (S2-Build): record the open-data licence terms of the page-facts editions', 'result', v_res,
            'by', 'migration 20261118185000'), v_admin);
  end loop;
  insert into pipeline.admin_control_events(area, action, target, detail, actor)
  values ('destination', 'page_facts_gap', 'RM1I / RM1C / RM1H',
          jsonb_build_object('study_australia_living_costs', 'studyaustralia.gov.au/en/life-in-australia/living-and-education-costs holds no figure (points to the Cost of Living Calculator and the Home Affairs checklist; costs last updated November 2023); not loaded',
                             'study_tasmania_living_costs', 'no official Study Tasmania page with a living-cost figure was found; not loaded',
                             'application_routes', 'TAC and direct routes need a source with published terms (Study Australia publishes none on its site); not loaded',
                             'minimum_wage', 'Fair Work Ombudsman terms are CC BY-NC 4.0 and its robots rules refuse automated reading; restricted until written permission',
                             'qilt', 'gated until written permission is recorded; not touched', 'by', 'migration 20261118185000'), v_admin);
end $e$;

-- 3. the facts read (patterns are data; a miss writes nothing and shows the page text around the anchor)
insert into destination.page_facts(country_code, edition_label, page_url, kind, rule_category, title, applicant_scope, pattern, unit, currency_code, min_value, max_value, anchor, note)
select 'AU', v.label, v.url, v.kind, v.cat, v.title, v.scope, v.pattern, v.unit, v.cur, v.lo, v.hi, v.anchor, 'Seeded 18 Nov 2026 (20261118185000)'
  from (values
    ('Home Affairs Student visa (subclass 500) and Temporary Graduate visa (subclass 485) pages', 'https://immi.homeaffairs.gov.au/visas/getting-a-visa/visa-listing/student-500',
     'amount', 'visa_fee', 'Student visa (subclass 500) application charge', 'main applicant', 'From\s+AUD\s?\$?\s?([0-9][0-9,]{2,})', 'AUD', 'AUD', 300::numeric, 20000::numeric, 'AUD'),
    ('Home Affairs Student visa (subclass 500) and Temporary Graduate visa (subclass 485) pages', 'https://immi.homeaffairs.gov.au/visas/getting-a-visa/visa-listing/student-500',
     'number', 'work_rights', 'Student visa (subclass 500) work limit while the course is in session', 'student', '([0-9]{2})\s+hours\s+(?:per|a|every|each|in\s+a)\s+fortnight', 'hours per fortnight', null, 20, 80, 'fortnight'),
    ('Home Affairs Student visa (subclass 500) and Temporary Graduate visa (subclass 485) pages', 'https://immi.homeaffairs.gov.au/visas/getting-a-visa/visa-listing/student-500',
     'amount', 'visa_funds', 'Student visa (subclass 500) 12-month living cost (financial capacity)', 'student', 'living costs?[^.]{0,200}?(?:AUD|A?\$)\s?([0-9]{2},?[0-9]{3})', 'AUD a year', 'AUD', 15000, 80000, 'living cost'),
    ('Home Affairs Student visa (subclass 500) and Temporary Graduate visa (subclass 485) pages', 'https://immi.homeaffairs.gov.au/visas/getting-a-visa/visa-listing/student-500',
     'text', 'health_insurance', 'Student visa (subclass 500) Overseas Student Health Cover', 'student and family members', '(Overseas Student Health Cover)', null, null, null, null, 'health'),
    ('Home Affairs Student visa (subclass 500) and Temporary Graduate visa (subclass 485) pages', 'https://immi.homeaffairs.gov.au/visas/getting-a-visa/visa-listing/temporary-graduate-485',
     'number', 'post_study_work', 'Temporary Graduate visa (subclass 485) Post-Higher Education Work stream stay', 'graduate', 'Post-Higher Education Work[^.]{0,240}?up to\s+([0-9])\s+years', 'years', null, 1, 8, 'Post-Higher Education'),
    ('Home Affairs Student visa (subclass 500) and Temporary Graduate visa (subclass 485) pages', 'https://immi.homeaffairs.gov.au/visas/getting-a-visa/visa-listing/temporary-graduate-485',
     'amount', 'visa_fee', 'Temporary Graduate visa (subclass 485) application charge', 'main applicant', 'From\s+AUD\s?\$?\s?([0-9][0-9,]{2,})', 'AUD', 'AUD', 300, 20000, 'AUD'),
    ('JSA OSCA Occupation data (2021 Census)', 'https://www.jobsandskills.gov.au/data/labour-market-insights',
     'workbook', null, 'OSCA Occupation data - 2021 Census (workbook)', null, 'OSCA\s+Occupation\s+data', null, null, null, null, 'OSCA'),
    ('Fair Work Ombudsman National Minimum Wage', 'https://www.fairwork.gov.au/minimum-wages',
     'amount', 'minimum_wage', 'National Minimum Wage per hour', 'adult employee', 'National Minimum Wage is \$([0-9]{2}\.[0-9]{2}) per hour', 'AUD per hour', 'AUD', 15, 60, 'Minimum Wage')
  ) v(label, url, kind, cat, title, scope, pattern, unit, cur, lo, hi, anchor)
 where not exists (select 1 from destination.page_facts f where f.edition_label = v.label and f.page_url = v.url and f.title = v.title and f.status = 'active');

-- 4. the limit
insert into pipeline.platform_toolset_settings(toolset_key, key, label, help, kind, value, min_value, max_value, unit, sort, reason, section, used_by) values
 ('pipeline', 'destination.career_rows_max', 'Destination: occupation rows one workbook load writes at most',
  'Job destination-page-facts-load reads the JSA OSCA occupation workbook; a load with more rows than this writes none and says so, so a changed workbook is looked at before it loads.',
  'number', '3000'::jsonb, 100, 20000, 'rows', 305, 'Platform Admin 18 Nov 2026 15:32 (S2-Build): RM1D JSA careers', 'Destination data', 'security.destination_page_facts_load_v1')
on conflict (toolset_key, key) do nothing;

-- 5. what the loader reads
create or replace function public.svc_destination_page_facts_v1()
 returns jsonb
 language plpgsql
 stable
 security definer
 set search_path to ''
as $function$
begin
  if current_user <> 'postgres' and coalesce(auth.role(), '') <> 'service_role' then raise exception 'service_role required'; end if;
  return jsonb_build_object(
    'facts', coalesce((select jsonb_agg(jsonb_build_object('id', f.id, 'page_url', f.page_url, 'pattern', f.pattern, 'flags', f.flags, 'kind', f.kind,
                                 'min', f.min_value, 'max', f.max_value, 'anchor', f.anchor) order by f.page_url, f.title)
                         from destination.page_facts f join destination.editions e on e.edition_label = f.edition_label
                        where f.status = 'active' and f.kind <> 'workbook' and e.terms_status <> 'restricted'), '[]'::jsonb),
    'jsa', (select jsonb_build_object('id', f.id, 'page_url', f.page_url, 'link_pattern', f.pattern)
              from destination.page_facts f join destination.editions e on e.edition_label = f.edition_label
             where f.status = 'active' and f.kind = 'workbook' and e.terms_status <> 'restricted' and e.domain = 'career_outcomes'
             order by f.created_at limit 1));
end $function$;
comment on function public.svc_destination_page_facts_v1() is 'RM1I/RM1C/RM1H/RM1D: the active page facts and the JSA workbook of editions whose terms are not restricted (service entry of layer1-destination-geo-loader, mode facts).';

-- 6. the load
create or replace function security.destination_page_facts_load_v1(p_payload jsonb)
 returns jsonb
 language plpgsql
 security definer
 set search_path to ''
as $function$
declare v_run uuid := nullif(p_payload->>'run_id', '')::uuid; v_dry boolean := coalesce((p_payload->>'dry_run')::boolean, false);
        pg jsonb; x jsonb; f destination.page_facts; e destination.editions; v_ev uuid; v_read timestamptz; v_val numeric; v_rule destination.study_rules;
        v_found int := 0; v_missed int := 0; v_written int := 0; v_unchanged int := 0; v_differs int := 0; v_failed int := 0;
        v_items jsonb := '[]'::jsonb; j jsonb; r jsonb; v_je destination.editions; v_jev uuid; v_cap int; v_jrows int := 0; v_jwritten int := 0; v_jkept int := 0;
        v_jsa jsonb; v_result jsonb; v_old record;
begin
  -- pages
  for pg in select * from jsonb_array_elements(coalesce(p_payload->'pages', '[]'::jsonb)) loop
    v_read := coalesce(nullif(pg->>'read_at', '')::timestamptz, now());
    v_ev := null;
    if pg ? 'error' then v_failed := v_failed + 1; end if;
    for x in select * from jsonb_array_elements(coalesce(pg->'facts', '[]'::jsonb)) loop
      select * into f from destination.page_facts where id = nullif(x->>'id', '')::uuid and status = 'active';
      if f.id is null then continue; end if;
      select * into e from destination.editions where edition_label = f.edition_label;
      if e.id is null or e.terms_status = 'restricted' then
        v_items := v_items || jsonb_build_object('title', f.title, 'status', 'held', 'reason', 'edition terms restricted or edition missing'); continue;
      end if;
      if pg ? 'error' or not coalesce((x->>'found')::boolean, false) then
        v_missed := v_missed + 1;
        if not v_dry then
          update destination.page_facts set last_read_at = v_read, last_status = case when pg ? 'error' then 'page_failed' else 'not_found' end,
                 last_reason = left(coalesce(pg->>'error', x->>'reason'), 500), last_windows = x->'windows', updated_at = now() where id = f.id;
        end if;
        v_items := v_items || jsonb_build_object('title', f.title, 'status', case when pg ? 'error' then 'page_failed' else 'not_found' end, 'reason', coalesce(pg->>'error', x->>'reason'));
        continue;
      end if;
      v_found := v_found + 1;
      v_val := case when f.kind = 'text' then null else nullif(x->>'value', '')::numeric end;
      if f.kind <> 'text' and (v_val is null or (f.min_value is not null and v_val < f.min_value) or (f.max_value is not null and v_val > f.max_value)) then
        v_found := v_found - 1; v_missed := v_missed + 1;
        v_items := v_items || jsonb_build_object('title', f.title, 'status', 'not_found', 'reason', 'value outside the plausible range');
        continue;
      end if;
      if position(coalesce(x->>'match', x->>'raw', '') in coalesce(x->>'quote', '')) = 0 or coalesce(btrim(x->>'quote'), '') = '' then
        v_found := v_found - 1; v_missed := v_missed + 1;
        v_items := v_items || jsonb_build_object('title', f.title, 'status', 'not_found', 'reason', 'the quote does not hold the matched text');
        continue;
      end if;
      v_items := v_items || jsonb_build_object('title', f.title, 'status', 'found', 'value', coalesce(x->>'raw', x->>'value'), 'quote', x->>'quote');
      if v_dry then continue; end if;
      if v_ev is null and coalesce(pg->>'sha256', '') <> '' then
        v_ev := security.destination_source_evidence_v1(pg->>'page_url', pg->>'sha256', 'text/html', nullif(pg->>'storage_path', ''),
                  jsonb_build_object('capture', 'destination-page-facts-v1', 'read_at', v_read, 'edition', e.edition_label));
      end if;
      select * into v_rule from destination.study_rules
       where edition_id = e.id and rule_category = f.rule_category and title = f.title and approval_status in ('draft', 'approved')
       order by (approval_status = 'approved') desc, created_at desc limit 1;
      if v_rule.id is not null and v_rule.approval_status = 'approved' then
        if v_rule.numeric_threshold is not distinct from v_val and (f.kind <> 'text' or v_rule.quote_on_page = x->>'quote') then
          update destination.study_rules set last_checked_at = v_read where id = v_rule.id;
          update destination.page_facts set last_read_at = v_read, last_status = 'found', last_value = coalesce(x->>'raw', x->>'value'), last_quote = x->>'quote',
                 last_reason = null, last_windows = null, updated_at = now() where id = f.id;
          v_unchanged := v_unchanged + 1;
        else
          update destination.page_facts set last_read_at = v_read, last_status = 'differs_from_approved', last_value = coalesce(x->>'raw', x->>'value'), last_quote = x->>'quote',
                 last_reason = 'The page now says something different from the approved rule; a person decides', updated_at = now() where id = f.id;
          v_differs := v_differs + 1;
        end if;
        continue;
      end if;
      if v_rule.id is null then
        insert into destination.study_rules(edition_id, country_id, rule_category, title, summary, applicant_scope, numeric_threshold, currency_code,
               application_fee_amount, fee_currency, work_hours_fortnight, financial_capacity_annual, post_study_work_years_max,
               quote_on_page, evidence_id, evidence_date, source_url, last_checked_at, approval_status)
        values (e.id, e.country_id, f.rule_category, f.title,
                f.title || case when v_val is not null then ': ' || coalesce(x->>'raw', v_val::text) || coalesce(' ' || f.unit, '') else '' end || ' (read ' || to_char(v_read at time zone 'Australia/Sydney', 'DD Mon YYYY') || ')',
                f.applicant_scope, v_val, f.currency_code,
                case when f.rule_category = 'visa_fee' then v_val end, case when f.rule_category = 'visa_fee' then f.currency_code end,
                case when f.rule_category = 'work_rights' then v_val::int end, case when f.rule_category = 'visa_funds' then v_val end,
                case when f.rule_category = 'post_study_work' then v_val end,
                x->>'quote', v_ev, (v_read at time zone 'Australia/Sydney')::date, pg->>'page_url', v_read, 'draft');
        v_written := v_written + 1;
      elsif v_rule.numeric_threshold is distinct from v_val or v_rule.quote_on_page is distinct from x->>'quote' then
        update destination.study_rules set numeric_threshold = v_val, quote_on_page = x->>'quote', evidence_id = coalesce(v_ev, evidence_id),
               evidence_date = (v_read at time zone 'Australia/Sydney')::date, last_checked_at = v_read,
               application_fee_amount = case when f.rule_category = 'visa_fee' then v_val else application_fee_amount end,
               work_hours_fortnight = case when f.rule_category = 'work_rights' then v_val::int else work_hours_fortnight end,
               financial_capacity_annual = case when f.rule_category = 'visa_funds' then v_val else financial_capacity_annual end,
               post_study_work_years_max = case when f.rule_category = 'post_study_work' then v_val else post_study_work_years_max end
         where id = v_rule.id;
        v_written := v_written + 1;
      else
        update destination.study_rules set last_checked_at = v_read, evidence_id = coalesce(evidence_id, v_ev) where id = v_rule.id;
        v_unchanged := v_unchanged + 1;
      end if;
      update destination.page_facts set last_read_at = v_read, last_status = 'found', last_value = coalesce(x->>'raw', x->>'value'), last_quote = x->>'quote',
             last_reason = null, last_windows = null, updated_at = now() where id = f.id;
    end loop;
  end loop;

  -- the JSA OSCA occupation workbook
  j := p_payload->'jsa';
  if j is not null and jsonb_typeof(j) = 'object' then
    select * into v_je from destination.editions where edition_label = 'JSA OSCA Occupation data (2021 Census)';
    v_jrows := coalesce(jsonb_array_length(j->'rows'), 0);
    v_cap := security.pipeline_num_v1('destination.career_rows_max', 3000)::int;
    v_jsa := jsonb_build_object('file', j->>'file_url', 'sheet', j->>'sheet', 'header', j->'header', 'rows', v_jrows,
                                'sheets', (select jsonb_agg(jsonb_build_object('name', s->>'name', 'rows', s->'rows')) from jsonb_array_elements(coalesce(j->'sheets', '[]'::jsonb)) s));
    if j ? 'error' then
      v_jsa := v_jsa || jsonb_build_object('status', 'failed', 'error', left(j->>'error', 500));
    elsif v_je.id is null or v_je.terms_status = 'restricted' then
      v_jsa := v_jsa || jsonb_build_object('status', 'held', 'reason', 'edition terms restricted or edition missing');
    elsif v_jrows = 0 then
      v_jsa := v_jsa || jsonb_build_object('status', 'no_rows', 'reason', 'no sheet has an occupation code, title and a measure column the reader knows; the sheet names and first rows are in the run result',
                                           'first_rows', (select jsonb_agg(jsonb_build_object('name', s->>'name', 'first', s->'first')) from jsonb_array_elements(coalesce(j->'sheets', '[]'::jsonb)) s));
    elsif v_jrows > v_cap then
      v_jsa := v_jsa || jsonb_build_object('status', 'over_limit', 'reason', format('%s rows is over destination.career_rows_max (%s); nothing written', v_jrows, v_cap));
    elsif not v_dry then
      if coalesce(j->>'sha256', '') <> '' then
        v_jev := security.destination_source_evidence_v1(j->>'file_url', j->>'sha256', 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
                   nullif(j->>'storage_path', ''), jsonb_build_object('capture', 'destination-jsa-osca-v1', 'read_at', j->>'read_at', 'sheet', j->>'sheet', 'header', j->'header'));
      end if;
      for r in select * from jsonb_array_elements(j->'rows') loop
        select id, status into v_old from destination.career_outcomes
         where edition_id = v_je.id and country_id = v_je.country_id and occupation_scheme = 'OSCA' and occupation_code = r->>'code'
           and geography_level = 'national' and state_code is null and locality_id is null;
        if v_old.id is null then
          insert into destination.career_outcomes(edition_id, country_id, occupation_scheme, occupation_code, occupation_title, median_salary, salary_currency, salary_period,
                 employment_count, source_url, last_checked_at, reference_period, dataset_edition, attribution_text, status, geography_level, series_kind)
          values (v_je.id, v_je.country_id, 'OSCA', r->>'code', r->>'title', nullif(r->>'median_weekly_earnings', '')::numeric, 'AUD', 'weekly',
                  nullif(r->>'employment_count', '')::numeric, j->>'file_url', coalesce(nullif(j->>'read_at', '')::timestamptz, now()), '2021 Census',
                  v_je.edition_label, v_je.attribution_text, 'draft', 'national', 'occupation');
          v_jwritten := v_jwritten + 1;
        elsif v_old.status = 'draft' then
          update destination.career_outcomes set occupation_title = r->>'title', median_salary = nullif(r->>'median_weekly_earnings', '')::numeric,
                 employment_count = nullif(r->>'employment_count', '')::numeric, source_url = j->>'file_url', last_checked_at = coalesce(nullif(j->>'read_at', '')::timestamptz, now())
           where id = v_old.id;
          v_jwritten := v_jwritten + 1;
        else
          v_jkept := v_jkept + 1;  -- approved, published, superseded or withdrawn: never changed by a load
        end if;
      end loop;
      v_jsa := v_jsa || jsonb_build_object('status', 'loaded', 'written', v_jwritten, 'kept_reviewed', v_jkept, 'evidence_id', v_jev);
    else
      v_jsa := v_jsa || jsonb_build_object('status', 'dry_run');
    end if;
  end if;

  v_result := jsonb_strip_nulls(jsonb_build_object('dry_run', v_dry, 'facts_found', v_found, 'facts_not_found', v_missed, 'pages_failed', v_failed,
    'rules_written', v_written, 'rules_unchanged', v_unchanged, 'differs_from_approved', v_differs, 'facts', v_items, 'jsa', v_jsa, 'trigger', p_payload->>'trigger'));
  insert into pipeline.admin_control_events(area, action, target, detail, actor)
  values ('destination', case when v_dry then 'page_facts_load_dry_run' else 'page_facts_load' end, 'destination-page-facts-load', v_result || jsonb_build_object('run_id', v_run), null);
  perform security.destination_run_finish_v1(v_run, v_result, null);
  return v_result;
end $function$;
comment on function security.destination_page_facts_load_v1(jsonb) is 'RM1I/RM1C/RM1H/RM1D: draft study rules from official page facts (value, verbatim quote, evidence, time read) and draft OSCA career rows from the JSA workbook; restricted editions held; a reviewed row is never changed; a dry run writes nothing.';

create or replace function public.svc_destination_page_facts_load_v1(p_payload jsonb)
 returns jsonb
 language plpgsql
 security definer
 set search_path to ''
as $function$
declare v_run uuid := nullif(p_payload->>'run_id', '')::uuid;
begin
  if current_user <> 'postgres' and coalesce(auth.role(), '') <> 'service_role' then raise exception 'service_role required'; end if;
  if p_payload ? 'error' then
    insert into pipeline.admin_control_events(area, action, target, detail, actor)
    values ('destination', 'page_facts_load_failed', 'destination-page-facts-load', jsonb_build_object('error', left(p_payload->>'error', 500), 'run_id', v_run, 'trigger', p_payload->>'trigger'), null);
    perform security.destination_run_finish_v1(v_run, null, left(p_payload->>'error', 500));
    return jsonb_build_object('recorded', true);
  end if;
  return security.destination_page_facts_load_v1(p_payload);
end $function$;
comment on function public.svc_destination_page_facts_load_v1(jsonb) is 'RM1I/RM1C/RM1H/RM1D: service entry of layer1-destination-geo-loader mode facts (a load, or the error of a failed one).';

-- 7. fire guard
create or replace function security.destination_page_facts_load_due_v1()
 returns boolean
 language sql
 stable
 set search_path to ''
as $function$
  -- fixed: fire guard. Scheduled at 18:30 and 19:30 UTC; exactly one is 05:30 in Sydney (AEDT or AEST), and only the 3rd of the month there runs (ABS has the 1st, BOM the 2nd)
  select extract(day from (now() at time zone 'Australia/Sydney')) = 3 and extract(hour from (now() at time zone 'Australia/Sydney')) = 5 -- fixed: fire guard
$function$;
comment on function security.destination_page_facts_load_due_v1() is 'RM1I/RM1C/RM1H/RM1D: true only on the 3rd of the month at 05:xx Sydney time (fire guard of job destination-page-facts-load).';

-- 8. Run now (md5-guarded edit of security.destination_job_run_now_v1)
do $e$
declare
  v_sig constant regprocedure := 'security.destination_job_run_now_v1(text,text,jsonb,uuid)'::regprocedure;
  v_src text := (select p.prosrc from pg_proc p where p.oid = 'security.destination_job_run_now_v1(text,text,jsonb,uuid)'::regprocedure);
  v_def text; v_c int;
  v_old constant text := $o$    ('destination-climate-load', 'layer1-destination-geo-loader', jsonb_build_object('mode', 'climate'))$o$;
  v_new constant text := $n$    ('destination-climate-load', 'layer1-destination-geo-loader', jsonb_build_object('mode', 'climate')),
    ('destination-page-facts-load', 'layer1-destination-geo-loader', jsonb_build_object('mode', 'facts'))$n$;
begin
  if position('destination-page-facts-load' in v_src) > 0 then raise notice 'security.destination_job_run_now_v1: already applied'; return; end if;
  if md5(v_src) <> '4d86b440f24f10e16707a777153fba62' then raise exception 'live security.destination_job_run_now_v1 differs from the definition this change edits (body md5 %)', md5(v_src); end if;
  v_def := replace(pg_get_functiondef(v_sig), chr(13), '');
  v_c := (length(v_def) - length(replace(v_def, v_old, ''))) / length(v_old);
  if v_c <> 1 then raise exception 'security.destination_job_run_now_v1: the edit must apply exactly once (found %)', v_c; end if;
  execute replace(v_def, v_old, v_new);
  if md5((select p.prosrc from pg_proc p where p.oid = v_sig)) <> md5(replace(v_src, v_old, v_new)) then
    raise exception 'security.destination_job_run_now_v1 after the edit is not the expected body';
  end if;
end $e$;

update pipeline.platform_toolset_settings
   set value = value || '["destination-page-facts-load"]'::jsonb, updated_at = now(),
       reason = 'RM1I/RM1C/RM1H/RM1D: destination-page-facts-load added (S2-Build, Platform Admin 18 Nov 2026 15:32); earlier entries kept'
 where toolset_key = 'pipeline' and key = 'run_now.jobs' and not (value ? 'destination-page-facts-load');

-- grants
revoke all on function security.destination_page_facts_load_v1(jsonb) from public, anon, authenticated;
revoke all on function security.destination_page_facts_load_due_v1() from public, anon, authenticated;
revoke all on function public.svc_destination_page_facts_load_v1(jsonb) from public, anon, authenticated;
revoke all on function public.svc_destination_page_facts_v1() from public, anon, authenticated;
grant execute on function public.svc_destination_page_facts_load_v1(jsonb) to service_role;
grant execute on function public.svc_destination_page_facts_v1() to service_role;

-- 9. the job and the register (the edge function is already on the nonce allowlist)
insert into pipeline.automation_catalogue(jobname, area, sort, label, description, control_rank, batch_editable) values
 ('destination-page-facts-load', 'Layer 1 register', 302, 'Destination: official page facts and JSA occupations',
  'Reads each official page named in Destination page facts (Home Affairs student and graduate visa pages), keeps each figure or rule with its verbatim quote, evidence and the time read as a draft study rule, and loads the JSA OSCA occupation workbook as draft career rows. Editions with restricted terms are not read. Runs on the 3rd of the month at 05:30 Sydney time.',
  6, false)
on conflict (jobname) do nothing;

select cron.schedule('destination-page-facts-load', '30 18,19 * * *', 'select pipeline.svc_pilot_submit_nonce(''layer1-destination-geo-loader'', jsonb_build_object(''mode'', ''facts'', ''trigger'', ''schedule'')) where security.destination_page_facts_load_due_v1()');

insert into pipeline.component_register(kind, name, layer, area, purpose, status, introduced_in)
select v.kind, v.name, v.layer, 'Destination data', v.purpose, 'active', '20261118185000'
  from (values
    ('job', 'destination-page-facts-load', 'L1 register', 'Official page facts (Home Affairs) and JSA OSCA occupations, monthly (RM1I/RM1C/RM1H/RM1D)'),
    ('table', 'destination.page_facts', 'Reference', 'Each figure or rule read from an official page, with its pattern and last read (RM1I/RM1C/RM1H/RM1D)'),
    ('function', 'security.destination_page_facts_load_v1', 'Layer 1', 'Draft study rules with verbatim quotes and draft OSCA career rows (RM1I/RM1C/RM1H/RM1D)'),
    ('function', 'public.svc_destination_page_facts_load_v1', 'Layer 1', 'Service entry of layer1-destination-geo-loader mode facts'),
    ('function', 'public.svc_destination_page_facts_v1', 'Layer 1', 'Active page facts and the JSA workbook for the loader'),
    ('function', 'security.destination_page_facts_load_due_v1', 'Layer 1', 'Fire guard of destination-page-facts-load')
  ) v(kind, name, layer, purpose)
 where not exists (select 1 from pipeline.component_register r where r.kind = v.kind and r.name = v.name);

-- 10. post-checks
do $$
declare v_prev jsonb;
begin
  if (select terms_status from destination.editions where edition_label = 'Fair Work Ombudsman National Minimum Wage') <> 'restricted' then raise exception 'post-check: Fair Work stays restricted'; end if;
  if (select terms_status from destination.editions where edition_label = 'JSA OSCA Occupation data (2021 Census)') <> 'approved' then raise exception 'post-check: JSA terms'; end if;
  if exists (select 1 from jsonb_array_elements(public.svc_destination_page_facts_v1()->'facts') f where f->>'page_url' like '%fairwork.gov.au%') then raise exception 'post-check: a restricted edition is read'; end if;
  if exists (select 1 from destination.editions where source_owner ilike '%QILT%' or edition_label ilike '%QILT%') then raise exception 'post-check: QILT stays gated'; end if;
  if not exists (select 1 from cron.job where jobname = 'destination-page-facts-load' and active) then raise exception 'post-check: job'; end if;
  if (select command from cron.job where jobname = 'destination-page-facts-load') ~ '\(\s*[0-9]+\s*[,)]' then raise exception 'post-check: a number in the job command'; end if;
  if not exists (select 1 from pipeline.automation_catalogue where jobname = 'destination-page-facts-load') then raise exception 'post-check: catalogue'; end if;
  if not (security.toolset_setting('pipeline', 'run_now.jobs') ? 'destination-page-facts-load') or not (security.toolset_setting('pipeline', 'run_now.jobs') ? 'destination-climate-load') then
    raise exception 'post-check: run_now.jobs';
  end if;
  -- a dry run writes nothing and keeps what it found
  v_prev := security.destination_page_facts_load_v1(jsonb_build_object('trigger', 'post-check', 'dry_run', true, 'pages', jsonb_build_array(jsonb_build_object(
    'page_url', 'https://immi.homeaffairs.gov.au/visas/getting-a-visa/visa-listing/student-500', 'sha256', 'post-check', 'read_at', now(),
    'facts', (select jsonb_agg(jsonb_build_object('id', f.id, 'found', true, 'raw', '48', 'value', 48, 'match', '48 hours per fortnight',
                                 'quote', 'You can work up to 48 hours per fortnight while your course is in session.'))
                from destination.page_facts f where f.rule_category = 'work_rights' and f.status = 'active')))));
  if (v_prev->>'facts_found')::int <> 1 or exists (select 1 from destination.study_rules where rule_category = 'work_rights' and title like 'Student visa (subclass 500)%') then
    raise exception 'post-check: the dry run must find the fact and write nothing (%)', v_prev;
  end if;
  v_prev := security.destination_page_facts_load_v1(jsonb_build_object('trigger', 'post-check', 'dry_run', true, 'pages', jsonb_build_array(jsonb_build_object(
    'page_url', 'https://immi.homeaffairs.gov.au/visas/getting-a-visa/visa-listing/student-500', 'sha256', 'post-check', 'read_at', now(),
    'facts', (select jsonb_agg(jsonb_build_object('id', f.id, 'found', true, 'raw', '480', 'value', 480, 'match', '480 hours per fortnight', 'quote', '480 hours per fortnight.'))
                from destination.page_facts f where f.rule_category = 'work_rights' and f.status = 'active')))));
  if (v_prev->>'facts_found')::int <> 0 then raise exception 'post-check: a value outside the plausible range is refused (%)', v_prev; end if;
end $$;

-- The first load is asked for by a follow-up migration once this change's edge function (v1.2.0) is deployed: Deploy on merge applies
-- migrations before it deploys functions, and v1.1.0 does not know mode facts.
