-- CF-247 coverage sweep v0.5.0: re-extraction from the stored page (evidence) when the extractor improves, without
-- fetching the page again. Pages read by an older extractor version are re-extracted in batches (cron every minute).
create or replace function public.svc_coverage_reextract_next(p_limit int, p_version text)
returns jsonb language plpgsql security definer set search_path to 'pg_catalog','catalogue','pipeline' as $f$
declare v jsonb;
begin
  if current_user<>'postgres' and coalesce(auth.role(),'')<>'service_role' then raise exception 'service_role required'; end if;
  select coalesce(jsonb_agg(jsonb_build_object('course_id',cp.course_id,'storage_path',e.storage_path,'title',c.canonical_title,'code',c.course_code,'status',cp.status,'url',cp.url)),'[]'::jsonb)
    into v
    from (select * from pipeline.coverage_course_pages cp0
           where cp0.read_status='read' and cp0.identity_basis is not null and cp0.evidence_id is not null
             and coalesce(cp0.candidates->>'extractor','')<>p_version
           order by cp0.read_at limit greatest(1,least(coalesce(p_limit,50),200))) cp
    join pipeline.evidence_artifacts e on e.id=cp.evidence_id join catalogue.courses c on c.id=cp.course_id;
  return v;
end $f$;
revoke all on function public.svc_coverage_reextract_next(int,text) from public, anon, authenticated;
grant execute on function public.svc_coverage_reextract_next(int,text) to service_role;

create or replace function public.svc_coverage_candidates_update(p_course_id uuid, p_candidates jsonb)
returns void language plpgsql security definer set search_path to 'pg_catalog','pipeline' as $f$
begin
  if current_user<>'postgres' and coalesce(auth.role(),'')<>'service_role' then raise exception 'service_role required'; end if;
  update pipeline.coverage_course_pages set candidates=p_candidates||jsonb_build_object('final_url',coalesce(candidates->>'final_url',p_candidates->>'final_url'))
   where course_id=p_course_id and read_status='read';
end $f$;
revoke all on function public.svc_coverage_candidates_update(uuid,jsonb) from public, anon, authenticated;
grant execute on function public.svc_coverage_candidates_update(uuid,jsonb) to service_role;

select cron.schedule('coverage-reextract','* * * * *',$$select pipeline.svc_pilot_submit_nonce('coverage-sweep','{"mode":"reextract","limit":150}'::jsonb)$$);
