do $body$
declare d text;
begin
  d := pg_get_functiondef('public.layer2_apply_course_candidate(uuid,boolean)'::regprocedure);
  d := replace(d, $x$values(v_course,v_field,r.source_id,r.evidence_id,'meta_description','First-party HTML meta description',true,'active',now(),now(),now())$x$, $x$values(v_course,v_field,r.source_id,r.evidence_id,'meta_description','First-party HTML meta description',true,'current',now(),now(),now())$x$);
  d := replace(d, $x$source_field_name=excluded.source_field_name,is_primary=true,status='active',observed_at=now(),updated_at=now()$x$, $x$source_field_name=excluded.source_field_name,is_primary=true,status='current',observed_at=now(),updated_at=now()$x$);
  execute d;
end $body$;
