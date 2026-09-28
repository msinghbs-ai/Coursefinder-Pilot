-- CF-247 / R23 (approved 28 Sep 2026): duplicate Layer 2 evidence clean-up, same method as R18.
-- Scope 'layer2' covers provider-page screenshots and HTML snapshots only. Every evidence record is
-- kept with its own capture time, URL, job and metadata (the proof of when a page was seen); records
-- whose file is byte-identical to an earlier capture of the same provider source are pointed at that
-- first stored copy, and only the redundant copies are removed from storage.
-- Other Layer 2 types (extraction inputs, raw JSON, documents) have no duplicates and stay out of scope.
-- Consumer API: not touched.
do $patch$
declare d text; n text;
begin
  d:=pg_get_functiondef('security.evidence_storage_dedupe_v1(text,boolean)'::regprocedure);
  if md5(d)<>'b748100227c68629580be364ececdb2a' then raise exception 'evidence_storage_dedupe_v1 changed since review (%); not patched', md5(d); end if;
  n:=replace(d,$a$if p_scope not in ('layer1') then$a$,$a$if p_scope not in ('layer1','layer2') then$a$);
  n:=replace(n,$a$and s.provider_id is null and e.evidence_type='regulatory_snapshot';$a$,
    $a$and ((p_scope='layer1' and s.provider_id is null and e.evidence_type='regulatory_snapshot')
       or (p_scope='layer2' and s.provider_id is not null and e.evidence_type in ('layer2_screenshot','layer2_html_snapshot')));$a$);
  if n=d or (length(n)-length(d))<100 then raise exception 'patch points not found'; end if;
  execute n;
end $patch$;

-- The Layer 2 set is about 17,000 records, which made the row-by-row group checks too slow.
-- Same rules, computed per group in one pass (checksum-guarded against the patched definition above).
do $guard$
begin
  if md5(pg_get_functiondef('security.evidence_storage_dedupe_v1(text,boolean)'::regprocedure))<>'7ff7b011ce449943fa081beec6e93aa8' then
    raise exception 'evidence_storage_dedupe_v1 changed since review; not replaced'; end if;
end $guard$;

create or replace function security.evidence_storage_dedupe_v1(p_scope text default 'layer1', p_apply boolean default false)
returns jsonb language plpgsql security definer set search_path to 'pg_catalog','pipeline','storage' as $f$
declare v_groups int; v_rows int; v_paths int; v_bytes bigint; v_unequal int; v_missing int;
begin
  if p_scope not in ('layer1','layer2') then raise exception 'scope % is not approved', p_scope; end if;
  create temp table if not exists t_dd(source_id uuid, content_hash text, id uuid, path text, sz bigint, created_at timestamptz, keeper_path text) on commit drop;
  truncate t_dd;
  insert into t_dd(source_id,content_hash,id,path,sz,created_at)
  select e.source_id, e.content_hash, e.id, e.storage_path, (o.metadata->>'size')::bigint, e.created_at
    from pipeline.evidence_artifacts e
    join pipeline.sources s on s.id=e.source_id
    left join storage.objects o on o.bucket_id='evidence' and o.name=e.storage_path
   where e.content_hash is not null and e.storage_path is not null and e.storage_path !~ '^[a-z-]+://'
     and ((p_scope='layer1' and s.provider_id is null and e.evidence_type='regulatory_snapshot')
       or (p_scope='layer2' and s.provider_id is not null and e.evidence_type in ('layer2_screenshot','layer2_html_snapshot')));
  create index if not exists t_dd_group on t_dd(source_id,content_hash);
  analyze t_dd;
  -- keeper: the earliest record whose stored object exists
  update t_dd t set keeper_path=k.path from (
    select distinct on (source_id,content_hash) source_id, content_hash, path from t_dd where sz is not null order by source_id, content_hash, created_at, path) k
   where k.source_id=t.source_id and k.content_hash=t.content_hash;
  -- group facts: distinct paths, keeper size, and whether any stored copy differs in size
  create temp table if not exists t_dd_g(source_id uuid, content_hash text, paths int, keeper_sz bigint, sizes int) on commit drop;
  truncate t_dd_g;
  insert into t_dd_g
  select t.source_id, t.content_hash, count(distinct t.path), max(t.sz) filter (where t.path=t.keeper_path), count(distinct t.sz)
    from t_dd t group by 1,2;
  select count(*) into v_unequal from t_dd_g where sizes>1;
  -- only groups with more than one distinct path, a keeper, and one identical size
  delete from t_dd t using t_dd_g g
   where g.source_id=t.source_id and g.content_hash=t.content_hash
     and (t.keeper_path is null or g.paths<2 or g.sizes>1);
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
