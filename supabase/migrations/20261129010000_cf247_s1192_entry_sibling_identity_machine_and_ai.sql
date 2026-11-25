-- CF-247 s1192 (S1-Build / Integration Controller; Platform Admin 26 Nov 2026 06:57 AEDT decision, option 2, and 08:19 AEDT: "Complete the sibling identity
-- integration into the AI reader and recorder ... Where existing approved policy permits admission, correct the technical routing or eligibility defect and
-- proceed through the existing mechanism"). S2-AER (shared identity and admission owner): the same approved proof, no new rule, recorded in the master plan.
-- Found live (rolled back, 26 Nov 2026 08:30 AEDT): of the 512 pending deterministic entry proposals, the existing machine admission (aer-machine-admission,
-- security.aer_machine_run_v1, mode 2, validated, not suspended) declined 20, every s1191 proposal, with "the page is matched to the course by exact_title,
-- which is not admitted for entry requirements": security.aer_machine_check_v1 repeats the identity test without the approved proven sibling page. 370 are
-- declined because the course already has active rows (no-overwrite: a person's decision) and 122 because every waiting row fails a row rule; both stay.
-- What this does, live on apply (each an md5-guarded one-line edit beside the existing 11 Nov title-identity extension security.aer_title_identity_ok_v1):
--   1. security.aer_machine_check_v1: the identity test also accepts security.entry_sibling_identity_v1 for the course's bound page. Every other check of the
--      machine admission (provenance, evidence, rows, confidence, audit sampling, active-rows no-overwrite, withdrawals, daily cap) is unchanged.
--   2. security.enrich_fields_slice_v1 (the AI read gate): for the entry requirements field only, a page the course page check refuses as shared passes when the
--      proven sibling page holds (the function itself requires every other part of the check to pass).
--   3. security.enrich_entry_record_v1 (the AI recorder): its identity test also accepts the proven sibling page.
--   4. the 20 pending s1191 proposals are checked once now through the existing machine admission (security.aer_machine_admit_v1(item, 'run')).
-- G1: no job. G2: no new value. G3: no consumer object changed (checked). Locks and cron checked unchanged. Other fields keep their identity rule.
-- Replaces: security.aer_machine_check_v1, security.enrich_fields_slice_v1 and security.enrich_entry_record_v1 (same functions, one identity line each).
-- Retires: nothing. Nothing dropped or deleted.
set local lock_timeout = '5s';  -- fixed: lock wait for the guard reads
set local statement_timeout = '300s';  -- fixed: the machine checks of the s1191 proposals

do $g$
declare v jsonb := security.consumer_api_check_v1();
begin
  if jsonb_array_length(coalesce(v->'drift', '[]'::jsonb)) <> 0 or (v->>'functions')::int <> 75 or (v->>'relations')::int <> 48 then
    raise exception 'guard: the consumer API is not at its baseline before this change: %', v;
  end if;
  if md5(pg_get_functiondef('security.aer_machine_check_v1(uuid)'::regprocedure)) <> '13aa1f26d18234413907861fd8b11642' then raise exception 'guard: security.aer_machine_check_v1 is not the definition read on 26 Nov 2026'; end if;
  if md5(pg_get_functiondef('security.enrich_fields_slice_v1(uuid,integer)'::regprocedure)) <> 'd68665cb163bb99f7cca088d39cf595b' then raise exception 'guard: security.enrich_fields_slice_v1 is not the definition read on 26 Nov 2026'; end if;
  if md5(pg_get_functiondef('security.enrich_entry_record_v1(bigint,jsonb)'::regprocedure)) <> 'add21880f6671ed5dfc73fe6fd82f118' then raise exception 'guard: security.enrich_entry_record_v1 is not the definition read on 26 Nov 2026'; end if;
end $g$;
create temp table s1192_locks on commit drop as select count(*) n from pipeline.manual_locks;
create temp table s1192_cron on commit drop as select count(*) n from cron.job where active;
create temp table s1192_idf on commit drop as select md5(pg_get_functiondef('security.coverage_identity_allowed(uuid,text,text)'::regprocedure)) m;

do $e$
declare d text; v_old text; v_new text;
begin
  -- 1. machine check
  d := pg_get_functiondef('security.aer_machine_check_v1(uuid)'::regprocedure);
  v_old := 'if not (security.coverage_identity_allowed(c.provider_id, g.identity_basis, ''entry_requirements'') or coalesce((security.aer_title_identity_ok_v1(c.id)->>''ok'')::boolean, false)) then';
  v_new := 'if not (security.coverage_identity_allowed(c.provider_id, g.identity_basis, ''entry_requirements'') or coalesce((security.aer_title_identity_ok_v1(c.id)->>''ok'')::boolean, false) or coalesce((security.entry_sibling_identity_v1(c.id, g.url)->>''ok'')::boolean, false)) then  -- CF-247 s1192: or the proven sibling page (Platform Admin 26 Nov 2026 06:57 AEDT)';
  if (length(d) - length(replace(d, v_old, ''))) / length(v_old) <> 1 then raise exception 's1192: the machine check identity line is not found exactly once'; end if;
  execute replace(d, v_old, v_new);
  -- 2. AI read gate (entry requirements only)
  d := pg_get_functiondef('security.enrich_fields_slice_v1(uuid,integer)'::regprocedure);
  v_old := 'coalesce(nullif(g.candidates->>''page_title'', ''''), g.candidates->>''h1''), g.identity_basis)->>''verdict'' <> ''refuse'');';
  v_new := 'coalesce(nullif(g.candidates->>''page_title'', ''''), g.candidates->>''h1''), g.identity_basis)->>''verdict'' <> ''refuse''
                 or (it.field = ''entry_requirements'' and coalesce((security.entry_sibling_identity_v1(it.course_id, g.url)->>''ok'')::boolean, false)));  -- CF-247 s1192: the proven sibling page (Platform Admin 26 Nov 2026 06:57 AEDT)';
  if (length(d) - length(replace(d, v_old, ''))) / length(v_old) <> 1 then raise exception 's1192: the read gate page check line is not found exactly once'; end if;
  execute replace(d, v_old, v_new);
  -- 3. AI recorder
  d := pg_get_functiondef('security.enrich_entry_record_v1(bigint,jsonb)'::regprocedure);
  v_old := 'if g.provider_id is null or not (security.coverage_identity_allowed(g.provider_id, g.identity_basis, ''entry_requirements'') or coalesce((security.aer_title_identity_ok_v1(i.course_id)->>''ok'')::boolean, false)) then';
  v_new := 'if g.provider_id is null or not (security.coverage_identity_allowed(g.provider_id, g.identity_basis, ''entry_requirements'') or coalesce((security.aer_title_identity_ok_v1(i.course_id)->>''ok'')::boolean, false) or coalesce((security.entry_sibling_identity_v1(i.course_id, g.url)->>''ok'')::boolean, false)) then  -- CF-247 s1192: or the proven sibling page';
  if (length(d) - length(replace(d, v_old, ''))) / length(v_old) <> 1 then raise exception 's1192: the recorder identity line is not found exactly once'; end if;
  execute replace(d, v_old, v_new);
end $e$;

do $run$
declare ev jsonb; r record; v jsonb; v_out jsonb := '{}'::jsonb; v_n int := 0;
begin
  select detail into ev from pipeline.admin_control_events where target = 'security.entry_sibling_identity_v1' order by id desc limit 1;
  for r in select i.id from pipeline.layer4_review_items i
            where i.status = 'pending' and i.field_code = 'course_entry_first_read' and i.proposed_value->>'reader' = 'aer_det'
              and i.entity_id in (select (x->>'course')::uuid from jsonb_array_elements(coalesce(ev->'courses', '[]'::jsonb)) x) loop
    v := security.aer_machine_admit_v1(r.id, 'run');
    v_n := v_n + 1;
    v_out := jsonb_set(v_out, array[coalesce(v->>'outcome', v->>'rule', 'unknown')], to_jsonb(coalesce((v_out->>coalesce(v->>'outcome', v->>'rule', 'unknown'))::int, 0) + 1));
  end loop;
  insert into pipeline.admin_control_events(area, action, target, detail, actor)
  values ('aer', 'identity_rule', 'security.aer_machine_check_v1', jsonb_build_object('reason', 'Proven sibling page in the machine check, AI read gate and AI recorder (Platform Admin 26 Nov 2026 06:57 and 08:19 AEDT)',
          'by', 'migration 20261129010000 (CF-247 s1192)', 'checked', v_n, 'outcomes', v_out), '63ba56cb-48d4-4169-98c2-7c4d1f72925b');  -- fixed: the deciding Platform Admin
  raise notice 's1192: % s1191 proposals checked: %', v_n, v_out;
end $run$;

do $c$
declare v_api jsonb;
begin
  if (select count(*) from cron.job where active) <> (select n from s1192_cron) then raise exception 'post-check: the number of active cron jobs changed'; end if;
  if (select count(*) from pipeline.manual_locks) <> (select n from s1192_locks) then raise exception 'post-check: manual locks changed'; end if;
  if md5(pg_get_functiondef('security.coverage_identity_allowed(uuid,text,text)'::regprocedure)) <> (select m from s1192_idf) then raise exception 'post-check: the identity rule of other fields changed'; end if;
  if pg_get_functiondef('security.aer_machine_check_v1(uuid)'::regprocedure) not like '%entry_sibling_identity_v1(c.id, g.url)%'
     or pg_get_functiondef('security.enrich_fields_slice_v1(uuid,integer)'::regprocedure) not like '%entry_sibling_identity_v1(it.course_id, g.url)%'
     or pg_get_functiondef('security.enrich_entry_record_v1(bigint,jsonb)'::regprocedure) not like '%entry_sibling_identity_v1(i.course_id, g.url)%' then
    raise exception 'post-check: a function does not use the proven sibling page';
  end if;
  v_api := security.consumer_api_check_v1();
  if jsonb_array_length(coalesce(v_api->'drift', '[]'::jsonb)) <> 0 or (v_api->>'functions')::int <> 75 or (v_api->>'relations')::int <> 48 then
    raise exception 'post-check: the consumer API moved: %', v_api;
  end if;
end $c$;
