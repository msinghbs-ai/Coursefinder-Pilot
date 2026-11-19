-- CF-247 s815 (Platform Admin 20 Nov 2026 09:55 AEDT, chat S1-Build): domestic-only scholarships refused by rule; the scholarship classifier and
-- the full scholarship attribute sync no longer time out (IQ-00239 / IQ-00241, IQ-00613).
-- 1. Domestic-only rule (sch-domestic-v1, $0): a held scholarship whose own page quote says who may apply (the reader's audience quote, or the
--    re-check's) names only domestic groups (Aboriginal and Torres Strait Islander, Indigenous Australian, First Nations, Australian, New Zealand or
--    Canadian citizens, permanent residents, domestic students) and names no international group, and does not only state a preference or an
--    exclusion, is refused as Not for international students, exactly as the Layer 4 choice does, with the quote kept. Live read 20 Nov 2026
--    10:35 AEDT: 82 held, 9 refused by the rule (UTS Jumbunna among them); the other 73 stay for a person. The patterns are settings.
--    It reads the quotes already held; no page is read again and no AI is asked (it runs before the held re-check would ask the AI again).
-- 2. Classifier (scholarship-coverage-classify, failed 07:29, 08:29 and 09:29 at 120.1 s): its Coverage snapshot called the university test and
--    security.fc_sch_eligible_v1 once per provider (about 2,600), and each call planned security.third_party_host_v1 again. Both are now worked
--    out for all providers at once (security.scholarship_university_ids_v1, security.fc_sch_eligible_ids_v1; the same answers, proved below).
-- 3. Full attribute sync (scholarship-course-attribute-full, failed 07:51 on 19 and 20 Nov at 120.1 s): 15,890 courses in 2,000-course batches in
--    one call. A full pass now works in chunks (batch.sch_attr_chunk) until a time budget (sch_attr.full_run_seconds) and keeps its place; the
--    15-minute run continues it until every course is done.
-- Parity before writing (read live 20 Nov 2026 10:47 AEDT): head 20261120110000, 2,207 rows; numbered above it.
-- G1: one rollup target (scholarship-domestic-rule, rollup-scheduler; no cron job). G2: seven settings. G3: no consumer object changes. No spend.
-- Replaces: the per-provider university and eligibility calls in security.scholarship_provider_coverage_refresh_v1; the single-call full pass of security.scholarship_course_attribute_sync_v1.
-- Retires: nothing.

