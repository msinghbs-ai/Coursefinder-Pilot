-- Layer 4 reviewer source (programme owner decision, 24 Sep 2026, option A).
-- Search shows official course links only from sources approved for that data type.
-- Reviewer-entered links had no source, so they were recorded but never reached search.
-- A dedicated source records that a named reviewer entered the value (their note and time
-- are on the decision record), and is approved for official course links only.
-- Also: can_approve is never empty (a missing value means "cannot approve").
do $mig$
declare v_src uuid;
begin
  select id into v_src from pipeline.sources where source_type='layer4_human_review' limit 1;
  if v_src is null then
    insert into pipeline.sources(source_type,label,trust_rank,status,metadata,created_at,updated_at)
    values ('layer4_human_review','Layer 4 human review (values entered by reviewers)',95,'active',
            jsonb_build_object('purpose','Values entered by named reviewers in Layer 4; see pipeline.layer4_decisions for who, when and why.',
                               'change_control','CF-CHG-20260915-247','decision','Programme owner, 24 Sep 2026, option A'),now(),now())
    returning id into v_src;
  end if;
  insert into search.enrichment_source_gates(projection_code,domain_code,source_id,gate_status,approval_ref,approved_at,created_at,updated_at)
  values ('courses','official_course_url',v_src,'approved','CF-CHG-20260915-247; programme owner decision 24 Sep 2026 (option A): reviewer-entered official course links',now(),now(),now())
  on conflict do nothing;
end $mig$;

-- Attribute reviewer-entered links to the reviewer source (guarded substitution).
do $mig$
declare d text;
  a1 text := $q$'Official provider course page (confirmed by reviewer)',false,'active',null,v_item.evidence_id,1,now(),now())
  on conflict(course_id,link_type,url) do update set label=excluded.label,status='active',confidence=1,last_verified_at=now(),updated_at=now()$q$;
  b1 text := $q$'Official provider course page (confirmed by reviewer)',false,'active',(select id from pipeline.sources where source_type='layer4_human_review' limit 1),v_item.evidence_id,1,now(),now())
  on conflict(course_id,link_type,url) do update set label=excluded.label,status='active',source_id=excluded.source_id,confidence=1,last_verified_at=now(),updated_at=now()$q$;
begin
  d := pg_get_functiondef('security.layer4_course_link_apply_impl(uuid,uuid,jsonb,text)'::regprocedure);
  if strpos(d,'layer4_human_review')>0 then return; end if;
  if (length(d)-length(replace(d,a1,'')))/length(a1) <> 1 then raise exception 'link anchor not found exactly once'; end if;
  execute replace(d,a1,b1);
end $mig$;

-- can_approve never empty (guarded substitution of the desk read).
do $mig$
declare d text;
  a1 text := $q$'can_approve', case$q$;
  b1 text := $q$'can_approve', coalesce(case$q$;
  a2 text := $q$      else b.entity_type='course' end,
    'scope_pending'$q$;
  b2 text := $q$      else b.entity_type='course' end,false),
    'scope_pending'$q$;
begin
  d := pg_get_functiondef('security.layer4_review_desk_v1_impl(text,integer)'::regprocedure);
  if strpos(d,$q$'can_approve', coalesce(case$q$)>0 then return; end if;
  if (length(d)-length(replace(d,a1,'')))/length(a1) <> 1 then raise exception 'anchor 1 not found exactly once'; end if;
  if (length(d)-length(replace(d,a2,'')))/length(a2) <> 1 then raise exception 'anchor 2 not found exactly once'; end if;
  execute replace(replace(d,a1,b1),a2,b2);
end $mig$;
