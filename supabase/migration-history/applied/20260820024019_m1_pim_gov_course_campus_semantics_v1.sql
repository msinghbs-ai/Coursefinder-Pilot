create or replace function public.ui_course_related_campuses(p_course_id uuid)
returns jsonb
language sql
stable
security definer
set search_path to 'public','catalogue','ref','pipeline','auth'
as $function$
select coalesce(
  jsonb_agg(
    jsonb_build_object(
      'id', ca.id,
      'stable_key', ca.stable_key,
      'name', ca.name,
      'campus_code', ca.campus_code,
      'provider_id', ca.provider_id,
      'country_code', co.iso_alpha2,
      'subdivision_code', sd.code,
      'subdivision_name', sd.name,
      'city', ca.city,
      'address_line1', ca.address_line1,
      'address_line2', ca.address_line2,
      'postcode', ca.postcode,
      'status', ca.status,
      'publication_status', ca.publication_status,
      'valid_from', ca.valid_from,
      'valid_to', ca.valid_to,
      'last_verified_at', ca.last_verified_at,
      'delivery_mode', cc.delivery_mode,
      'is_primary', cc.is_primary,
      'website', ca.website,
      'campus_source', jsonb_build_object(
        'source_id', ca.source_id,
        'source_label', cs.label,
        'source_type', cs.source_type,
        'source_url', cs.url
      ),
      'campus_evidence', case when ce.id is null then null else jsonb_build_object(
        'id', ce.id,
        'type', ce.evidence_type,
        'source_url', ce.source_url,
        'captured_at', ce.captured_at,
        'content_hash', ce.content_hash
      ) end,
      'relationship_source', jsonb_build_object(
        'source_id', cc.source_id,
        'source_label', rs.label,
        'source_type', rs.source_type,
        'source_url', rs.url
      ),
      'relationship_evidence', case when re.id is null then null else jsonb_build_object(
        'id', re.id,
        'type', re.evidence_type,
        'source_url', re.source_url,
        'captured_at', re.captured_at,
        'content_hash', re.content_hash
      ) end
    ) order by cc.is_primary desc nulls last, ca.name
  ),
  '[]'::jsonb
)
from catalogue.course_campuses cc
join catalogue.campuses ca on ca.id=cc.campus_id
join ref.countries co on co.id=ca.country_id
left join ref.subdivisions sd on sd.id=ca.subdivision_id
left join pipeline.sources cs on cs.id=ca.source_id
left join pipeline.evidence_artifacts ce on ce.id=ca.evidence_id
left join pipeline.sources rs on rs.id=cc.source_id
left join pipeline.evidence_artifacts re on re.id=cc.evidence_id
where cc.course_id=p_course_id
  and auth.uid() is not null;
$function$;

revoke all on function public.ui_course_related_campuses(uuid) from public;
revoke execute on function public.ui_course_related_campuses(uuid) from authenticated;
grant execute on function public.ui_course_related_campuses(uuid) to service_role;