insert into pipeline.platform_toolset_settings (toolset_key, key, label, help, kind, value, min_value, max_value, unit, sort, section, used_by, reason)
values
 ('pipeline', 'sch_dom.on', 'Domestic-only rule on', 'Held scholarships whose page quote names only domestic groups are refused as Not for international students, with the quote kept.',
  'number', '1'::jsonb, 0, 1, 'on (1) or off (0)', 3310, 'Scholarships', 'security.scholarship_domestic_rule_v1', 'CF-247 s815 (Platform Admin 20 Nov 2026 09:55): deterministic domestic-only refusal'),
 ('pipeline', 'sch_dom.phrases', 'Domestic-only rule: domestic groups', 'Patterns (case ignored) that name a group only domestic applicants belong to. A quote must contain one.',
  'list', '["\\m(Aboriginal|Torres Strait Islanders?)\\M", "\\mIndigenous Australians?\\M", "\\mFirst Nations\\M", "\\m(Australian|New Zealand|Canadian) citizens?(hip)?\\M", "\\mpermanent residen(t|ts|cy)\\M", "\\mdomestic (students?|applicants?|candidates?)\\M"]'::jsonb,
  null, null, 'patterns', 3311, 'Scholarships', 'security.scholarship_domestic_quote_v1', 'CF-247 s815: the phrases the Platform Admin named on 20 Nov 2026'),
 ('pipeline', 'sch_dom.international_words', 'Domestic-only rule: international words', 'A quote with any of these patterns is never refused by the rule (it may be open to international students).',
  'list', '["\\m(international|overseas)\\M", "\\mnon[- ]?residents?\\M", "\\mforeign\\M", "\\mstudy permits?\\M", "\\mstudent visas?\\M", "\\mall nationalities\\M", "\\many (country|nationality)\\M"]'::jsonb,
  null, null, 'patterns', 3312, 'Scholarships', 'security.scholarship_domestic_quote_v1', 'CF-247 s815: international eligibility always wins'),
 ('pipeline', 'sch_dom.not_exclusive_words', 'Domestic-only rule: not exclusive', 'A quote that only states a preference, a priority or an exclusion is left for a person.',
  'list', '["\\mprefer(ence|red)?\\M", "\\mpriorit(y|ised|ized)\\M", "\\mencouraged\\M", "\\mexclud(e|es|ed|ing)\\M", "\\m(not eligible|ineligible)\\M", "\\mother than\\M"]'::jsonb,
  null, null, 'patterns', 3313, 'Scholarships', 'security.scholarship_domestic_quote_v1', 'CF-247 s815: "preference will be given to" is not domestic-only'),
 ('pipeline', 'batch.sch_domestic_rule', 'Domestic-only rule: reviews a run', 'Held scholarships the domestic-only rule reads in one run.',
  'number', '200'::jsonb, 1, 2000, 'reviews', 3314, 'Job sizes', 'security.scholarship_domestic_rule_v1 (rollup target scholarship-domestic-rule)', 'CF-247 s815'),
 ('pipeline', 'sch_attr.full_run_seconds', 'Full scholarship attribute sync: seconds a run', 'A full pass of the scholarship attributes on course search documents works for this long, then continues on the next run.',
  'number', '60'::jsonb, 10, 100, 'seconds', 3315, 'Scholarships', 'security.scholarship_course_attribute_sync_v1', 'CF-247 s815 (IQ-00613): the full pass timed out at 120 s'),
 ('pipeline', 'batch.sch_attr_chunk', 'Scholarship attribute sync: courses a chunk', 'Courses refreshed together by the scholarship attribute sync.',
  'number', '500'::jsonb, 50, 2000, 'courses', 3316, 'Job sizes', 'security.scholarship_course_attribute_sync_v1', 'CF-247 s815 (IQ-00613): 2,000 at once ran past the time-out')
on conflict do nothing;

-- 1. the domestic-only rule
create or replace function security.scholarship_domestic_quote_v1(p_text text)
returns text language sql stable security definer set search_path to '' as $f$
  -- the domestic group a quote names, or null when it names none, names an international group, or only states a preference or an exclusion
  select case when nullif(btrim(coalesce(p_text, '')), '') is null then null
              when exists (select 1 from unnest(security.pipeline_list_v1('sch_dom.international_words', '[]'::jsonb)) w where p_text ~* w) then null
              when exists (select 1 from unnest(security.pipeline_list_v1('sch_dom.not_exclusive_words', '[]'::jsonb)) w where p_text ~* w) then null
              else (select d from unnest(security.pipeline_list_v1('sch_dom.phrases', '[]'::jsonb)) with ordinality x(d, n) where p_text ~* d order by n limit 1) end
$f$;
revoke all on function security.scholarship_domestic_quote_v1(text) from public, anon, authenticated;
comment on function security.scholarship_domestic_quote_v1(text) is 'CF-247 s815: the domestic-only group a page quote names (sch_dom.* settings), or null.';

create or replace function security.scholarship_domestic_rule_v1(p_limit integer default null)
returns jsonb language plpgsql security definer set search_path to '' as $f$
-- held scholarships (Layer 4 › Held scholarship) whose page quote is domestic-only are refused as Not for international students, with the quote;
-- no page is read and no AI is asked
declare v_lim int := greatest(0, coalesce(p_limit, security.pipeline_num_v1('batch.sch_domestic_rule', 200)::int)); rw record; v_hit text;
        v_seen int := 0; v_n int := 0; v_err int := 0; v_last text;
