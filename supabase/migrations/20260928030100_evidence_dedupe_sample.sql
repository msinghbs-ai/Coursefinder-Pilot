-- CF-247 / Decision 155 step 5: random sample of logged copies for byte-for-byte verification before removal.
create or replace function public.svc_evidence_dedupe_sample(p_limit integer default 10)
returns jsonb language sql volatile security definer set search_path to 'pg_catalog','pipeline' as $f$
  select coalesce(jsonb_agg(jsonb_build_object('path',path,'keeper_path',keeper_path,'content_hash',content_hash)),'[]'::jsonb)
  from (select path, keeper_path, content_hash from pipeline.evidence_storage_dedupe_log where status='repointed' order by random() limit greatest(1,least(coalesce(p_limit,10),30))) s
$f$;
revoke all on function public.svc_evidence_dedupe_sample(integer) from public, anon, authenticated;
grant execute on function public.svc_evidence_dedupe_sample(integer) to service_role;
