-- CF-247 scholarship discovery, step-2 hand-check (29 Sep 2026): five admitted pages were not single scholarships -
-- two University of Sydney faculty listings, two University of Canberra articles ("The impact of a scholarship",
-- "Your introduction to UC's international scholarships") and a University of Newcastle information page ("Costs and
-- scholarships"). Extractor scholarship-sweep-v0.4.4 excludes these classes, and an admitted page read again is checked
-- against the admission rules: one that no longer meets them is withdrawn here (lifecycle inactive, sweep course links
-- removed, logged) instead of applied. Nothing is published. All admitted pages are read again now.
create or replace function security.scholarship_admission_withdraw_v1(p_scholarship_id uuid, p_reason jsonb)
returns jsonb language plpgsql security definer set search_path to 'pg_catalog','scholarship','pipeline','search' as $f$
declare s record; v_courses uuid[];
begin
  select * into s from scholarship.scholarships where id=p_scholarship_id for update;
  if s.id is null or s.lifecycle_status<>'active' then return jsonb_build_object('withdrawn',false); end if;
  if s.publication_status='published' then return jsonb_build_object('withdrawn',false,'reason','published; left for the publication review'); end if;
  if not exists (select 1 from pipeline.scholarship_pages where scholarship_id=s.id and url_source='admitted') then return jsonb_build_object('withdrawn',false,'reason','not admitted from a provider page'); end if;
  select coalesce(array_agg(course_id),'{}') into v_courses from scholarship.course_mappings where scholarship_id=s.id and mapping_basis='sweep_level_field_scope';
  delete from scholarship.course_mappings where scholarship_id=s.id and mapping_basis='sweep_level_field_scope';
  update scholarship.scholarships set lifecycle_status='inactive', updated_at=now() where id=s.id;
  update pipeline.scholarship_page_candidates set admit_status='withdrawn', admit_reasons=array(select jsonb_array_elements_text(coalesce(p_reason->'reasons','[]'))) where admitted_scholarship_id=s.id;
  insert into pipeline.scholarship_sweep_changes(scholarship_id,field,before_value,after_value) values (s.id,'admission_withdrawn',jsonb_build_object('lifecycle_status','active'),p_reason);
  insert into pipeline.scholarship_admission_log(scholarship_id,provider_id,action,detail) values (s.id,s.provider_id,'withdrawn',p_reason);
  if cardinality(v_courses)>0 then perform search.refresh_course_enrichment_scoped_v1(v_courses,true); end if;
  return jsonb_build_object('withdrawn',true);
end $f$;
revoke all on function security.scholarship_admission_withdraw_v1(uuid,jsonb) from public, anon, authenticated;

do $patch$
declare v text; o text; n text;
begin
  if (select md5(prosrc) from pg_proc where oid='public.svc_scholarship_read_record(uuid,text,int,text,text,text,text,jsonb)'::regprocedure)<>'783247d1d82e0f4a06f61fe295a1dc2e' then
    raise exception 'svc_scholarship_read_record changed since review; not replaced'; end if;
  v:=pg_get_functiondef('public.svc_scholarship_read_record(uuid,text,int,text,text,text,text,jsonb)'::regprocedure);
  o:=$o$  if p_read_status='read' then r:=security.scholarship_sweep_apply_v1(p_scholarship_id); end if;$o$;
  n:=$n$  -- an admitted page that no longer meets the admission rules is withdrawn, not applied
  if p_read_status='read' and p_facts ? 'admission' and coalesce((p_facts->'admission'->>'admit')::boolean,true) is false
     and exists (select 1 from pipeline.scholarship_pages where scholarship_id=p_scholarship_id and url_source='admitted') then
    r:=security.scholarship_admission_withdraw_v1(p_scholarship_id, jsonb_build_object('reasons',p_facts->'admission'->'reasons','extractor',p_facts->>'extractor'));
  elsif p_read_status='read' then r:=security.scholarship_sweep_apply_v1(p_scholarship_id); end if;$n$;
  if position(o in v)=0 then raise exception 'read_record anchor not found'; end if;
  execute replace(v,o,n);
end $patch$;

update pipeline.scholarship_pages set next_read_at=now(), attempts=0, leased_until=null where url_source='admitted';
-- candidates rejected or admitted by earlier extractors are not read again; only unread candidates continue.
