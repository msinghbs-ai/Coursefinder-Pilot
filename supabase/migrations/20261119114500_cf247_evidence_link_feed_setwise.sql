-- CF-247 s720 follow-up (S2-Build; Platform Admin 19 Nov 2026 11:42, critical alert on evidence-link-index, IQ-00348).
--
-- What was read (19 Nov 2026 11:45-11:47 AEDT, rolled-back read-backs through the dry-run workflow):
--   * evidence-link-index returns 500 "svc_evidence_link_index_next_v1: canceling statement due to statement timeout" (PostgREST roles have
--     statement_timeout 8 s). The feed took 9.5 s and returned nothing.
--   * The queue of ranked providers is drained: 165,657 eligible artifacts, 46,597 not indexed, none of them of a ranked provider
--     (layer2_onboarding_snapshot, 1,121 providers). The keyset walk of 20261119104500 sorts every ranked provider's artifacts by capture time
--     before finding that, so an empty queue is the slowest case. The same artifacts read as one anti-join take 0.45 s.
-- What it changes (CREATE OR REPLACE of the existing function, guarded by its live body md5; same signature, same rows; no table or function;
-- the consumer API is not touched, G3 75/48):
--   public.svc_evidence_link_index_next_v1 reads the ranked providers' eligible artifacts as one set (the partial index
--   evidence_artifacts_link_queue_idx), drops those already indexed (or in error for less than 6 hours) with one anti-join, and orders only what
--   is left by provider rank and capture time. It stops itself at 4 s (statement_timeout), inside the 8 s gateway limit.
-- Replaces: the per-provider keyset walk of 20261119104500.
-- Retires: nothing.

do $g$ begin
  if md5((select prosrc from pg_proc where oid = 'public.svc_evidence_link_index_next_v1(integer)'::regprocedure)) <> 'ff9d9bc6d96f61f076871ab4d9e33ce0'
     and position('20261119114500' in (select prosrc from pg_proc where oid = 'public.svc_evidence_link_index_next_v1(integer)'::regprocedure)) = 0 then
    raise exception 'live public.svc_evidence_link_index_next_v1 differs from the definition this change replaces';
  end if;
end $g$;

create or replace function public.svc_evidence_link_index_next_v1(p_limit integer default 60)
 returns jsonb
 language sql
 stable security definer
 set search_path to 'pg_catalog', 'pipeline'
 set statement_timeout to '4s'  -- fixed: a query time-out inside the 8 s gateway limit, so a slow read fails fast instead of at the gateway
as $function$
  -- 20261119114500 (s720, IQ-00348): the ranked providers' eligible artifacts as one set, those already indexed dropped by one anti-join, and only
  -- what is left ordered by provider rank and capture time (an empty queue is now the fastest case; was a per-provider sort, 9.5 s)
  select coalesce(jsonb_agg(jsonb_build_object('id',x.id,'path',x.storage_path,'mime',x.mime_type,'url',x.source_url,'type',x.evidence_type)
                            order by x.rank_no, x.captured_at desc nulls last),'[]'::jsonb)
  from (select e.id, e.storage_path, e.mime_type, e.source_url, e.evidence_type, e.captured_at, o.rank_no
          from pipeline.layer2_onboarding_snapshot o
          join pipeline.sources s on s.provider_id = o.provider_id
          join pipeline.evidence_artifacts e on e.source_id = s.id
         where e.storage_path is not null and e.storage_path !~ '^[a-z-]+://'
           and e.evidence_type = any (array['layer2_html_snapshot','layer2_extraction_input','source_snapshot','provider_contact_html_snapshot'])
           and (e.mime_type ~~* '%html%' or e.mime_type ~~* '%json%')
           and not exists (select 1 from pipeline.evidence_link_index_state st
                            where st.evidence_id = e.id and not (st.status = 'error' and st.indexed_at < now() - interval '6 hours'))  -- fixed: the retry wait the function had
         order by o.rank_no, e.captured_at desc nulls last
         limit greatest(1, least(coalesce(p_limit, 60), 200))) x
$function$;

-- post-checks
do $c$
declare v_drift jsonb; v_t timestamptz := clock_timestamp(); v_n int;
begin
  v_n := jsonb_array_length(public.svc_evidence_link_index_next_v1(60));
  if extract(epoch from clock_timestamp() - v_t) > 3 then
    raise exception 'svc_evidence_link_index_next_v1 took % s (limit 3 s)', round(extract(epoch from clock_timestamp() - v_t)::numeric, 2);
  end if;
  v_drift := security.consumer_api_check_v1();
  if jsonb_array_length(coalesce(v_drift->'drift', '[]'::jsonb)) > 0 then raise exception 'consumer API drift: %', v_drift->'drift'; end if;
end $c$;
