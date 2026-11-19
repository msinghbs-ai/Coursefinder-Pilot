do $body$
declare d text;
begin
  d := pg_get_functiondef('public.layer2_apply_course_candidate(uuid,boolean)'::regprocedure);
  d := replace(d, 'v_course uuid; v_field uuid; v_desc_applied int:=0;', 'v_course uuid; v_field uuid; v_entity uuid; v_desc_applied int:=0;');
  d := replace(d,
$x$    select id into v_field from pim.attribute_definitions where code='course_description' and entity_type='course' and status='active' limit 1;
     if v_field is null then raise exception 'course_description attribute definition missing';end if;
     insert into catalogue.course_field_observations(course_id,field_id,source_id,evidence_id,source_field_code,source_field_name,is_primary,status,observed_at,created_at,updated_at)
     values(v_course,v_field,r.source_id,r.evidence_id,'meta_description','First-party HTML meta description',true,'current',now(),now(),now())
     on conflict(course_id,source_id,source_field_code) do update set field_id=excluded.field_id,evidence_id=excluded.evidence_id,source_field_name=excluded.source_field_name,is_primary=true,status='current',observed_at=now(),updated_at=now();$x$,
$x$    select id into v_field from pim.attribute_definitions where code='course_description' and entity_type='course' and status='active' limit 1;
     if v_field is null then raise exception 'course_description attribute definition missing';end if;
     select er.id into v_entity from catalogue.courses c join pim.entity_registry er on er.entity_type='course' and er.stable_key=c.stable_key where c.id=v_course limit 1;
     if v_entity is null then raise exception 'course PIM entity registry row missing';end if;
     insert into pim.attribute_values(entity_id,attribute_id,value_text,source_id,evidence_id,confidence,review_status,is_preferred,created_at,updated_at)
     values(v_entity,v_field,v_desc,r.source_id,r.evidence_id,1,'accepted',true,now(),now());$x$);
  execute d;
end $body$;
