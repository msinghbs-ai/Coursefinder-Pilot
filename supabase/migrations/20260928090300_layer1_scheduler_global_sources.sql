-- CF-247 / Layer 1 closure: the scheduled verification only picked up sources with a country, so the
-- global ranking sources (QS, THE) were never re-verified on schedule (THE 2026 was due on 2 Sep 2026 and
-- stayed overdue). They are now due like any other source, with country code GLOBAL; the scheduled worker
-- (layer1-operations-scheduled v1.2.0) verifies them through ranking-layer1-etl. Checksum-guarded.
do $patch$
declare d text; n text;
begin
  d:=pg_get_functiondef('security.layer1_regulatory_scheduler_tick_impl(timestamptz,integer,boolean)'::regprocedure);
  if md5(d)<>'20de040a9f99b73d60b86fc4293f255a' then raise exception 'layer1_regulatory_scheduler_tick_impl changed since review (%); not patched', md5(d); end if;
  n:=replace(d,'select o.source_id,c.iso_alpha2::text country_code from','select o.source_id,coalesce(c.iso_alpha2::text,''GLOBAL'') country_code from');
  n:=replace(n,'join ref.countries c on c.id=s.country_id','left join ref.countries c on c.id=s.country_id');
  if (select count(*) from regexp_matches(n,'coalesce\(c\.iso_alpha2::text,''GLOBAL''\)|left join ref\.countries c','g'))<>2 then raise exception 'scheduler patch points not found as expected'; end if;
  execute n;
end $patch$;
