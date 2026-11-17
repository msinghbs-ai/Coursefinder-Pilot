-- REVIEW ONLY. Nothing in this file has run in production.
-- Admin #382 critical comment 6685067695; three exact field-reader admissions.
-- An explicitly authorised Platform Admin completes the three variables below.
-- Root must verify exclusive authority and stop/reconcile active writes first.
-- Apply the forward semantic guard before this reviewed correction. No human
-- locks, source links, intake labels/years/starts, item readings or API shape change.
-- Do not use admin_intake_date_withdraw_v1: that route requires calendar-process
-- provenance and adds intakes locks; these values came from field_enrich_items.
-- Source/consumer evidence: /workspace/p0-review/2026-11-06-1242-p0-deadline-verification.json
begin;
set local statement_timeout = '8s';
set local lock_timeout = '3s';
do $review_only$
declare
  v_approved boolean := false;  -- set true only for a separately recorded approval of these exact three corrections
  v_actor uuid := null;        -- actual authorising Platform Admin, never an invented user or claim
  v_decision text := null;     -- immutable Admin decision/approval reference
  v_operation constant text := 'P0-DEADLINE-382-20261106-THREE';
  v_before jsonb; v_count integer; v_rows integer; r record; v_payload jsonb; v_path text;
begin
  if not v_approved or v_actor is null or coalesce(length(btrim(v_decision)), 0) = 0 then
    raise exception 'review-only proposal: exact correction approval, actual actor and durable decision reference are required';
  end if;
  if current_user <> 'postgres' and (auth.uid() is distinct from v_actor or security.current_role_rank() < 6) then
    raise exception 'execute only through the approved Platform Admin SQL context';
  end if;
  if md5(pg_get_functiondef('security.course_deadline_in_quote_v1(date,text)'::regprocedure)) <> '2357306ca969fb7b299021bac3b6f3fa' then
    raise exception 'forward semantic guard is not the reviewed version; no correction performed';
  end if;
  -- Lock the exact values. Concurrent attempts cannot both pass the value guard.
  perform 1 from catalogue.course_intakes where id in
    ('0bae1bde-3d71-4ae8-86ff-118049910790','8dcd0a7e-c634-4f9d-92ba-2832413f3583','8e7d1957-58ce-4a2d-9583-fef41ea30bdc') order by id for update;
  if exists (select 1 from pipeline.admin_control_events where area = 'intake_dates' and action = 'deadline_semantic_withdraw' and target = v_operation) then
    select count(*) into v_count from catalogue.course_intakes where id in
      ('0bae1bde-3d71-4ae8-86ff-118049910790','8dcd0a7e-c634-4f9d-92ba-2832413f3583','8e7d1957-58ce-4a2d-9583-fef41ea30bdc') and application_deadline is null;
    if v_count <> 3 then raise exception 'operation already recorded but current values differ: reconcile, do not replay'; end if;
    raise notice 'operation already committed and the three deadlines are still empty; no action repeated';
    return;
  end if;
  if exists (select 1 from pipeline.manual_locks where entity = 'course'
    and entity_id in ('2b19936a-69ad-49b8-9a33-56644609ccfc','2bad6b65-cd92-4a35-9efc-a69d4bb43d99','2bb7f6ea-be1f-44e2-a51c-72a277045475')
    and field in ('all','deadline','intake','intakes')) then
    raise exception 'affected human lock exists: stop for its owner, never bypass or change it';
  end if;
  -- Same current catalogue value, exact filled item, exact kept quote, exact
  -- supporting reading artifact. Torrens has a newer item artifact at the same
  -- official URL; its older intake evidence must not be silently substituted.
  with expected(course_id,intake_id,item_id,wrong_date,quote,item_evidence,intake_evidence) as (values
    ('2b19936a-69ad-49b8-9a33-56644609ccfc'::uuid,'0bae1bde-3d71-4ae8-86ff-118049910790'::uuid,273361::bigint,'2026-11-02'::date,'Start date 02 Nov 2026','75891841-a6d3-4707-906f-3ad39d444d53'::uuid,'9b66aac4-dc0c-46dc-893b-b233291984f1'::uuid),
    ('2bad6b65-cd92-4a35-9efc-a69d4bb43d99','8dcd0a7e-c634-4f9d-92ba-2832413f3583',273381,'2027-02-15','Intakes 15 February 2027','1458055d-c99a-458c-9d6a-62af342a36ab','1458055d-c99a-458c-9d6a-62af342a36ab'),
    ('2bb7f6ea-be1f-44e2-a51c-72a277045475','8e7d1957-58ce-4a2d-9583-fef41ea30bdc',273383,'2026-10-12','Start Dates 12 October 2026','05e4b193-3ffc-461a-b6bc-16e6e225dd3a','05e4b193-3ffc-461a-b6bc-16e6e225dd3a'))
  select count(*), jsonb_agg(jsonb_build_object('intake',to_jsonb(i),'item_id',f.id,'item_evidence',f.evidence_id,'quote',x.quote) order by i.id)
    into v_count,v_before from expected x join catalogue.course_intakes i on i.id=x.intake_id and i.course_id=x.course_id
    join pipeline.field_enrich_items f on f.id=x.item_id and f.course_id=x.course_id and f.field='deadline' and f.state='filled' and f.evidence_id=x.item_evidence
   where i.status='active' and i.application_deadline=x.wrong_date and i.evidence_id=x.intake_evidence
     and exists (select 1 from jsonb_array_elements(f.value->'deadlines') d where d->>'date'=x.wrong_date::text and d->>'quote'=x.quote
                   and d->>'outcome'='kept' and d->'intake_ids' @> jsonb_build_array(x.intake_id::text))
     and not security.course_deadline_in_quote_v1(x.wrong_date,x.quote);
  if v_count <> 3 then raise exception 'only % of 3 exact admission/value guards match; nothing changed',v_count; end if;
  insert into pipeline.admin_control_events(area,action,target,detail,actor)
  values ('intake_dates','deadline_semantic_withdraw',v_operation,jsonb_build_object('governance','Admin #382','decision',v_decision,
    'reason','Start/intake dates were misclassified as application-closing dates','before',v_before,'fields_changed',jsonb_build_array('application_deadline'),'count',3),v_actor);
  update catalogue.course_intakes set application_deadline=null where id in
    ('0bae1bde-3d71-4ae8-86ff-118049910790','8dcd0a7e-c634-4f9d-92ba-2832413f3583','8e7d1957-58ce-4a2d-9583-fef41ea30bdc');
  get diagnostics v_rows=row_count;
  if v_rows <> 3 then raise exception 'updated %, expected 3; transaction must roll back',v_rows; end if;
  perform search.refresh_course_enrichment_scoped_v1(array['2b19936a-69ad-49b8-9a33-56644609ccfc'::uuid,'2bad6b65-cd92-4a35-9efc-a69d4bb43d99'::uuid,'2bb7f6ea-be1f-44e2-a51c-72a277045475'::uuid],true);
  -- Post-write consumer SQL readback is mandatory before commit. Root then checks
  -- Website/Zoho HTTP and cache behaviour separately; SQL success is not closure.
  for r in select * from (values
      ('2b19936a-69ad-49b8-9a33-56644609ccfc'::uuid,'095229D','November'),
      ('2bad6b65-cd92-4a35-9efc-a69d4bb43d99'::uuid,'094185G','February'),
      ('2bb7f6ea-be1f-44e2-a51c-72a277045475'::uuid,'106137B','October')) x(course_id,code,label) loop
    foreach v_path in array array['website','zoho_v1','zoho_v2'] loop
      v_payload := case v_path when 'website' then api.website_v2_course_item(r.course_id)
        when 'zoho_v1' then public.zoho_edge_course_lookup_v1(r.code)->'item'
        else public.zoho_v2_course(r.code)->'item' end;
      if v_payload is null or (select count(*) from jsonb_array_elements(coalesce(v_payload->'intakes','[]'::jsonb)) i
          where i->>'label'=r.label and i->>'application_deadline' is null) <> 1 then
        raise exception '% projection does not show the exact intake with an empty deadline; transaction must roll back',v_path;
      end if;
    end loop;
  end loop;
end $review_only$;
commit;
-- Recovery: never restore these known-wrong dates automatically. Use the retained
-- before-state to reconcile uncertain execution, then obtain actual application-
-- closing evidence and the existing human-governed admission route. Do not unlock.
