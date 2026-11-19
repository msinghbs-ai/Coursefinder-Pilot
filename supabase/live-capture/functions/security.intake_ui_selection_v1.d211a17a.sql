CREATE OR REPLACE FUNCTION security.intake_ui_selection_v1(p_scope text, p_size integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare unis jsonb:=security.intake_ui_scopes_v1(); ids uuid[]; result jsonb; cap integer:=security.pipeline_num_v1('run_now.pilot_cap',20)::int;
begin
 if p_size is null or p_size<1 or p_size>cap then raise exception 'cohort size must be between 1 and %',cap; end if;
 if p_scope is null or not (p_scope='top-au' or exists(select 1 from jsonb_array_elements(unis) u where u->>'id'=p_scope)) then
   raise exception 'invalid scope: select within the approved top Australian universities'; end if;
 ids:=array(select c.id from catalogue.courses c where c.lifecycle_status='active' and c.provider_id in
   (select (u->>'id')::uuid from jsonb_array_elements(unis) u where p_scope='top-au' or u->>'id'=p_scope));
 with all_plan as materialized(
 select p.* from jsonb_array_elements(unis) u
 cross join lateral security.intake_dates_plan_v3(
 array(select c.id from catalogue.courses c where c.provider_id=(u->>'id')::uuid and c.lifecycle_status='active'),
 least(greatest(1,security.pipeline_num_v1('run_now.preview_rows_per_university',5)::int),greatest(1,security.pipeline_num_v1('run_now.cohort_scan_rows',1500)::int / greatest(jsonb_array_length(unis),1)))) p),
 plan as materialized(select * from all_plan where p_scope='top-au' or provider_id::text=p_scope),
 f as(select * from plan where outcome='filled'),
 c as(select course_id,min(provider_id::text)::uuid provider_id,
 array_remove(array[case when bool_or(new_year is not null) then 'year' end,case when bool_or(new_start is not null) then 'start_date' end,case when bool_or(new_deadline is not null) then 'application_deadline' end],null) fills,
 string_agg(distinct coalesce(start_precision,'-')||'/'||coalesce(deadline_kind,'-'),'+' order by coalesce(start_precision,'-')||'/'||coalesce(deadline_kind,'-')) pattern,
 jsonb_agg(jsonb_build_object('intake_id',intake_id,'proposal_id',proposal_id,'calendar_evidence_id',calendar_evidence_id,'calendar_url',calendar_url,
 'page_url',(select e.source_url from catalogue.course_intakes i join pipeline.evidence_artifacts e on e.id=i.evidence_id where i.id=intake_id),'periods',periods,'page_quote',page_quote,'start_quote',start_quote,'deadline_quote',deadline_quote,'deadline_kind',deadline_kind,
 'before',before_value,'planned',jsonb_build_object('year',new_year,'start_date',new_start,'application_deadline',new_deadline),'rule',rule) order by intake_id) at_selection
 from f group by course_id),
 r as(select c.*,row_number() over(partition by provider_id order by cardinality(fills) desc,md5(course_id::text)) rp,
 row_number() over(partition by pattern order by cardinality(fills) desc,md5(course_id::text)) rq from c),
 pick as(select r.*,row_number() over(order by rp,rq,cardinality(fills) desc,md5(course_id::text)) n from r)
 select jsonb_build_object('scope',p_scope,'size',p_size,'cap',cap,'scan_rows',security.pipeline_num_v1('run_now.cohort_scan_rows',1500),
 'universities',(select jsonb_agg(u||jsonb_build_object(
 'scan_limit',least(greatest(1,security.pipeline_num_v1('run_now.preview_rows_per_university',5)::int),greatest(1,security.pipeline_num_v1('run_now.cohort_scan_rows',1500)::int / greatest(jsonb_array_length(unis),1))),
 'rows_planned',(select count(*) from all_plan where provider_id=(u->>'id')::uuid),
 'eligible_courses',(select count(distinct course_id) from all_plan where provider_id=(u->>'id')::uuid and outcome='filled'),
 'eligible_values',(select count(*) from all_plan where provider_id=(u->>'id')::uuid and outcome='filled')) order by (u->>'active_courses')::int desc,md5(u->>'id')) from jsonb_array_elements(unis) u),'scope_courses',cardinality(ids),'rows_planned',(select count(*) from plan),
 'eligible_courses',(select count(distinct course_id) from f),'rows_eligible',(select count(*) from f),
 'skipped_by_reason',(select coalesce(jsonb_object_agg(reason,n),'{}') from(select coalesce(reason,outcome) reason,count(*) n from plan where outcome<>'filled' group by 1) x),
 'rule','Existing intake-dates-plan-v3 filled outcome: official stored page and approved calendar; independent equal-share scan per university; most missing fields first, round-robin universities and evidence patterns; no scope widening',
 'courses',coalesce((select jsonb_agg(jsonb_build_object('course_id',p.course_id,'provider_id',p.provider_id,'pick',p.n,'pattern',p.pattern,'fills',p.fills,
 'course_title',coalesce(cc.display_title,cc.canonical_title),'provider_name',coalesce(pp.display_name,pp.canonical_name),'course_url',cc.course_url,
 'eligibility_reason','The existing intake plan found supported missing values from the stored course wording and an approved calendar; its manual-lock, same-month and admission guards remain authoritative.',
 'at_selection',p.at_selection) order by p.n) from pick p join catalogue.courses cc on cc.id=p.course_id join catalogue.providers pp on pp.id=p.provider_id where p.n<=p_size),'[]')) into result;
 return result;
end $function$