begin
  if security.pipeline_num_v1('sch_dom.on', 0) < 1 then return jsonb_build_object('on', false); end if;
  for rw in select v.id, v.provider_id, v.candidate_id, x.id ext_id,
                   btrim(coalesce(x.answer->>'audience_quote', '') || ' ' || coalesce(v.recheck->>'audience_quote', '')) q
              from pipeline.scholarship_ai_reviews v
              cross join lateral (select e.id, e.answer from pipeline.scholarship_ai_extractions e where e.id = any (v.extraction_ids) and e.answer is not null
                                   order by coalesce((e.answer->>'is_scholarship')::boolean, false) desc, e.at desc limit 1) x
             where v.status = 'pending'
               and coalesce(x.answer->>'audience', '') <> 'international' and coalesce(v.recheck->>'audience', '') <> 'international'
             order by v.id limit v_lim
               for update of v skip locked loop
    v_seen := v_seen + 1;
    v_hit := security.scholarship_domestic_quote_v1(rw.q);
    continue when v_hit is null;
    begin
      perform security.scholarship_ai_review_apply_v1(rw.id, 'refuse', rw.ext_id, left('Not for international students (rule sch-domestic-v1): the page says "' || rw.q || '"', 600), null);
      -- the page is recorded as domestic-only (the refusal by a person would read refused_by_person)
      update pipeline.scholarship_page_candidates c set admit_reasons = array['domestic_only'],
             facts = coalesce(c.facts, '{}'::jsonb) || jsonb_build_object('domestic_rule', jsonb_build_object('quote', rw.q, 'pattern', v_hit, 'review_id', rw.id, 'at', now()))
       where c.id = rw.candidate_id and c.admit_reasons = array['refused_by_person'];
      update pipeline.layer4_item_groups set state = 'closed', closed_at = now() where kind = 'held_scholarship' and ref = rw.id::text and state = 'waiting';
      insert into pipeline.admin_control_events(area, action, target, detail, actor)
      values ('scholarship_rule', 'domestic_refuse', 'held_scholarship:' || rw.id,
              jsonb_build_object('review_id', rw.id, 'provider_id', rw.provider_id, 'extraction_id', rw.ext_id, 'quote', rw.q, 'pattern', v_hit, 'rule', 'sch-domestic-v1'), null);
      v_n := v_n + 1;
    exception when others then v_err := v_err + 1; v_last := left(sqlerrm, 200);
    end;
  end loop;
  return jsonb_build_object('on', true, 'read', v_seen, 'refused', v_n, 'errors', v_err, 'last_error', v_last);
end $f$;
revoke all on function security.scholarship_domestic_rule_v1(integer) from public, anon, authenticated;
comment on function security.scholarship_domestic_rule_v1(integer) is 'CF-247 s815: refuses held scholarships whose page quote is domestic-only (rule sch-domestic-v1), with the quote; rollup target scholarship-domestic-rule.';

insert into pipeline.rollup_targets(target_code, legacy_job, call_sql, call_md5, schedule, rollup_group, priority, enabled, mode, expected_ms, note)
values ('scholarship-domestic-rule', null, 'select security.scholarship_domestic_rule_v1()', md5('select security.scholarship_domestic_rule_v1()'), '3-59/10 * * * *', 'A', 70, true, 'live', 1000,
        's815 (20 Nov 2026): held scholarships whose page quote is domestic-only are refused as Not for international students (sch_dom.*; $0, before the held re-check asks the AI again).')
on conflict (target_code) do nothing;

