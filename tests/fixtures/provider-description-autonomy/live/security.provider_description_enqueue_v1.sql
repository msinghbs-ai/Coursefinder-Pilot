CREATE OR REPLACE FUNCTION security.provider_description_enqueue_v1()
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_n int;
begin
  if security.pipeline_num_v1('pdesc.enabled', 0) < 1 then return 0; end if;
  insert into pipeline.provider_description_reads(provider_id)
  select p.id from catalogue.providers p
   where security.provider_description_scope_v1(p.id)
     and not exists (select 1 from security.provider_hidden_v1 h where h.provider_id = p.id)
     and not exists (select 1 from pipeline.manual_locks l where l.entity = 'provider' and l.entity_id = p.id and l.field in ('description', 'p_description', 'all'))
     and not exists (select 1 from pipeline.provider_description_reads r where r.provider_id = p.id
                      and (r.state in ('queued', 'reading', 'proposed', 'dead_letter')
                           or (r.state in ('held', 'rejected') and r.updated_at > now() - make_interval(days => security.pipeline_num_v1('pdesc.recheck_days', 180)::int))
                           or (r.state in ('admitted', 'verified') and coalesce(r.last_verified_at, r.updated_at) > now() - make_interval(days => security.pipeline_num_v1('pdesc.recheck_days', 180)::int))))
     and (nullif(btrim(p.description), '') is null
          or exists (select 1 from pipeline.provider_description_reads r2 where r2.provider_id = p.id and r2.state in ('admitted', 'verified')))
   order by (nullif(btrim(p.description), '') is not null), coalesce(p.display_name, p.canonical_name)
   limit greatest(1, security.pipeline_num_v1('pdesc.queue_per_run', 10)::int)
  on conflict do nothing;
  get diagnostics v_n = row_count;
  return v_n;
end $function$

