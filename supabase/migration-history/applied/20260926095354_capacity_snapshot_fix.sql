create index if not exists evidence_artifacts_storage_path_idx on pipeline.evidence_artifacts(storage_path);
do $patch$
declare d text; n int;
  old_cond constant text := 'where e.storage_path=o.name or e.storage_path=(''evidence/''||o.name)';
  new_cond constant text := 'where e.storage_path in (o.name, ''evidence/''||o.name)';
begin
  select pg_get_functiondef(p.oid) into d from pg_proc p join pg_namespace ns on ns.oid=p.pronamespace
   where ns.nspname='security' and p.proname='platform_capacity_snapshot_internal';
  if md5(d) <> 'a799f708ff56c74a00a94b8f2edea7d1' then raise exception 'platform_capacity_snapshot_internal changed since review (md5 %)', md5(d); end if;
  n := (length(d)-length(replace(d,old_cond,'')))/length(old_cond);
  if n <> 3 then raise exception 'expected 3 occurrences, found %', n; end if;
  execute replace(d, old_cond, new_cond);
end $patch$;