-- 2. the university test and the scholarship eligibility for all providers at once
create or replace function security.scholarship_university_ids_v1()
returns setof uuid language sql stable security definer set search_path to '' as $f$
  -- the providers security.scholarship_university(id) is true for (the same three tests), worked out once
  with grp as materialized (select distinct m.provider_id from catalogue.provider_collection_memberships m join ref.institution_collections ic on ic.id = m.collection_id
                             where m.status = 'active' and ic.collection_type = 'university_group' and ic.status = 'active' and (m.valid_to is null or m.valid_to >= current_date))
  select p.id from catalogue.providers p join ref.countries c on c.id = p.country_id
   where p.lifecycle_status = 'active' and (
         (c.iso_alpha2 = 'AU' and (p.id in (select g.provider_id from grp g)
                                   or (p.canonical_name ~* '\muniversity\M' and p.canonical_name !~* '(college|pathways?|language cent|senior|theology|divinity)')))
      or (c.iso_alpha2 <> 'AU' and c.scholarship_ingestion_enabled
          and (p.id in (select g.provider_id from grp g)
               or (p.canonical_name ~* '\m(university|université|universite)\M' and p.canonical_name !~* '(college|pathways?|language cent|senior|theology|divinity)')))
      or (security.pipeline_num_v1('sch_cov.legal_name_identity_on', 0) >= 1 and c.scholarship_ingestion_enabled and position(';' in coalesce(p.canonical_name, '')) > 0
          and btrim(split_part(p.canonical_name, ';', 1)) ~* '\m(university|université|universite)\M'
          and btrim(split_part(p.canonical_name, ';', 1)) !~* '(college|pathways?|language cent|senior|theology|divinity)'))
$f$;
revoke all on function security.scholarship_university_ids_v1() from public, anon, authenticated;
comment on function security.scholarship_university_ids_v1() is 'CF-247 s815: every provider security.scholarship_university is true for, worked out at once.';

create or replace function security.fc_sch_eligible_ids_v1(p_ids uuid[])
returns table(provider_id uuid, eligible boolean) language sql stable security definer set search_path to '' as $f$
  -- security.fc_sch_eligible_v1 for many providers at once: the legitimacy test while scholarship.legitimacy_checks_on (and the pilot scope),
  -- else not Australian or at least scholarship_min_courses CRICOS-coded courses; the third-party host list is read once
  with ids as (select distinct x id from unnest(p_ids) x where x is not null),
  univ as materialized (select u from security.scholarship_university_ids_v1() u),
  lnk as materialized (select l.domain from pipeline.important_links l where l.enabled and l.retired_at is null and l.domain is not null
                         and 'not_provider_site' = any (l.uses) and l.authority_category in ('third_party_directory', 'general_web', 'ranking_publisher')),
  b as (select i.id, p.id pid, p.lifecycle_status, p.publication_status, p.enrols_international, p.website, k.iso_alpha2, t.status t_status, t.code t_code,
               security.site_host_v1(p.website) h
          from ids i left join catalogue.providers p on p.id = i.id left join ref.countries k on k.id = p.country_id left join ref.provider_types t on t.id = p.provider_type_id),
  w as (select b.*, nullif(btrim(coalesce(b.website, '')), '') is not null
                    and not coalesce((select bool_or(case when l.domain like '%.%' then b.h = l.domain or b.h like '%.' || l.domain else b.h ~ ('(^|\.)' || l.domain) end)
                                        from lnk l where b.h is not null), false) site_ok
          from b)
  select w.id,
         case when security.scholarship_flag_v1('scholarship.legitimacy_checks_on', false)
                   and (not security.scholarship_flag_v1('scholarship.pilot_only', true) or security.scholarship_pilot_member_v1(w.id))
              then coalesce(w.pid is not null and w.lifecycle_status = 'active' and w.publication_status = 'published' and w.enrols_international is not false and w.site_ok
                   and ((w.t_status = 'active' and w.t_code <> 'school'
                         and (select count(*) from catalogue.courses c where c.provider_id = w.id and c.lifecycle_status = 'active')
                             >= security.pipeline_num_v1('scholarship.legitimacy_min_courses', 1))
                        or w.id in (select u.u from univ u)), false)
              else w.iso_alpha2 is distinct from 'AU'
                   or (select count(*)::int from catalogue.courses c where c.provider_id = w.id and c.lifecycle_status = 'active' and c.course_code ~ '^[0-9]{6}[0-9A-Z]$')
                      >= security.fc_setting_num_v1('scholarship_min_courses', 30) end
    from w
