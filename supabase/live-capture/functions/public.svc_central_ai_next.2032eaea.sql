CREATE OR REPLACE FUNCTION public.svc_central_ai_next(p_limit integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v jsonb; s pipeline.central_ai_settings%rowtype;
begin
  if current_user <> 'postgres' and coalesce(auth.role(), '') <> 'service_role' then raise exception 'service_role required'; end if;
  select * into s from pipeline.central_ai_settings where id = 1;
  if not coalesce(s.enabled, false) then return '[]'::jsonb; end if;
  with pick as (select q.id from pipeline.central_ai_queue q where (q.state = 'queued' or (q.state = 'leased' and q.leased_until < now())) and q.attempts < 3
                 order by q.id limit greatest(1, least(coalesce(p_limit, 6), 10)) for update skip locked),
  upd as (update pipeline.central_ai_queue q set state = 'leased', leased_until = now() + interval '4 minutes', attempts = q.attempts + 1 from pick where q.id = pick.id returning q.*)
  select coalesce(jsonb_agg(jsonb_build_object('queue_id', u.id, 'id', u.fact_source_id, 'kind', u.kind, 'url', f.url, 'provider', coalesce(p.display_name, p.canonical_name),
           'storage_path', e.storage_path, 'model', s.model_identifier, 'model_code', s.model_code)), '[]'::jsonb) into v
    from upd u join pipeline.provider_fact_sources f on f.id = u.fact_source_id join pipeline.evidence_artifacts e on e.id = f.evidence_id
    join catalogue.providers p on p.id = u.provider_id;
  return v;
end $function$
