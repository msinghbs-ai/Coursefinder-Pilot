do $patch$
declare d text; n text;
begin
  d:=pg_get_functiondef('security.layer1_regulatory_scheduler_tick_impl(timestamptz,integer,boolean)'::regprocedure);
  if md5(d)<>'20de040a9f99b73d60b86fc4293f255a' then raise exception 'layer1_regulatory_scheduler_tick_impl changed since review (%); not patched', md5(d); end if;
  n:=replace(d,'select o.source_id,c.iso_alpha2::text country_code','select o.source_id,coalesce(c.iso_alpha2::text,''GLOBAL'') country_code');
  n:=replace(n,'join ref.countries c on c.id=s.country_id','left join ref.countries c on c.id=s.country_id');
  if (select count(*) from regexp_matches(n,'coalesce\(c\.iso_alpha2::text,''GLOBAL''\)|left join ref\.countries c','g'))<>2 then raise exception 'scheduler patch points not found as expected'; end if;
  execute n;
end $patch$;
