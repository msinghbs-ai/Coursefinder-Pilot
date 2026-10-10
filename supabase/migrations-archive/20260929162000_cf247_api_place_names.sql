-- CF-247 consumer API: campus localities stored in capitals by the register ("HAWTHORN") are shown in title case
-- ("Hawthorn"); mixed-case names are unchanged. Output only; filters still compare case-insensitively.
create or replace function security.place_presentable(p text)
returns text language sql immutable as $f$
  select case when p is null then null
              when p ~ '[a-z]' or p !~ '[A-Z]' then btrim(p)
              else regexp_replace(initcap(btrim(p)),'\mMc([a-z])','Mc\1','g') end
$f$;
do $patch$
declare v text;
begin
  if (select md5(prosrc) from pg_proc where oid='public.website_edge_course_search_v1(jsonb,int,int)'::regprocedure)<>'a36efb8c473d2d5bc0354631048c8af9' then
    raise exception 'website_edge_course_search_v1 changed since review; not replaced'; end if;
  v:=pg_get_functiondef('public.website_edge_course_search_v1(jsonb,int,int)'::regprocedure);
  v:=replace(v,'select k.city from','select security.place_presentable(k.city) from');
  v:=replace(v,$o$jsonb_build_object('city',k.city,$o$,$n$jsonb_build_object('city',security.place_presentable(k.city),$n$);
  execute v;
end $patch$;
