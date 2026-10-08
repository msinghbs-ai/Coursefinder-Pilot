-- CF-247, 8 Oct 2026: the course-directory sitemap purge failed on its first batch ("column u.id does not exist"):
-- pipeline.coverage_provider_urls has no id column; its key is (provider_id, url). Nothing was removed. The background worker now
-- selects the batch by that key. Patch of security.retention_tick_v1 (migration 2400) behind an md5 guard and two exact anchors.
do $p$
declare d text;
  a1 text := 'pipeline.coverage_provider_urls where id in (';
  a2 text := 'select u.id from pipeline.coverage_provider_urls u join';
begin
  if (select md5(replace(prosrc, E'\r', '')) from pg_proc where oid = 'security.retention_tick_v1()'::regprocedure) is distinct from '1fb619423df88750fc97df5f07794bb0' then
    raise exception 'retention_tick_v1 is not the migration 2400 definition; refusing to patch it';
  end if;
  d := pg_get_functiondef('security.retention_tick_v1()'::regprocedure);
  if (length(d) - length(replace(d, a1, ''))) / length(a1) <> 1 or (length(d) - length(replace(d, a2, ''))) / length(a2) <> 1 then
    raise exception 'an anchor was not found exactly once';
  end if;
  d := replace(d, a1, 'pipeline.coverage_provider_urls where (provider_id, url) in (');
  d := replace(d, a2, 'select u.provider_id, u.url from pipeline.coverage_provider_urls u join');
  execute d;
end $p$;
