-- CF-247 S1-RM-Design s870 and s871 (Platform Admin 20 Nov 2026 16:28 AEDT, chat S1-RM-Design): Layer 4 Review › Entry requirements (AER) no longer ends
-- in dead-end cards. Of the 2,069 AER items the job layer4-groups files under Technical recovery (class repair:completeness_gate, "the platform is
-- recovering it"), 1,985 are course first reads by the earlier AI readers (openai/gpt-4.1-mini, qwen3-30b) held by the completeness gate (D-R3);
-- 1,952 of them have a stored copy of the course page bound. Nothing was recovering them: the deterministic academic reader aer-det-v1.3 (s835)
-- skips a course while the AI read's proposed rows or its Layer 4 item stand (has_rows, earlier_read).
--   s870 security.aer_det_reread_v1: one rule for "re-read from the stored copy". A pending course first read held as technical recovery, not an
--        audit sample, not read by the deterministic reader already, with no manual lock and with a bound stored copy is superseded (Layer 4 item
--        status superseded with its supersession row, the read's proposed entry rows inactive with their reason, the readiness and group rows
--        closed), and its course is opened again to aer-det-v1.3: the sweep (job aer-det-sweep) reads the stored copy (no model, no Firecrawl)
--        and the proposer then proposes, through the unchanged machine rule and Layer 4. A course with no bound stored copy is put on the Course
--        page needed list instead (security.course_page_needed_add_v1); the search lane runs it under its own daily share. Through three new
--        read or act actions of public.admin_layer4_inbox (aer_det_reread_check, aer_det_reread, aer_page_fetch; md5-guarded, one action list
--        extended), answered by security.layer4_rule_groups_v1 (replaced: the rule groups also put technical-recovery AER items in their own
--        groups, keys aerb:<code>, so "Waiting for a reviewer" counts only items a person can decide; and each AER card carries its re-read check).
--        The deterministic proposer's earlier-read check no longer counts a superseded item (md5-guarded, one fragment of
--        security.aer_det_propose_v1), so a superseded read no longer blocks the course.
--   s871 the stale holds themselves: every pending AI course first read held by the completeness gate (machine reason gate_incomplete) that the rule
--        above can re-read is superseded once here, with the Platform Admin's reason. Entry-matrix items (the 66 first runs and the 6 matrix
--        changes), S677, audit samples, active rows (no-overwrite), manual locks (7,585) and every other kind are not touched.
-- Numbering: specs s870-s871 (S1-RM-Design's s836-s839 are used; s840-s869 are held by S1-ELR, S1-Fees-Intakes and S1-Structure-Outcomes);
-- migration 20261120145500, the last number of S1-RM-Design's window (Platform Admin 15:25 lane roster).
-- Objects (no new public function, table or view): function security.aer_det_reread_v1(text,uuid[],text,text); security.layer4_rule_groups_v1 replaced
-- (same signature); two md5-guarded edits: public.admin_layer4_inbox(text,jsonb) and security.aer_det_propose_v1(). G1: no new job (the existing
-- aer-det-sweep does the reading). G2: no new value (the batch is layer4.rule_batch_max). G3: security.consumer_api_check_v1() read before and after
-- (75 functions, 48 relations). Spend: none here; the re-read is deterministic (no model, no Firecrawl). Nothing is dropped or deleted.
-- Replaces: the dead-end Technical recovery card for course first reads with a stored copy (it now has Re-read from stored copy ($0)).
-- Retires: nothing.
-- Rollback: the superseded items keep their rows (status superseded, supersession row with mode reconcile); the inactive rows keep status_reason
-- 'superseded: ...'; reversing one sets both back. The two edits are each one changed line.
set local lock_timeout = '5s';

do $g$
declare v jsonb := security.consumer_api_check_v1();
begin
  if jsonb_array_length(coalesce(v->'drift', '[]'::jsonb)) <> 0 or (v->>'functions')::int <> 75 or (v->>'relations')::int <> 48 then
    raise exception 'guard: the consumer API is not at its baseline before this change: %', v;
  end if;
end $g$;

create or replace function security.aer_det_reread_v1(p_action text, p_refs uuid[], p_reason text, p_actor text)
returns jsonb language plpgsql security definer set search_path to '' as $function$
declare v_ext constant text := 'aer-det-v1.3';  -- fixed: the deterministic reader that reads the stored copy (s835); a new reader ships with its own migration
        v_items jsonb := '{}'::jsonb; v_skip jsonb := '{}'::jsonb; v_ok uuid[]; v_courses uuid[]; v_n int := 0; v_rows int := 0; v_pages int := 0; v_fetch int := 0;
        r record; v_note text;
begin
  if p_action not in ('check', 'apply', 'fetch') then raise exception 'INVALID_INPUT: unknown action' using errcode = '22023'; end if;
  for r in
    with i as (select x.id, x.status, x.field_code, x.entity_type, x.entity_id, x.proposed_value
                 from pipeline.layer4_review_items x where x.id = any (coalesce(p_refs, '{}'::uuid[])))
    select i.*,
           (select g.grp || '/' || g.cls from pipeline.layer4_item_groups g where g.kind = 'aer_review' and g.ref = i.id::text and g.state = 'waiting') grp,
           (select m.reason_code from pipeline.aer_machine_admissions m where m.review_item_id = i.id order by m.created_at desc limit 1) code,
           (select p.evidence_id from pipeline.coverage_course_pages p where i.entity_type = 'course' and p.course_id = i.entity_id and p.status = 'bound' and p.evidence_id is not null
             order by p.bound_at desc nulls last limit 1) stored,
           (select p.url from pipeline.coverage_course_pages p where i.entity_type = 'course' and p.course_id = i.entity_id order by p.bound_at desc nulls last limit 1) page_url,
           exists (select 1 from pipeline.manual_locks l where i.entity_type = 'course' and l.entity = 'course' and l.entity_id = i.entity_id and l.field in ('entry_requirements', 'all')) locked,
           exists (select 1 from catalogue.courses c where i.entity_type = 'course' and c.id = i.entity_id and c.lifecycle_status = 'active') course_active
      from i
  loop
    v_note := case
      when r.status <> 'pending' then 'not_waiting'
      when r.field_code <> 'course_entry_first_read' or r.entity_type <> 'course' then 'not_a_course_read'   -- entry matrices, S677 and matrix changes are never touched here
      when coalesce(r.proposed_value->>'reader', '') = 'aer_det' then 'already_deterministic'
      when r.grp is distinct from 'B/repair:completeness_gate' then 'not_technical_recovery'
      when r.code = 'audit_sample' then 'audit_sample'
      when r.locked then 'locked'
      when not r.course_active then 'course_not_active'
      when r.stored is null then 'no_stored_page'
      else 'rereadable' end;
    v_items := v_items || jsonb_build_object(r.id::text, jsonb_build_object('verdict', v_note, 'evidence_id', r.stored, 'course_id', r.entity_id, 'code', r.code));
    if v_note = 'rereadable' and p_action = 'apply' then v_ok := v_ok || r.id; v_courses := v_courses || r.entity_id;
    elsif v_note = 'no_stored_page' and p_action = 'fetch' then
      perform security.course_page_needed_add_v1(r.entity_id, coalesce(r.page_url, r.proposed_value->>'url'), left('AER: no stored page bound; asked from Layer 4 (' || p_reason || ')', 300), 'aer_layer4', null, null);
      v_fetch := v_fetch + 1;
    else v_skip := jsonb_set(v_skip, array[v_note], to_jsonb(coalesce((v_skip->>v_note)::int, 0) + 1));
    end if;
  end loop;
  if p_action = 'check' then
    return jsonb_build_object('items', v_items, 'rereadable', (select count(*) from jsonb_each(v_items) e where e.value->>'verdict' = 'rereadable'),
                              'no_stored_page', (select count(*) from jsonb_each(v_items) e where e.value->>'verdict' = 'no_stored_page'));
  end if;
  if p_action = 'apply' and coalesce(array_length(v_ok, 1), 0) > 0 then
    update pipeline.layer4_review_items set status = 'superseded', decided_at = now(),
           change_control_ref = left(coalesce(change_control_ref, '') || ' | superseded: stale partial read, re-read from the stored copy by ' || v_ext || ' ($0) (' || p_actor || ')', 400)
     where id = any (v_ok) and status = 'pending';
    get diagnostics v_n = row_count;
    insert into pipeline.layer4_supersessions(item_id, field_code, entity_type, entity_id, reason, covered_by_item, evidence, mode)
    select x.id, x.field_code, x.entity_type, x.entity_id, 'decided_before', null,
           jsonb_build_object('by', 'aer-det-reread', 'actor', p_actor, 'reason', p_reason, 'reader_after', v_ext, 'evidence_id', (v_items->(x.id::text))->>'evidence_id'), 'reconcile'
      from pipeline.layer4_review_items x where x.id = any (v_ok) and x.status = 'superseded';
    update pipeline.layer4_item_readiness set item_status = 'superseded', readiness = 'closed', classified_at = now() where item_id = any (v_ok);
    update pipeline.layer4_item_groups set state = 'closed', closed_at = now() where kind = 'aer_review' and ref = any (array(select u::text from unnest(v_ok) u));
    update catalogue.course_entry_requirements set status = 'inactive', status_reason = left('superseded: stale partial read, re-read from the stored copy by ' || v_ext || ' (' || p_reason || ')', 500), updated_at = now()
     where status = 'proposed' and provenance->>'review_item_id' = any (array(select u::text from unnest(v_ok) u));
    get diagnostics v_rows = row_count;
    update pipeline.aer_det_academic_pages set outcome = null, outcome_at = null
     where course_id = any (v_courses) and extractor = v_ext and outcome in ('has_rows', 'earlier_read');
    get diagnostics v_pages = row_count;
  end if;
  if (p_action = 'apply' and v_n > 0) or (p_action = 'fetch' and v_fetch > 0) then
    insert into pipeline.admin_control_events(area, action, target, detail, actor)
    values ('layer4', case p_action when 'apply' then 'aer_det_reread' else 'aer_page_fetch' end, 'aer_review',
            jsonb_build_object('superseded', v_n, 'rows_inactive', v_rows, 'pages_reopened', v_pages, 'fetch_queued', v_fetch, 'skipped', v_skip, 'reason', p_reason, 'by', p_actor,
                               'reader', v_ext, 'refs', to_jsonb((coalesce(v_ok, '{}'::uuid[]))[1:50])), auth.uid());
  end if;
  return jsonb_build_object('action', p_action, 'asked', coalesce(array_length(p_refs, 1), 0), 'superseded', v_n, 'rows_inactive', v_rows, 'pages_reopened', v_pages,
                            'fetch_queued', v_fetch, 'skipped', v_skip, 'reader', v_ext, 'spend', 0);
end $function$;
revoke all on function security.aer_det_reread_v1(text, uuid[], text, text) from public, anon, authenticated;
comment on function security.aer_det_reread_v1(text, uuid[], text, text) is 'CF-247 s870: a stale partial AER course first read held as technical recovery is superseded and its course re-read from the stored copy by aer-det-v1.3 ($0); a course with no stored copy goes on the Course page needed list. check / apply / fetch. Entry matrices, audit samples, locks and active rows are never touched.';

-- s870: the rule groups (s837) also keep technical-recovery AER items apart and carry each AER card's re-read check (replaced; same signature; md5 read live f7187ce2)
do $p$
begin
  if md5(replace(pg_get_functiondef('security.layer4_rule_groups_v1(text,jsonb,jsonb,integer)'::regprocedure), chr(13), '')) <> 'f7187ce274c64139a53e37199bd963f0' then
    raise exception 'pre-check: security.layer4_rule_groups_v1 changed since it was read';
  end if;
end $p$;
create or replace function security.layer4_rule_groups_v1(p_action text, p_args jsonb, p_kinds jsonb, p_target int)
returns jsonb language plpgsql stable security definer set search_path to '' as $function$
declare v_kind text := nullif(p_args->>'kind', ''); v_prov uuid := nullif(p_args->>'provider_id', '')::uuid;
        v_max int := security.pipeline_num_v1('layer4.rule_group_refs_max', 500)::int;
        v_batch int := security.pipeline_num_v1('layer4.rule_batch_max', 50)::int;
        v_refs text[]; v_aer jsonb := '[]'::jsonb; t0 timestamptz := clock_timestamp(); v_out jsonb; v_rank int; v_ids uuid[]; v_rr jsonb := '{}'::jsonb;
begin
  if p_action not in ('rule_groups', 'rule_group_items', 'aer_det_reread_check', 'aer_det_reread', 'aer_page_fetch') then raise exception 'INVALID_INPUT: unknown action' using errcode = '22023'; end if;
  -- s870 (Platform Admin 20 Nov 2026 16:28): a stale partial AER read is re-read from its stored copy by the deterministic reader ($0), or a course with no
  -- stored page goes on the Course page needed list. Checking is open to a Curator; acting is the Platform Admin's, as every AER decision (A3).
  if p_action in ('aer_det_reread_check', 'aer_det_reread', 'aer_page_fetch') then
    v_rank := security.current_role_rank();
    if p_action <> 'aer_det_reread_check' and v_rank < 6 then raise exception 'Platform Admin role required' using errcode = '42501'; end if;
    if p_action <> 'aer_det_reread_check' and length(btrim(coalesce(p_args->>'reason', ''))) < 5 then raise exception 'INVALID_INPUT: a reason of at least 5 characters is needed' using errcode = '22023'; end if;
    v_ids := array(select y.x::uuid from jsonb_array_elements_text(case when jsonb_typeof(p_args->'refs') = 'array' then p_args->'refs' else '[]'::jsonb end) with ordinality y(x, n)
                    where y.x ~ '^[0-9a-f-]{36}$' order by y.n limit v_batch);
    return security.aer_det_reread_v1(case p_action when 'aer_det_reread_check' then 'check' when 'aer_det_reread' then 'apply' else 'fetch' end, v_ids, btrim(coalesce(p_args->>'reason', '')),
             coalesce((select u.email from auth.users u where u.id = auth.uid()), auth.uid()::text, 'unknown'));
  end if;
  if v_kind is null then raise exception 'INVALID_INPUT: choose a kind' using errcode = '22023'; end if;
  -- a registered (hook) kind has its own page reader: the screen shows its list as before
  if not (security.layer4_inbox_kinds_v1() ? v_kind) then
    return jsonb_build_object('kind', v_kind, 'built_in', false, 'total', null, 'groups', '[]'::jsonb, 'items', '[]'::jsonb);
  end if;

  if p_action = 'rule_group_items' then
    v_refs := array(select y.x from jsonb_array_elements_text(case when jsonb_typeof(p_args->'refs') = 'array' then p_args->'refs' else '[]'::jsonb end) with ordinality y(x, n)
                     order by y.n limit v_batch);
    if v_kind = 'aer_review' then  -- s870: whether each card can be re-read from its stored copy ($0), and if not, why
      v_rr := coalesce(security.aer_det_reread_v1('check', array(select r::uuid from unnest(v_refs) r where r ~ '^[0-9a-f-]{36}$'), '', '')->'items', '{}'::jsonb);
    end if;
    return (with b as (select i.kind, i.ref, i.provider_id, coalesce(p.display_name, p.canonical_name) provider, i.subject, i.why, i.suggestion, i.created_at, i.detail
                         from security.layer4_inbox_items_v2(null, v_kind, array(select v_kind || ':' || r from unnest(v_refs) r), true) i
                         left join catalogue.providers p on p.id = i.provider_id
                        where coalesce(array_length(v_refs, 1), 0) > 0)
      select jsonb_build_object('kind', v_kind, 'built_in', true, 'asked', coalesce(array_length(v_refs, 1), 0), 'batch_max', v_batch,
               'items', coalesce(jsonb_agg(jsonb_build_object('kind', b.kind, 'ref', b.ref, 'provider_id', b.provider_id, 'provider', b.provider, 'subject', b.subject,
                          'why', b.why, 'suggestion', b.suggestion, 'created_at', b.created_at, 'late', b.created_at < now() - make_interval(days => p_target),
                          'detail', b.detail, 'o', (p_kinds->b.kind->>'order')::int) || case when v_rr ? b.ref then jsonb_build_object('reread', v_rr->b.ref) else '{}'::jsonb end
                        order by array_position(v_refs, b.ref)), '[]'::jsonb),
               'ms', round(extract(epoch from clock_timestamp() - t0) * 1000)::int)
        from b);
  end if;

  if v_kind = 'aer_review' then v_aer := coalesce(security.layer4_aer_hold_reasons_v1('{}'::jsonb)->'reasons', '[]'::jsonb); end if;
  with i as (
         select r.ref, r.created_at, r.why,
                case when v_kind = 'provider_description' then coalesce(r.detail->'machine'->>'reason_code', r.detail->'proposed'->>'held_rule', '') end code,
                regexp_replace(regexp_replace(btrim(coalesce(r.why, '')), '([.;])\s.*$', '\1'), '[.;:]+$', '') clause
           from security.layer4_inbox_items_v2(v_prov, v_kind, null, v_kind = 'provider_description') r),
       k as (
         select i.*,
                case when v_kind = 'provider_description' then 'cd:' || (case
                       when i.code = '' then 'first_provider_sample'
                       when i.code = 'policy_refused_word' then 'banned_word'
                       when i.code in ('identity_margin_thin', 'identity_not_allowed') then 'identity_margin_thin'
                       when i.code = 'binding_ambiguous' then 'binding_ambiguous'
                       when i.code = 'check_sentence_count' then 'sentence_count_over_2'
                       when i.code = 'check_length' then 'length'
                       when i.code like 'policy\_%' or i.code in ('check_unsupported_claim', 'check_unsupported_marketing') then 'boilerplate_detected'
                       when i.code in ('check_quote_not_on_page', 'check_unsupported_sentence', 'check_copied_sentence', 'source_recheck_failed') then 'quote_mismatch'
                       when i.code in ('evidence_moved', 'page_url_changed', 'reading_other_evidence') then 'evidence_moved'
                       when i.code = 'wrong_page_kind' then 'wrong_page_kind'
                       when i.code like 'duplicate\_%' or i.code = 'check_duplicate_other_course' then 'duplicate'
                       when i.code like 'rejected\_before%' or i.code = 'withdrawn_awaiting_person' then 'rejected_before'
                       else 'other' end)
                     when v_kind = 'aer_review' then (case when exists (select 1 from pipeline.layer4_item_groups x where x.kind = 'aer_review' and x.ref = i.ref and x.grp = 'B' and x.state = 'waiting')
                                                            then 'aerb:' else 'aer:' end) || coalesce(substring(i.why from 'did not admit this: ([a-z_]+)'), 'other')
                     else v_kind || ':' || lower(i.clause) end gkey
           from i),
       g as (
         select k.gkey, count(*) n, min(k.created_at) oldest, count(*) filter (where k.created_at < now() - make_interval(days => p_target)) late,
                (array_agg(k.clause order by k.created_at, k.ref))[1] clause,
                (array_agg(k.ref order by k.created_at, k.ref))[1:v_max] refs
           from k group by k.gkey)
  select jsonb_build_object('kind', v_kind, 'built_in', true, 'provider_id', v_prov, 'total', coalesce(sum(g.n), 0), 'refs_max', v_max, 'batch_max', v_batch,
           'groups', coalesce(jsonb_agg(jsonb_build_object('key', g.gkey, 'n', g.n, 'oldest', g.oldest, 'late', g.late,
                       'label', case when v_kind = 'aer_review' then coalesce((select r->>'label' from jsonb_array_elements(v_aer) r where (r->>'code') = regexp_replace(g.gkey, '^aerb?:', '') limit 1),
                                                   initcap(replace(regexp_replace(g.gkey, '^aerb?:', ''), '_', ' ')))
                                     when v_kind = 'provider_description' then null else nullif(g.clause, '') end,
                       'refs', to_jsonb(g.refs), 'recovery', g.gkey like 'aerb:%') order by g.n desc, g.gkey), '[]'::jsonb),
           'as_at', now(), 'ms', round(extract(epoch from clock_timestamp() - t0) * 1000)::int)
    into v_out from g;
  return v_out;
end $function$;

revoke all on function security.layer4_rule_groups_v1(text, jsonb, jsonb, int) from public, anon, authenticated;

create or replace function pg_temp.cf_edit_def(p_sig regprocedure, p_md5 text, p_old text[], p_new text[])
returns void language plpgsql as $f$
declare v_def text := replace(pg_get_functiondef(p_sig), chr(13), ''); v_c int; i int;
begin
  if p_md5 is not null and md5(v_def) <> p_md5 then raise exception 'pre-check: % changed since it was read (definition md5 %)', p_sig, md5(v_def); end if;
  for i in 1 .. array_length(p_old, 1) loop
    v_c := (length(v_def) - length(replace(v_def, p_old[i], ''))) / length(p_old[i]);
    if v_c <> 1 then raise exception 'pre-check: %: fragment % must occur exactly once (found %)', p_sig, i, v_c; end if;
    v_def := replace(v_def, p_old[i], p_new[i]);
  end loop;
  execute v_def;
end $f$;

-- s870: public.admin_layer4_inbox (md5 read live 20 Nov 2026 16:45 AEDT, after s837): three more read or act actions on the same branch
select pg_temp.cf_edit_def('public.admin_layer4_inbox(text,jsonb)'::regprocedure, '93cb781009da3ef410943e905f9d893b',
  array[$o$  if p_action in ('rule_groups', 'rule_group_items') then$o$],
  array[$n$  if p_action in ('rule_groups', 'rule_group_items', 'aer_det_reread_check', 'aer_det_reread', 'aer_page_fetch') then  -- CF-247 s870$n$]);

-- s870: security.aer_det_propose_v1 (S1-AER s835; md5 read live 20 Nov 2026 16:45 AEDT): a superseded earlier read no longer blocks the course
select pg_temp.cf_edit_def('security.aer_det_propose_v1()'::regprocedure, '8516a3992010f7f55a7f9bcc8a9c8bb3',
  array[$o$r.entity_id = pg.course_id and r.field_code = 'course_entry_first_read') then v_outcome := 'earlier_read';$o$],
  array[$n$r.entity_id = pg.course_id and r.field_code = 'course_entry_first_read' and r.status <> 'superseded') then v_outcome := 'earlier_read';  -- CF-247 s870$n$]);

