-- CF-CHG-20260905-205 — classify legacy no-explicit-scope Scholarship cohorts as semantic-warning groups.

create or replace function public.layer4_scholarship_scope_groups(p_limit integer default 100)
returns jsonb language plpgsql security definer
set search_path='pg_catalog','public','security','pipeline','scholarship','catalogue','auth'
as $$
declare v_actor uuid:=auth.uid(); v_rank int; v jsonb;
begin
 if v_actor is null then raise exception 'authentication required' using errcode='42501'; end if;
 v_rank:=security.current_role_rank(); if v_rank<3 then raise exception 'curator role required' using errcode='42501'; end if;
 with g as (
  select cmc.scholarship_id,cmc.candidate_reason,s.name scholarship_name,s.provider_id,p.canonical_name provider_name,
   count(*) candidate_count,count(cmc.evidence_id) evidence_count,
   count(*) filter(where c.provider_id is distinct from s.provider_id) provider_mismatch_count,
   count(*) filter(where exists(select 1 from scholarship.course_mappings m where m.scholarship_id=cmc.scholarship_id and m.course_id=cmc.course_id)) already_mapped_count,
   count(*) filter(where cmc.updated_at<now()-interval '7 days') stale_count,count(distinct c.study_level_id) study_level_count,
   bool_or(lower(cmc.candidate_reason) ~ '(exclusion|exact|requires governed review|country|eligib|no[_ ]explicit|scope)') semantic_warning,
   min(cmc.updated_at) oldest_at,max(cmc.updated_at) newest_at,(array_agg(c.canonical_title order by c.canonical_title))[1:5] sample_courses
  from scholarship.course_mapping_candidates cmc join scholarship.scholarships s on s.id=cmc.scholarship_id join catalogue.providers p on p.id=s.provider_id join catalogue.courses c on c.id=cmc.course_id
  where cmc.status='needs_review' group by cmc.scholarship_id,cmc.candidate_reason,s.name,s.provider_id,p.canonical_name order by count(*) desc,s.name limit greatest(1,least(coalesce(p_limit,100),250))
 ) select coalesce(jsonb_agg(jsonb_build_object('group_id',md5(scholarship_id::text||'|'||candidate_reason),'scholarship_id',scholarship_id,'scholarship_name',scholarship_name,'provider_id',provider_id,'provider_name',provider_name,'candidate_reason',candidate_reason,'candidate_count',candidate_count,'evidence_count',evidence_count,'provider_mismatch_count',provider_mismatch_count,'already_mapped_count',already_mapped_count,'stale_count',stale_count,'study_level_count',study_level_count,'semantic_warning',semantic_warning,'structural_ready',(evidence_count=candidate_count and provider_mismatch_count=0),'oldest_at',oldest_at,'newest_at',newest_at,'sample_courses',to_jsonb(sample_courses))),'[]'::jsonb) into v from g;
 return v;
end $$;

create or replace function public.layer4_scholarship_scope_preview(p_scholarship_id uuid,p_candidate_reason text)
returns jsonb language plpgsql security definer
set search_path='pg_catalog','public','security','pipeline','scholarship','catalogue','auth'
as $$
declare v_actor uuid:=auth.uid();v_rank int;v_count int;v_evidence int;v_mismatch int;v_mapped int;v_sample jsonb;v_name text;v_provider text;
begin
 if v_actor is null then raise exception 'authentication required' using errcode='42501'; end if; v_rank:=security.current_role_rank();if v_rank<3 then raise exception 'curator role required' using errcode='42501';end if;
 select count(*),count(cmc.evidence_id),count(*) filter(where c.provider_id is distinct from s.provider_id),count(*) filter(where exists(select 1 from scholarship.course_mappings m where m.scholarship_id=cmc.scholarship_id and m.course_id=cmc.course_id)),max(s.name),max(p.canonical_name) into v_count,v_evidence,v_mismatch,v_mapped,v_name,v_provider from scholarship.course_mapping_candidates cmc join scholarship.scholarships s on s.id=cmc.scholarship_id join catalogue.providers p on p.id=s.provider_id join catalogue.courses c on c.id=cmc.course_id where cmc.status='needs_review' and cmc.scholarship_id=p_scholarship_id and cmc.candidate_reason=p_candidate_reason;
 select coalesce(jsonb_agg(x),'[]'::jsonb) into v_sample from(select jsonb_build_object('course_id',c.id,'course_title',c.canonical_title,'course_code',c.course_code,'has_evidence',cmc.evidence_id is not null,'already_mapped',exists(select 1 from scholarship.course_mappings m where m.scholarship_id=cmc.scholarship_id and m.course_id=cmc.course_id),'provider_match',c.provider_id=s.provider_id)x from scholarship.course_mapping_candidates cmc join scholarship.scholarships s on s.id=cmc.scholarship_id join catalogue.courses c on c.id=cmc.course_id where cmc.status='needs_review' and cmc.scholarship_id=p_scholarship_id and cmc.candidate_reason=p_candidate_reason order by c.canonical_title limit 20)q;
 return jsonb_build_object('ok',true,'scholarship_id',p_scholarship_id,'scholarship_name',v_name,'provider_name',v_provider,'candidate_reason',p_candidate_reason,'candidate_count',v_count,'evidence_count',v_evidence,'missing_evidence_count',v_count-v_evidence,'provider_mismatch_count',v_mismatch,'already_mapped_count',v_mapped,'semantic_warning',lower(coalesce(p_candidate_reason,'')) ~ '(exclusion|exact|requires governed review|country|eligib|no[_ ]explicit|scope)','structural_ready',(v_count>0 and v_evidence=v_count and v_mismatch=0),'accept_confirmation','ACCEPT '||v_count,'reject_confirmation','REJECT '||v_count,'sample',v_sample,'publication_changed',false);
end $$;
