CREATE OR REPLACE FUNCTION security.provider_contact_disposition_current(p_provider_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'security', 'pipeline', 'auth'
AS $function$
declare v_rank int; v pipeline.provider_contact_dispositions%rowtype;
begin
  if auth.uid() is null then raise exception 'authentication required' using errcode='42501'; end if;
  v_rank:=security.current_role_rank(); if v_rank<1 then raise exception 'assigned CourseFinder role required' using errcode='42501'; end if;
  select * into v from pipeline.provider_contact_dispositions where provider_id=p_provider_id order by created_at desc,id desc limit 1;
  if not found then return jsonb_build_object('disposition','pending_acquisition'); end if;
  return jsonb_build_object(
    'id',v.id,'disposition',v.disposition,'international_students_url',v.international_students_url,
    'contact_team_url',v.contact_team_url,'general_email',v.general_email,
    'named_contact_count',v.named_contact_count,'territory_contact_count',v.territory_contact_count,
    'source_urls',v.source_urls,'evidence_ids',v.evidence_ids,'layer3_interpretation_id',v.layer3_interpretation_id,
    'interpretation_source',v.interpretation_source,'observed_at',v.observed_at,'last_verified_at',v.last_verified_at
  );
end $function$
