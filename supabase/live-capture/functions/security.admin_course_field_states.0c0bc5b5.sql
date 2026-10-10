CREATE OR REPLACE FUNCTION security.admin_course_field_states(p_course_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'catalogue', 'pipeline', 'pim', 'ref', 'security', 'auth'
AS $function$
declare
  c catalogue.courses%rowtype;
  v_l4 text[]:=array[]::text[];
  v_codes text[];
  v_domains text[]:=array[]::text[];
  v_course_url text; v_url_ev uuid;
  v_fee record; v_fee_l3 record; v_reg_tuition int:=0; v_l3_open text;
  v_mode_count int:=0; v_intake_count int:=0; v_english_count int:=0; v_campus_count int:=0; v_reg_count int:=0; v_academic_count int:=0; v_category_count int:=0; v_collection_count int:=0;
  v_fee_state jsonb;
  function_result jsonb;
begin
  if auth.uid() is null or security.current_role_rank()<1 then raise exception 'assigned CourseFinder role required' using errcode='42501'; end if;
  select * into c from catalogue.courses where id=p_course_id;
  if c.id is null then return '[]'::jsonb; end if;

  select coalesce(array_agg(distinct field_code),array[]::text[]) into v_l4 from pipeline.layer4_course_field_resolutions where course_id=c.id and status='applied';
  -- Provider-scoped Layer 2 sources (Decision 149): the provider's CRICOS codes and the domains its qualified sources admit.
  select coalesce(array_agg(distinct upper(btrim(pr.registration_code))),array[]::text[]) into v_codes
    from catalogue.provider_registrations pr where pr.provider_id=c.provider_id and lower(pr.registration_scheme)='cricos';
  select coalesce(array_agg(distinct d),array[]::text[]) into v_domains
    from pipeline.course_fact_source_qualifications q, unnest(q.admitted_domains) d
   where upper(btrim(q.provider_cricos))=any(v_codes) and q.qualification_status in ('qualified','bounded')
     and not exists (select 1 from pipeline.sources s where s.id=q.source_id and s.source_type='provider_fee_schedule');

  select cl.url, cl.evidence_id into v_course_url, v_url_ev from catalogue.course_links cl
   where cl.course_id=c.id and cl.link_type='official_course' and coalesce(cl.status,'active')='active'
   order by (cl.audience='international') desc, cl.last_verified_at desc nulls last, cl.created_at desc limit 1;
  v_course_url:=coalesce(nullif(c.course_url,''),v_course_url);

  select f.id, f.evidence_id, f.source_id into v_fee from catalogue.course_fees f
   where f.course_id=c.id and f.fee_type='provider_current_tuition' and coalesce(f.status,'active')='active'
   order by f.fee_year desc nulls last, f.updated_at desc nulls last limit 1;
  if v_fee.id is not null then
    select w.id, coalesce(p.model_identifier, p.code) model into v_fee_l3 from pipeline.layer3_work_items w
      left join pipeline.layer3_interpretations i on i.id=w.interpretation_id
      left join pipeline.layer3_model_profiles p on p.id=coalesce(i.profile_id,w.profile_id)
     where w.entity_id=c.id and w.status='admitted' and w.evidence_id=v_fee.evidence_id order by w.updated_at desc limit 1;
  end if;
  select count(*) into v_reg_tuition from catalogue.course_fees f
   where f.course_id=c.id and f.fee_type='tuition' and f.basis='registered_total_course' and coalesce(f.status,'active')='active';
  select case when bool_or(w.status in ('pending','reserved','interpreting','validated','admission_pending','failed')) then 'awaiting_l3'
              when bool_or(w.status='layer4_required') then 'awaiting_l4' end
    into v_l3_open from pipeline.layer3_work_items w where w.entity_id=c.id and w.task_class='provider_current_tuition_validation';

  select count(*) into v_intake_count from catalogue.course_intakes i where i.course_id=c.id and coalesce(i.status,'active')='active';
  select count(*) into v_english_count from catalogue.course_english_requirements e where e.course_id=c.id and coalesce(e.status,'active')='active';
  select count(*), count(*) filter (where nullif(cc.delivery_mode,'') is not null) into v_campus_count, v_mode_count from catalogue.course_campuses cc where cc.course_id=c.id;
  select count(*) into v_reg_count from catalogue.course_regulatory_observations r where r.course_id=c.id and r.valid_to is null;
  select count(*) into v_academic_count from catalogue.course_academic_options a where a.course_id=c.id and coalesce(a.status,'active')='active';
  select count(*) into v_category_count from pim.entity_categories ec join pim.entity_registry er on er.id=ec.entity_id where er.entity_type='course' and er.stable_key=c.stable_key;
  select count(*) into v_collection_count from catalogue.course_collection_memberships m where m.course_id=c.id;

  -- Provider tuition (Decision 162: CRICOS registered tuition is the Layer 1 figure; provider tuition is a refinement).
  if v_fee.id is not null then
    v_fee_state:=jsonb_build_object('value_state','resolved',
      'resolved_layer',case when 'provider_current_tuition'=any(v_l4) then 4 when v_fee_l3.id is not null then 3 else 2 end,
      'resolved_by',case when 'provider_current_tuition'=any(v_l4) then 'Layer 4 resolution' when v_fee_l3.id is not null then 'Layer 3 · '||coalesce(v_fee_l3.model,'qualified model') when exists (select 1 from pipeline.sources fs where fs.id=v_fee.source_id and fs.source_type='provider_fee_schedule') then 'Layer 2 provider fee schedule' else 'Layer 2 provider rule' end,
      'evidence_id',v_fee.evidence_id);
  elsif v_l3_open is not null then
    v_fee_state:=jsonb_build_object('value_state',v_l3_open,'resolved_layer',null);
  elsif 'international_fee'=any(v_domains) then
    v_fee_state:=jsonb_build_object('value_state','awaiting_l2','resolved_layer',null);
  elsif v_reg_tuition>0 then
    v_fee_state:=jsonb_build_object('value_state','l1_covers','resolved_layer',1,'resolved_by','CRICOS registered international tuition applies');
  else
    v_fee_state:=jsonb_build_object('value_state','not_collected','resolved_layer',null);
  end if;

  function_result:=jsonb_build_array(
    jsonb_build_object('code','provider','label','Provider','group','Identity','value_state',case when c.provider_id is not null then 'resolved' else 'source_missing' end,'resolved_layer',1,'resolved_by','CRICOS','editable_l4',false,'authority','Layer 1'),
    jsonb_build_object('code','course_code','label','CRICOS / Course code','group','Identity','value_state',case when nullif(c.course_code,'') is not null then 'resolved' else 'source_missing' end,'resolved_layer',1,'resolved_by','CRICOS','editable_l4',false,'authority','Layer 1'),
    jsonb_build_object('code','study_level','label','Study level','group','Identity','value_state',case when c.study_level_id is not null then 'resolved' else 'source_missing' end,'resolved_layer',1,'resolved_by','CRICOS','editable_l4',false,'authority','Layer 1'),
    jsonb_build_object('code','field_of_study','label','Field of study','group','Identity','value_state',case when c.primary_field_id is not null then 'resolved' else 'source_missing' end,'resolved_layer',1,'resolved_by','CRICOS','editable_l4',false,'authority','Layer 1'),
    jsonb_build_object('code','duration','label','Duration','group','Course facts','value_state',case when c.duration_value is not null then 'resolved' else 'not_collected' end,'resolved_layer',case when 'duration'=any(v_l4) then 4 when c.duration_value is not null then 1 end,'resolved_by',case when 'duration'=any(v_l4) then 'Layer 4 resolution' else 'CRICOS' end,'editable_l4',true,'authority','Layer 1'),
    jsonb_build_object('code','delivery_mode','label','Delivery mode','group','Course facts','value_state',case when nullif(c.delivery_mode,'') is not null or v_mode_count>0 then 'resolved' else 'not_collected' end,'resolved_layer',case when 'delivery_mode'=any(v_l4) then 4 when nullif(c.delivery_mode,'') is not null or v_mode_count>0 then 1 end,'resolved_by',case when 'delivery_mode'=any(v_l4) then 'Layer 4 resolution' else 'CRICOS course locations' end,'editable_l4',true,'authority','Layer 1'),
    jsonb_build_object('code','official_course_url','label','Official Course URL','group','Course facts','value_state',case when v_course_url is not null then 'resolved' when 'official_course_url'=any(v_domains) then 'awaiting_l2' else 'not_collected' end,'resolved_layer',case when 'official_course_url'=any(v_l4) then 4 when v_course_url is not null then 2 end,'resolved_by',case when 'official_course_url'=any(v_l4) then 'Layer 4 resolution' when v_course_url is not null then 'Layer 2 provider rule' end,'evidence_id',v_url_ev,'editable_l4',true,'authority','Enrichment'),
    jsonb_build_object('code','course_description','label','Course description','group','Course facts','value_state',case when nullif(c.description,'') is not null then 'resolved' when 'official_course_url'=any(v_domains) then 'awaiting_l2' else 'not_collected' end,'resolved_layer',case when 'course_description'=any(v_l4) then 4 when nullif(c.description,'') is not null then 2 end,'editable_l4',true,'authority','Enrichment'),
    jsonb_build_object('code','provider_current_tuition','label','Current Provider tuition','group','Fees','editable_l4',true,'authority','Enrichment')||v_fee_state,
    jsonb_build_object('code','intakes','label','Intakes','group','Entry & availability','value_state',case when v_intake_count>0 then 'resolved' when 'intake'=any(v_domains) then 'awaiting_l2' else 'not_collected' end,'resolved_layer',case when 'intakes'=any(v_l4) then 4 when v_intake_count>0 then 2 end,'editable_l4',true,'authority','Enrichment'),
    jsonb_build_object('code','english_requirement','label','English requirement','group','Entry & availability','value_state',case when v_english_count>0 then 'resolved' when 'english_requirement'=any(v_domains) then 'awaiting_l2' else 'not_collected' end,'resolved_layer',case when 'english_requirement'=any(v_l4) then 4 when v_english_count>0 then 2 end,'editable_l4',true,'authority','Enrichment'),
    jsonb_build_object('code','campuses','label','Campuses','group','Delivery','value_state',case when v_campus_count>0 then 'resolved' else 'source_missing' end,'resolved_layer',1,'resolved_by','CRICOS','editable_l4',false,'authority','Layer 1'),
    jsonb_build_object('code','academic_options','label','Academic options','group','Structure','value_state',case when v_academic_count>0 then 'resolved' else 'not_collected' end,'resolved_layer',case when v_academic_count>0 then 2 end,'editable_l4',true,'authority','Enrichment'),
    jsonb_build_object('code','categories','label','Categories','group','Structure','value_state',case when v_category_count>0 then 'resolved' else 'l4_input' end,'resolved_layer',case when v_category_count>0 then 4 end,'editable_l4',true,'authority','PIM / Layer 4'),
    jsonb_build_object('code','collections','label','Collections','group','Structure','value_state',case when v_collection_count>0 then 'resolved' else 'l4_input' end,'resolved_layer',case when v_collection_count>0 then 4 end,'editable_l4',true,'authority','PIM / Layer 4'),
    jsonb_build_object('code','regulatory_facts','label','Regulatory facts','group','Regulatory','value_state',case when v_reg_count>0 then 'resolved' else 'source_missing' end,'resolved_layer',1,'resolved_by','CRICOS','editable_l4',false,'authority','Layer 1'),
    jsonb_build_object('code','publication','label','Publication','group','Governance','value_state','resolved','resolved_layer',null,'editable_l4',false,'authority','Governed action')
  );
  return function_result;
end $function$
