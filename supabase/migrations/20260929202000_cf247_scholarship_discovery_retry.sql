-- CF-247 scholarship discovery, first run: UWA's site map lists internal Sitecore addresses
-- (/sitecore/content/...) which robots.txt disallows; one was matched to "Global Excellence Scholarship" and could not
-- be read. Sitecore addresses are no longer candidates (worker), and a discovered page that could not be used
-- (name mismatch, robots disallowed, gone) no longer blocks another match for the same scholarship.
do $patch$
declare v text; o text; n text;
begin
  v:=pg_get_functiondef('security.scholarship_page_match_v1(uuid,text,text,bigint)'::regprocedure);
  o:=$o$not (url_source='discovered' and read_status='name_mismatch'))$o$;
  n:=$n$not (url_source='discovered' and read_status in ('name_mismatch','robots_disallowed','gone')))$n$;
  if position(o in v)=0 then raise exception 'match anchor 1 not found'; end if;
  v:=replace(v,o,n);
  o:=$o$delete from pipeline.scholarship_pages where scholarship_id=s.id and url_source='discovered' and read_status='name_mismatch';$o$;
  n:=$n$delete from pipeline.scholarship_pages where scholarship_id=s.id and url_source='discovered' and read_status in ('name_mismatch','robots_disallowed','gone');$n$;
  if position(o in v)=0 then raise exception 'match anchor 2 not found'; end if;
  execute replace(v,o,n);

  v:=pg_get_functiondef('public.svc_scholarship_search_next(int)'::regprocedure);
  o:=$o$not (sp.url_source='discovered' and sp.read_status='name_mismatch'))$o$;
  n:=$n$not (sp.url_source='discovered' and sp.read_status in ('name_mismatch','robots_disallowed','gone')))$n$;
  if position(o in v)=0 then raise exception 'search anchor not found'; end if;
  execute replace(v,o,n);

  v:=pg_get_functiondef('security.scholarship_held_without_page(uuid)'::regprocedure);
  o:=$o$not exists (select 1 from pipeline.scholarship_pages sp where sp.scholarship_id=s.id)$o$;
  n:=$n$not exists (select 1 from pipeline.scholarship_pages sp where sp.scholarship_id=s.id and not (sp.url_source='discovered' and sp.read_status in ('name_mismatch','robots_disallowed','gone')))$n$;
  if position(o in v)=0 then raise exception 'held anchor not found'; end if;
  execute replace(v,o,n);
end $patch$;

-- the Sitecore match is released (logged) and internal Sitecore addresses are removed from the candidates
insert into pipeline.scholarship_sweep_changes(scholarship_id,field,before_value,after_value)
select sp.scholarship_id,'provider_page_rejected',jsonb_build_object('url',sp.url,'url_source',sp.url_source,'read_status',sp.read_status),jsonb_build_object('reason','internal Sitecore address (robots.txt disallowed)')
  from pipeline.scholarship_pages sp where sp.url_source='discovered' and sp.url ~* '/sitecore/';
delete from pipeline.scholarship_pages where url_source='discovered' and url ~* '/sitecore/';
delete from pipeline.scholarship_page_candidates where url ~* '/sitecore/' and admitted_scholarship_id is null;