$f$;
revoke all on function security.fc_sch_eligible_ids_v1(uuid[]) from public, anon, authenticated;
comment on function security.fc_sch_eligible_ids_v1(uuid[]) is 'CF-247 s815: security.fc_sch_eligible_v1 for many providers at once (third-party hosts and universities read once).';

create or replace function pg_temp.cf_edit_def(p_sig regprocedure, p_md5 text, p_old text[], p_new text[])
returns void language plpgsql as $f$
declare v_def text := replace(pg_get_functiondef(p_sig), chr(13), ''); v_c int; i int;
begin
  if md5(v_def) <> p_md5 then raise exception 'pre-check: % changed since it was read (definition md5 %)', p_sig, md5(v_def); end if;
  for i in 1 .. array_length(p_old, 1) loop
    v_c := (length(v_def) - length(replace(v_def, p_old[i], ''))) / length(p_old[i]);
    if v_c <> 1 then raise exception 'pre-check: %: fragment % must occur exactly once (found %)', p_sig, i, v_c; end if;
    v_def := replace(v_def, p_old[i], p_new[i]);
  end loop;
  execute v_def;
end $f$;

select pg_temp.cf_edit_def('security.scholarship_provider_coverage_refresh_v1()'::regprocedure, 'cbccd8a5104ffdf1cc88d63d18adb56e',
  array[$o$with univ as materialized (select p.id from catalogue.providers p where security.scholarship_university(p.id)),$o$,
        $o$cand as (
  select k.provider_id, count(*) n,$o$,
        $o$security.fc_sch_eligible_v1(p.id) search_eligible,$o$,
        $o$    left join rv v on v.provider_id = p.id left join fc f on f.provider_id = p.id)$o$],
  array[$n$with univ as materialized (select u.id from security.scholarship_university_ids_v1() u(id)),  -- s815: worked out once$n$,
        $n$elig as materialized (select e.provider_id, e.eligible from security.fc_sch_eligible_ids_v1(array(select pop.id from pop)) e),  -- s815: worked out once
cand as (
  select k.provider_id, count(*) n,$n$,
        $n$el.eligible search_eligible,$n$,
        $n$    left join rv v on v.provider_id = p.id left join fc f on f.provider_id = p.id
    left join elig el on el.provider_id = p.id)$n$]);

-- 3. the full scholarship attribute sync works in chunks within a time budget and keeps its place
alter table pipeline.scholarship_attribute_sync add column if not exists full_cursor uuid, add column if not exists full_started_at timestamptz,
  add column if not exists full_finished_at timestamptz, add column if not exists full_done integer not null default 0, add column if not exists full_changed integer not null default 0;

do $$ begin
  if md5(replace(pg_get_functiondef('security.scholarship_course_attribute_sync_v1(boolean)'::regprocedure), chr(13), '')) <> 'b01031c801e770fd1c30e691ab06fb01' then
    raise exception 'pre-check: security.scholarship_course_attribute_sync_v1 changed since it was read'; end if;
end $$;
create or replace function security.scholarship_course_attribute_sync_v1(p_full boolean default false)
returns jsonb language plpgsql security definer set search_path to 'pg_catalog', 'scholarship', 'pipeline', 'search', 'security' as $function$
-- CF-247 s815 (IQ-00613): the incremental run as before, in chunks of batch.sch_attr_chunk; a full pass (p_full) starts from the first course and
-- works in chunks until sch_attr.full_run_seconds, keeping its place (full_cursor); every later run continues it until all courses are done
declare v_since timestamptz; v_now timestamptz := now(); v_ids uuid[]; v_res jsonb; v_done int := 0; v_batch uuid[]; i int := 0;
        v_chunk int := greatest(1, security.pipeline_num_v1('batch.sch_attr_chunk', 500)::int);
        v_budget numeric := security.pipeline_num_v1('sch_attr.full_run_seconds', 60);
        v_t0 timestamptz := clock_timestamp(); v_cur uuid; v_fn int := 0; v_fc int := 0; v_was uuid;
