CREATE OR REPLACE FUNCTION public.svc_retention_files_next(p_run_id uuid, p_limit integer DEFAULT 100)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_cat text; v_out jsonb;
begin
  if current_user <> 'postgres' and coalesce(auth.role(), '') <> 'service_role' then raise exception 'service_role required'; end if;
  select category into v_cat from pipeline.retention_runs where id = p_run_id and status = 'running';
  if v_cat = 'adapter_screenshots' then
    return coalesce((select jsonb_agg(jsonb_build_object('name', o.name, 'size', (o.metadata->>'size')::bigint, 'bucket', 'adapter-captures'))
                       from (select name, metadata from storage.objects where bucket_id = 'adapter-captures' and created_at < now() - interval '7 days' order by created_at limit least(greatest(p_limit, 1), 200)) o), '[]'::jsonb);
  elsif v_cat = 'evidence_unreferenced' then
    with h as (
      update pipeline.retention_file_queue q set status = 'handed', handed_at = now()
       where q.id in (select id from pipeline.retention_file_queue where run_id = p_run_id and status = 'queued' order by id limit least(greatest(p_limit, 1), 200))
      returning q.name, q.size, q.bucket)
    select coalesce(jsonb_agg(jsonb_build_object('name', name, 'size', size, 'bucket', bucket)), '[]'::jsonb) into v_out from h;
    return v_out;
  end if;
  return '[]'::jsonb;
end $function$
