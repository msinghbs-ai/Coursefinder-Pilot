-- CF-247 (15 Oct 2026): central pages for the top Australian providers, and fee admission after a cross-check. Platform Admin decisions
-- (multiple choice, 15 Oct 2026): "Central pages, per course group"; "Qualify first, then decide" then "Clear the >=90% ones";
-- "Auto-approve checked AI proposals", "Double degrees take the shared default", "Research degrees need a research default", "Keep the other holds".
-- Found before: in the top 50, English and intakes are mostly not printed on course pages (ANU: 412 pages read, English on none); 21 AI readings
-- of central pages had waited for a person since 12 Oct; approved English policies held back 925 research degrees, 634 double degrees and 940
-- other courses (Decision 227 holds); 456 fees read by adapters were not admitted. Fee cross-check (annual fee x years against the CRICOS
-- registered course total, within 25%): Wollongong 96%, Tasmania 91%, TAFE NSW 90%, Notre Dame 100% (3); Victoria University 1%,
-- Academies Australasia 0%, Torrens 57% stay blocked and are flagged.
-- 1 Settings (Pipeline settings › Admission checks)   2 Rules   3 Replaced functions (md5-guarded)   4 Fee admission for four adapters
-- 5 Central pages read with AI for the focus providers; automatic approval job   6 First run
-- Nothing dropped or deleted. Values are written only where a course has none (unchanged apply rules); an automatic approval is refused when
-- most comparable course pages disagree, and is recorded and flagged.

do $guard$
declare v_expected jsonb := '{"security.provider_english_plan_v1(uuid)": "a14d3730795e09918e52964bdead2c43", "security.provider_english_apply_v1(uuid)": "af9a96c994115a1f05313cf239efddc6", "security.adapter_overwrite_gated_v1(integer)": "62780a64c3be452ecdda706e2de476f7"}'::jsonb;
  v_sig text;
begin
  for v_sig in select jsonb_object_keys(v_expected) loop
    if md5(replace(pg_get_functiondef(v_sig::regprocedure), E'\r', '')) <> v_expected->>v_sig then
      raise exception 'live % differs from the definition this change replaces', v_sig;
    end if;
  end loop;
end $guard$;

-- 1 Settings
insert into pipeline.platform_toolset_settings(toolset_key, key, label, help, kind, value, min_value, max_value, unit, sort, reason, section, used_by) values
 ('pipeline', 'admit.fee_crosscheck_pct', 'Fee read by an adapter: most it may differ from the registered course total', 'Before an adapter fee is admitted, the annual fee times the years of the course is compared with the CRICOS registered course total. A fee further off than this is held back and flagged.', 'number', to_jsonb(25), 5, 100, '%', 720, 'Platform Admin 15 Oct 2026: "Qualify first, then decide", then "Clear the >=90% ones"', 'Admission checks', 'adapter-overwrite (fee check)'),
 ('pipeline', 'central.auto_approve', 'Approve AI readings of central pages automatically (focus providers)', 'Yes: an AI reading of a top provider''s English policy or academic calendar is approved when every value is quoted on the page and the course pages do not mostly disagree. No: a person approves each.', 'boolean', 'true'::jsonb, null, null, 'yes or no', 721, 'Platform Admin 15 Oct 2026: "Central pages, per course group", "Auto-approve checked AI proposals"', 'Admission checks', 'policy-auto-approve job'),
 ('pipeline', 'central.max_disagree_pct', 'Automatic approval: most course pages that may disagree', 'An English default is not approved automatically when more than this share of the courses that show a score on their own page disagree with it.', 'number', to_jsonb(50), 0, 100, '%', 722, 'CF-247 15 Oct 2026: the rule a Platform Admin approval already follows (more disagree than agree)', 'Admission checks', 'policy-auto-approve job'),
 ('pipeline', 'central.min_compare', 'Automatic approval: least comparable courses before disagreement counts', 'Below this many courses with their own score the disagreement rule does not apply.', 'number', to_jsonb(10), 1, 500, 'courses', 723, 'CF-247 15 Oct 2026: the rule a Platform Admin approval already follows (10 courses)', 'Admission checks', 'policy-auto-approve job')
on conflict do nothing;

