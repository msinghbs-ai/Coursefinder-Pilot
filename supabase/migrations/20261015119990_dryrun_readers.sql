-- DRY RUN ONLY (rolled back by the raise at the end)
select set_config('request.jwt.claim.sub', (select id::text from auth.users where email = 'msingh.bs+supabase@gmail.com'), true),
       set_config('request.jwt.claims', json_build_object('sub', (select id::text from auth.users where email = 'msingh.bs+supabase@gmail.com'), 'role', 'authenticated')::text, true);
create temp table _cs on commit drop as
  select distinct h.course_id from pipeline.layer3_fact_handoffs h left join pipeline.layer3_work_items w on w.id = h.work_item_id
   where h.task_class = 'provider_english_validation' and (h.work_item_id is null or w.status in ('interpreting', 'validated', 'queued', 'pending'));
create temp table _props on commit drop as
  select p.id from pipeline.provider_policy_proposals p
   where p.kind = 'english_policy' and p.status in ('approved', 'proposed')
     and p.provider_id in (select c.provider_id from catalogue.courses c where c.id in (select course_id from _cs));
create temp table _b on commit drop as select x.id pid, e.* from _props x cross join lateral security.provider_english_plan_v1(x.id) e;
create temp table _s_b on commit drop as select security.admin_layer_status_summary_compute()->'layer2' j;
create temp table _p_b on commit drop as select security.admin_layer2_parent_runs(20) j;
create temp table _l_b on commit drop as select security.layer2_lineage_for_job(i.job_id) j, i.job_id from pipeline.layer2_run_items i where i.job_id is not null order by i.completed_at desc nulls last limit 20;
create temp table _r_b on commit drop as select
  (select coalesce(sum(estimated_cost_usd),0) from pipeline.layer3_interpretations where call_completed_at >= '2026-10-01') m_oct,
  (select coalesce(sum(estimated_cost_usd),0) from pipeline.layer3_interpretations where call_completed_at >= '2026-09-01' and call_completed_at < '2026-10-01') m_sep,
  (select count(*) from pipeline.layer3_interpretations where call_completed_at >= '2026-10-05 03:00+00' and call_completed_at < '2026-10-05 04:00+00') h_calls,
  (select sum(coalesce(input_tokens,0)+coalesce(output_tokens,0)) from pipeline.layer3_interpretations where call_completed_at >= '2026-10-05 03:00+00' and call_completed_at < '2026-10-05 04:00+00') h_tok;
