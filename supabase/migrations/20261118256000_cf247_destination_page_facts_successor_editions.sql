-- CF-247 RM1I / RM1C / RM1H / RM1D page facts: a published edition is never written to; a change on the page goes into a successor edition
-- (S2-Build; Platform Admin 18 Nov 2026 15:32 and 17:55).
--
-- What was read live (18 Nov 2026 19:05 AEDT, fourth load through workflow destination-run-now, run 70ae1116): the load failed whole with
-- "DESTINATION_EDITION_FIXED: rows of a published edition cannot change; import a new edition". The Home Affairs and JSA editions were
-- published at 18:41 by destination-open-licence-publish, and the load then tried to touch their rows (the time each approved rule was
-- checked, and the new Post-Higher Education Work stream fact). security.destination_row_guard_v1 keeps published rows fixed by design.
--
-- What it changes (security.destination_page_facts_load_v1, replaced whole; the function is this programme's own, 20261118185000):
--   * Pass 1 reads every fact of the run (values, verbatim quotes, evidence) without writing any rule.
--   * Pass 2, per edition:
--       - a draft or in-review edition: rules are written as before (draft; a reviewed rule never changed);
--       - a published edition with nothing new: no row is touched; each fact's own read is recorded on destination.page_facts only;
--       - a published edition with a new fact or a changed value: a successor edition is opened (same owner, terms, attribution and source;
--         label "<label> (read <date>)", effective from today, draft). It holds every fact found in this run and a copy of each published rule
--         not read this time (quote and evidence kept), so it is complete. The facts move to the successor's label. destination-open-licence-
--         publish approves its attributed rows and publishes it, which supersedes the earlier edition (security.destination_edition_publish_v1).
--   * The JSA workbook: a published edition whose file is unchanged (same address and SHA-256 as its stored evidence) is left as it is; a
--     changed file loads into a successor edition the same way.
-- A dry run writes nothing. The terms of a restricted edition are still never read. Nothing is dropped or deleted. G3 untouched.
-- Replaces: the single-pass load that wrote into any edition.
-- Retires: nothing.

create or replace function security.destination_page_facts_load_v1(p_payload jsonb)
 returns jsonb
 language plpgsql
 security definer
 set search_path to ''
as $function$
declare v_run uuid := nullif(p_payload->>'run_id', '')::uuid; v_dry boolean := coalesce((p_payload->>'dry_run')::boolean, false);
        pg jsonb; x jsonb; f destination.page_facts; e destination.editions; s destination.editions; v_ev uuid; v_read timestamptz; v_val numeric;
        v_rule destination.study_rules; v_found jsonb := '[]'::jsonb; fd jsonb; v_eds uuid[]; v_ed uuid; v_changed boolean; v_label text;
        v_nfound int := 0; v_missed int := 0; v_written int := 0; v_unchanged int := 0; v_differs int := 0; v_failed int := 0; v_successors jsonb := '[]'::jsonb;
        v_items jsonb := '[]'::jsonb; j jsonb; r jsonb; v_je destination.editions; v_jt destination.editions; v_jev uuid; v_cap int; v_jrows int := 0; v_jwritten int := 0; v_jkept int := 0;
        v_jsa jsonb; v_result jsonb; v_old record; v_day text := to_char(now() at time zone 'Australia/Sydney', 'DD Mon YYYY');
begin
  -- pass 1: read every fact; nothing is written to a rule here
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
        v_items := v_items || jsonb_build_object('title', f.title, 'status', case when pg ? 'error' then 'page_failed' else 'not_found' end, 'reason', coalesce(pg->>'error', x->>'reason'),
                                                'page_bytes', pg->'bytes', 'page_text_length', pg->'text_length');
        continue;
      end if;
      v_val := case when f.kind = 'text' then null else nullif(x->>'value', '')::numeric end;
      if f.kind <> 'text' and (v_val is null or (f.min_value is not null and v_val < f.min_value) or (f.max_value is not null and v_val > f.max_value)) then
        v_missed := v_missed + 1;
        v_items := v_items || jsonb_build_object('title', f.title, 'status', 'not_found', 'reason', 'value outside the plausible range');
        continue;
      end if;
      if position(coalesce(x->>'match', x->>'raw', '') in coalesce(x->>'quote', '')) = 0 or coalesce(btrim(x->>'quote'), '') = '' then
        v_missed := v_missed + 1;
        v_items := v_items || jsonb_build_object('title', f.title, 'status', 'not_found', 'reason', 'the quote does not hold the matched text');
        continue;
      end if;
      v_nfound := v_nfound + 1;
      v_items := v_items || jsonb_build_object('title', f.title, 'status', 'found', 'value', coalesce(x->>'raw', x->>'value'), 'quote', x->>'quote');
      if v_dry then continue; end if;
      if v_ev is null and coalesce(pg->>'sha256', '') <> '' then
        v_ev := security.destination_source_evidence_v1(pg->>'page_url', pg->>'sha256', 'text/html', nullif(pg->>'storage_path', ''),
                  jsonb_build_object('capture', 'destination-page-facts-v1', 'read_at', v_read, 'edition', e.edition_label, 'read_via', pg->>'read_via'));
      end if;
      update destination.page_facts set last_read_at = v_read, last_status = 'found', last_value = coalesce(x->>'raw', x->>'value'), last_quote = x->>'quote',
             last_reason = null, last_windows = null, updated_at = now() where id = f.id;
      v_found := v_found || jsonb_build_object('fact_id', f.id, 'edition_id', e.id, 'value', v_val, 'raw', coalesce(x->>'raw', x->>'value'), 'quote', x->>'quote',
                                               'evidence_id', v_ev, 'read_at', v_read, 'page_url', pg->>'page_url');
    end loop;
  end loop;

  -- pass 2: per edition
  if not v_dry then
    select array_agg(distinct (fd->>'edition_id')::uuid) into v_eds from jsonb_array_elements(v_found) fd;
    foreach v_ed in array coalesce(v_eds, '{}'::uuid[]) loop
      select * into e from destination.editions where id = v_ed;
      v_changed := false;
      if e.status = 'published' then
        select exists (
          select 1 from jsonb_array_elements(v_found) fd join destination.page_facts pf on pf.id = (fd->>'fact_id')::uuid
           where (fd->>'edition_id')::uuid = e.id
             and not exists (select 1 from destination.study_rules r where r.edition_id = e.id and r.rule_category = pf.rule_category and r.title = pf.title
                               and r.approval_status = 'approved' and r.numeric_threshold is not distinct from nullif(fd->>'value', '')::numeric
                               and (pf.kind <> 'text' or r.quote_on_page = fd->>'quote'))) into v_changed;
        if not v_changed then
          v_unchanged := v_unchanged + (select count(*) from jsonb_array_elements(v_found) fd where (fd->>'edition_id')::uuid = e.id)::int;
          continue;  -- a published edition with nothing new: no row is touched
        end if;
        -- a successor edition holds the change; the earlier one stays published until the successor is
        v_label := e.edition_label || ' (read ' || v_day || ')';
        select * into s from destination.editions where country_id = e.country_id and domain = e.domain and edition_label = v_label;
        if s.id is null then
          insert into destination.editions(country_id, domain, edition_label, effective_from, status, source_url, source_owner, attribution_text, terms_status, last_checked_at)
          values (e.country_id, e.domain, v_label, current_date, 'draft', e.source_url, e.source_owner, e.attribution_text, e.terms_status, now())
          returning * into s;
        end if;
        -- a copy of each published rule not read this time, quote and evidence kept, so the successor is complete
        insert into destination.study_rules(edition_id, country_id, rule_category, title, summary, applicant_scope, numeric_threshold, currency_code,
               application_fee_amount, fee_currency, work_hours_fortnight, financial_capacity_annual, post_study_work_years_max,
               quote_on_page, evidence_id, evidence_date, source_url, last_checked_at, approval_status)
        select s.id, r.country_id, r.rule_category, r.title, r.summary, r.applicant_scope, r.numeric_threshold, r.currency_code,
               r.application_fee_amount, r.fee_currency, r.work_hours_fortnight, r.financial_capacity_annual, r.post_study_work_years_max,
               r.quote_on_page, r.evidence_id, r.evidence_date, r.source_url, r.last_checked_at, 'draft'
          from destination.study_rules r
         where r.edition_id = e.id and r.approval_status = 'approved'
           and not exists (select 1 from jsonb_array_elements(v_found) fd join destination.page_facts pf on pf.id = (fd->>'fact_id')::uuid
                            where (fd->>'edition_id')::uuid = e.id and pf.rule_category = r.rule_category and pf.title = r.title)
           and not exists (select 1 from destination.study_rules q where q.edition_id = s.id and q.rule_category = r.rule_category and q.title = r.title);
        update destination.page_facts set edition_label = s.edition_label, updated_at = now() where edition_label = e.edition_label and status = 'active';
        v_successors := v_successors || jsonb_build_object('from', e.edition_label, 'to', s.edition_label);
        e := s;
      end if;
      -- write the facts of this run into a draft edition (the original draft, or the successor)
      for fd in select * from jsonb_array_elements(v_found) z where (z->>'edition_id')::uuid = v_ed loop
        select * into f from destination.page_facts where id = (fd->>'fact_id')::uuid;
        v_val := nullif(fd->>'value', '')::numeric; v_read := (fd->>'read_at')::timestamptz;
        select * into v_rule from destination.study_rules
         where edition_id = e.id and rule_category = f.rule_category and title = f.title and approval_status in ('draft', 'approved')
         order by (approval_status = 'approved') desc, created_at desc limit 1;
        if v_rule.id is not null and v_rule.approval_status = 'approved' then
          if v_rule.numeric_threshold is not distinct from v_val and (f.kind <> 'text' or v_rule.quote_on_page = fd->>'quote') then v_unchanged := v_unchanged + 1;
          else
            update destination.page_facts set last_status = 'differs_from_approved', last_reason = 'The page now says something different from the approved rule; a person decides', updated_at = now() where id = f.id;
            v_differs := v_differs + 1;
          end if;
          continue;
        end if;
        if v_rule.id is null then
          insert into destination.study_rules(edition_id, country_id, rule_category, title, summary, applicant_scope, numeric_threshold, currency_code,
                 application_fee_amount, fee_currency, work_hours_fortnight, financial_capacity_annual, post_study_work_years_max,
                 quote_on_page, evidence_id, evidence_date, source_url, last_checked_at, approval_status)
          values (e.id, e.country_id, f.rule_category, f.title,
                  f.title || case when v_val is not null then ': ' || coalesce(fd->>'raw', v_val::text) || coalesce(' ' || f.unit, '') else '' end || ' (read ' || to_char(v_read at time zone 'Australia/Sydney', 'DD Mon YYYY') || ')',
                  f.applicant_scope, v_val, f.currency_code,
                  case when f.rule_category = 'visa_fee' then v_val end, case when f.rule_category = 'visa_fee' then f.currency_code end,
                  case when f.rule_category = 'work_rights' then v_val::int end, case when f.rule_category = 'visa_funds' then v_val end,
                  case when f.rule_category = 'post_study_work' then v_val end,
                  fd->>'quote', nullif(fd->>'evidence_id', '')::uuid, (v_read at time zone 'Australia/Sydney')::date, fd->>'page_url', v_read, 'draft');
          v_written := v_written + 1;
        elsif v_rule.numeric_threshold is distinct from v_val or v_rule.quote_on_page is distinct from fd->>'quote' then
          update destination.study_rules set numeric_threshold = v_val, quote_on_page = fd->>'quote', evidence_id = coalesce(nullif(fd->>'evidence_id', '')::uuid, evidence_id),
                 evidence_date = (v_read at time zone 'Australia/Sydney')::date, last_checked_at = v_read,
                 application_fee_amount = case when f.rule_category = 'visa_fee' then v_val else application_fee_amount end,
                 work_hours_fortnight = case when f.rule_category = 'work_rights' then v_val::int else work_hours_fortnight end,
                 financial_capacity_annual = case when f.rule_category = 'visa_funds' then v_val else financial_capacity_annual end,
                 post_study_work_years_max = case when f.rule_category = 'post_study_work' then v_val else post_study_work_years_max end
           where id = v_rule.id;
          v_written := v_written + 1;
        else
          update destination.study_rules set last_checked_at = v_read, evidence_id = coalesce(evidence_id, nullif(fd->>'evidence_id', '')::uuid) where id = v_rule.id;
          v_unchanged := v_unchanged + 1;
        end if;
      end loop;
    end loop;
  end if;

  -- the JSA OSCA occupation workbook
  j := p_payload->'jsa';
  if j is not null and jsonb_typeof(j) = 'object' then
    select f2.edition_label into v_label from destination.page_facts f2 where f2.kind = 'workbook' and f2.status = 'active' order by f2.created_at limit 1;
    select * into v_je from destination.editions where edition_label = coalesce(v_label, 'JSA OSCA Occupation data (2021 Census)');
    v_jrows := coalesce(jsonb_array_length(j->'rows'), 0);
    v_cap := security.pipeline_num_v1('destination.career_rows_max', 3000)::int;
    v_jsa := jsonb_build_object('file', j->>'file_url', 'sheet', j->>'sheet', 'header', j->'header', 'rows', v_jrows,
                                'sheets', (select jsonb_agg(jsonb_build_object('name', q->>'name', 'rows', q->'rows')) from jsonb_array_elements(coalesce(j->'sheets', '[]'::jsonb)) q));
    if j ? 'error' then
      v_jsa := v_jsa || jsonb_build_object('status', 'failed', 'error', left(j->>'error', 500));
    elsif v_je.id is null or v_je.terms_status = 'restricted' then
      v_jsa := v_jsa || jsonb_build_object('status', 'held', 'reason', 'edition terms restricted or edition missing');
    elsif v_jrows = 0 then
      v_jsa := v_jsa || jsonb_build_object('status', 'no_rows', 'reason', 'no sheet has an occupation code, title and a measure column the reader knows; the sheet names and the rows around their code headings are in the run result',
                                           'first_rows', (select jsonb_agg(jsonb_build_object('name', q->>'name', 'first', q->'first')) from jsonb_array_elements(coalesce(j->'sheets', '[]'::jsonb)) q));
    elsif v_jrows > v_cap then
      v_jsa := v_jsa || jsonb_build_object('status', 'over_limit', 'reason', format('%s rows is over destination.career_rows_max (%s); nothing written', v_jrows, v_cap));
    elsif v_dry then
      v_jsa := v_jsa || jsonb_build_object('status', 'dry_run');
    elsif v_je.status = 'published' and exists (select 1 from pipeline.evidence_artifacts a where a.source_url = j->>'file_url' and a.content_hash = j->>'sha256') then
      v_jsa := v_jsa || jsonb_build_object('status', 'unchanged', 'reason', 'the published edition was loaded from this same file; nothing written');
    else
      v_jt := v_je;
      if v_je.status = 'published' then
        v_label := v_je.edition_label || ' (read ' || v_day || ')';
        select * into v_jt from destination.editions where country_id = v_je.country_id and domain = v_je.domain and edition_label = v_label;
        if v_jt.id is null then
          insert into destination.editions(country_id, domain, edition_label, effective_from, status, source_url, source_owner, attribution_text, terms_status, last_checked_at)
          values (v_je.country_id, v_je.domain, v_label, current_date, 'draft', v_je.source_url, v_je.source_owner, v_je.attribution_text, v_je.terms_status, now())
          returning * into v_jt;
        end if;
        update destination.page_facts set edition_label = v_jt.edition_label, updated_at = now() where edition_label = v_je.edition_label and status = 'active';
        v_successors := v_successors || jsonb_build_object('from', v_je.edition_label, 'to', v_jt.edition_label);
      end if;
      if coalesce(j->>'sha256', '') <> '' then
        v_jev := security.destination_source_evidence_v1(j->>'file_url', j->>'sha256', 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
                   nullif(j->>'storage_path', ''), jsonb_build_object('capture', 'destination-jsa-osca-v1', 'read_at', j->>'read_at', 'sheet', j->>'sheet', 'header', j->'header'));
      end if;
      for r in select * from jsonb_array_elements(j->'rows') loop
        select id, status into v_old from destination.career_outcomes
         where edition_id = v_jt.id and country_id = v_jt.country_id and occupation_scheme = 'OSCA' and occupation_code = r->>'code'
           and geography_level = 'national' and state_code is null and locality_id is null;
        if v_old.id is null then
          insert into destination.career_outcomes(edition_id, country_id, occupation_scheme, occupation_code, occupation_title, median_salary, salary_currency, salary_period,
                 employment_count, source_url, last_checked_at, reference_period, dataset_edition, attribution_text, status, geography_level, series_kind)
          values (v_jt.id, v_jt.country_id, 'OSCA', r->>'code', r->>'title', nullif(r->>'median_weekly_earnings', '')::numeric, 'AUD', coalesce(nullif(j->'header'->>'earnings_period', ''), 'weekly'),
                  nullif(r->>'employment_count', '')::numeric, j->>'file_url', coalesce(nullif(j->>'read_at', '')::timestamptz, now()), '2021 Census',
                  v_jt.edition_label, v_jt.attribution_text, 'draft', 'national', 'occupation');
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
      v_jsa := v_jsa || jsonb_build_object('status', 'loaded', 'edition', v_jt.edition_label, 'written', v_jwritten, 'kept_reviewed', v_jkept, 'evidence_id', v_jev);
    end if;
  end if;

  v_result := jsonb_strip_nulls(jsonb_build_object('dry_run', v_dry, 'facts_found', v_nfound, 'facts_not_found', v_missed, 'pages_failed', v_failed,
    'rules_written', v_written, 'rules_unchanged', v_unchanged, 'differs_from_approved', v_differs, 'successor_editions', case when jsonb_array_length(v_successors) > 0 then v_successors end,
    'facts', v_items, 'jsa', v_jsa, 'trigger', p_payload->>'trigger'));
  insert into pipeline.admin_control_events(area, action, target, detail, actor)
  values ('destination', case when v_dry then 'page_facts_load_dry_run' else 'page_facts_load' end, 'destination-page-facts-load', v_result || jsonb_build_object('run_id', v_run), null);
  perform security.destination_run_finish_v1(v_run, v_result, null);
  return v_result;
end $function$;
comment on function security.destination_page_facts_load_v1(jsonb) is 'RM1I/RM1C/RM1H/RM1D: reads every page fact (value, verbatim quote, evidence, time read), then writes per edition: draft rules into a draft edition; nothing into a published edition with nothing new; a successor edition for a new fact or a changed value (complete: the facts read and a copy of each published rule not read). The JSA workbook loads only when its file changed. Restricted editions held; a reviewed row is never changed; a dry run writes nothing.';
revoke all on function security.destination_page_facts_load_v1(jsonb) from public, anon, authenticated;

-- post-checks: a dry run writes nothing; published rows are untouched by this change
do $$
declare v_prev jsonb; v_n int := (select count(*) from destination.study_rules); v_e int := (select count(*) from destination.editions);
begin
  v_prev := security.destination_page_facts_load_v1(jsonb_build_object('trigger', 'post-check', 'dry_run', true, 'pages', jsonb_build_array(jsonb_build_object(
    'page_url', 'https://immi.homeaffairs.gov.au/visas/getting-a-visa/visa-listing/student-500', 'sha256', 'post-check', 'read_at', now(),
    'facts', (select jsonb_agg(jsonb_build_object('id', f.id, 'found', true, 'raw', '48', 'value', 48, 'match', '48 hours a fortnight',
                                 'quote', 'work up to 48 hours a fortnight when your course of study or training is in session.'))
                from destination.page_facts f where f.rule_category = 'work_rights' and f.status = 'active')))));
  if (v_prev->>'facts_found')::int <> 1 then raise exception 'post-check: the dry run must find the fact (%)', v_prev; end if;
  if (select count(*) from destination.study_rules) <> v_n or (select count(*) from destination.editions) <> v_e then raise exception 'post-check: a dry run wrote rows'; end if;
end $$;