-- 2 Rules
CREATE OR REPLACE FUNCTION security.double_degree_same_group_v1(p_title text, p_grp text)
 RETURNS boolean
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO ''
AS $function$
  -- a double degree whose every award is in the same group as the course (for example Bachelor of Arts / Bachelor of Laws, both undergraduate)
  select p_grp is not null and coalesce((
    select count(*) >= 2 and bool_and(case when m[1] in ('bachelor', 'associate degree') then 'undergraduate'
                                           when m[1] in ('master', 'graduate certificate', 'graduate diploma') then 'postgraduate' else 'other' end = p_grp)
      from regexp_matches(lower(coalesce(p_title, '')), '(bachelor|associate degree|master|graduate certificate|graduate diploma|diploma|doctor)', 'g') m), false)
$function$;

CREATE OR REPLACE FUNCTION security.fee_crosscheck_guard_v1()
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_pct numeric := security.pipeline_num_v1('admit.fee_crosscheck_pct', 25); r record; v_n int := 0; v_reason text;
begin
  -- an adapter fee not yet held is compared with the CRICOS registered course total; one too far off is held back (adapter exclusion) and flagged
  for r in
    select x.course_id, x.provider_id, x.fee, x.months, x.reg from (
      select pg.course_id, pg.provider_id, (pg.candidates->'fee'->>'value')::numeric fee, d.regulatory_tuition_amount reg,
             case co.duration_unit when 'months' then co.duration_value when 'weeks' then co.duration_value * 12 / 52.0 when 'years' then co.duration_value * 12 end months
        from pipeline.coverage_course_pages pg
        join pipeline.uni_adapters u on u.provider_id = pg.provider_id and u.enabled and u.admit and 'fee' = any (u.admit_fields)
        join catalogue.courses co on co.id = pg.course_id and co.lifecycle_status = 'active'
        join search.course_documents d on d.course_id = pg.course_id
       where pg.read_status = 'read' and pg.candidates->>'fee_by' = 'adapter' and (pg.candidates->'fee'->>'value') ~ '^[0-9]+(\.[0-9]+)?$'
         and d.regulatory_tuition_basis = 'registered_total_course' and d.regulatory_tuition_amount > 0
         and not d.has_provider_current_tuition
         and not exists (select 1 from pipeline.uni_adapter_exclusions e where e.course_id = pg.course_id and e.field = 'fee')) x
     where x.months >= 12 and abs(x.fee * x.months / 12.0 - x.reg) > v_pct / 100.0 * x.reg
  loop
    v_reason := format('automatic: the fee read (%s a year, %s months) is more than %s%% from the CRICOS registered course total (%s); held back for review (CF-247 15 Oct 2026)',
                       r.fee, round(r.months), v_pct, r.reg);
    insert into pipeline.uni_adapter_exclusions(course_id, field, provider_id, active, reason) values (r.course_id, 'fee', r.provider_id, true, v_reason)
    on conflict (course_id, field) do nothing;
    insert into pipeline.enrichment_flags(entity, entity_key, provider_id, field, reason_code, reason, source)
    values ('course', r.course_id::text, r.provider_id, 'fee', 'fee_crosscheck', v_reason, 'adapter-overwrite')
    on conflict (entity, entity_key, field, reason_code) do nothing;
    v_n := v_n + 1;
  end loop;
  return v_n;
end $function$;

CREATE OR REPLACE FUNCTION security.policy_auto_approve_v1()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare r record; v_sum jsonb; v_ag int; v_df int; v_ok int := 0; v_refused int := 0;
        v_max numeric := security.pipeline_num_v1('central.max_disagree_pct', 50);
        v_min int := security.pipeline_num_v1('central.min_compare', 10)::int;
        v_note text := 'Automatic: AI reading of the central page, every value quoted on the page (Platform Admin 15 Oct 2026: "Central pages, per course group", "Auto-approve checked AI proposals")';
