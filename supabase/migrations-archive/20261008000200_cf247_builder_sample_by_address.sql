-- CF-247, 8 Oct 2026: Use as sample also takes a page address with the provider (the adapter's course list shows pages by address), and the
-- builder sample setting moves from 3 to 6 (applied with 20261008000100; recorded here).
update pipeline.platform_toolset_settings set value = '6'::jsonb where toolset_key = 'firecrawl' and key = 'builder_samples' and value = '3'::jsonb;
do $p$
declare d text;
begin
  d := pg_get_functiondef('public.admin_adapter_builder(text,jsonb)'::regprocedure);
  if md5(d) <> 'ae42f698a266888bef526a54507061d6' then raise exception 'admin_adapter_builder is not the version this migration expects'; end if;
  if strpos(d, $a$     where pg.course_id = v_cid and pg.url is not null order by (pg.read_status = 'read') desc limit 1;$a$) = 0 then raise exception 'anchor not found'; end if;
  d := replace(d, $a$     where pg.course_id = v_cid and pg.url is not null order by (pg.read_status = 'read') desc limit 1;$a$,
                  $b$     where pg.url is not null and (pg.course_id = v_cid or (v_cid is null and pg.provider_id = v_pid and pg.url = nullif(p_args->>'url', '')))
     order by (pg.read_status = 'read') desc limit 1;$b$);
  execute d;
end $p$;
