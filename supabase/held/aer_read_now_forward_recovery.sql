-- HELD (not a migration): forward recovery for 20261110220000 (AER read now). Run only if the Platform Admin decides to take the four in-place edits back:
--   security.aer_course_population_v1()      the scheduled reader's eligibility rules are written in the function itself again (live body md5 d593eb0aa0fe06b0b4b28c86821bfff5)
--   security.data_delivery_aer_v1()          the key reviewer is removed (live body md5 27a42c5f02d09f518e77bd965814bbe0)
--   security.layer4_aer_review_detail_v1     the Facts section is removed from the reviewer card (live body md5 330e079018c93f8db8a649ed3a08ae12)
--   security.data_delivery_v1()              the recovery state reads off when ANY switch of the lane is off again, and the key switches_off is removed
-- Each of the first three is taken back only from the text this change wrote (its after md5); a function that is neither that text nor the original stops with a message and nothing is applied.
-- The Data Delivery edit is taken back wherever it sits in whatever is live. The new functions (security.aer_course_population_v1(uuid), aer_packet_rows_v1, aer_packet_facts_v1, aer_pending_packets_v1, aer_read_now_plan_v1,
-- aer_read_now_status_v1, aer_read_now_v1, aer_read_now_out_v1 and public.admin_aer_read_now) are left in place (the screen stops calling them with the release that takes the action back); they are dropped by a paste file only on the Platform Admin's say.
-- The on-demand requests already recorded (pipeline.admin_control_events, area aer_read_now) are history and stay. Repeatable.

