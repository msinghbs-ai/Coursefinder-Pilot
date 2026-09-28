-- CF-247 / Decision 155 step 5 (R18): duplicate evidence clean-up, proof first.
-- Evidence records are never deleted: every record keeps its own capture time, job and metadata.
-- Where several records of the same source hold byte-identical files (same content hash and size),
-- they are pointed at the first stored copy and the redundant copies are removed from storage.
-- Scope 'layer1' covers regulatory register files only; other scopes need their own approval.
-- Consumer API: not touched.

create table if not exists pipeline.evidence_storage_dedupe_log(
  id bigint generated always as identity primary key,
  path text not null unique,
  keeper_path text not null,
  content_hash text not null,
  bytes bigint,
  source_id uuid,
  scope text not null,
  repointed_rows integer not null,
  status text not null default 'repointed' check (status in ('repointed','deleted','failed')),
  error text,
  created_at timestamptz not null default now(),
  deleted_at timestamptz);
alter table pipeline.evidence_storage_dedupe_log enable row level security;
revoke all on pipeline.evidence_storage_dedupe_log from public, anon, authenticated;

-- Proof (p_apply=false) or apply: repoint duplicate records to the keeper copy and log the freed paths.
create or replace function security.evidence_storage_dedupe_v1(p_scope text default 'layer1', p_apply boolean default false)
returns jsonb language plpgsql security definer set search_path to 'pg_catalog','pipeline','storage' as $f$
declare v_groups int; v_rows int; v_paths int; v_bytes bigint; v_unequal int; v_missing int;
begin
  if p_scope not in ('layer1') then raise exception 'scope % is not approved', p_scope; end if;
  create temp table if not exists t_dd(source_id uuid, content_hash text, id uuid, path text, sz bigint, created_at timestamptz, keeper_path text) on commit drop;
  truncate t_dd;
  insert into t_dd(source_id,content_hash,id,path,sz,created_at)
  select e.source_id, e.content_hash, e.id, e.storage_path, (o.metadata->>'size')::bigint, e.created_at
    from pipeline.evidence_artifacts e
    join pipeline.sources s on s.id=e.source_id
    left join storage.objects o on o.bucket_id='evidence' and o.name=e.storage_path
   where e.content_hash is not null and e.storage_path is not null and e.storage_path !~ '^[a-z-]+://'
     and s.provider_id is null and e.evidence_type='regulatory_snapshot';
  -- keeper: the earliest record whose stored object exists
  update t_dd t set keeper_path=k.path from (
    select distinct on (source_id,content_hash) source_id, content_hash, path from t_dd where sz is not null order by source_id, content_hash, created_at, path) k
   where k.source_id=t.source_id and k.content_hash=t.content_hash;
  -- only groups with more than one distinct path, a keeper, and one identical size
  delete from t_dd t where t.keeper_path is null
     or (select count(distinct path) from t_dd x where x.source_id=t.source_id and x.content_hash=t.content_hash)<2;
  select count(*) into v_unequal from (select source_id,content_hash from t_dd where sz is not null group by 1,2 having count(distinct sz)>1) z;
  delete from t_dd t where exists (select 1 from t_dd x where x.source_id=t.source_id and x.content_hash=t.content_hash and x.sz is not null and x.sz is distinct from (select sz from t_dd k where k.source_id=t.source_id and k.content_hash=t.content_hash and k.path=t.keeper_path limit 1));
  select count(*) into v_missing from t_dd where sz is null and path<>keeper_path;
  select count(distinct (source_id,content_hash)), count(*) filter (where path<>keeper_path), count(distinct path) filter (where path<>keeper_path and sz is not null),
         coalesce(sum(sz) filter (where path<>keeper_path),0)
    into v_groups, v_rows, v_paths, v_bytes from t_dd;
  if p_apply then
    update pipeline.evidence_artifacts e set storage_path=t.keeper_path,
           metadata=coalesce(e.metadata,'{}'::jsonb)||jsonb_build_object('storage_deduplicated_from',t.path,'storage_deduplicated_at',now())
      from t_dd t where t.id=e.id and t.path<>t.keeper_path;
    insert into pipeline.evidence_storage_dedupe_log(path,keeper_path,content_hash,bytes,source_id,scope,repointed_rows)
    select t.path, min(t.keeper_path), min(t.content_hash), max(t.sz), min(t.source_id::text)::uuid, p_scope, count(*)
      from t_dd t where t.path<>t.keeper_path and t.sz is not null
     group by t.path
    on conflict (path) do nothing;
  end if;
  return jsonb_build_object('scope',p_scope,'applied',p_apply,'duplicate_groups',v_groups,'records_repointed',v_rows,'copies_to_remove',v_paths,
    'bytes_to_free',v_bytes,'size_mismatch_groups_skipped',v_unequal,'records_without_object',v_missing);
end $f$;
revoke all on function security.evidence_storage_dedupe_v1(text,boolean) from public, anon, authenticated;

-- Next copies to remove: only paths no longer referenced by any record that stores a path.
create or replace function public.svc_evidence_dedupe_next(p_limit integer default 100)
returns jsonb language sql stable security definer set search_path to 'pg_catalog','pipeline' as $f$
  select coalesce(jsonb_agg(l.path),'[]'::jsonb) from (
    select l.path from pipeline.evidence_storage_dedupe_log l
     where l.status='repointed'
       and not exists (select 1 from pipeline.evidence_artifacts e where e.storage_path=l.path)
       and not exists (select 1 from pipeline.evidence_lineage_reconciliations r where r.storage_path=l.path)
       and not exists (select 1 from ranking.manual_imports m where m.storage_path=l.path)
       and not exists (select 1 from catalogue.provider_assets a where a.storage_path=l.path)
       and not exists (select 1 from pipeline.provider_contact_import_batches b where b.storage_path=l.path)
     order by l.id limit greatest(1,least(coalesce(p_limit,100),500))) l
$f$;
create or replace function public.svc_evidence_dedupe_mark(p_paths text[], p_ok boolean, p_error text default null)
returns integer language sql security definer set search_path to 'pg_catalog','pipeline' as $f$
  with u as (update pipeline.evidence_storage_dedupe_log set status=case when p_ok then 'deleted' else 'failed' end,
             deleted_at=case when p_ok then now() end, error=left(p_error,500) where path=any(p_paths) and status='repointed' returning 1)
  select count(*)::int from u
$f$;
revoke all on function public.svc_evidence_dedupe_next(integer) from public, anon, authenticated;
revoke all on function public.svc_evidence_dedupe_mark(text[],boolean,text) from public, anon, authenticated;
grant execute on function public.svc_evidence_dedupe_next(integer) to service_role;
grant execute on function public.svc_evidence_dedupe_mark(text[],boolean,text) to service_role;

-- Allow the clean-up function to be started with a one-time nonce (checksum-guarded patch).
do $patch$
declare v_def text; v_md5 text;
begin
  v_def:=pg_get_functiondef('pipeline.svc_pilot_submit_nonce(text,jsonb)'::regprocedure);
  if v_def like '%''evidence-storage-dedupe''%' then return; end if;
  v_md5:=md5(v_def);
  if v_md5<>'7a9192017017c49021eab508a0e209c6' then raise exception 'svc_pilot_submit_nonce changed (md5 %); aborting', v_md5; end if;
  if (select count(*) from regexp_matches(v_def,'''layer1-operations-control'',','g'))<>1 then raise exception 'allow-list anchor not found exactly once'; end if;
  execute replace(v_def,'''layer1-operations-control'',','''layer1-operations-control'',''evidence-storage-dedupe'',');
end $patch$;