-- CF-247 (15 Oct 2026): usage audit decisions D6, D7, D9 and D10. Platform Admin 22:12: "Proceed with D6, D7, D9 and D10."
-- The audit (admin repo docs/platform/usage-audit/USAGE-AUDIT.md) found live jobs still reading the retired Layer 3 tables about 13 million
-- times a day. This change moves those jobs off them so the rows nothing live uses can be exported and purged, and takes the empty
-- pipeline.layer2_scope_wave_items out of every function so it can be dropped. Purges and drops are in the paste files, not here.
-- Kept in the Layer 3 tables (still used): tuition work items (the fee rules still admit them; the course field states screen shows a
-- fee's Layer 3 source), open work items (course coverage counts them), interpretations linked to a Layer 4 review, a kept work item or a
-- scholarship AI run.
-- Replaces: the English plan's "waiting for Layer 3" check (Layer 3 is retired, so those 54 courses were waiting for nothing); adapter
--   overwrite's and the admit input mark's reads of validated interpretations (now pipeline.layer3_validated_readings, the same rows);
--   the hourly and month-to-date AI spend read from interpretations (now pipeline.layer3_call_costs_hourly, the same totals);
--   every read of pipeline.layer2_scope_wave_items (empty since 1 Oct; now an empty set)
--   and the fixed values in the functions re-created here (retention worker, retention estimate, screenshot removal, platform resources):
--   now settings in Housekeeping at today's values (G2)
-- Retires: pipeline.layer2_scope_wave_items and 14 tables nothing uses (marked retiring, dropped by paste file)
-- 1 Settings  2 Frozen copies  3 Readers changed  4 Register  Nothing dropped or deleted.

do $guard$
declare v_expected jsonb := '{"security.provider_english_plan_v1(uuid)": "6f331c061b2655d3a66b0e7b60678312", "security.adapter_overwrite_v1(integer)": "eeeae4a72954f7e1669b45eacc4842c5", "security.admit_input_mark_v1()": "8a282bf1d4a07ea8aecf2a24a3a1c6a4", "security.platform_resource_observe_v1()": "cff466274457327fc009261a689bcfe3", "security.retention_tick_v1()": "6fbd858175d763108c03b1bfee119736", "security.retention_estimate_v1(text)": "eab919bb7db5578238f2408bf8846706", "security.admin_layer2_parent_runs(integer)": "dca92f43f61a019b0a733ecf54a1db67", "security.admin_layer_status_summary_compute()": "c6d0ef3131c1df620ee489d14e206fb9", "security.layer2_lineage_for_job(uuid)": "7ab780f673ba689a8d68f6a4ec3e5710", "public.svc_retention_files_next(uuid,integer)": "ed2d774a39a454c300c235f960c505c8"}'::jsonb;
  v_sig text;
begin
  for v_sig in select jsonb_object_keys(v_expected) loop
    if md5(replace(pg_get_functiondef(v_sig::regprocedure), E'\r', '')) <> v_expected->>v_sig then
      raise exception 'live % differs from the definition this change replaces', v_sig;
    end if;
  end loop;
end $guard$;

-- 1 Settings (G2: the retention worker and the platform resources job are re-created here, so their fixed values become settings, at today's values)
insert into pipeline.platform_toolset_settings(toolset_key, key, label, help, kind, value, min_value, max_value, unit, sort, reason, section, used_by) values
 ('pipeline', 'retention.job_log_keep_days', 'Keep the job run log for', 'Storage & retention removes scheduled-job run records older than this when the job log clean-up is run.', 'number', to_jsonb(7), 1, 90, 'days', 742, 'CF-247 15 Oct 2026: was fixed in the retention worker (G2)', 'Housekeeping', 'security.retention_tick_v1; security.retention_estimate_v1'),
 ('pipeline', 'retention.screenshot_keep_days', 'Keep adapter screenshots for', 'Storage & retention removes adapter builder screenshots older than this when the screenshot clean-up is run.', 'number', to_jsonb(7), 1, 90, 'days', 743, 'CF-247 15 Oct 2026: was fixed in the retention worker (G2)', 'Housekeeping', 'public.svc_retention_files_next; security.retention_estimate_v1'),
 ('pipeline', 'retention.resource_observations_days', 'Keep hourly platform resource readings for', 'Platform resources keeps one reading an hour (database size, jobs, AI spend) for this long.', 'number', to_jsonb(180), 30, 730, 'days', 744, 'CF-247 15 Oct 2026: was fixed in platform-resource-observe (G2)', 'Housekeeping', 'security.platform_resource_observe_v1'),
 ('pipeline', 'retention.estimate_refresh_hours', 'Refresh Storage & retention estimates every', 'The retention worker measures one category''s removable rows and bytes at a time, each no more often than this.', 'number', to_jsonb(1), 1, 24, 'hours', 745, 'CF-247 15 Oct 2026: was fixed in the retention worker (G2)', 'Housekeeping', 'security.retention_tick_v1'),
 ('pipeline', 'batch.retention_rows', 'Rows removed per retention run (job log, shared directory links)', 'Each retention worker run (every 2 minutes) removes up to this many rows, so a clean-up never holds the database for long.', 'number', to_jsonb(20000), 1000, 100000, 'rows', 746, 'CF-247 15 Oct 2026: was fixed in the retention worker (G2)', 'Housekeeping', 'security.retention_tick_v1'),
 ('pipeline', 'batch.retention_layer2_rows', 'Rows removed per retention run (retired Layer 2 tables)', 'Each retention worker run removes up to this many rows from the retired Layer 2 tables.', 'number', to_jsonb(5000), 500, 50000, 'rows', 747, 'CF-247 15 Oct 2026: was fixed in the retention worker (G2)', 'Housekeeping', 'security.retention_tick_v1'),
 ('pipeline', 'batch.retention_evidence', 'Evidence records checked per retention run', 'Each retention worker run checks up to this many unreferenced evidence records for removal.', 'number', to_jsonb(500), 50, 5000, 'records', 748, 'CF-247 15 Oct 2026: was fixed in the retention worker (G2)', 'Housekeeping', 'security.retention_tick_v1')
on conflict do nothing;
-- 2 Frozen copies of what live jobs still need from layer3_interpretations (Layer 3 has written nothing since 11 Oct 2026)
create table if not exists pipeline.layer3_validated_readings as
  select i.id, i.entity_type, i.entity_id, i.task_class, i.status, i.candidate_value, i.created_at
    from pipeline.layer3_interpretations i
   where i.status = 'validated' and i.task_class in ('provider_intake_validation', 'provider_english_validation', 'provider_current_tuition_validation');
alter table pipeline.layer3_validated_readings add primary key (id);
create index if not exists layer3_validated_readings_entity on pipeline.layer3_validated_readings (entity_type, entity_id, status, task_class);
comment on table pipeline.layer3_validated_readings is 'CF-247 15 Oct 2026 (usage audit D7): every validated Layer 3 reading of intakes, English and tuition, copied from layer3_interpretations (same id, value and time) before that table was purged. Adapter overwrite uses it as corroboration (rule 5); the admit input mark uses its latest time. Never written; Layer 3 is retired.';
alter table pipeline.layer3_validated_readings enable row level security;
revoke all on pipeline.layer3_validated_readings from anon, authenticated;

create table if not exists pipeline.layer3_call_costs_hourly as
  select date_trunc('hour', i.call_completed_at) as hour, count(*)::int calls,
         sum(coalesce(i.input_tokens, 0) + coalesce(i.output_tokens, 0))::bigint tokens, sum(coalesce(i.estimated_cost_usd, 0)) cost_usd
    from pipeline.layer3_interpretations i
   where i.call_completed_at is not null
   group by 1;
alter table pipeline.layer3_call_costs_hourly add primary key (hour);
comment on table pipeline.layer3_call_costs_hourly is 'CF-247 15 Oct 2026 (usage audit D7): Layer 3 AI calls, tokens and estimated cost per hour, summed from layer3_interpretations before it was purged. Platform resources reads it for the hourly and month-to-date AI spend. Never written; Layer 3 is retired.';
alter table pipeline.layer3_call_costs_hourly enable row level security;
revoke all on pipeline.layer3_call_costs_hourly from anon, authenticated;

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
           false in_l3,  -- CF-247 15 Oct 2026 (usage audit D6): Layer 3 is retired, so no course waits for it
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

CREATE OR REPLACE FUNCTION security.adapter_overwrite_v1(p_limit integer DEFAULT 200)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare r record; v_src uuid; v_ok int := 0; v_err int := 0; v_last text; v_courses uuid[] := '{}'; v_payload jsonb; v_itk text[]; v_ielts numeric; v_band numeric; v_fee numeric; v_fy int; v_cur text; v_mode_n int := 0;
begin
  for r in
    select pg.course_id, pg.provider_id, pg.url, pg.evidence_id, e.content_hash, pg.candidates c, pg.identity_basis ib, u.admit_fields af, u.reading rd, co.delivery_mode cur_mode, coalesce(security.delivery_mode_from_text(pg.candidates->'adapter_extra'->>'mode'), security.delivery_mode_from_location(coalesce(pg.candidates->'adapter_extra'->>'location', pg.candidates->'adapter_extra'->>'campus'))) new_mode,
           (select pr.registration_code from catalogue.provider_registrations pr where pr.provider_id = pg.provider_id and lower(pr.registration_scheme) = 'cricos' and coalesce(pr.status, 'active') not in ('inactive', 'cancelled', 'archived') order by pr.checked_at desc nulls last limit 1) pc,
           (select cr.registration_code from catalogue.course_registrations cr where cr.course_id = pg.course_id and lower(cr.scheme) = 'cricos' limit 1) cc,
           (select array_agg(distinct i.intake_label order by i.intake_label) from catalogue.course_intakes i where i.course_id = pg.course_id and i.status = 'active') cur_itk,
           (select r2.overall_score from catalogue.course_english_requirements r2 join ref.english_tests t on t.id = r2.english_test_id where r2.course_id = pg.course_id and t.code = 'IELTS' and coalesce(r2.status, 'active') = 'active' limit 1) cur_ielts,
           (select f.amount from catalogue.course_fees f where f.course_id = pg.course_id and f.status = 'active' and f.fee_type = 'provider_current_tuition' and f.audience = 'international' order by f.fee_year desc nulls last limit 1) cur_fee,
           u.admit adm,
           (select (select array_agg(distinct z::int order by z::int) from jsonb_array_elements_text(l.cv->'months') z)
                   = (select array_agg(distinct extract(month from to_date(i.intake_label, 'Month'))::int order by extract(month from to_date(i.intake_label, 'Month'))::int)
                        from catalogue.course_intakes i where i.course_id = pg.course_id and i.status = 'active' and i.intake_label ~ '^(January|February|March|April|May|June|July|August|September|October|November|December)$')
              from (select x.candidate_value cv from pipeline.layer3_validated_readings x where x.entity_type = 'course' and x.entity_id = pg.course_id and x.status = 'validated'
                       and x.task_class = 'provider_intake_validation' and jsonb_typeof(x.candidate_value->'months') = 'array' order by x.created_at desc limit 1) l) r5_itk,
           (select (select (t->>'overall')::numeric from jsonb_array_elements(l.cv->'tests') t where t->>'test' = 'IELTS' limit 1)
                   = (select r3.overall_score from catalogue.course_english_requirements r3 join ref.english_tests t3 on t3.id = r3.english_test_id where r3.course_id = pg.course_id and t3.code = 'IELTS' and coalesce(r3.status, 'active') = 'active' limit 1)
              from (select x.candidate_value cv from pipeline.layer3_validated_readings x where x.entity_type = 'course' and x.entity_id = pg.course_id and x.status = 'validated'
                       and x.task_class = 'provider_english_validation' and jsonb_typeof(x.candidate_value->'tests') = 'array' order by x.created_at desc limit 1) l) r5_eng,
           (select abs((l.cv->>'amount')::numeric - (select f.amount from catalogue.course_fees f where f.course_id = pg.course_id and f.status = 'active' and f.fee_type = 'provider_current_tuition' and f.audience = 'international' order by f.fee_year desc nulls last limit 1))
                   <= 0.01 * (l.cv->>'amount')::numeric
              from (select x.candidate_value cv from pipeline.layer3_validated_readings x where x.entity_type = 'course' and x.entity_id = pg.course_id and x.status = 'validated'
                       and x.task_class = 'provider_current_tuition_validation' and (x.candidate_value->>'amount') ~ '^[0-9]+(\.[0-9]+)?$' order by x.created_at desc limit 1) l) r5_fee
      from pipeline.coverage_course_pages pg
      join pipeline.evidence_artifacts e on e.id = pg.evidence_id
      join catalogue.courses co on co.id = pg.course_id and co.lifecycle_status = 'active'
      join pipeline.uni_adapters u on u.provider_id = pg.provider_id and u.enabled
       and (u.admit or exists (select 1 from pipeline.layer3_validated_readings l3 where l3.entity_type = 'course' and l3.entity_id = pg.course_id and l3.status = 'validated'
                                and l3.task_class in ('provider_intake_validation', 'provider_english_validation', 'provider_current_tuition_validation')))
     where pg.read_status = 'read' and pg.identity_basis is not null
       and (pg.candidates->>'intakes_by' = 'adapter' or pg.candidates->>'english_by' = 'adapter' or pg.candidates->>'fee_by' = 'adapter' or pg.candidates->'adapter_extra' ? 'mode' or pg.candidates->'adapter_extra' ? 'campus' or pg.candidates->'adapter_extra' ? 'location')
       and security.coverage_identity_allowed(pg.provider_id, pg.identity_basis, null)
       and not exists (select 1 from security.provider_hidden_v1 h where h.provider_id = pg.provider_id)  -- v2.15.237: paused while the provider is unpublished or archived
       and not security.layer4_entity_or_parent_blocked('course', pg.course_id, 'operational')
  loop
    exit when v_ok >= greatest(1, least(coalesce(p_limit, 200), 1000));
    v_payload := '{}'::jsonb;
    v_itk := (select array_agg(distinct m order by m) from jsonb_array_elements_text(coalesce(r.c->'intakes', '[]'::jsonb)) m);
    if r.c->>'intakes_by' = 'adapter' and v_itk is not null and r.cur_itk is distinct from v_itk
       and security.coverage_identity_allowed(r.provider_id, r.ib, 'intakes') and (('intakes' = any (r.af) and r.adm) or coalesce(r.r5_itk, false)) and not security.uni_adapter_excluded(r.course_id, 'intakes')
       and not exists (select 1 from pipeline.manual_locks k where k.entity = 'course' and k.entity_id = r.course_id and k.field in ('intakes', 'intake')) then
      v_payload := v_payload || jsonb_build_object('intakes', (select jsonb_agg(jsonb_build_object('intake_label', m, 'source_intake_key', lower(coalesce(r.cc, r.course_id::text)) || ':current:' || lower(m))) from unnest(v_itk) m));
    end if;
    v_ielts := nullif(r.c->'english'->>'ielts_overall', '')::numeric;
    v_band := nullif(r.c->'english'->>'ielts_min_band', '')::numeric;
    if r.c->>'english_by' = 'adapter' and v_ielts is not null and r.cur_ielts is distinct from v_ielts
       and security.coverage_identity_allowed(r.provider_id, r.ib, 'english') and (('english' = any (r.af) and r.adm) or coalesce(r.r5_eng, false)) and not security.uni_adapter_excluded(r.course_id, 'english')
       and not exists (select 1 from pipeline.manual_locks k where k.entity = 'course' and k.entity_id = r.course_id and k.field in ('english', 'english_requirements')) then
      v_payload := v_payload || jsonb_build_object('english_requirements', jsonb_build_array(jsonb_build_object('test_code', 'IELTS', 'overall_score', v_ielts,
                      'component_scores', case when v_band is null then '{}'::jsonb else jsonb_build_object('listening', v_band, 'reading', v_band, 'writing', v_band, 'speaking', v_band) end,
                      'notes', 'University adapter reading of the course page')));
    end if;
    -- v0.17 (Platform Admin 23:41, decision 4): the international annual fee the adapter read is admitted too
    v_fee := nullif(r.c->'fee'->>'value', '')::numeric;
    v_fy := coalesce(nullif(r.c->'fee'->>'fee_year', '')::int, security.adapter_fee_year_setting(r.rd), extract(year from now() at time zone 'Australia/Melbourne')::int);
    v_cur := coalesce(nullif(r.c->'fee'->>'currency', ''), case security.coverage_country(r.provider_id) when 'NZ' then 'NZD' when 'CA' then 'CAD' else 'AUD' end);
    if r.c->>'fee_by' = 'adapter' and v_fee is not null and v_fee between 1000 and 500000 and (select f.amount from catalogue.course_fees f where f.course_id = r.course_id and f.status = 'active' and f.fee_type = 'provider_current_tuition' and f.audience = 'international' and coalesce(f.fee_year, 0) = coalesce(v_fy, 0) order by f.updated_at desc nulls last limit 1) is distinct from v_fee
       and (('fee' = any (r.af) and r.adm) or coalesce(r.r5_fee, false)) and not security.uni_adapter_excluded(r.course_id, 'fee') and not exists (select 1 from pipeline.manual_locks k where k.entity = 'course' and k.entity_id = r.course_id and k.field in ('tuition', 'fee', 'fees')) then
      v_payload := v_payload || jsonb_build_object('fee_amount', v_fee, 'fee_year', v_fy, 'currency_code', v_cur, 'fee_basis', 'annual', 'audience', 'international',
                     'fee_notes', 'University adapter reading of the course page (international annual fee)',
                     'fee_key', lower(coalesce(r.cc, r.course_id::text)) || ':international:' || coalesce(v_fy::text, 'current') || ':annual');
    end if;
    -- 5 Oct (Platform Admin 11:48): delivery read from the international view of the course page
    if r.new_mode is not null and r.cur_mode is distinct from r.new_mode and ('delivery' = any (r.af) and r.adm) and not security.uni_adapter_excluded(r.course_id, 'delivery')
       and not exists (select 1 from pipeline.manual_locks k where k.entity = 'course' and k.entity_id = r.course_id and k.field in ('delivery_mode', 'delivery')) then
      begin
        update catalogue.courses set delivery_mode = r.new_mode, updated_at = now() where id = r.course_id;
        insert into pipeline.adapter_overwrite_changes(course_id, provider_id, field, before, after, evidence_id, page_url) values (r.course_id, r.provider_id, 'delivery', to_jsonb(r.cur_mode), to_jsonb(r.new_mode), r.evidence_id, r.url);
        v_mode_n := v_mode_n + 1; v_courses := v_courses || r.course_id;
      exception when others then v_err := v_err + 1; v_last := left(sqlerrm, 200);
      end;
    end if;
    continue when v_payload = '{}'::jsonb;
    begin
      v_src := security.coverage_sweep_source(r.provider_id);
      insert into search.enrichment_source_gates(projection_code, domain_code, source_id, gate_status, approval_ref, approved_at, created_at, updated_at)
        select 'courses', d, v_src, 'approved', 'CF-CHG-20260915-247, Decision 253, Platform Admin 4 Oct 2026 22:43 (adapter readings replace held values)', now(), now(), now()
        from unnest(array_remove(array[case when v_payload ? 'intakes' then 'course_intake' end, case when v_payload ? 'english_requirements' then 'course_english' end, case when v_payload ? 'fee_amount' then 'provider_current_tuition' end], null)) d
        where not exists (select 1 from search.enrichment_source_gates g where g.projection_code = 'courses' and g.domain_code = d and g.source_id = v_src);
      if v_payload ? 'intakes' then
        update catalogue.course_intakes set status = 'withdrawn' where course_id = r.course_id and status = 'active' and source_id is not null and intake_label <> all (v_itk);
        insert into pipeline.adapter_overwrite_changes(course_id, provider_id, field, before, after, evidence_id, page_url) values (r.course_id, r.provider_id, 'intakes', to_jsonb(r.cur_itk), to_jsonb(v_itk), r.evidence_id, r.url);
      end if;
      if v_payload ? 'english_requirements' then
        insert into pipeline.adapter_overwrite_changes(course_id, provider_id, field, before, after, evidence_id, page_url) values (r.course_id, r.provider_id, 'english_ielts', to_jsonb(r.cur_ielts), to_jsonb(v_ielts), r.evidence_id, r.url);
      end if;
      if v_payload ? 'fee_amount' then
        update catalogue.course_fees set status = 'superseded', updated_at = now() where course_id = r.course_id and status = 'active' and fee_type = 'provider_current_tuition' and audience = 'international' and source_id is not null and coalesce(fee_year, 0) = coalesce(v_fy, 0) and amount <> v_fee;
        insert into pipeline.adapter_overwrite_changes(course_id, provider_id, field, before, after, evidence_id, page_url) values (r.course_id, r.provider_id, 'fee', to_jsonb(r.cur_fee), jsonb_build_object('amount', v_fee, 'year', v_fy, 'currency', v_cur), r.evidence_id, r.url);
      end if;
      if r.pc is null or r.cc is null then
        perform security.coverage_apply_course_v1(r.course_id, v_src, r.evidence_id, r.url, r.content_hash, v_payload);
      else
        perform public.svc_coursefacts_apply_record(v_src, r.evidence_id, r.pc, r.cc, 'coverage:' || r.course_id, r.url, r.content_hash, v_payload, true);
      end if;
      update pipeline.layer4_review_items set status = 'superseded', decided_at = now() where entity_type = 'course' and entity_id = r.course_id and status = 'pending' and field_code in (case when v_payload ? 'intakes' then 'course_intake' end, case when v_payload ? 'english_requirements' then 'course_english' end, case when v_payload ? 'fee_amount' then 'course_tuition' end);
      v_ok := v_ok + 1; v_courses := v_courses || r.course_id;
    exception when others then v_err := v_err + 1; v_last := left(sqlerrm, 200);
    end;
  end loop;
  if cardinality(v_courses) > 0 then perform search.refresh_course_enrichment_scoped_v1(v_courses, true); end if;
  return jsonb_build_object('delivery', v_mode_n, 'replaced', v_ok, 'errors', v_err, 'last_error', v_last);
end $function$;

CREATE OR REPLACE FUNCTION security.admit_input_mark_v1()
 RETURNS timestamp with time zone
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  -- the newest change any admit job depends on: pages read, adapters and their admission, checked values, exclusions, locks, review decisions,
  -- courses and providers (lifecycle, Published switch)
  select greatest(
    (select max(pg.read_at) from pipeline.coverage_course_pages pg),
    (select max(greatest(u.updated_at, u.admit_changed_at)) from pipeline.uni_adapters u),
    (select max(i.created_at) from pipeline.layer3_validated_readings i where i.status = 'validated'),  -- CF-247 15 Oct 2026: frozen copy
    (select max(x.set_at) from pipeline.uni_adapter_exclusions x),
    (select max(x.set_at) from pipeline.uni_adapter_delivery_exclusions x),
    (select max(k.set_at) from pipeline.manual_locks k),
    (select max(r.decided_at) from pipeline.layer4_review_items r),
    (select max(c.updated_at) from catalogue.courses c),
    (select max(p.updated_at) from catalogue.providers p),
    '-infinity'::timestamptz)
$function$;

CREATE OR REPLACE FUNCTION security.platform_resource_observe_v1()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'pipeline', 'cron', 'net'
AS $function$
declare h timestamptz := date_trunc('hour', now()); h0 timestamptz := date_trunc('hour', now()) - interval '1 hour';  -- fixed: one reading per hour (the reading's own period)
  m timestamptz := date_trunc('month', now()); cp pipeline.platform_compute_profile%rowtype; r pipeline.platform_resource_observations%rowtype;
begin
  select * into cp from pipeline.platform_compute_profile where id=1;
  r.observed_at := h; r.memory_bytes := cp.memory_bytes; r.compute_size := cp.compute_size;
  r.db_bytes := pg_database_size(current_database());
  select round(100.0*sum(blks_hit)/nullif(sum(blks_hit)+sum(blks_read),0),2) into r.cache_hit_pct from pg_stat_database where datname=current_database();
  select count(*), count(*) filter (where state='active') into r.connections, r.active_connections from pg_stat_activity where backend_type='client backend';
  select count(*), count(*) filter (where status not in ('succeeded','running')), round(max(extract(epoch from coalesce(end_time, case when status in ('running','starting','sending','connecting') then now() end)-start_time))::numeric,1)
    into r.cron_runs, r.cron_failures, r.cron_max_seconds from cron.job_run_details where start_time >= h0 and start_time < h;
  select coalesce(max(c) filter (where t >= h0 and t < h and d = 1),0) into r.cron_max_concurrent from (
    select e.t, e.d, sum(e.d) over (order by e.t, e.d desc) c from (
      select b.start_time t, 1 d from cron.job_run_details b where b.start_time >= h0 - interval '1 hour' and b.start_time < h  -- fixed: runs overlapping the hour read
      union all
      select coalesce(b.end_time, case when b.status in ('running','starting','sending','connecting') then now() else b.start_time end), -1
        from cron.job_run_details b where b.start_time >= h0 - interval '1 hour' and b.start_time < h) e) z;  -- fixed: runs overlapping the hour read
  select count(*) into r.http_requests from net._http_response where created >= h0 and created < h;
  select coalesce(jsonb_agg(jsonb_build_object('provider',coalesce(ap.provider_key,'unknown'),'units',u,'cost_usd',cst)),'[]'::jsonb) into r.acquisition
    from (select ri.selected_provider_id, sum(coalesce(ri.vendor_units,0)) u, sum(coalesce(ri.vendor_cost_usd,0)) cst
          from pipeline.layer2_run_items ri where ri.completed_at >= h0 and ri.completed_at < h group by 1) x
    left join pipeline.layer2_acquisition_providers ap on ap.id=x.selected_provider_id;
  select sum(coalesce(vendor_units,0)), sum(coalesce(vendor_cost_usd,0)) into r.acquisition_units_mtd, r.acquisition_cost_mtd_usd
    from pipeline.layer2_run_items where completed_at >= m;
  -- CF-247 15 Oct 2026 (usage audit D7): Layer 3 calls from their hourly totals (same sums; layer3_interpretations is purged)
  select coalesce(sum(n),0), sum(tok), sum(cst) into r.ai_calls, r.ai_tokens, r.ai_cost_usd
    from (select k.calls n, k.tokens tok, k.cost_usd cst from pipeline.layer3_call_costs_hourly k where k.hour >= h0 and k.hour < h
          union all select 1, coalesce(input_tokens,0)+coalesce(output_tokens,0), coalesce(estimated_cost_usd,0) from pipeline.layer3_quality_benchmark_runs where completed_at >= h0 and completed_at < h) z;
  select coalesce(sum(estimated_cost_usd),0) into r.ai_cost_mtd_usd
    from (select k.cost_usd estimated_cost_usd from pipeline.layer3_call_costs_hourly k where k.hour >= m
          union all select estimated_cost_usd from pipeline.layer3_quality_benchmark_runs where completed_at >= m) z;
  select coalesce(jsonb_agg(jsonb_build_object('table',t,'bytes',b) order by b desc),'[]'::jsonb) into r.largest_tables
    from (select n.nspname||'.'||c.relname t, pg_total_relation_size(c.oid) b from pg_class c join pg_namespace n on n.oid=c.relnamespace
          where c.relkind='r' and n.nspname not in ('pg_catalog','information_schema') order by 2 desc limit 5) z;
  insert into pipeline.platform_resource_observations select r.* on conflict (observed_at) do update set
    db_bytes=excluded.db_bytes, cache_hit_pct=excluded.cache_hit_pct, connections=excluded.connections, active_connections=excluded.active_connections,
    cron_runs=excluded.cron_runs, cron_failures=excluded.cron_failures, cron_max_seconds=excluded.cron_max_seconds, cron_max_concurrent=excluded.cron_max_concurrent,
    http_requests=excluded.http_requests, acquisition=excluded.acquisition, acquisition_units_mtd=excluded.acquisition_units_mtd, acquisition_cost_mtd_usd=excluded.acquisition_cost_mtd_usd,
    ai_calls=excluded.ai_calls, ai_tokens=excluded.ai_tokens, ai_cost_usd=excluded.ai_cost_usd, ai_cost_mtd_usd=excluded.ai_cost_mtd_usd, largest_tables=excluded.largest_tables;
  delete from pipeline.platform_resource_observations where observed_at < now() - make_interval(days => security.pipeline_num_v1('retention.resource_observations_days', 180)::int);
  return to_jsonb(r);
end $function$;

CREATE OR REPLACE FUNCTION security.retention_tick_v1()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare r pipeline.retention_runs%rowtype; v_n bigint := 0; v_cat text; v_hosts text[]; v_t text; v_col record; v_done int := 0;
        v_ev record; v_del int := 0; v_skip int := 0; v_q int := 0;
begin
  -- keep the estimates fresh (one category per run, oldest first)
  select c->>'key' into v_cat from jsonb_array_elements(security.retention_catalogue_v1()) c
   left join pipeline.retention_estimates e on e.category = c->>'key'
   where c->>'key' <> 'evidence_audit' and (e.measured_at is null or e.measured_at < now() - make_interval(hours => security.pipeline_num_v1('retention.estimate_refresh_hours', 1)::int))
   order by e.measured_at nulls first limit 1;
  if v_cat is not null then perform security.retention_estimate_v1(v_cat); end if;

  select * into r from pipeline.retention_runs where status in ('queued', 'running') order by created_at limit 1 for update skip locked;
  if r.id is null then return jsonb_build_object('idle', true); end if;
  begin
    if r.status = 'queued' then
      perform security.retention_estimate_v1(r.category);
      update pipeline.retention_runs set status = 'running', started_at = now(), estimate = (select to_jsonb(e) from pipeline.retention_estimates e where e.category = r.category),
             note = 'Running in small batches.', updated_at = now() where id = r.id;
      if r.category = 'evidence_audit' then
        delete from pipeline.evidence_audit_refs;
        delete from pipeline.evidence_audit_columns;
        insert into pipeline.evidence_audit_columns(tbl, col)
        select distinct format('%I.%I', n.nspname, c.relname), a.attname
          from pg_attribute a join pg_class c on c.oid = a.attrelid join pg_namespace n on n.oid = c.relnamespace
         where c.relkind = 'r' and a.attnum > 0 and not a.attisdropped and a.atttypid = 'uuid'::regtype
           and n.nspname in ('catalogue', 'pipeline', 'scholarship', 'ranking', 'workflow', 'pim', 'search')
           and (a.attname in ('evidence_id', 'evidence_artifact_id', 'source_artifact_id', 'supersedes_evidence_id') or a.attname like '%\_evidence\_id' escape '\')
           and c.relname not in ('evidence_audit_refs');
      end if;
      return jsonb_build_object('started', r.id);
    end if;

    if r.category = 'job_log' then
      delete from cron.job_run_details where runid in (select d.runid from cron.job_run_details d where d.start_time < coalesce(r.started_at, now()) - make_interval(days => security.pipeline_num_v1('retention.job_log_keep_days', 7)::int) limit security.pipeline_num_v1('batch.retention_rows', 20000)::int);
      get diagnostics v_n = row_count;
    elsif r.category = 'retired_layer2' then
      foreach v_t in array array['pipeline.layer2_provider_trial_results', 'pipeline.layer2_course_discovery_candidates', 'pipeline.layer2_provider_attempts',
                                 'pipeline.layer2_scale_qualification_items'] loop  -- CF-247 15 Oct 2026: layer2_scope_wave_items retired
        execute format('delete from %s where ctid = any(array(select ctid from %s limit %s))', v_t, v_t, security.pipeline_num_v1('batch.retention_layer2_rows', 5000)::int);
        get diagnostics v_n = row_count;
        exit when v_n > 0;
      end loop;
    elsif r.category = 'directory_urls' then
      select array(select jsonb_array_elements_text(coalesce(r.estimate->'detail'->'hosts', '[]'::jsonb))) into v_hosts;
      delete from pipeline.coverage_provider_urls where (provider_id, url) in (
        select u.provider_id, u.url from pipeline.coverage_provider_urls u join catalogue.providers p on p.id = u.provider_id
         where substring(u.url from '^https?://(?:www\.)?([^/:?#]+)') = any(v_hosts)
           and (p.website is null or p.website not ilike '%' || substring(u.url from '^https?://(?:www\.)?([^/:?#]+)') || '%')
           and not exists (select 1 from pipeline.coverage_course_pages pg where pg.url = u.url)
         limit security.pipeline_num_v1('batch.retention_rows', 20000)::int);
      get diagnostics v_n = row_count;
    elsif r.category = 'adapter_screenshots' then
      -- files go through Storage: hand the run to the worker; it reports back with svc_retention_files_done
      if r.note is distinct from 'Removing files through Storage.' or r.updated_at < now() - interval '10 minutes' then
        update pipeline.retention_runs set note = 'Removing files through Storage.', updated_at = now() where id = r.id;
        perform pipeline.svc_pilot_submit_nonce('coverage-sweep', jsonb_build_object('mode', 'retention_files', 'run_id', r.id));
      end if;
      return jsonb_build_object('handed_to_worker', r.id);
    elsif r.category = 'evidence_unreferenced' then
      -- files of the last batch still with the worker: hand them again if the worker has not reported for 10 minutes
      if exists (select 1 from pipeline.retention_file_queue q where q.run_id = r.id and q.status in ('queued', 'handed')) then
        if r.updated_at < now() - interval '10 minutes' or exists (select 1 from pipeline.retention_file_queue q where q.run_id = r.id and q.status = 'queued') then
          update pipeline.retention_file_queue set status = 'queued' where run_id = r.id and status = 'handed' and handed_at < now() - interval '10 minutes';
          update pipeline.retention_runs set updated_at = now() where id = r.id;
          perform pipeline.svc_pilot_submit_nonce('coverage-sweep', jsonb_build_object('mode', 'retention_files', 'run_id', r.id));
        end if;
        return jsonb_build_object('handed_to_worker', r.id);
      end if;
      if not exists (select 1 from pipeline.retention_runs a where a.category = 'evidence_audit' and a.status = 'done')
         or exists (select 1 from pipeline.retention_runs a where a.category = 'evidence_audit' and a.status in ('queued', 'running')) then
        raise exception 'Run the evidence audit first and let it finish.';
      end if;
      -- next batch: candidates not yet skipped in this run
      create temporary table ev_batch on commit drop as
        select c.evidence_id id, c.storage_path from security.retention_evidence_candidates_v1() c
         where not exists (select 1 from pipeline.retention_evidence_skips s where s.run_id = r.id and s.evidence_id = c.evidence_id)
         order by c.created_at limit security.pipeline_num_v1('batch.retention_evidence', 500)::int;
      if not exists (select 1 from ev_batch) then
        perform security.retention_estimate_v1('evidence_unreferenced');
        update pipeline.retention_runs set status = 'done', finished_at = now(), updated_at = now(),
               note = format('Done: %s records and %s MB of files removed; %s skipped because they were referenced again.', removed, round(bytes / 1e6),
                             (select count(*) from pipeline.retention_evidence_skips s where s.run_id = r.id))
         where id = r.id;
        return jsonb_build_object('run', r.id, 'done', true);
      end if;
      -- re-check every reference column of the audit just before removal
      for v_col in select * from pipeline.evidence_audit_columns order by tbl, col loop
        execute format('insert into pipeline.retention_evidence_skips(run_id, evidence_id, reason) select %L::uuid, b.id, %L from pg_temp.ev_batch b where exists (select 1 from %s t where t.%I = b.id) on conflict do nothing',
                       r.id, 'referenced: ' || v_col.tbl || '.' || v_col.col, v_col.tbl, v_col.col);
      end loop;
      create temporary table ev_gone (storage_path text) on commit drop;
      for v_ev in select b.id, b.storage_path from ev_batch b
                   where not exists (select 1 from pipeline.retention_evidence_skips s where s.run_id = r.id and s.evidence_id = b.id) loop
        begin
          delete from pipeline.evidence_artifacts where id = v_ev.id;
          insert into ev_gone values (v_ev.storage_path);
          v_del := v_del + 1;
        exception when foreign_key_violation then
          insert into pipeline.retention_evidence_skips(run_id, evidence_id, reason) values (r.id, v_ev.id, 'still referenced (foreign key)') on conflict do nothing;
          v_skip := v_skip + 1;
        end;
      end loop;
      -- a file goes only when no remaining evidence record uses it
      insert into pipeline.retention_file_queue(run_id, bucket, name, size)
      select r.id, 'evidence', o.name, coalesce((o.metadata->>'size')::bigint, 0)
        from (select distinct storage_path from ev_gone where storage_path is not null) g
        join storage.objects o on o.bucket_id = 'evidence' and o.name = g.storage_path
       where not exists (select 1 from pipeline.evidence_artifacts e where e.storage_path = g.storage_path);
      get diagnostics v_q = row_count;
      update pipeline.retention_runs set removed = removed + v_del, updated_at = now(),
             note = format('Running: %s records removed, %s MB of files so far.', removed + v_del, round(bytes / 1e6)) where id = r.id;
      if v_q > 0 then perform pipeline.svc_pilot_submit_nonce('coverage-sweep', jsonb_build_object('mode', 'retention_files', 'run_id', r.id)); end if;
      return jsonb_build_object('run', r.id, 'removed', v_del, 'files_queued', v_q, 'skipped_fk', v_skip);
    elsif r.category = 'evidence_audit' then
      for v_col in select * from pipeline.evidence_audit_columns where done_at is null order by tbl, col limit 3 loop
        execute format('insert into pipeline.evidence_audit_refs(evidence_id) select distinct %I from %s where %I is not null on conflict do nothing', v_col.col, v_col.tbl, v_col.col);
        get diagnostics v_n = row_count;
        update pipeline.evidence_audit_columns set done_at = now(), rows_found = v_n where tbl = v_col.tbl and col = v_col.col;
        v_done := v_done + 1;
      end loop;
      if v_done = 0 then
        perform security.retention_estimate_v1('evidence_audit');
        update pipeline.retention_runs set status = 'done', finished_at = now(), updated_at = now(),
               removed = 0, estimate = (select to_jsonb(e) from pipeline.retention_estimates e where e.category = 'evidence_audit'),
               note = format('Audit complete: %s evidence records are not referenced anywhere (%s MB of files). Nothing was deleted.',
                             (select purgeable_rows from pipeline.retention_estimates where category = 'evidence_audit'),
                             round(coalesce((select purgeable_bytes from pipeline.retention_estimates where category = 'evidence_audit'), 0) / 1e6))
         where id = r.id;
      else
        update pipeline.retention_runs set note = format('Auditing: %s of %s reference columns done.', (select count(*) from pipeline.evidence_audit_columns where done_at is not null),
               (select count(*) from pipeline.evidence_audit_columns)), updated_at = now() where id = r.id;
      end if;
      return jsonb_build_object('audited_columns', v_done);
    end if;

    if v_n = 0 then
      perform security.retention_estimate_v1(r.category);
      update pipeline.retention_runs set status = 'done', finished_at = now(), updated_at = now(), note = format('Done: %s rows removed.', removed) where id = r.id;
    else
      update pipeline.retention_runs set removed = removed + v_n, note = format('Running: %s rows removed so far.', removed + v_n), updated_at = now() where id = r.id;
    end if;
    return jsonb_build_object('run', r.id, 'removed', v_n);
  exception when others then
    update pipeline.retention_runs set status = 'failed', error = left(sqlerrm, 500), finished_at = now(), updated_at = now() where id = r.id;
    return jsonb_build_object('failed', r.id, 'error', sqlerrm);
  end;
end $function$;

CREATE OR REPLACE FUNCTION security.retention_estimate_v1(p_cat text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_size bigint; v_rows bigint; v_bytes bigint; v_detail jsonb := '{}'::jsonb;
begin
  if p_cat = 'adapter_screenshots' then
    select coalesce(sum((o.metadata->>'size')::bigint), 0), count(*) filter (where o.created_at < now() - make_interval(days => security.pipeline_num_v1('retention.screenshot_keep_days', 7)::int)),
           coalesce(sum((o.metadata->>'size')::bigint) filter (where o.created_at < now() - make_interval(days => security.pipeline_num_v1('retention.screenshot_keep_days', 7)::int)), 0)
      into v_size, v_rows, v_bytes from storage.objects o where o.bucket_id = 'adapter-captures';
  elsif p_cat = 'retired_layer2' then
    select sum(pg_total_relation_size(t::regclass)) into v_size
      from unnest(array['pipeline.layer2_provider_trial_results', 'pipeline.layer2_course_discovery_candidates', 'pipeline.layer2_provider_attempts',
                        'pipeline.layer2_scale_qualification_items']) t;  -- CF-247 15 Oct 2026: layer2_scope_wave_items retired
    v_rows := (select count(*) from pipeline.layer2_provider_trial_results) + (select count(*) from pipeline.layer2_course_discovery_candidates)
            + (select count(*) from pipeline.layer2_provider_attempts) + (select count(*) from pipeline.layer2_scale_qualification_items);
    v_bytes := v_size;
    v_detail := jsonb_build_object('trial_results', (select count(*) from pipeline.layer2_provider_trial_results), 'discovery_candidates', (select count(*) from pipeline.layer2_course_discovery_candidates),
      'provider_attempts', (select count(*) from pipeline.layer2_provider_attempts), 'scale_qualification_items', (select count(*) from pipeline.layer2_scale_qualification_items),
      'scope_wave_items', 0);
  elsif p_cat = 'job_log' then
    v_size := pg_total_relation_size('cron.job_run_details');
    select count(*) filter (where d.start_time < now() - make_interval(days => security.pipeline_num_v1('retention.job_log_keep_days', 7)::int)), count(*) into v_rows, v_bytes from cron.job_run_details d;
    v_bytes := case when v_bytes > 0 then v_size * v_rows / v_bytes else 0 end;
  elsif p_cat = 'directory_urls' then
    v_size := pg_total_relation_size('pipeline.coverage_provider_urls');
    with h as (select provider_id, substring(url from '^https?://(?:www\.)?([^/:?#]+)') host from pipeline.coverage_provider_urls),
         shared as (select host from h group by host having count(distinct provider_id) >= 3)
    select coalesce(jsonb_agg(host order by host), '[]'::jsonb) into v_detail from shared;
    v_detail := jsonb_build_object('hosts', v_detail);
    select count(*) into v_rows from pipeline.coverage_provider_urls u join catalogue.providers p on p.id = u.provider_id
     where substring(u.url from '^https?://(?:www\.)?([^/:?#]+)') in (select jsonb_array_elements_text(v_detail->'hosts'))
       and (p.website is null or p.website not ilike '%' || substring(u.url from '^https?://(?:www\.)?([^/:?#]+)') || '%')
       and not exists (select 1 from pipeline.coverage_course_pages pg where pg.url = u.url);
    v_bytes := case when (select reltuples from pg_class where oid = 'pipeline.coverage_provider_urls'::regclass) > 0
                    then (v_size * v_rows / greatest(1, (select reltuples from pg_class where oid = 'pipeline.coverage_provider_urls'::regclass)))::bigint else 0 end;
  elsif p_cat = 'evidence_audit' then
    v_size := pg_total_relation_size('pipeline.evidence_artifacts');
    select count(*), count(*) filter (where c.done_at is not null) into v_rows, v_bytes from pipeline.evidence_audit_columns c;
    v_detail := jsonb_build_object('columns', v_rows, 'columns_done', v_bytes, 'references', (select count(*) from pipeline.evidence_audit_refs),
      'evidence_records', (select count(*) from pipeline.evidence_artifacts),
      'evidence_files_bytes', (select coalesce(sum((o.metadata->>'size')::bigint), 0) from storage.objects o where o.bucket_id = 'evidence'));
    if v_rows > 0 and v_rows = v_bytes then
      select count(*), coalesce(sum((o.metadata->>'size')::bigint), 0) into v_rows, v_bytes
        from pipeline.evidence_artifacts e left join storage.objects o on o.bucket_id = 'evidence' and o.name = e.storage_path
       where not exists (select 1 from pipeline.evidence_audit_refs r where r.evidence_id = e.id);
    else
      v_rows := null; v_bytes := null;
    end if;
  elsif p_cat = 'evidence_unreferenced' then
    v_size := pg_total_relation_size('pipeline.evidence_artifacts');
    if exists (select 1 from pipeline.retention_runs r where r.category = 'evidence_audit' and r.status = 'done')
       and not exists (select 1 from pipeline.retention_runs r where r.category = 'evidence_audit' and r.status in ('queued', 'running')) then
      -- bytes: each file once, and only files no other (kept) evidence record uses
      with c as materialized (select evidence_id, storage_path from security.retention_evidence_candidates_v1()),
           f as (select distinct storage_path from c where storage_path is not null)
      select (select count(*) from c),
             coalesce((select sum((o.metadata->>'size')::bigint) from f join storage.objects o on o.bucket_id = 'evidence' and o.name = f.storage_path
                        where not exists (select 1 from pipeline.evidence_artifacts e where e.storage_path = f.storage_path
                                            and not exists (select 1 from c where c.evidence_id = e.id))), 0)
        into v_rows, v_bytes;
      v_detail := (select jsonb_build_object('audit_run', r.id, 'audit_started_at', r.started_at, 'audit_finished_at', r.finished_at)
                     from pipeline.retention_runs r where r.category = 'evidence_audit' and r.status = 'done' order by r.finished_at desc limit 1);
    else
      v_rows := null; v_bytes := null; v_detail := jsonb_build_object('note', 'Run the evidence audit first (and let it finish).');
    end if;
  else
    raise exception 'unknown category';
  end if;
  insert into pipeline.retention_estimates(category, size_bytes, purgeable_rows, purgeable_bytes, detail, measured_at)
  values (p_cat, v_size, v_rows, v_bytes, v_detail, now())
  on conflict (category) do update set size_bytes = excluded.size_bytes, purgeable_rows = excluded.purgeable_rows, purgeable_bytes = excluded.purgeable_bytes,
         detail = excluded.detail, measured_at = excluded.measured_at;
end $function$;

CREATE OR REPLACE FUNCTION security.admin_layer2_parent_runs(p_limit integer DEFAULT 10)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'security', 'pipeline', 'auth'
AS $function$
declare v_rank integer:=0; v_result jsonb;
begin
  if auth.uid() is null then raise exception 'authentication required' using errcode='42501'; end if;
  select security.current_role_rank() into v_rank;
  if v_rank<4 then raise exception 'pipeline_operator role required' using errcode='42501'; end if;

  with recent as (
    select r.*
    from pipeline.layer2_scope_wave_requests r
    order by r.created_at desc
    limit greatest(1,least(coalesce(p_limit,10),50))
  )
  select coalesce(jsonb_agg(jsonb_build_object(
    'parent_run_id',coalesce(r.metadata->>'parent_run_id',r.id::text),
    'scope_wave_request_id',r.id,
    'status',r.status,
    'country_code',r.country_code,
    'scope_type',r.scope_type,
    'scope_id',r.scope_id,
    'route_mode',r.route_mode,
    'total_items',r.total_items,
    'dispatched_items',r.dispatched_items,
    'completed_items',r.completed_items,
    'failed_items',greatest(r.failed_items-coalesce(classify.acceptance_isolation_items,0),0),
    'recorded_failed_items',r.failed_items,
    'rescheduled_items',coalesce(classify.acceptance_isolation_items,0),
    'acceptance_isolation_items',coalesce(classify.acceptance_isolation_items,0),
    'scheduled_remainder',greatest(r.total_items-r.completed_items-r.failed_items,0),
    'last_wave_at',r.last_wave_at,
    'next_wave_not_before',r.next_wave_not_before,
    'created_at',r.created_at,
    'updated_at',r.updated_at,
    'child_batches',coalesce(items.child_batches,0),
    'active_batches',coalesce(items.active_batches,0),
    'cancelled_batches',coalesce(hist.cancelled_batches,0),
    'processed_items',r.completed_items+r.failed_items,
    'resolved_l2',coalesce(items.resolved_l2,0),
    'escalated_l3',coalesce(items.escalated_l3,0),
    'blocked',coalesce(items.blocked,0),
    'vendor_units',coalesce(items.vendor_units,0),
    'vendor_cost_usd',coalesce(items.vendor_cost_usd,0),
    'heartbeat_at',items.heartbeat_at,
    'historical_cancelled_processed',coalesce(hist.historical_cancelled_processed,0),
    'child_jobs',coalesce(items.child_jobs,0),
    'evidence_count',coalesce(ev.evidence_count,0),
    'latest_evidence_at',ev.latest_evidence_at
  ) order by r.created_at desc),'[]'::jsonb)
  into v_result
  from recent r
  left join lateral (
    select
      count(distinct wi.batch_id) filter(where wi.batch_id is not null)::int child_batches,
      count(distinct b.id) filter(where b.status in('queued','running'))::int active_batches,
      count(*) filter(where i.status='resolved_l2')::int resolved_l2,
      count(*) filter(where i.status='layer3_required')::int escalated_l3,
      count(*) filter(where i.status='blocked')::int blocked,
      coalesce(sum(i.vendor_units),0) vendor_units,
      coalesce(sum(i.vendor_cost_usd),0) vendor_cost_usd,
      max(b.heartbeat_at) heartbeat_at,
      count(distinct i.job_id) filter(where i.job_id is not null)::int child_jobs
    from (select null::uuid batch_id, null::uuid course_id, null::uuid request_id, null::text status, null::text blocker, null::int ordinal where false) wi  -- CF-247 15 Oct 2026: layer2_scope_wave_items retired (empty)
    left join pipeline.layer2_run_batches b on b.id=wi.batch_id
    left join pipeline.layer2_run_items i
      on i.batch_id=wi.batch_id and i.entity_id=wi.course_id
    where wi.request_id=r.id
      and wi.status in('dispatched','completed','failed')
  ) items on true
  left join lateral (
    select
      count(distinct e.id)::int evidence_count,
      max(e.captured_at) latest_evidence_at
    from (select null::uuid batch_id, null::uuid course_id, null::uuid request_id, null::text status, null::text blocker, null::int ordinal where false) wi  -- CF-247 15 Oct 2026: layer2_scope_wave_items retired (empty)
    join pipeline.layer2_run_items i
      on i.batch_id=wi.batch_id and i.entity_id=wi.course_id
    join pipeline.evidence_artifacts e on e.job_id=i.job_id
    where wi.request_id=r.id
      and wi.status in('dispatched','completed','failed')
  ) ev on true
  left join lateral (
    select
      count(*) filter(
        where wi.status='failed'
          and (
            lower(coalesce(wi.blocker,'')) like '%acceptance%isolation%'
            or exists(
              select 1
              from pipeline.layer2_run_items ai
              where ai.batch_id=wi.batch_id
                and lower(coalesce(ai.blocker,'')) like '%acceptance isolation%'
            )
          )
      )::int acceptance_isolation_items
    from (select null::uuid batch_id, null::uuid course_id, null::uuid request_id, null::text status, null::text blocker, null::int ordinal where false) wi  -- CF-247 15 Oct 2026: layer2_scope_wave_items retired (empty)
    where wi.request_id=r.id
  ) classify on true
  left join lateral (
    select
      count(*) filter(where b.status='cancelled')::int cancelled_batches,
      coalesce(sum(b.processed_count) filter(where b.status='cancelled'),0)::int historical_cancelled_processed
    from pipeline.layer2_run_batches b
    where b.policy_snapshot->>'scope_wave_request_id'=r.id::text
  ) hist on true;

  return v_result;
end $function$;

CREATE OR REPLACE FUNCTION security.admin_layer_status_summary_compute()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'security', 'pipeline', 'catalogue', 'scholarship', 'auth'
AS $function$
begin
 return jsonb_build_object(
  'layer1',jsonb_build_object(
    'active_sources',(select count(*) from pipeline.sources where status='active' and coalesce(metadata->>'layer','')='1'),
    'running_jobs',(select count(*) from pipeline.jobs where job_type='regulatory_sync' and status='running'),
    'failed_24h',(select count(*) from pipeline.jobs where job_type='regulatory_sync' and status='failed' and created_at>now()-interval '24 hours'),
    'latest_activity',(select max(created_at) from pipeline.jobs where job_type='regulatory_sync')
  ),
  'layer2',jsonb_build_object(
    'active_batches',(select count(*) from pipeline.layer2_run_batches where status in('queued','running','partial')),
    'scheduled_wave_requests',(select count(*) from pipeline.layer2_scope_wave_requests where status in('scheduled','running','wave1_dispatched')),
    'wave_pending_courses',0,  -- CF-247 15 Oct 2026: layer2_scope_wave_items retired (empty since 1 Oct)
    'processed_24h',(select count(*) from pipeline.layer2_run_items where completed_at>now()-interval '24 hours'),
    'evidence_24h',(select count(*) from pipeline.evidence_artifacts where coalesce(metadata->>'layer','') like '2%' and captured_at>now()-interval '24 hours')
  ),
  'layer3',jsonb_build_object(
    'qualified_profiles',(select count(*) from pipeline.layer3_model_profiles where enabled and not paused and coalesce((quality_benchmark->>'pass')::boolean,false)),
    'pending_evidence_candidates',(
      select count(distinct ri.entity_id)
      from pipeline.layer2_run_items ri
      join pipeline.layer2_provider_attempts pa on pa.job_id=ri.job_id and pa.status='succeeded'
      where ri.entity_type='course' and ri.status='layer3_required'
        and exists (
          select 1 from pipeline.evidence_artifacts e
          where e.id in (pa.raw_evidence_id,pa.html_evidence_id)
            and e.storage_path is not null and e.content_hash is not null
            and (e.valid_to is null or e.valid_to>now())
            and coalesce(e.review_state,'') not in ('rejected','invalid')
            and (e.mime_type is null or e.mime_type like 'text/%' or e.mime_type in ('application/json','application/xml','application/xhtml+xml'))
        )
    ),
    'interpretations_24h',(select count(*) from pipeline.layer3_interpretations where created_at>now()-interval '24 hours'),
    'calls_24h',(select coalesce(sum(external_call_count),0) from pipeline.layer3_interpretations where created_at>now()-interval '24 hours'),
    'tokens_24h',(select coalesce(sum(input_tokens+output_tokens),0) from pipeline.layer3_interpretations where created_at>now()-interval '24 hours'),
    'recorded_cost_24h',(select coalesce(sum(estimated_cost_usd),0) from pipeline.layer3_interpretations where created_at>now()-interval '24 hours')
  ),
  'layer4',jsonb_build_object(
    'pending_reviews',(select count(*) from pipeline.layer4_review_items where status='pending'),
    'active_overrides',(select count(*) from (
      select distinct on(entity_type,entity_id,field_code) event_type
      from pipeline.layer4_override_decisions order by entity_type,entity_id,field_code,created_at desc,id desc
    ) x where event_type<>'revert'),
    'publication_decisions',(select count(*) from pipeline.layer4_publication_decisions)
  ),
  'scholarships',jsonb_build_object(
    'scholarships',(select count(*) from scholarship.scholarships),
    'course_mappings',(select count(*) from scholarship.course_mappings where mapping_state='mapped'),
    'review_candidates',(select count(*) from scholarship.course_mapping_candidates where status='needs_review')
  )
 );
end $function$;

CREATE OR REPLACE FUNCTION security.layer2_lineage_for_job(p_job_id uuid)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'pipeline', 'security'
AS $function$
  select jsonb_build_object(
    'parent_run_id',coalesce(r.metadata->>'parent_run_id',r.id::text),
    'scope_wave_request_id',r.id,
    'batch_id',i.batch_id,
    'scope_type',r.scope_type,
    'scope_id',r.scope_id,
    'country_code',r.country_code,
    'route_mode',r.route_mode,
    'lineage_version','a26-v1'
  )
  from pipeline.layer2_run_items i
  join (select null::uuid batch_id, null::uuid course_id, null::uuid request_id, null::text status, null::text blocker, null::int ordinal where false) wi  -- CF-247 15 Oct 2026: layer2_scope_wave_items retired (empty)
    on wi.batch_id=i.batch_id and wi.course_id=i.entity_id
  join pipeline.layer2_scope_wave_requests r on r.id=wi.request_id
  where i.job_id=p_job_id
  order by wi.ordinal
  limit 1
$function$;

CREATE OR REPLACE FUNCTION public.svc_retention_files_next(p_run_id uuid, p_limit integer DEFAULT 100)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_cat text; v_out jsonb;
begin
  if current_user <> 'postgres' and coalesce(auth.role(), '') <> 'service_role' then raise exception 'service_role required'; end if;
  select category into v_cat from pipeline.retention_runs where id = p_run_id and status = 'running';
  if v_cat = 'adapter_screenshots' then
    return coalesce((select jsonb_agg(jsonb_build_object('name', o.name, 'size', (o.metadata->>'size')::bigint, 'bucket', 'adapter-captures'))
                       from (select name, metadata from storage.objects where bucket_id = 'adapter-captures' and created_at < now() - make_interval(days => security.pipeline_num_v1('retention.screenshot_keep_days', 7)::int) order by created_at limit least(greatest(p_limit, 1), 200)) o), '[]'::jsonb);
  elsif v_cat = 'evidence_unreferenced' then
    with h as (
      update pipeline.retention_file_queue q set status = 'handed', handed_at = now()
       where q.id in (select id from pipeline.retention_file_queue where run_id = p_run_id and status = 'queued' order by id limit least(greatest(p_limit, 1), 200))
      returning q.name, q.size, q.bucket)
    select coalesce(jsonb_agg(jsonb_build_object('name', name, 'size', size, 'bucket', bucket)), '[]'::jsonb) into v_out from h;
    return v_out;
  end if;
  return '[]'::jsonb;
end $function$;

-- 4 Register: the two frozen copies; the tables the paste file drops are marked retiring (Platform Admin decision, no 14-day wait)
insert into pipeline.component_register(kind, name, layer, purpose, status, introduced_in) values
 ('table', 'pipeline.layer3_validated_readings', 'Layer 3 (retired)', 'Validated Layer 3 readings kept for adapter overwrite corroboration', 'active', '20261015120000'),
 ('table', 'pipeline.layer3_call_costs_hourly', 'Layer 3 (retired)', 'Layer 3 AI calls and cost per hour, for platform resources', 'active', '20261015120000')
on conflict (kind, name) do update set purpose = excluded.purpose, status = 'active', introduced_in = excluded.introduced_in, updated_at = now();
update pipeline.component_register
   set status = 'retiring', retire_after = current_date, updated_at = now(),
       note = 'Usage audit 15 Oct 2026, decision ' || case when name = 'pipeline.layer2_scope_wave_items' then 'D9' else 'D10' end
              || ' (Platform Admin 22:12: "Proceed with D6, D7, D9 and D10"): no reads or writes since 12 Oct; rows exported to Storage (archive bucket) before the drop'
 where kind = 'table' and name in ('pipeline.layer2_scope_wave_items', 'pipeline.zz_qualify_scratch_v1', 'pipeline.reading_restores_20261005', 'public._layer1_depth_uat_control',
       'pipeline.layer2_fanout_tasks', 'pipeline.night_run_queue', 'pipeline.night_run_rebatch', 'pipeline.refused_host_changes', 'pipeline.scholarship_reread_snapshots',
       'pipeline.layer2_provider_benchmark_observations', 'pipeline.pilot_edge_execution_queue', 'search.intent_aliases', 'pipeline.evidence_links',
       'pipeline.layer2_domain_refresh_policies', 'pipeline.layer3_work_item_rebinds');
update pipeline.component_register set note = 'Usage audit 15 Oct 2026, decisions D6 and D7: rows nothing live uses exported to Storage and purged by paste file; still used rows kept', updated_at = now()
 where kind = 'table' and name in ('pipeline.layer3_interpretations', 'pipeline.layer3_work_items', 'pipeline.layer3_fact_handoffs');

do $post$
declare v_expected jsonb := '{"security.provider_english_plan_v1(uuid)": "60f5892657ef976634b12914d91f24a9", "security.adapter_overwrite_v1(integer)": "c96ca02c38878da034758b637abf60a8", "security.admit_input_mark_v1()": "93dcde29d68d8653d61cb8b53065d50c", "security.platform_resource_observe_v1()": "a35a7eb5678ab8dd35a2bb5f145e2a37", "security.retention_tick_v1()": "f07532088b71cade49c48ddd2aa07943", "security.retention_estimate_v1(text)": "67188cf89e76c7b48725cfdb7982bb0d", "security.admin_layer2_parent_runs(integer)": "50165e495917dd2bb002379d9efa4067", "security.admin_layer_status_summary_compute()": "5560c2b5ac501a90e9487139a957de3d", "security.layer2_lineage_for_job(uuid)": "eb1385cb96173a721d7a6ee4f47e6ca8", "public.svc_retention_files_next(uuid,integer)": "44fe53e8d1a4e92b88c8cbee102d3402"}'::jsonb;
  v_sig text;
begin
  for v_sig in select jsonb_object_keys(v_expected) loop
    if md5(replace(pg_get_functiondef(v_sig::regprocedure), E'\r', '')) <> v_expected->>v_sig then
      raise exception 'retired table readers post-check: % not as intended', v_sig;
    end if;
  end loop;
end $post$;

do $post2$
declare v_n bigint; v_m bigint; v_a numeric; v_b numeric;
begin
  select count(*) into v_n from pipeline.layer3_validated_readings;
  select count(*) into v_m from pipeline.layer3_interpretations where status = 'validated' and task_class in ('provider_intake_validation', 'provider_english_validation', 'provider_current_tuition_validation');
  if v_n <> v_m or v_n = 0 then raise exception 'validated readings copy: % rows, expected %', v_n, v_m; end if;
  select coalesce(sum(calls), 0), coalesce(sum(cost_usd), 0) into v_n, v_a from pipeline.layer3_call_costs_hourly;
  select count(*), coalesce(sum(coalesce(estimated_cost_usd, 0)), 0) into v_m, v_b from pipeline.layer3_interpretations where call_completed_at is not null;
  if v_n <> v_m or v_a <> v_b then raise exception 'hourly cost copy: % calls %, expected % calls %', v_n, v_a, v_m, v_b; end if;
  if (select count(*) from pipeline.component_register where kind = 'table' and status = 'retiring' and retire_after = current_date
       and name in ('pipeline.layer2_scope_wave_items', 'pipeline.zz_qualify_scratch_v1', 'pipeline.reading_restores_20261005', 'public._layer1_depth_uat_control',
       'pipeline.layer2_fanout_tasks', 'pipeline.night_run_queue', 'pipeline.night_run_rebatch', 'pipeline.refused_host_changes', 'pipeline.scholarship_reread_snapshots',
       'pipeline.layer2_provider_benchmark_observations', 'pipeline.pilot_edge_execution_queue', 'search.intent_aliases', 'pipeline.evidence_links',
       'pipeline.layer2_domain_refresh_policies', 'pipeline.layer3_work_item_rebinds')) <> 15 then
    raise exception 'register: the 15 tables are not all marked retiring';
  end if;
end $post2$;

do $dry$
declare v jsonb;
begin
  create temp table _a on commit drop as select x.id pid, e.* from _props x cross join lateral security.provider_english_plan_v1(x.id) e;
  v := jsonb_build_object(
    'courses_waiting_on_l3', (select count(*) from _cs),
    'plan_rows', (select count(*) from _b), 'plan_rows_after', (select count(*) from _a),
    'changed', (select count(*) from _b b join _a a using (pid, course_id) where b.outcome is distinct from a.outcome),
    'changed_outside_54', (select count(*) from _b b join _a a using (pid, course_id) where b.outcome is distinct from a.outcome and b.course_id not in (select course_id from _cs)),
    'transitions', (select jsonb_object_agg(k, n) from (select b.outcome || '>' || a.outcome k, count(*) n from _b b join _a a using (pid, course_id) where b.outcome is distinct from a.outcome group by 1) z),
    'summary_same', (select j from _s_b) = security.admin_layer_status_summary_compute()->'layer2',
    'parent_runs_same', (select j from _p_b) = security.admin_layer2_parent_runs(20),
    'lineage_same', not exists (select 1 from _l_b l where l.j is distinct from security.layer2_lineage_for_job(l.job_id)),
    'lineage_nonnull_before', (select count(*) from _l_b where j is not null),
    'cost_oct_same', (select m_oct from _r_b) = (select coalesce(sum(cost_usd),0) from pipeline.layer3_call_costs_hourly where hour >= '2026-10-01'),
    'cost_sep_same', (select m_sep from _r_b) = (select coalesce(sum(cost_usd),0) from pipeline.layer3_call_costs_hourly where hour >= '2026-09-01' and hour < '2026-10-01'),
    'hour_same', (select (h_calls::bigint, h_tok::numeric) from _r_b) = (select (coalesce(sum(calls),0)::bigint, sum(tokens)::numeric) from pipeline.layer3_call_costs_hourly where hour >= '2026-10-05 03:00+00' and hour < '2026-10-05 04:00+00'),
    'resource_observe', security.platform_resource_observe_v1() - 'largest_tables' - 'acquisition',
    'retention_estimate', (select to_jsonb(e) from pipeline.retention_estimates e where e.category = 'retired_layer2'),
    'input_mark', security.admit_input_mark_v1(),
    'readings', (select count(*) from pipeline.layer3_validated_readings),
    'cost_hours', (select count(*) from pipeline.layer3_call_costs_hourly));
  perform security.retention_estimate_v1('retired_layer2');
  v := v || jsonb_build_object('retention_estimate_after', (select to_jsonb(e) - 'computed_at' from pipeline.retention_estimates e where e.category = 'retired_layer2'));
  v := v || jsonb_build_object('tick', security.retention_tick_v1(), 'files_next', public.svc_retention_files_next(gen_random_uuid(), 5), 'settings', (select count(*) from pipeline.platform_toolset_settings where key like 'retention.%' or key like 'batch.retention%'));
  raise exception 'DRYRUN %', jsonb_build_object('changed', v->'changed', 'outside', v->'changed_outside_54', 'transitions', v->'transitions', 'summary_same', v->'summary_same', 'parent_runs_same', v->'parent_runs_same', 'cost', jsonb_build_array(v->'cost_oct_same', v->'cost_sep_same', v->'hour_same'), 'mtd', v->'resource_observe'->'ai_cost_mtd_usd', 'est', v->'retention_estimate_after'->'size_bytes', 'tick', v->'tick', 'files_next', v->'files_next', 'settings', v->'settings', 'readings', v->'readings');
end $dry$;
