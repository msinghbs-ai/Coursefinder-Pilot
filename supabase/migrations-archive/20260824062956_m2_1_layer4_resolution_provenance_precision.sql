create or replace function security.admin_course_field_states(p_course_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path='pg_catalog','catalogue','pipeline','pim','ref','security','auth'
as $$
declare
  c catalogue.courses%rowtype;
  v_payload jsonb;
  v_fee_count int:=0; v_intake_count int:=0; v_english_count int:=0; v_campus_count int:=0; v_reg_count int:=0; v_academic_count int:=0; v_category_count int:=0; v_collection_count int:=0;
  v_course_url text;
  v_try_url boolean:=false; v_try_description boolean:=false; v_try_fee boolean:=false; v_try_intakes boolean:=false; v_try_english boolean:=false;
  v_l4_fields text[]:=array[]::text[];
  result jsonb:='[]'::jsonb;
begin
  if auth.uid() is null or security.current_role_rank()<1 then raise exception 'assigned CourseFinder role required' using errcode='42501'; end if;
  select * into c from catalogue.courses where id=p_course_id;
  if c.id is null then return '[]'::jsonb; end if;
  select coalesce(array_agg(distinct field_code),array[]::text[]) into v_l4_fields from pipeline.layer4_course_field_resolutions where course_id=c.id and status='applied';
  select cl.url into v_course_url from catalogue.course_links cl where cl.course_id=c.id and cl.link_type='official_course' and coalesce(cl.status,'active')='active' order by (cl.audience='international') desc,cl.last_verified_at desc nulls last,cl.created_at desc limit 1;
  v_course_url:=coalesce(nullif(c.course_url,''),v_course_url);
  select count(*) into v_fee_count from catalogue.course_fees f where f.course_id=c.id and f.basis is distinct from 'registered_total_course' and coalesce(f.status,'active')='active';
  select count(*) into v_intake_count from catalogue.course_intakes i where i.course_id=c.id and coalesce(i.status,'active')='active';
  select count(*) into v_english_count from catalogue.course_english_requirements e where e.course_id=c.id and coalesce(e.status,'active')='active';
  select count(*) into v_campus_count from catalogue.course_campuses cc where cc.course_id=c.id;
  select count(*) into v_reg_count from catalogue.course_regulatory_observations r where r.course_id=c.id and r.valid_to is null;
  select count(*) into v_academic_count from catalogue.course_academic_options a where a.course_id=c.id and coalesce(a.status,'active')='active';
  select count(*) into v_category_count from pim.entity_categories ec join pim.entity_registry er on er.id=ec.entity_id where er.entity_type='course' and er.stable_key=c.stable_key;
  select count(*) into v_collection_count from catalogue.course_collection_memberships m where m.course_id=c.id;
  select r.parsed_payload into v_payload from pipeline.course_fact_source_records r where r.course_cricos=c.course_code and coalesce((r.parsed_payload->>'identity_match')::boolean,true)=true order by r.observed_at desc nulls last limit 1;
  if v_payload is not null then
    v_try_url := v_payload ? 'official_course_url' or v_payload ? 'course_url';
    v_try_description := v_payload ? 'description_candidate' or v_payload ? 'description';
    v_try_fee := v_payload ? 'provider_current_tuition' or v_payload ? 'fee_candidates' or v_payload ? 'fee_rejection_reason';
    v_try_intakes := v_payload ? 'intakes';
    v_try_english := v_payload ? 'english_requirements';
  end if;
  result:=jsonb_build_array(
    jsonb_build_object('code','provider','label','Provider','group','Identity','value_state',case when c.provider_id is not null then 'resolved' else 'source_missing' end,'resolved_layer',1,'editable_l4',false,'authority','Layer 1'),
    jsonb_build_object('code','course_code','label','CRICOS / Course code','group','Identity','value_state',case when nullif(c.course_code,'') is not null then 'resolved' else 'source_missing' end,'resolved_layer',1,'editable_l4',false,'authority','Layer 1'),
    jsonb_build_object('code','study_level','label','Study level','group','Identity','value_state',case when c.study_level_id is not null then 'resolved' else 'source_missing' end,'resolved_layer',1,'editable_l4',false,'authority','Layer 1'),
    jsonb_build_object('code','field_of_study','label','Field of study','group','Identity','value_state',case when c.primary_field_id is not null then 'resolved' else 'source_missing' end,'resolved_layer',1,'editable_l4',false,'authority','Layer 1'),
    jsonb_build_object('code','duration','label','Duration','group','Course facts','value_state',case when c.duration_value is not null then 'resolved' else 'awaiting_l2' end,'resolved_layer',case when 'duration'=any(v_l4_fields) then 4 when c.duration_value is not null then 1 end,'editable_l4',true,'authority','Enrichment'),
    jsonb_build_object('code','delivery_mode','label','Delivery mode','group','Course facts','value_state',case when nullif(c.delivery_mode,'') is not null then 'resolved' else 'awaiting_l2' end,'resolved_layer',case when 'delivery_mode'=any(v_l4_fields) then 4 when nullif(c.delivery_mode,'') is not null then 1 end,'editable_l4',true,'authority','Enrichment'),
    jsonb_build_object('code','official_course_url','label','Official Course URL','group','Course facts','value_state',case when v_course_url is not null then 'resolved' when v_try_url then 'awaiting_l3' else 'awaiting_l2' end,'resolved_layer',case when 'official_course_url'=any(v_l4_fields) then 4 when v_course_url is not null then 2 end,'editable_l4',true,'authority','Enrichment'),
    jsonb_build_object('code','course_description','label','Course description','group','Course facts','value_state',case when nullif(c.description,'') is not null then 'resolved' when v_try_description then 'awaiting_l3' else 'awaiting_l2' end,'resolved_layer',case when 'course_description'=any(v_l4_fields) then 4 when nullif(c.description,'') is not null then 2 end,'editable_l4',true,'authority','Enrichment'),
    jsonb_build_object('code','provider_current_tuition','label','Current Provider tuition','group','Fees','value_state',case when v_fee_count>0 then 'resolved' when v_try_fee then 'awaiting_l3' else 'awaiting_l2' end,'resolved_layer',case when v_fee_count>0 then 2 end,'editable_l4',true,'authority','Enrichment'),
    jsonb_build_object('code','intakes','label','Intakes','group','Entry & availability','value_state',case when v_intake_count>0 then 'resolved' when v_try_intakes then 'awaiting_l3' else 'awaiting_l2' end,'resolved_layer',case when v_intake_count>0 then 2 end,'editable_l4',true,'authority','Enrichment'),
    jsonb_build_object('code','english_requirement','label','English requirement','group','Entry & availability','value_state',case when v_english_count>0 then 'resolved' when v_try_english then 'awaiting_l3' else 'awaiting_l2' end,'resolved_layer',case when v_english_count>0 then 2 end,'editable_l4',true,'authority','Enrichment'),
    jsonb_build_object('code','campuses','label','Campuses','group','Delivery','value_state',case when v_campus_count>0 then 'resolved' else 'source_missing' end,'resolved_layer',1,'editable_l4',false,'authority','Layer 1'),
    jsonb_build_object('code','academic_options','label','Academic options','group','Structure','value_state',case when v_academic_count>0 then 'resolved' else 'awaiting_l2' end,'resolved_layer',case when v_academic_count>0 then 2 end,'editable_l4',true,'authority','Enrichment'),
    jsonb_build_object('code','categories','label','Categories','group','Structure','value_state',case when v_category_count>0 then 'resolved' else 'l4_input' end,'resolved_layer',case when v_category_count>0 then 4 end,'editable_l4',true,'authority','PIM / Layer 4'),
    jsonb_build_object('code','collections','label','Collections','group','Structure','value_state',case when v_collection_count>0 then 'resolved' else 'l4_input' end,'resolved_layer',case when v_collection_count>0 then 4 end,'editable_l4',true,'authority','PIM / Layer 4'),
    jsonb_build_object('code','regulatory_facts','label','Regulatory facts','group','Regulatory','value_state',case when v_reg_count>0 then 'resolved' else 'source_missing' end,'resolved_layer',1,'editable_l4',false,'authority','Layer 1'),
    jsonb_build_object('code','publication','label','Publication','group','Governance','value_state','resolved','resolved_layer',null,'editable_l4',false,'authority','Governed action')
  );
  return result;
end$$;

create or replace function public.layer4_course_scalar_resolve(p_course_id uuid,p_field_code text,p_value jsonb,p_reason text)
returns jsonb
language plpgsql
security definer
set search_path='pg_catalog','public','security','catalogue','pipeline','auth'
as $$
declare
  v_rank int; v_actor uuid:=auth.uid(); v_prior jsonb; v_new jsonb:=p_value; v_prev_id uuid; v_resolution_id uuid; v_text text; v_duration numeric; v_unit text;
begin
  if v_actor is null then raise exception 'authentication required' using errcode='42501'; end if;
  v_rank:=security.current_role_rank(); if v_rank<3 then raise exception 'curator role required for Layer 4 resolution' using errcode='42501'; end if;
  if not exists(select 1 from catalogue.courses where id=p_course_id) then raise exception 'course not found' using errcode='22023'; end if;
  if nullif(trim(coalesce(p_reason,'')),'') is null or length(trim(p_reason))<5 then raise exception 'resolution reason is required' using errcode='22023'; end if;
  if p_field_code not in ('course_description','official_course_url','delivery_mode','duration') then raise exception 'field is not enabled for scalar Layer 4 editing' using errcode='22023'; end if;
  select id into v_prev_id from pipeline.layer4_course_field_resolutions where course_id=p_course_id and field_code=p_field_code and status='applied' order by created_at desc limit 1;
  if p_field_code='course_description' then
    select to_jsonb(c.description) into v_prior from catalogue.courses c where c.id=p_course_id; v_text:=p_value #>> '{}';
    if nullif(trim(v_text),'') is null then raise exception 'description cannot be empty' using errcode='22023'; end if;
    update catalogue.courses set description=v_text,updated_at=now(),last_verified_at=now() where id=p_course_id;
  elsif p_field_code='delivery_mode' then
    select to_jsonb(c.delivery_mode) into v_prior from catalogue.courses c where c.id=p_course_id; v_text:=p_value #>> '{}';
    if nullif(trim(v_text),'') is null then raise exception 'delivery mode cannot be empty' using errcode='22023'; end if;
    update catalogue.courses set delivery_mode=v_text,updated_at=now(),last_verified_at=now() where id=p_course_id;
  elsif p_field_code='duration' then
    select jsonb_build_object('value',c.duration_value,'unit',c.duration_unit) into v_prior from catalogue.courses c where c.id=p_course_id;
    v_duration:=nullif(p_value->>'value','')::numeric; v_unit:=nullif(trim(p_value->>'unit'),'');
    if v_duration is null or v_duration<=0 or v_unit is null then raise exception 'duration requires positive value and unit' using errcode='22023'; end if;
    update catalogue.courses set duration_value=v_duration,duration_unit=v_unit,updated_at=now(),last_verified_at=now() where id=p_course_id;
  elsif p_field_code='official_course_url' then
    select to_jsonb(cl.url) into v_prior from catalogue.course_links cl where cl.course_id=p_course_id and cl.link_type='official_course' and coalesce(cl.status,'active')='active' order by (cl.audience='international') desc,cl.last_verified_at desc nulls last,cl.created_at desc limit 1;
    v_text:=p_value #>> '{}'; if v_text !~* '^https?://[^[:space:]]+$' then raise exception 'official Course URL must be http/https' using errcode='22023'; end if;
    update catalogue.course_links set status='superseded',valid_to=current_date,updated_at=now() where course_id=p_course_id and link_type='official_course' and coalesce(status,'active')='active';
    insert into catalogue.course_links(course_id,link_type,url,audience,label,is_primary,status,valid_from,confidence,last_verified_at) values(p_course_id,'official_course',v_text,'international','Layer 4 human resolution',true,'active',current_date,1,now());
  end if;
  if v_prev_id is not null then update pipeline.layer4_course_field_resolutions set status='superseded' where id=v_prev_id; end if;
  insert into pipeline.layer4_course_field_resolutions(course_id,field_code,prior_value,resolved_value,resolution_reason,actor_id,supersedes_id) values(p_course_id,p_field_code,v_prior,v_new,trim(p_reason),v_actor,v_prev_id) returning id into v_resolution_id;
  return jsonb_build_object('ok',true,'resolution_id',v_resolution_id,'course_id',p_course_id,'field_code',p_field_code,'resolved_value',v_new,'layer',4,'publication_changed',false,'search_changed',false);
end$$;
