-- CF-247 / Decision 155 step 2: planned batches read the stored register file, so the slice also
-- returns the stored files' source URLs and publisher metadata (snapshot dates).
create or replace function public.svc_layer1_plan_slice(p_run_id uuid, p_offset integer, p_limit integer)
returns jsonb language sql stable security definer set search_path to 'pg_catalog','pipeline' as $f$
  select jsonb_build_object(
    'exists', p.run_id is not null,
    'to_apply', jsonb_array_length(p.items),
    'register_total', p.register_total,
    'keys', coalesce((select jsonb_agg(i->0 order by o) from jsonb_array_elements(p.items) with ordinality x(i,o)
                       where o>greatest(p_offset,0) and o<=greatest(p_offset,0)+greatest(least(p_limit,500),1)),'[]'::jsonb),
    'zip_evidence_id', p.zip_evidence_id, 'zip_path', z.storage_path, 'zip_hash', z.content_hash, 'zip_url', z.source_url, 'zip_meta', z.metadata,
    'course_evidence_id', p.course_evidence_id, 'course_path', c.storage_path, 'course_hash', p.course_hash, 'course_url', c.source_url, 'course_meta', c.metadata)
  from pipeline.layer1_run_plans p
  left join pipeline.evidence_artifacts z on z.id=p.zip_evidence_id
  left join pipeline.evidence_artifacts c on c.id=p.course_evidence_id
  where p.run_id=p_run_id
$f$;
revoke all on function public.svc_layer1_plan_slice(uuid,integer,integer) from public, anon, authenticated;
grant execute on function public.svc_layer1_plan_slice(uuid,integer,integer) to service_role;