-- s871: the stale partial-table holds, once (Platform Admin 20 Nov 2026 16:28 AEDT)
do $s$
declare v_refs uuid[]; v_r jsonb; v_before int; v_after int; v_mx int; v_mx2 int; v_locks int; v_locks2 int; v_active int; v_active2 int;
begin
  select count(*) into v_locks from pipeline.manual_locks;
  select count(*) into v_active from catalogue.course_entry_requirements where status = 'active';
  select count(*) into v_mx from pipeline.layer4_review_items where status = 'pending' and field_code in ('entry_matrix_first_run', 'entry_matrix_change');
  select array_agg(i.id order by i.created_at) into v_refs
    from pipeline.layer4_review_items i join pipeline.layer4_item_groups g on g.kind = 'aer_review' and g.ref = i.id::text and g.state = 'waiting' and g.grp = 'B'
   where i.status = 'pending' and i.field_code = 'course_entry_first_read' and i.entity_type = 'course' and coalesce(i.proposed_value->>'reader', '') <> 'aer_det'
     and (select m.reason_code from pipeline.aer_machine_admissions m where m.review_item_id = i.id order by m.created_at desc limit 1) = 'gate_incomplete';
  select count(*) into v_before from pipeline.layer4_review_items where status = 'pending' and field_code = 'course_entry_first_read';
  v_r := security.aer_det_reread_v1('apply', v_refs,
           'Platform Admin 20 Nov 2026 16:28 AEDT: stale partial-table hold (completeness gate, D-R3); re-read from the bound stored copy by the deterministic reader ($0)', 'migration 20261120145500 (s871)');
  select count(*) into v_after from pipeline.layer4_review_items where status = 'pending' and field_code = 'course_entry_first_read';
  select count(*) into v_mx2 from pipeline.layer4_review_items where status = 'pending' and field_code in ('entry_matrix_first_run', 'entry_matrix_change');
  select count(*) into v_locks2 from pipeline.manual_locks;
  select count(*) into v_active2 from catalogue.course_entry_requirements where status = 'active';
  if v_mx2 <> v_mx then raise exception 'post-check: entry matrix items changed (% to %)', v_mx, v_mx2; end if;
  if v_locks2 <> v_locks then raise exception 'post-check: manual locks changed (% to %)', v_locks, v_locks2; end if;
  if v_active2 <> v_active then raise exception 'post-check: active entry rows changed (% to %)', v_active, v_active2; end if;
  if v_before - v_after <> (v_r->>'superseded')::int then raise exception 'post-check: % superseded but the waiting count moved by %', v_r->>'superseded', v_before - v_after; end if;
  raise notice 'CF-247 s871: % stale holds asked, % superseded, % proposed rows inactive, % reader pages reopened, skipped %; waiting course first reads % to %; matrices %; locks %; active rows %',
    coalesce(array_length(v_refs, 1), 0), v_r->>'superseded', v_r->>'rows_inactive', v_r->>'pages_reopened', v_r->'skipped', v_before, v_after, v_mx2, v_locks2, v_active2;
end $s$;

do $g$
declare v jsonb := security.consumer_api_check_v1();
begin
  if jsonb_array_length(coalesce(v->'drift', '[]'::jsonb)) <> 0 or (v->>'functions')::int <> 75 or (v->>'relations')::int <> 48 then
    raise exception 'guard: the consumer API changed: %', v;
  end if;
end $g$;
