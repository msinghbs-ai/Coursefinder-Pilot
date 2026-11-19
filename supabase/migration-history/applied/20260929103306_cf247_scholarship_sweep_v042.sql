-- CF-247 scholarship discovery hand-check (29 Sep 2026) of the first admitted and matched pages:
--  * HonduFuturo-RMIT (and GuateFuturo-RMIT) Joint Scholarship: full tuition for PhD but 20% for coursework, given 100%;
--  * College of Design and Social Context Student Bursary: "(excluding Master by Research or PhD)" read as research;
--  * RMIT Vietnam Alumni Postgraduate Scholarship: the undergraduate degree already completed read as a level.
-- Extractor scholarship-sweep-v0.4.2 fixes these error classes (full tuition only with no other percentage; a level in
-- the scholarship's title decides; excluded levels and earlier study ignored). Values and course links the sweep applied
-- to discovered and admitted pages are reverted (logged) and those pages are read again with v0.4.2.
-- Candidate reads also rotate across universities (one page per university in turn, "international" pages first).
create or replace function public.svc_scholarship_candidate_next(p_limit int)
returns jsonb language plpgsql security definer set search_path to 'pg_catalog','pipeline','security' as $f$
declare v jsonb;
begin
  if current_user<>'postgres' and coalesce(auth.role(),'')<>'service_role' then raise exception 'service_role required'; end if;
  with ranked as (
    select c.id, d.priority, row_number() over (partition by c.provider_id order by (c.url ~* 'international') desc, c.found_at, c.id) rn
      from pipeline.scholarship_page_candidates c join pipeline.scholarship_discovery_providers d on d.provider_id=c.provider_id
     where c.matched_scholarship_id is null and c.admit_status is null and c.next_read_at<=now() and coalesce(c.leased_until,'-infinity')<now() and c.attempts<3
       and security.australian_university(c.provider_id)),
  pick as (
    select c.id from pipeline.scholarship_page_candidates c join ranked r on r.id=c.id
     order by r.rn, (r.priority not in (0,3)), c.id
     limit greatest(1,least(coalesce(p_limit,30),60)) for update of c skip locked),
  upd as (update pipeline.scholarship_page_candidates c set leased_until=now()+interval '5 minutes', attempts=c.attempts+1 from pick where c.id=pick.id
          returning c.id, c.url, c.provider_id)
  select coalesce(jsonb_agg(jsonb_build_object('candidate_id',u.id,'url',u.url,'provider_id',u.provider_id,
           'site',(select coalesce(site_origin,website) from pipeline.scholarship_discovery_providers d where d.provider_id=u.provider_id),
           'hosts',(select to_jsonb(allowed_hosts) from pipeline.scholarship_discovery_providers d where d.provider_id=u.provider_id))),'[]'::jsonb)
    into v from upd u;
  return v;
end $f$;

-- revert what the sweep applied to discovered and admitted pages read before v0.4.2, then read them again
do $rv$
declare v_ids uuid[]; v_courses uuid[];
begin
  select coalesce(array_agg(sp.scholarship_id),'{}') into v_ids from pipeline.scholarship_pages sp
   where sp.url_source in ('discovered','admitted') and sp.read_status='read' and coalesce(sp.facts->>'extractor','') in ('scholarship-sweep-v0.4.0','scholarship-sweep-v0.4.1');
  with ch as (select distinct on (scholarship_id) scholarship_id, before_value from pipeline.scholarship_sweep_changes
               where field='award_value' and scholarship_id=any(v_ids) order by scholarship_id, id)
  update scholarship.scholarships s set award_value_type=coalesce(ch.before_value->>'type','text_only'), award_percentage=null, award_amount=null,
         award_currency_code=null, award_applies_to_fee_type=null, award_value_text=ch.before_value->>'text', updated_at=now()
    from ch where s.id=ch.scholarship_id;
  insert into pipeline.scholarship_sweep_changes(scholarship_id,field,before_value,after_value)
  select distinct scholarship_id,'revert','{"reason":"discovery hand-check; re-read with scholarship-sweep-v0.4.2"}'::jsonb,null::jsonb
    from pipeline.scholarship_sweep_changes where scholarship_id=any(v_ids) and field in ('award_value','course_links');
  select coalesce(array_agg(distinct course_id),'{}') into v_courses from scholarship.course_mappings where scholarship_id=any(v_ids) and mapping_basis='sweep_level_field_scope';
  delete from scholarship.course_mappings where scholarship_id=any(v_ids) and mapping_basis='sweep_level_field_scope';
  delete from scholarship.scopes sc using pipeline.sources src where sc.source_id=src.id and src.source_type='provider_course_page_sweep' and sc.scope_type='study_level' and sc.scholarship_id=any(v_ids);
  if cardinality(v_courses)>0 then perform search.refresh_course_enrichment_scoped_v1(v_courses,true); end if;
  update pipeline.scholarship_pages set next_read_at=now(), applied_at=null, apply_result=null, attempts=0, leased_until=null where scholarship_id=any(v_ids);
end $rv$;
