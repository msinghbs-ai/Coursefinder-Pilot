do $$
declare
  v_oid oid;
  v_def text;
  v_old text := $old$  select id into v_pub_id from ranking.publisher_institutions where system_id=v_system_id and lower(institution_name)=lower(v_name) and lower(coalesce(country_text,''))=lower(coalesce(v_country,'')) limit 1;$old$;
  v_new text := $new$  v_pub_id:=null;
  if nullif(v_row->>'publisher_institution_id','') is not null then
   select id into v_pub_id from ranking.publisher_institutions
   where system_id=v_system_id and publisher_institution_id=nullif(v_row->>'publisher_institution_id','')
   limit 1;
  end if;
  if v_pub_id is null then
   select id into v_pub_id from ranking.publisher_institutions
   where system_id=v_system_id and lower(institution_name)=lower(v_name)
     and lower(coalesce(country_text,''))=lower(coalesce(v_country,''))
   limit 1;
  end if;$new$;
begin
  select p.oid into v_oid
  from pg_proc p join pg_namespace n on n.oid=p.pronamespace
  where n.nspname='public' and p.proname='svc_ranking_ingest_apply'
  limit 1;
  if v_oid is null then raise exception 'svc_ranking_ingest_apply not found'; end if;
  v_def:=pg_get_functiondef(v_oid);
  if position(v_new in v_def)>0 then return; end if;
  if position(v_old in v_def)=0 then raise exception 'expected ingest lookup fragment not found; refusing unbounded rewrite'; end if;
  v_def:=replace(v_def,v_old,v_new);
  execute v_def;
end $$;
