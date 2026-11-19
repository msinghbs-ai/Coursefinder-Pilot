create or replace function public.svc_qs_official_compact_apply(
 p_edition_year integer,
 p_source_artifact_id uuid,
 p_source_url text,
 p_source_hash text,
 p_rows jsonb
) returns jsonb
language plpgsql security definer
set search_path to pg_catalog,public,ranking
as $$
declare v_full jsonb; v_result jsonb;
begin
 if current_user not in ('service_role','postgres') then raise exception 'service role required' using errcode='42501'; end if;
 if jsonb_typeof(coalesce(p_rows,'[]'::jsonb))<>'array' then raise exception 'rows must be array' using errcode='22023'; end if;
 select coalesce(jsonb_agg(jsonb_build_object(
   'institution_name',r->>'n','country_text',nullif(r->>'c',''),'location_text',nullif(r->>'l',''),
   'rank_display',nullif(r->>'r',''),'rank_exact',r->'x','rank_low',r->'lo','rank_high',r->'hi','is_tied',coalesce((r->>'t')::boolean,false),'rank_status',coalesce(r->>'s','unknown'),
   'overall_score',r->'o','overall_score_display',case when r->'o' is null or r->'o'='null'::jsonb then null else trim(both '"' from (r->'o')::text) end,
   'overall_score_low',null,'overall_score_high',null,'source_row_ordinal',nullif(r->>'q','')::integer,
   'publisher_institution_id',null,'profile_url',null,
   'indicators',coalesce((select jsonb_object_agg(e.key,jsonb_build_object(
      'label',case e.key when 'academic_reputation' then 'Academic Reputation' when 'employer_reputation' then 'Employer Reputation' when 'faculty_student_ratio' then 'Faculty Student Ratio' when 'citations_per_faculty' then 'Citations per Faculty' when 'international_faculty_ratio' then 'International Faculty Ratio' when 'international_student_ratio' then 'International Student Ratio' when 'international_student_diversity' then 'International Student Diversity' when 'international_research_network' then 'International Research Network' when 'employment_outcomes' then 'Employment Outcomes' when 'sustainability' then 'Sustainability' else e.key end,
      'value_numeric',e.value->0,'value_display',case when e.value->0 is null or e.value->0='null'::jsonb then null else trim(both '"' from (e.value->0)::text) end,'unit','score','methodology_version',p_edition_year::text
   )) from jsonb_each(coalesce(r->'i','{}'::jsonb)) e),'{}'::jsonb),
   'source_row_payload',jsonb_build_object('qs_official_workbook',true,'previous_rank',r->'p','indicator_rank',coalesce(r->'ir','{}'::jsonb),'classification',coalesce(r->'cl','{}'::jsonb))
  ) order by ord),'[]'::jsonb)
 into v_full
 from jsonb_array_elements(p_rows) with ordinality a(r,ord);
 select public.svc_ranking_ingest_apply('qs_wur',p_edition_year,p_source_url,null,p_source_artifact_id,p_source_hash,'official_qs_xlsx',v_full) into v_result;
 return v_result;
end $$;
revoke all on function public.svc_qs_official_compact_apply(integer,uuid,text,text,jsonb) from public,anon,authenticated;
grant execute on function public.svc_qs_official_compact_apply(integer,uuid,text,text,jsonb) to service_role;
