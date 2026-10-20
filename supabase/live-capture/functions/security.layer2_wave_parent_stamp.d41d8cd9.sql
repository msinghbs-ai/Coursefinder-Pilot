CREATE OR REPLACE FUNCTION security.layer2_wave_parent_stamp()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'pipeline', 'ref', 'security'
AS $function$
declare
  v_terminal uuid;
  v_root uuid;
begin
  select q.id into v_terminal
  from pipeline.layer2_scale_qualification_runs q
  join ref.countries c on c.id=q.country_id
  where q.requested_by=new.requested_by
    and c.iso_alpha2::text=upper(new.country_code)
    and q.scope_type=new.scope_type
    and q.scope_id is not distinct from new.scope_id
    and q.status in('completed','partial')
    and coalesce((q.result_summary->>'auto_progress_scope')::boolean,false)
  order by
    case when not coalesce((q.result_summary->>'auto_progress_processed')::boolean,false) then 0 else 1 end,
    q.completed_at desc nulls last,q.created_at desc
  limit 1;

  if v_terminal is not null then
    v_root:=security.layer2_qualification_root(v_terminal);
  end if;

  update pipeline.layer2_scope_wave_requests
  set metadata=coalesce(metadata,'{}'::jsonb)||jsonb_build_object(
    'parent_run_id',coalesce(v_root,new.id),
    'parent_run_kind',case when v_root is null then 'scope_wave_request' else 'qualification_root' end,
    'qualification_terminal_run_id',v_terminal,
    'scope_wave_request_id',new.id,
    'lineage_version','a26-v1'
  )
  where id=new.id;
  return new;
end $function$
