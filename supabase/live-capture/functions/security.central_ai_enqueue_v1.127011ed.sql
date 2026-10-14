CREATE OR REPLACE FUNCTION security.central_ai_enqueue_v1(p_provider uuid)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_n int;
begin
  if not coalesce((select s.enabled from pipeline.central_ai_settings s where s.id = 1), false) then return 0; end if;
  insert into pipeline.central_ai_queue(fact_source_id, provider_id, kind, content_hash)
  select f.id, f.provider_id, f.kind, f.content_hash from pipeline.provider_fact_sources f
    join pipeline.evidence_artifacts e on e.id = f.evidence_id and e.storage_path is not null
   where f.provider_id = p_provider and f.kind in ('english_policy', 'intake_calendar') and f.status in ('read', 'parsed', 'no_values')
     and not exists (select 1 from pipeline.provider_policy_proposals pp where pp.fact_source_id = f.id and pp.status in ('proposed', 'approved'))
     and not exists (select 1 from pipeline.central_ai_queue q where q.fact_source_id = f.id and (q.state in ('queued', 'leased') or q.content_hash is not distinct from f.content_hash))
  on conflict do nothing;
  get diagnostics v_n = row_count;
  return v_n;
end $function$