do $m$
declare r record; v_def text; v_src text; v_c int; k int; v_sig regprocedure;
begin
  -- 1. the eligibility rules: the original text, if the body is the one this change wrote
  v_sig := to_regprocedure('security.aer_course_population_v1()');
  if v_sig is null then raise exception 'security.aer_course_population_v1() is missing'; end if;
  v_src := (select p.prosrc from pg_proc p where p.oid = v_sig);
  if md5(v_src) = 'd593eb0aa0fe06b0b4b28c86821bfff5' then raise notice 'security.aer_course_population_v1(): already the original text';
  elsif md5(v_src) <> '39df48e65bc7f0d4c3dcb4cde5d244cc' then raise exception 'live security.aer_course_population_v1() is neither the text this change wrote nor the original (body md5 %)', md5(v_src);
  else
    execute $e$create or replace function security.aer_course_population_v1()
 RETURNS TABLE(course_id uuid, provider_id uuid, country text, provider_name text, tier integer, prio bigint, title text)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  with s as (select coalesce(security.toolset_setting('pipeline', 'aer.schedule_lock_fields'), '[]'::jsonb) locks,
                    coalesce(security.toolset_setting('pipeline', 'aer.priority_provider_types'), '[]'::jsonb) pt,
                    -- CF-247 workstream C (Integration Controller 3 Nov 2026 18:30): followed providers, then the largest AER shortfall, first
                    coalesce((security.toolset_setting('pipeline', 'coverage.aer_reader_priority_on') #>> '{}')::boolean, false) gap_first,
                    coalesce(security.toolset_setting('pipeline', 'coverage.aer_priority_providers'), '[]'::jsonb) followed),
  pv as (select e.provider_id, e.country, coalesce(p.display_name, p.short_name, p.canonical_name) pname,
                case when s.gap_first and s.followed ? e.provider_id::text then -1000000
                     when s.gap_first and coalesce(k.shortfall, 0) > 0 then -least(k.shortfall, 999999)
                     when s.pt ? coalesce(t.code, '') then 1 else 2 end tier
           from security.aer_eligible_v1() e
           join catalogue.providers p on p.id = e.provider_id
           left join ref.provider_types t on t.id = p.provider_type_id
           left join pipeline.coverage_provider_reconciliation k on k.domain = 'aer' and k.provider_id = e.provider_id
          cross join s
          where (security.aer_schedule_country_v1(e.country)->>'on')::boolean
            and not exists (select 1 from security.provider_hidden_v1 h where h.provider_id = e.provider_id)),
  pr as (select pv.*, dense_rank() over (order by pv.tier, pv.pname, pv.provider_id) prio from pv)
  select c.id, pr.provider_id, pr.country, pr.pname, pr.tier, pr.prio, c.canonical_title
    from pr
    join catalogue.courses c on c.provider_id = pr.provider_id and c.lifecycle_status = 'active'
    join pipeline.coverage_course_pages g on g.course_id = c.id and g.status = 'bound'
    join pipeline.evidence_artifacts a on a.id = g.evidence_id and a.storage_path is not null
   cross join s
   where security.coverage_identity_allowed(c.provider_id, g.identity_basis, 'entry_requirements')
     and not exists (select 1 from pipeline.manual_locks l where l.entity = 'course' and l.entity_id = c.id and (s.locks ? l.field or l.field = 'all'))
$function$$e$;
    v_src := (select p.prosrc from pg_proc p where p.oid = v_sig);
    if md5(v_src) <> 'd593eb0aa0fe06b0b4b28c86821bfff5' then raise exception 'security.aer_course_population_v1() after the recovery has body md5 %, expected d593eb0aa0fe06b0b4b28c86821bfff5', md5(v_src); end if;
    raise notice 'security.aer_course_population_v1(): restored';
  end if;
  -- 2. the anchored edits, reversed
  for r in select * from (values
    ('security.data_delivery_aer_v1()', '27a42c5f02d09f518e77bd965814bbe0', 'f66f692580977dcef97f8db5b01b3403', true,
     array[$o$  -- 10 Nov 2026 (AER read now): reviewer-ready packets against active approved rows, from the stored completeness gate and the proposed rows (never a gate per item)
  pk as (select * from security.aer_pending_packets_v1(null, null)),
  pf as (select count(*) rows, count(*) filter (where x.country <> 'not_stated' and x.qualification <> 'not_stated' and x.grade <> 'not_stated' and x.scale <> 'not_stated' and x.applicability <> 'not_stated' and x.source_page <> 'not_stated' and x.year <> 'not_stated') complete,
                jsonb_strip_nulls(jsonb_build_object('country', nullif(count(*) filter (where x.country = 'not_stated'), 0), 'qualification', nullif(count(*) filter (where x.qualification = 'not_stated'), 0), 'grade', nullif(count(*) filter (where x.grade = 'not_stated'), 0),
                  'scale', nullif(count(*) filter (where x.scale = 'not_stated'), 0), 'applicability', nullif(count(*) filter (where x.applicability = 'not_stated'), 0), 'source_page', nullif(count(*) filter (where x.source_page = 'not_stated'), 0),
                  'year', nullif(count(*) filter (where x.year = 'not_stated'), 0))) ns
           from security.aer_packet_rows_v1(null) x join pk on pk.item_id = x.item_id and pk.packet_state = 'reviewer_ready'),
  rvw as (select jsonb_build_object('known', true, 'pending', (select count(*) from pk), 'classified_at', (select max(classified_at) from pk),
            'reviewer_ready', (select count(*) from pk where packet_state = 'reviewer_ready'), 'technical_hold', (select count(*) from pk where packet_state = 'technical_hold'),
            'needs_input', (select count(*) from pk where packet_state = 'needs_input'), 'not_checked', (select count(*) from pk where packet_state = 'not_checked'),
            'by_kind', (select coalesce(jsonb_object_agg(z.field_code, jsonb_build_object('pending', z.n, 'reviewer_ready', z.r)), '{}'::jsonb) from (select field_code, count(*) n, count(*) filter (where packet_state = 'reviewer_ready') r from pk group by 1) z),
            'ready_rows', (select jsonb_build_object('rows', pf.rows, 'every_fact_stated', pf.complete, 'with_a_fact_not_stated', pf.rows - pf.complete, 'not_stated', pf.ns) from pf),
            'active_rows', jsonb_build_object('matrix', (select count(*) from catalogue.provider_entry_matrix where status = 'active'), 'course', (select count(*) from catalogue.course_entry_requirements where status = 'active')),
            'decided', (select jsonb_build_object('approved', count(*) filter (where i.status in ('approved', 'edited_approved')), 'rejected', count(*) filter (where i.status = 'rejected'), 'last_decided_at', max(i.decided_at))
                          from pipeline.layer4_review_items i where i.field_code = any (security.aer_review_kinds_v1()) and i.status in ('approved', 'edited_approved', 'rejected')),
            'on_demand', (select jsonb_build_object('requests_24h', count(*), 'last_request_at', max(e.created_at), 'queued_24h', count(*) filter (where e.detail->>'outcome' = 'queued')) from pipeline.admin_control_events e where e.area = 'aer_read_now' and e.created_at > now() - interval '1 day')) j),
  blk as (select coalesce(jsonb_agg(v.t), '[]'::jsonb) j$o$,
           $o$'layer4_readiness', rv.j, 'reviewer', rvw.j, 'last_run', lastrun.j, 'jobs', jobs.j, 'blockers', blk.j)$o$,
           $o$from cov, bycc, disp, gaps, other, prk, lastrun, jobs, sf, srcs, rv, rvw, blk);$o$],
     array[$n$  blk as (select coalesce(jsonb_agg(v.t), '[]'::jsonb) j$n$,
           $n$'layer4_readiness', rv.j, 'last_run', lastrun.j, 'jobs', jobs.j, 'blockers', blk.j)$n$,
           $n$from cov, bycc, disp, gaps, other, prk, lastrun, jobs, sf, srcs, rv, blk);$n$]),
    ('security.layer4_aer_review_detail_v1(text)', '330e079018c93f8db8a649ed3a08ae12', 'e377494a017ea32e2b5d50f7b87c733c', true,
     array[$o$    jsonb_build_object('key', 'facts', 'title', 'Facts the page states', 'body', (security.aer_packet_facts_v1(p_ref::uuid))->'section'),
    jsonb_build_object('key', 'rows', 'title', 'Proposed rows (' || (p->'proposed'->>'count') || ')', 'body', p->'proposed'->'rows'),$o$],
     array[$n$    jsonb_build_object('key', 'rows', 'title', 'Proposed rows (' || (p->'proposed'->>'count') || ')', 'body', p->'proposed'->'rows'),$n$]),
    ('security.data_delivery_v1()', '208067f054c2f3ac7adb1196e3e8c25c', '-', false,
     array[$o$v_rd jsonb; v_job jsonb; v_sw text[]; v_sw_all int;$o$,
           $o$    -- 10 Nov 2026 (AER read now): a stream is OFF only when every switch of its lane that exists is off; one optional recovery route that is off (for example a deliberately paused pilot) is named, it does not turn the whole stream off
    select coalesce(array_agg(k.key order by k.key) filter (where (st.value #>> '{}') in ('0', 'false')), '{}'::text[]), count(*) filter (where st.key is not null) into v_sw, v_sw_all from unnest(s.switch_keys) k(key)
      left join pipeline.platform_toolset_settings st on st.toolset_key = 'pipeline' and st.key = k.key;
    v_off := cardinality(v_sw) > 0 and cardinality(v_sw) = v_sw_all;$o$,
           $o$else 'No open issues; the scheduled job retries on its next run' || case when cardinality(v_sw) > 0 then '. Switched off, so these routes do not run: ' || array_to_string(v_sw, ', ') else '' end end,$o$,
           $o$'switches_off', to_jsonb(v_sw), 'open_issues', v_open, 'issue_refs', v_issue_refs,$o$],
     array[$n$v_rd jsonb; v_job jsonb;$n$,
           $n$    select coalesce(bool_or((st.value #>> '{}') in ('0', 'false')), false) into v_off from unnest(s.switch_keys) k(key)
      join pipeline.platform_toolset_settings st on st.toolset_key = 'pipeline' and st.key = k.key;$n$,
           $n$else 'No open issues; the scheduled job retries on its next run' end,$n$,
           $n$'open_issues', v_open, 'issue_refs', v_issue_refs,$n$])
  ) v(sig, md5_before, md5_after, must_match, olds, news) loop
    v_sig := to_regprocedure(r.sig);
    if v_sig is null then raise exception '% is missing', r.sig; end if;
    v_src := (select p.prosrc from pg_proc p where p.oid = v_sig);
    if r.must_match then
      if md5(v_src) = r.md5_before then raise notice '%: already the original text', r.sig; continue; end if;
      if md5(v_src) <> r.md5_after then raise exception 'live % is neither the text this change wrote nor the original (body md5 %)', r.sig, md5(v_src); end if;
    elsif position('v_sw_all' in v_src) = 0 then raise notice '%: carries no switch derivation of this change', r.sig; continue;
    end if;
    v_def := replace(pg_get_functiondef(v_sig), chr(13), '');
    for k in 1 .. array_length(r.olds, 1) loop
      v_c := (length(v_def) - length(replace(v_def, r.olds[k], ''))) / length(r.olds[k]);
      if v_c <> 1 then raise exception '%: edit % must apply exactly once (found %)', r.sig, k, v_c; end if;
      v_def := replace(v_def, r.olds[k], r.news[k]);
    end loop;
    execute v_def;
    v_src := (select p.prosrc from pg_proc p where p.oid = v_sig);
    if r.must_match and md5(v_src) <> r.md5_before then raise exception '% after the recovery has body md5 %, expected %', r.sig, md5(v_src), r.md5_before; end if;
    raise notice '%: restored', r.sig;
  end loop;
end $m$;
