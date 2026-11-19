-- CF-247: Layer 3 picks course pages by "course code printed on the page" (identity_basis 'cricos_code'). New Zealand
-- programme codes (e.g. AUT "AK3717") are printed on NZ course pages in the same way, so once NZ discovery started on
-- 1 Oct 2026 NZ pages began reaching Layer 3: four went to the tuition step (which records amounts in AUD) and others to
-- the intake and English steps. Nothing was written to any NZ course: the admission steps need a CRICOS provider and
-- course registration, which NZ courses do not have, so each NZ answer was sent to the Layer 4 queue as "could not be
-- recorded automatically" instead. Left alone, that would fill Layer 4 with thousands of NZ items and spend AI calls on
-- answers that cannot be used.
-- This change limits both Layer 3 hand-off steps (tuition: public.svc_coverage_tuition_handoff_next; intake and English:
-- public.layer3_fact_claim_service) to Australian providers, parks the open NZ Layer 3 items and marks their pending
-- Layer 4 items superseded with the reason. NZ admission (NZQA programme identity, NZD currency) is a separate, reviewed
-- change. Guards: each function is replaced only if its live body is the one checked on 1 Oct 2026.

do $guard$
declare v text;
begin
  select md5(p.prosrc) into v from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'svc_coverage_tuition_handoff_next';
  if v is distinct from '6b1eaef271e92ad6a5ac0610e6e185e8' then
    raise exception 'svc_coverage_tuition_handoff_next changed (md5 %); not replacing', v;
  end if;
end $guard$;

create or replace function public.svc_coverage_tuition_handoff_next(p_limit integer) returns jsonb
language plpgsql security definer set search_path = pg_catalog, catalogue, pipeline, security as $fn$
declare v jsonb;
begin
  if current_user<>'postgres' and coalesce(auth.role(),'')<>'service_role' then raise exception 'service_role required'; end if;
  if not exists (select 1 from pipeline.layer3_model_profiles where 'provider_current_tuition_validation'=any(allowed_task_classes) and enabled and not paused and coalesce((quality_benchmark->>'pass')::boolean,false)) then return '[]'::jsonb; end if;
  with pick as (
    select p.course_id
      from pipeline.coverage_course_pages p
      join pipeline.evidence_artifacts e on e.id=p.evidence_id and e.storage_path is not null
      join catalogue.courses co on co.id=p.course_id and co.lifecycle_status='active'
      join catalogue.providers pr on pr.id=p.provider_id
      join ref.countries k on k.id=pr.country_id and k.iso_alpha2='AU'
     where p.read_status='read' and p.identity_basis='cricos_code' and p.l3_work_item_id is null
       and (p.l3_handoff_at is null or p.l3_handoff_at < now()-interval '1 day')
       and security.coverage_tuition_target_v1(p.candidates->'fee') is not null
       and not exists (select 1 from catalogue.course_fees f where f.course_id=p.course_id and f.fee_type='provider_current_tuition' and f.status='active')
       and not security.layer4_entity_or_parent_blocked('course',p.course_id,'operational')
     order by p.read_at limit greatest(1,least(coalesce(p_limit,50),100)) for update of p skip locked),
  upd as (update pipeline.coverage_course_pages p set l3_handoff_at=now() from pick where p.course_id=pick.course_id returning p.course_id, p.url, p.evidence_id)
  select coalesce(jsonb_agg(jsonb_build_object('course_id',u.course_id,'storage_path',e.storage_path,'url',u.url)),'[]'::jsonb) into v
    from upd u join pipeline.evidence_artifacts e on e.id=u.evidence_id;
  return v;
end $fn$;

-- layer3_fact_claim_service: one join added (provider must be Australian); the rest of the live body is kept as is.
do $claim$
declare s text; v text; n int;
  old_txt text := E'\n      join catalogue.courses co on co.id=pg.course_id and co.lifecycle_status=''active''\n      left join pipeline.layer3_fact_handoffs h';
  new_txt text := E'\n      join catalogue.courses co on co.id=pg.course_id and co.lifecycle_status=''active''\n      join catalogue.providers pv on pv.id=pg.provider_id\n      join ref.countries kc on kc.id=pv.country_id and kc.iso_alpha2=''AU''\n      left join pipeline.layer3_fact_handoffs h';
begin
  select p.prosrc into s from pg_proc p join pg_namespace ns on ns.oid = p.pronamespace
   where ns.nspname = 'public' and p.proname = 'layer3_fact_claim_service';
  v := md5(s);
  if v is distinct from '5f0868e73a37194ce14ca0f1ff578de8' then
    raise exception 'layer3_fact_claim_service changed (md5 %); not replacing', v;
  end if;
  n := (length(s) - length(replace(s, old_txt, ''))) / length(old_txt);
  if n <> 1 then raise exception 'expected the courses join once in layer3_fact_claim_service, found %', n; end if;
  execute format('create or replace function public.layer3_fact_claim_service(p_task_class text, p_limit integer, p_worker text, p_binding_hash text) returns jsonb language plpgsql volatile security definer set search_path = pg_catalog, pipeline, catalogue, security as %L', replace(s, old_txt, new_txt));
end $claim$;

-- Park every open NZ (non-Australian) Layer 3 item and supersede its pending Layer 4 items.
update pipeline.layer3_work_items w
   set status = 'parked', last_error = 'parked: not an Australian provider; NZ admission is a separate reviewed change (CF-247, 1 Oct 2026)', updated_at = now()
  from catalogue.providers pr join ref.countries k on k.id = pr.country_id, catalogue.courses c
 where c.id = w.entity_id and w.entity_type = 'course' and pr.id = c.provider_id and k.iso_alpha2 <> 'AU'
   and w.status in ('pending','reserved','interpreting','validated','admission_pending','layer4_required','failed');

update pipeline.layer4_review_items i
   set status = 'superseded', decided_at = now(),
       escalation_reason = coalesce(i.escalation_reason,'') || ' [Closed automatically on 1 Oct 2026: New Zealand course. NZ values are not admitted until the NZ admission path (NZQA programme identity, NZD) is approved. CF-247]'
  from catalogue.courses c join catalogue.providers pr on pr.id = c.provider_id join ref.countries k on k.id = pr.country_id
 where i.entity_type = 'course' and i.entity_id = c.id and k.iso_alpha2 <> 'AU' and i.status = 'pending'
   and i.field_code in ('course_intake','course_english','provider_current_tuition_validation');