begin
  select last_run_at, full_cursor into v_since, v_cur from pipeline.scholarship_attribute_sync where id = 1 for update;
  if p_full then
    v_cur := '00000000-0000-0000-0000-000000000000';  -- fixed: the first course id
    update pipeline.scholarship_attribute_sync set full_cursor = v_cur, full_started_at = v_now, full_finished_at = null, full_done = 0, full_changed = 0 where id = 1;
  else
    select array_agg(distinct x) into v_ids from (
      select m.course_id x from scholarship.course_mappings m join scholarship.scholarships s on s.id = m.scholarship_id where s.updated_at > v_since
      union select fc.course_id from scholarship.course_financial_calculations fc where fc.calculated_at > v_since
      union select m.course_id from scholarship.course_mappings m join pipeline.scholarship_publication_batches b on m.scholarship_id = any(b.scholarship_ids) where b.created_at > v_since
      union select m.course_id from scholarship.course_mappings m where m.updated_at > v_since) q;
    v_ids := coalesce(v_ids, '{}');
    while i * v_chunk < cardinality(v_ids) loop
      v_batch := v_ids[i * v_chunk + 1 : (i + 1) * v_chunk];
      v_res := search.refresh_course_enrichment_core_scoped_v1(v_batch, true);
      v_done := v_done + coalesce((v_res->>'changed')::int, 0);
      i := i + 1;
    end loop;
  end if;
  v_was := v_cur;
  while v_cur is not null and extract(epoch from clock_timestamp() - v_t0) < v_budget loop
    select array_agg(z.x order by z.x) into v_batch from (
      select q.x from (select course_id x from scholarship.course_mappings where mapping_state = 'mapped' and course_id > v_cur
                       union select d.course_id from search.course_documents d where d.course_id > v_cur and coalesce(jsonb_array_length(d.scholarship_options), 0) > 0) q
       order by q.x limit v_chunk) z;
    if v_batch is null then v_cur := null; exit; end if;
    v_res := search.refresh_course_enrichment_core_scoped_v1(v_batch, true);
    v_fn := v_fn + cardinality(v_batch); v_fc := v_fc + coalesce((v_res->>'changed')::int, 0);
    v_cur := v_batch[cardinality(v_batch)];
  end loop;
  if v_was is not null then
    update pipeline.scholarship_attribute_sync set full_cursor = v_cur, full_done = full_done + v_fn, full_changed = full_changed + v_fc,
           full_finished_at = case when v_cur is null then clock_timestamp() end where id = 1;
  end if;
  v_res := jsonb_build_object('full', p_full, 'courses', cardinality(coalesce(v_ids, '{}')), 'changed', v_done, 'since', v_since,
                              'full_pass', case when v_was is not null then jsonb_build_object('courses', v_fn, 'changed', v_fc, 'finished', v_cur is null, 'cursor', v_cur) end);
  update pipeline.scholarship_attribute_sync set last_run_at = case when p_full then last_run_at else v_now end, last_result = v_res where id = 1;
  return v_res;
end $function$;
comment on function security.scholarship_course_attribute_sync_v1(boolean) is 'CF-247 s815 (IQ-00613): scholarship attributes on course search documents; incremental since the last run, and a full pass in chunks within sch_attr.full_run_seconds that keeps its place.';

