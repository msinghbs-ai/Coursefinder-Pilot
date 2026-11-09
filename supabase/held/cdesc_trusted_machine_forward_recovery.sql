-- HELD (not a migration): forward recovery for 20261110060100 (the machine admission of first course descriptions), the one in-place edit it makes: security.course_description_trusted_v1.
-- Run only if the Platform Admin decides to count machine decisions as person-trust again (only meaningful if enrich.course_description_review_first is ever lowered). It restores the function byte for byte
-- (body md5 ae8b327f85f0262b3d0b878010a4af3c, read from live 10 Nov 2026), guarded by the md5 of what is live now (the edited text, 16568089f58b528b9a6647e78eca3ed5, or the original).
do $g$
declare v text := (select md5(p.prosrc) from pg_proc p where p.oid = to_regprocedure('security.course_description_trusted_v1(uuid)'));
begin
  if v is null then raise exception 'security.course_description_trusted_v1 is missing'; end if;
  if v not in ('16568089f58b528b9a6647e78eca3ed5', 'ae8b327f85f0262b3d0b878010a4af3c') then raise exception 'live security.course_description_trusted_v1 differs from both texts this recovery knows (body md5 %)', v; end if;
end $g$;

CREATE OR REPLACE FUNCTION security.course_description_trusted_v1(p_provider uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  with n as (select greatest(1, security.pipeline_num_v1('enrich.course_description_review_first', 5)::int) k),
  d as (select r.status from pipeline.layer4_review_items r join catalogue.courses c on c.id = r.entity_id
         where r.entity_type = 'course' and r.field_code = 'course_description_first_read' and c.provider_id = p_provider
           and r.status in ('approved', 'edited_approved', 'rejected', 'more_evidence', 'returned_layer2', 'returned_layer3')
         order by r.decided_at desc nulls last limit (select k from n))
  select count(*) = (select k from n) and bool_and(d.status in ('approved', 'edited_approved')) from d
$function$;

do $p$ begin
  if md5((select p.prosrc from pg_proc p where p.oid = to_regprocedure('security.course_description_trusted_v1(uuid)'))) <> 'ae8b327f85f0262b3d0b878010a4af3c' then raise exception 'post-check: the restored body does not match'; end if;
end $p$;