begin
  if not coalesce((select (s.value #>> '{}')::boolean from pipeline.platform_toolset_settings s where s.toolset_key = 'pipeline' and s.key = 'central.auto_approve'), false) then
    return jsonb_build_object('off', true);
  end if;
  for r in select x.* from pipeline.provider_policy_proposals x
             join pipeline.enrich_focus_providers f on f.provider_id = x.provider_id and f.in_focus
            where x.status = 'proposed' and x.parser like 'ai:%' and x.kind in ('english_policy', 'intake_calendar')
            order by f.rank, x.created_at loop
    if r.kind = 'english_policy' then
      v_sum := security.provider_policy_refresh_one_v1(r.id);
      v_ag := coalesce((v_sum->>'agrees')::int, 0); v_df := coalesce((v_sum->>'differs')::int, 0);
      if v_ag + v_df >= v_min and 100.0 * v_df / (v_ag + v_df) > v_max then
        insert into pipeline.enrichment_flags(entity, entity_key, provider_id, field, reason_code, reason, source)
        values ('policy', r.id::text, r.provider_id, 'english', 'policy_disagrees',
                format('Not approved automatically: %s course pages agree and %s disagree with this default; a person decides (%s)', v_ag, v_df, r.url), 'policy-auto-approve')
        on conflict (entity, entity_key, field, reason_code) do update set reason = excluded.reason, flagged_at = now(), cleared_at = null;
        v_refused := v_refused + 1;
        continue;
      end if;
    end if;
    update pipeline.provider_policy_proposals set status = 'approved', decided_by = null, decided_at = now(), decision_note = v_note, updated_at = now() where id = r.id;
    insert into pipeline.admin_control_events(area, action, target, detail, actor)
    values ('policies', 'approve', r.kind || ': ' || r.url, jsonb_build_object('decision', 'Platform Admin 15 Oct 2026: automatic approval of checked AI readings', 'proposal_id', r.id, 'provider_id', r.provider_id), null);
    update pipeline.provider_policy_proposals
       set status = 'superseded', decided_at = now(), updated_at = now(), decision_note = 'Closed: another document for this university was approved (' || r.url || ')'
     where provider_id = r.provider_id and kind = r.kind and status = 'proposed' and id <> r.id;
    v_ok := v_ok + 1;
  end loop;
  return jsonb_build_object('approved', v_ok, 'refused', v_refused);
end $function$;

revoke execute on function security.double_degree_same_group_v1(text, text), security.fee_crosscheck_guard_v1(), security.policy_auto_approve_v1() from public, anon, authenticated;

-- 3 Replaced functions

CREATE OR REPLACE FUNCTION security.provider_english_plan_v1(p_proposal_id uuid)
 RETURNS TABLE(course_id uuid, title text, study_level text, plan text, reason text, requirements jsonb, existing jsonb, outcome text)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'catalogue', 'pipeline', 'ref', 'security'
AS $function$
declare x pipeline.provider_policy_proposals%rowtype; v_named jsonb; v_defaults jsonb;
begin
  select * into x from pipeline.provider_policy_proposals where id = p_proposal_id;
  if x.id is null or x.kind <> 'english_policy' then raise exception 'not an English policy proposal'; end if;
  v_defaults := coalesce(x.proposal->'defaults', '{}'::jsonb);
  select coalesce(jsonb_agg(jsonb_build_object('k', s.k, 'reqs', s.reqs)), '[]'::jsonb) into v_named from (
    select security.english_title_key(n) k, null::jsonb reqs from jsonb_array_elements_text(coalesce(x.proposal->'named', '[]'::jsonb)) n
    union all
    select security.english_title_key(e->>'name'), case when jsonb_typeof(e->'reqs') = 'array' and jsonb_array_length(e->'reqs') > 0
                                                       then (select jsonb_agg(q - 'quote') from jsonb_array_elements(e->'reqs') q) end
      from jsonb_array_elements(coalesce(x.proposal->'exceptions', '[]'::jsonb)) e) s where length(s.k) >= 4;
  return query
  with named as materialized (
    select e->>'k' k, nullif(e->'reqs', 'null'::jsonb) reqs,
           array(select distinct t from unnest(regexp_split_to_array(e->>'k', '[ /]+')) t where t not in ('of', 'and', 'in', 'the', '')) toks
      from jsonb_array_elements(v_named) e),
  c0 as materialized (
    select co.id, co.canonical_title t, security.english_title_key(co.canonical_title) k, sl.code lvl
      from catalogue.courses co left join ref.study_levels sl on sl.id = co.study_level_id
     where co.provider_id = x.provider_id and co.lifecycle_status = 'active'),
  c as materialized (
    select c0.*, array(select distinct t from unnest(regexp_split_to_array(c0.k, '[ /]+')) t where t not in ('of', 'and', 'in', 'the', '')) toks,
           case when c0.lvl in ('bachelor', 'bachelor_honours', 'associate_degree') then 'undergraduate'
                when c0.lvl in ('graduate_certificate', 'graduate_diploma', 'masters', 'masters_coursework', 'masters_extended') then 'postgraduate'
                when c0.lvl in ('doctorate', 'masters_research') then 'research' end grp,  -- CF-247 15 Oct: research degrees take the policy's research default
           (select coalesce(jsonb_object_agg(et.code, r.overall_score), '{}'::jsonb) from catalogue.course_english_requirements r
              join ref.english_tests et on et.id = r.english_test_id where r.course_id = c0.id and r.status = 'active') ex,
           exists (select 1 from catalogue.course_english_requirements r where r.course_id = c0.id) any_row,
           exists (select 1 from pipeline.manual_locks l where l.entity = 'course' and l.entity_id = c0.id and l.field in ('english', 'english_requirements', 'course_english')) locked,
           exists (select 1 from pipeline.layer4_review_items i where i.entity_type = 'course' and i.entity_id = c0.id and i.field_code = 'course_english' and i.status = 'pending') in_review,
           exists (select 1 from pipeline.layer3_fact_handoffs h left join pipeline.layer3_work_items w on w.id = h.work_item_id
                    where h.course_id = c0.id and h.task_class = 'provider_english_validation'
                      and (h.work_item_id is null or w.status in ('interpreting', 'validated', 'queued', 'pending'))) in_l3,
           exists (select 1 from pipeline.coverage_course_pages g where g.course_id = c0.id and g.status in ('bound', 'ambiguous')
                      and (g.read_status is null or g.read_status = 'needs_render')) page_waiting
      from c0),
  m as (
    select c.*,
           (select jsonb_agg(distinct named.reqs) from named where named.k = c.k and named.reqs is not null) exact_reqs,
           exists (select 1 from named where named.k = c.k) exact_named,
           exists (select 1 from named where named.k <> c.k and (position(named.k in c.k) > 0 or position(c.k in named.k) > 0
                     or (cardinality(c.toks) > 0 and cardinality(named.toks) > 0
                         and (select count(*) from unnest(c.toks) t where t = any(named.toks))::numeric / greatest(cardinality(c.toks), cardinality(named.toks)) >= 0.75))) close_named,
           case when c.grp is not null then v_defaults->c.grp end dflt
      from c),
  p as (
    select m.*,
           case when m.lvl is null then 'held|study level unknown'
                when m.lvl in ('doctorate', 'masters_research') and jsonb_typeof(v_defaults->'research') is distinct from 'array' then 'held|research degree (the policy states no research requirement)'
                when m.t ~* 'exit award' then 'held|exit award only'
                when (m.k ~ '/' or m.k ~ ' and (bachelor|master|doctor|graduate|diploma|associate) (of|in) ') and not security.double_degree_same_group_v1(m.t, m.grp) then 'held|double degree (its parts are at different levels)'
                when m.exact_reqs is not null and jsonb_array_length(m.exact_reqs) > 1 then 'held|the policy gives this course more than one requirement'
                when m.exact_reqs is not null then 'named|'
                when m.exact_named or m.close_named then 'held|named in the policy (it may have its own requirement)'
                when m.grp is null then 'held|level not covered by the policy default'
                when m.dflt is null or jsonb_typeof(m.dflt) <> 'array' then 'held|the policy gives no default for this level'
                else 'default|' end pr
      from m),
  q as (
    select p.*, split_part(p.pr, '|', 1) pl, nullif(split_part(p.pr, '|', 2), '') rs,
           case when p.pr like 'named|%' then p.exact_reqs->0 when p.pr like 'default|%' then p.dflt end reqs
      from p)
  select q.id, q.t, q.lvl, q.pl, q.rs, q.reqs, q.ex,
         case when q.pl = 'held' then 'held'
              when q.any_row and exists (select 1 from jsonb_array_elements(q.reqs) r where q.ex ? (r->>'test_code') and (q.ex->>(r->>'test_code'))::numeric <> (r->>'overall_score')::numeric) then 'differs'
              when q.any_row and exists (select 1 from jsonb_array_elements(q.reqs) r where q.ex ? (r->>'test_code')) then 'agrees'
              when q.any_row then 'other_value'
              when q.locked then 'set_by_hand'
              when q.in_review then 'in_review'
              when q.in_l3 or q.page_waiting then 'waiting'
              else 'write' end
    from q;
end $function$;

CREATE OR REPLACE FUNCTION security.provider_english_apply_v1(p_proposal_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'catalogue', 'pipeline', 'security', 'search'
AS $function$
declare x pipeline.provider_policy_proposals%rowtype; v_src uuid; v_name text; r record; v_ok int := 0; v_err int := 0; v_courses uuid[] := '{}'; v_last text;
  v_flag boolean; v_flagged int := 0; v_appr text;
begin
  select * into x from pipeline.provider_policy_proposals where id = p_proposal_id;
  if x.id is null or x.kind <> 'english_policy' then raise exception 'not an English policy proposal'; end if;
  if x.status <> 'approved' then raise exception 'proposal is not approved'; end if;
  if x.evidence_id is null then
    select fs.evidence_id into x.evidence_id from pipeline.provider_fact_sources fs where fs.id = x.fact_source_id and fs.url = x.url and fs.evidence_id is not null;
  end if;
  if x.evidence_id is null or coalesce(x.content_hash, '') = '' then raise exception 'the policy document has no stored evidence'; end if;
  v_src := security.coverage_sweep_source(x.provider_id);
  select coalesce(p.display_name, p.canonical_name) into v_name from catalogue.providers p where p.id = x.provider_id;
  v_flag := security.provider_english_flagged(x.proposal);
  -- CF-247 15 Oct: say who approved it
  v_appr := case when x.decided_by is null and coalesce(x.decision_note, '') like 'Automatic:%' then '(approved automatically: every value is quoted on the page; Platform Admin decision 15 Oct 2026)' else '(approved by a Platform Admin, Decision 227)' end;
  -- courses open to international students first
  for r in select pl.* from security.provider_english_plan_v1(p_proposal_id) pl join catalogue.courses co on co.id = pl.course_id
            where pl.outcome = 'write' order by co.open_to_international desc nulls last, pl.title loop
    begin
      perform security.coverage_apply_course_v1(r.course_id, v_src, x.evidence_id, x.url, x.content_hash,
        jsonb_build_object('english_requirements', (select jsonb_agg(jsonb_build_object(
            'test_code', q->>'test_code', 'overall_score', q->'overall_score', 'component_scores', coalesce(q->'component_scores', '{}'::jsonb),
            'source_requirement_key', 'policy:' || x.id || ':' || lower(q->>'test_code'),
            'notes', case when r.plan = 'named' then 'From ' || v_name || '''s English language policy, which names this course ' || v_appr
                          else 'Default for ' || case when r.study_level in ('graduate_certificate', 'graduate_diploma', 'masters', 'masters_coursework', 'masters_extended') then 'postgraduate coursework' when r.study_level in ('doctorate', 'masters_research') then 'research' else 'undergraduate' end
                               || ' courses in ' || v_name || '''s English language policy ' || v_appr
                               || case when v_flag then '. Flagged: this is the university standard; the policy says some courses need more and does not list them, so check the course page' else '' end end))
          from jsonb_array_elements(r.requirements) q where q->>'test_code' in (select code from ref.english_tests))));
      if v_flag and r.plan <> 'named' then
        update catalogue.course_english_requirements set confidence = 0.6
         where course_id = r.course_id and source_requirement_key like 'policy:' || x.id || ':%';
        v_flagged := v_flagged + 1;
      end if;
      v_ok := v_ok + 1; v_courses := v_courses || r.course_id;
    exception when others then v_err := v_err + 1; v_last := left(sqlerrm, 200);
    end;
  end loop;
  if v_ok > 0 then
    insert into search.enrichment_source_gates(projection_code, domain_code, source_id, gate_status, approval_ref, approved_at, created_at, updated_at)
    select 'courses', 'course_english', v_src, 'approved', 'CF-CHG-20260915-247; Decision 227 (English from the provider''s policy, approved by a Platform Admin)', now(), now(), now()
     where not exists (select 1 from search.enrichment_source_gates g where g.projection_code = 'courses' and g.domain_code = 'course_english' and g.source_id = v_src);
    perform search.refresh_course_enrichment_scoped_v1(v_courses, true);
  end if;
  update pipeline.provider_policy_proposals
     set apply_summary = coalesce(apply_summary, '{}'::jsonb) || jsonb_build_object('written', coalesce((apply_summary->>'written')::int, 0) + v_ok,
           'refused', v_err, 'last_error', v_last, 'last_applied_at', now(),
           'flagged', coalesce((apply_summary->>'flagged')::int, 0) + v_flagged), updated_at = now()
   where id = p_proposal_id;
  return jsonb_build_object('written', v_ok, 'refused', v_err, 'last_error', v_last);
end $function$;

CREATE OR REPLACE FUNCTION security.adapter_overwrite_gated_v1(p_limit integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare m pipeline.job_input_marks%rowtype; v_in timestamptz := security.admit_input_mark_v1(); v jsonb; v_more boolean;
        v_full int := security.pipeline_num_v1('waste.admit_full_check_hours', 6)::int;
begin
  insert into pipeline.job_input_marks(job_key) values ('adapter-overwrite') on conflict do nothing;
  select * into m from pipeline.job_input_marks where job_key = 'adapter-overwrite' for update;
  if not coalesce((m.last_result->>'more')::boolean, true) and m.last_input_at is not null and v_in <= m.last_input_at
     and m.last_full_at > now() - make_interval(hours => v_full) then
    update pipeline.job_input_marks set runs_skipped = runs_skipped + 1, last_run_at = now() where job_key = 'adapter-overwrite';
    return jsonb_build_object('skipped', 'no new input');
  end if;
  perform security.fee_crosscheck_guard_v1();  -- CF-247 15 Oct: a fee far from the registered course total is held back first
  v := security.adapter_overwrite_v1(p_limit);
  v_more := coalesce((v->>'replaced')::int, 0) >= p_limit;
  update pipeline.job_input_marks set last_input_at = v_in, last_full_at = now(), last_run_at = now(), last_result = v || jsonb_build_object('more', v_more),
         runs_done = runs_done + 1 where job_key = 'adapter-overwrite';
  return v;
end $function$;

-- 4 Fee admission (fee only) for the four adapters that passed the cross-check; the fees that fail it are held back first
update pipeline.uni_adapters set admit_fields = admit_fields || array['fee'], admit_changed_at = now(), updated_at = now(),
       admit_reason = coalesce(admit_reason || ' | ', '') || 'Fee admitted 15 Oct 2026 (Platform Admin "Clear the >=90% ones"): cross-check against the CRICOS registered total passed for 96% (Wollongong) or 91% (Tasmania); fees that fail it are held back'
 where provider_id in ('62e61a02-9fcb-4c5e-bb11-1c43bed6eee6', '719403bc-6957-4d21-af69-2b3b102df578') and admit and not ('fee' = any (admit_fields));
update pipeline.uni_adapters set admit = true, admit_fields = array['fee'], admit_changed_at = now(), updated_at = now(),
       admit_reason = 'Fee only admitted 15 Oct 2026 (Platform Admin "Clear the >=90% ones"): cross-check against the CRICOS registered total passed (TAFE NSW 90%, Notre Dame 100%); English and intakes were listed but are not admitted'
 where provider_id in ('430a7fd4-6c32-41d8-b756-0ebbd16b2c0c', 'dce54a01-39c1-4bdf-877d-b67da3afc81e') and not admit;
select security.fee_crosscheck_guard_v1();
insert into pipeline.enrichment_flags(entity, entity_key, provider_id, field, reason_code, reason, source)
select 'provider', u.provider_id::text, u.provider_id, 'fee', 'adapter_fee_fails_check',
       'The adapter''s fee reading failed the cross-check with the CRICOS registered totals (15 Oct 2026); the adapter needs a fix before fees are admitted', 'Platform Admin 15 Oct 2026'
  from pipeline.uni_adapters u join catalogue.providers p on p.id = u.provider_id
 where p.canonical_name ~* '^(Victoria University|Academies Australasia Institute|Torrens University Australia)'
   and exists (select 1 from pipeline.enrich_focus_providers f where f.provider_id = u.provider_id and f.in_focus)
on conflict (entity, entity_key, field, reason_code) do nothing;

-- 5 Central pages: the focus providers' English policies and calendars read with AI (never read, or read before the research default existed)
select security.central_ai_enqueue_v1(f.provider_id) from pipeline.enrich_focus_providers f where f.in_focus;
insert into pipeline.central_ai_queue(fact_source_id, provider_id, kind, content_hash)
select s.id, s.provider_id, s.kind, s.content_hash
  from pipeline.provider_fact_sources s
  join pipeline.enrich_focus_providers f on f.provider_id = s.provider_id and f.in_focus
  join pipeline.evidence_artifacts e on e.id = s.evidence_id and e.storage_path is not null
 where s.kind = 'english_policy' and s.status in ('read', 'parsed', 'no_values')
   and not exists (select 1 from pipeline.central_ai_queue q where q.fact_source_id = s.id and (q.state in ('queued', 'leased') or q.created_at > now() - interval '1 hour'))  -- fixed: this run only
on conflict do nothing;
update pipeline.central_ai_settings set reason = reason || ' | 15 Oct 2026 (Platform Admin): readings for the focus providers are approved automatically when every value is quoted and course pages do not mostly disagree (Pipeline settings › Admission checks); others still go to a person'
 where id = 1 and reason not like '%15 Oct 2026%';
insert into pipeline.automation_catalogue(jobname, area, sort, label, description, control_rank, batch_editable) values
 ('policy-auto-approve', 'Admission', 93, 'Approve checked AI readings of central pages',
  'Every 10 minutes: approves an AI reading of a focus provider''s English policy or calendar when every value is quoted on the page and course pages do not mostly disagree; otherwise flags it for a person.', 6, false)
on conflict do nothing;
select cron.schedule('policy-auto-approve', '5-59/10 * * * *', 'select security.policy_auto_approve_v1()');

-- 6 First run: the readings waiting since 12 Oct
select security.policy_auto_approve_v1();

do $post$
declare v_expected jsonb := '{"security.provider_english_plan_v1(uuid)": "6f331c061b2655d3a66b0e7b60678312", "security.provider_english_apply_v1(uuid)": "760c173d759c77e0cfa9fa8c04355e14", "security.adapter_overwrite_gated_v1(integer)": "ef72b3865d2a75bb7146321e1d2ef1ac"}'::jsonb;
  v_sig text;
begin
  for v_sig in select jsonb_object_keys(v_expected) loop
    if md5(replace(pg_get_functiondef(v_sig::regprocedure), E'\r', '')) <> v_expected->>v_sig then
      raise exception 'central policies and fee checks post-check: % not as intended', v_sig;
    end if;
  end loop;
end $post$;

do $post2$
declare v_n int;
begin
  select count(*) into v_n from pipeline.platform_toolset_settings where toolset_key = 'pipeline' and section = 'Admission checks';
  if v_n <> 4 then raise exception 'central policies post-check: % settings, expected 4', v_n; end if;
  select count(*) into v_n from pipeline.uni_adapters where provider_id in ('62e61a02-9fcb-4c5e-bb11-1c43bed6eee6', '719403bc-6957-4d21-af69-2b3b102df578', '430a7fd4-6c32-41d8-b756-0ebbd16b2c0c', 'dce54a01-39c1-4bdf-877d-b67da3afc81e') and admit and 'fee' = any (admit_fields);
  if v_n <> 4 then raise exception 'central policies post-check: % of 4 adapters admit fee', v_n; end if;
  if not exists (select 1 from cron.job where jobname = 'policy-auto-approve' and active) then raise exception 'central policies post-check: job missing'; end if;
  if exists (select 1 from security.controls_check_v1()) then raise exception 'central policies post-check: a running job has a number written into it'; end if;
end $post2$;

do $dry$
begin
  raise exception 'DRYRUN %', jsonb_build_object('dd_test', jsonb_build_array(security.double_degree_same_group_v1('Bachelor of Arts / Bachelor of Laws','undergraduate'), security.double_degree_same_group_v1('Bachelor of Science/Master of Science','undergraduate'), security.double_degree_same_group_v1('Master of Business Administration and Master of Engineering','postgraduate'), security.double_degree_same_group_v1('Bachelor of Laws (Honours)/Juris Doctor','undergraduate')),
    'plan_write_top50', (select jsonb_object_agg(o, n) from (select pl.outcome||':'||coalesce(pl.reason,'') o, count(distinct pl.course_id) n
        from pipeline.provider_policy_proposals pp join pipeline.enrich_focus_providers f on f.provider_id=pp.provider_id and f.in_focus
        cross join lateral security.provider_english_plan_v1(pp.id) pl where pp.kind='english_policy' and pp.status='approved' group by 1) x),
    'fee_held', (select jsonb_object_agg(p.canonical_name, n) from (select provider_id, count(*) n from pipeline.enrichment_flags where reason_code='fee_crosscheck' group by 1) x join catalogue.providers p on p.id=x.provider_id));
end $dry$;