-- post-checks (rolled back): same answers, the times, the rule
do $$
declare v_o text := ''; t0 timestamptz; v_ms int; v_cms int; v_r jsonb; v_n int; v_ids uuid[];
begin
  -- the university test: the same providers
  if exists (select u from security.scholarship_university_ids_v1() u except select p.id from catalogue.providers p where security.scholarship_university(p.id))
     or exists (select p.id from catalogue.providers p where security.scholarship_university(p.id) except select u from security.scholarship_university_ids_v1() u) then
    raise exception 'post-check: the university set differs'; end if;
  -- eligibility: the same answer for a spread of 400 providers (every country and kind)
  v_ids := array(select p.id from catalogue.providers p order by md5(p.id::text) limit 400);
  select count(*) into v_n from security.fc_sch_eligible_ids_v1(v_ids) e where e.eligible is distinct from security.fc_sch_eligible_v1(e.provider_id);
  if v_n > 0 then raise exception 'post-check: eligibility differs for % providers', v_n; end if;
  v_o := 'same universities (' || (select count(*) from security.scholarship_university_ids_v1()) || ') and eligibility (400 providers)';
  -- the Coverage snapshot and the classifier, timed (rolled back)
  t0 := clock_timestamp();
  begin perform security.scholarship_provider_coverage_refresh_v1(); raise exception 'cf-s815-undo';
  exception when others then if sqlerrm <> 'cf-s815-undo' then raise exception 'post-check: the snapshot failed: %', sqlerrm; end if; end;
  v_ms := round(extract(epoch from clock_timestamp() - t0) * 1000);
  t0 := clock_timestamp();
  begin v_r := security.scholarship_coverage_classify_v1(); raise exception 'cf-s815-undo';
  exception when others then if sqlerrm <> 'cf-s815-undo' then raise exception 'post-check: the classifier failed: %', sqlerrm; end if; end;
  v_cms := round(extract(epoch from clock_timestamp() - t0) * 1000);
  v_o := v_o || ' | snapshot ' || v_ms || ' ms (was 70 to 120 s) | classifier run ' || v_cms || ' ms';
  if v_cms > 60000 then raise exception 'post-check: the classifier took % ms', v_cms; end if;
  -- the domestic-only rule
  if security.scholarship_domestic_quote_v1('this scholarship is offered to commencing Indigenous Australian students of exceptional research potential') is null
     or security.scholarship_domestic_quote_v1('Preference will be given to Canadian Citizens.') is not null
     or security.scholarship_domestic_quote_v1('Open to Canadian citizens. Open to foreign nationals holding Canadian study permits.') is not null
     or security.scholarship_domestic_quote_v1('For citizens of any South Pacific Nation (excluding New Zealander and Australian citizens)') is not null
     or security.scholarship_domestic_quote_v1('Be a citizen of a country other than Australia or New Zealand.') is not null then
    raise exception 'post-check: the domestic-only patterns'; end if;
  begin
    v_r := security.scholarship_domestic_rule_v1(null);
    if (v_r->>'errors')::int > 0 then raise exception 'post-check: the rule failed: %', v_r->>'last_error'; end if;
    v_o := v_o || ' | domestic rule: read ' || (v_r->>'read') || ', refused ' || (v_r->>'refused')
               || '; Jumbunna refused: ' || coalesce((select (status = 'refused')::text from pipeline.scholarship_ai_reviews where id = 2300), 'not held');
    raise exception 'cf-s815-undo';
  exception when others then if sqlerrm <> 'cf-s815-undo' then raise; end if; end;
  -- the full attribute pass: one run, within the budget
  t0 := clock_timestamp();
  begin
    update pipeline.platform_toolset_settings set value = '8'::jsonb where toolset_key = 'pipeline' and key = 'sch_attr.full_run_seconds';  -- the dry run's own budget (rolled back)
    v_r := security.scholarship_course_attribute_sync_v1(true);
    v_o := v_o || ' | full attribute run ' || round(extract(epoch from clock_timestamp() - t0) * 1000) || ' ms, ' || (v_r->'full_pass'->>'courses') || ' courses, finished ' || (v_r->'full_pass'->>'finished');
    raise exception 'cf-s815-undo';
  exception when others then if sqlerrm <> 'cf-s815-undo' then raise exception 'post-check: the full attribute run failed: %', sqlerrm; end if; end;
  if not exists (select 1 from pipeline.rollup_targets where target_code = 'scholarship-domestic-rule' and mode = 'live' and enabled and call_md5 = md5(call_sql)) then
    raise exception 'post-check: the rollup target is not live'; end if;
  perform set_config('cf.diag', v_o, true);
end $$;
