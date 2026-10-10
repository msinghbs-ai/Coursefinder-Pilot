insert into pipeline.layer4_field_registry(entity_type,field_code,display_label,value_kind,editability_class,min_role_rank,publication_sensitive,notes)
values
('scholarship','name','Scholarship name','text','editable',3,false,'Effective-value overlay only'),
('scholarship','description','Scholarship description','text','editable',3,false,'Effective-value overlay only'),
('scholarship','audience','Audience','text','editable',3,false,'Effective-value overlay only'),
('scholarship','award_value_text','Award value','text','editable',3,false,'Effective-value overlay only'),
('scholarship','source_url','Official scholarship URL','url','editable',3,false,'Effective-value overlay only'),
('scholarship','stable_key','Stable key','text','immutable',6,true,'Protected scholarship identity'),
('scholarship','provider_id','Provider ID','uuid','immutable',6,true,'Protected provider relationship'),
('scholarship','source_id','Source ID','uuid','immutable',6,true,'Protected source authority'),
('scholarship','evidence_id','Evidence ID','uuid','immutable',6,true,'Protected Evidence relationship'),
('provider_contact','full_name','Contact name','text','editable',3,false,'Effective-value overlay only'),
('provider_contact','job_title','Job title','text','editable',3,false,'Effective-value overlay only'),
('provider_contact','team_name','Team name','text','editable',3,false,'Effective-value overlay only'),
('provider_contact','territory_text','Territory / market','text','editable',3,false,'Effective-value overlay only'),
('provider_contact','work_email','Institutional email','email','editable',3,false,'Effective-value overlay only'),
('provider_contact','work_phone','Public work phone','phone','editable',3,false,'Effective-value overlay only'),
('provider_contact','professional_profile_url','Professional profile URL','url','editable',3,false,'Effective-value overlay only'),
('provider_contact','source_url','First-party source URL','url','immutable',6,true,'Protected source authority'),
('provider_contact','provider_id','Provider ID','uuid','immutable',6,true,'Protected provider relationship'),
('provider_contact','profile_id','Contact profile ID','uuid','immutable',6,true,'Protected acquisition relationship'),
('provider_contact','evidence_id','Evidence ID','uuid','immutable',6,true,'Protected Evidence relationship'),
('provider_contact','identity_hash','Identity hash','text','immutable',6,true,'Protected identity/provenance')
on conflict(entity_type,field_code) do update
set display_label=excluded.display_label,value_kind=excluded.value_kind,editability_class=excluded.editability_class,
    min_role_rank=excluded.min_role_rank,publication_sensitive=excluded.publication_sensitive,notes=excluded.notes,enabled=true;

create or replace function security.layer4_entity_exists(p_entity_type text,p_entity_id uuid)
returns boolean language sql stable security definer
set search_path='pg_catalog','catalogue','scholarship','pipeline'
as $$
  select case p_entity_type
    when 'course' then exists(select 1 from catalogue.courses where id=p_entity_id)
    when 'provider' then exists(select 1 from catalogue.providers where id=p_entity_id)
    when 'campus' then exists(select 1 from catalogue.campuses where id=p_entity_id)
    when 'scholarship' then exists(select 1 from scholarship.scholarships where id=p_entity_id)
    when 'provider_contact' then exists(select 1 from pipeline.provider_contact_observations where id=p_entity_id)
    else false
  end
$$;

create or replace function security.layer4_underlying_value(p_entity_type text,p_entity_id uuid,p_field_code text)
returns jsonb language plpgsql stable security definer
set search_path='pg_catalog','catalogue','scholarship','pipeline'
as $$
declare v jsonb;
begin
  if p_entity_type='course' then
    if p_field_code='course_description' then select to_jsonb(description) into v from catalogue.courses where id=p_entity_id;
    elsif p_field_code='delivery_mode' then select to_jsonb(delivery_mode) into v from catalogue.courses where id=p_entity_id;
    elsif p_field_code='duration' then select jsonb_build_object('value',duration_value,'unit',duration_unit) into v from catalogue.courses where id=p_entity_id;
    elsif p_field_code='official_course_url' then
      select to_jsonb(coalesce((select cl.url from catalogue.course_links cl where cl.course_id=p_entity_id and cl.link_type='official_course' and coalesce(cl.status,'active')='active' order by (cl.audience='international') desc,cl.last_verified_at desc nulls last,cl.created_at desc limit 1),c.course_url)) into v from catalogue.courses c where c.id=p_entity_id;
    elsif p_field_code='stable_key' then select to_jsonb(stable_key) into v from catalogue.courses where id=p_entity_id;
    elsif p_field_code='canonical_title' then select to_jsonb(canonical_title) into v from catalogue.courses where id=p_entity_id;
    elsif p_field_code='course_code' then select to_jsonb(course_code) into v from catalogue.courses where id=p_entity_id;
    elsif p_field_code='canonical_source_id' then select to_jsonb(canonical_source_id) into v from catalogue.courses where id=p_entity_id;
    end if;
  elsif p_entity_type='provider' then
    if p_field_code='display_name' then select to_jsonb(display_name) into v from catalogue.providers where id=p_entity_id;
    elsif p_field_code='website' then select to_jsonb(website) into v from catalogue.providers where id=p_entity_id;
    elsif p_field_code='description' then select to_jsonb(description) into v from catalogue.providers where id=p_entity_id;
    elsif p_field_code='primary_city' then select to_jsonb(primary_city) into v from catalogue.providers where id=p_entity_id;
    elsif p_field_code='phone' then select to_jsonb(phone) into v from catalogue.providers where id=p_entity_id;
    elsif p_field_code='email' then select to_jsonb(email) into v from catalogue.providers where id=p_entity_id;
    elsif p_field_code='stable_key' then select to_jsonb(stable_key) into v from catalogue.providers where id=p_entity_id;
    elsif p_field_code='canonical_name' then select to_jsonb(canonical_name) into v from catalogue.providers where id=p_entity_id;
    elsif p_field_code='country_id' then select to_jsonb(country_id) into v from catalogue.providers where id=p_entity_id;
    elsif p_field_code='canonical_source_id' then select to_jsonb(canonical_source_id) into v from catalogue.providers where id=p_entity_id;
    end if;
  elsif p_entity_type='campus' then
    if p_field_code='name' then select to_jsonb(name) into v from catalogue.campuses where id=p_entity_id;
    elsif p_field_code='city' then select to_jsonb(city) into v from catalogue.campuses where id=p_entity_id;
    elsif p_field_code='address_line1' then select to_jsonb(address_line1) into v from catalogue.campuses where id=p_entity_id;
    elsif p_field_code='address_line2' then select to_jsonb(address_line2) into v from catalogue.campuses where id=p_entity_id;
    elsif p_field_code='postcode' then select to_jsonb(postcode) into v from catalogue.campuses where id=p_entity_id;
    elsif p_field_code='phone' then select to_jsonb(phone) into v from catalogue.campuses where id=p_entity_id;
    elsif p_field_code='website' then select to_jsonb(website) into v from catalogue.campuses where id=p_entity_id;
    elsif p_field_code='stable_key' then select to_jsonb(stable_key) into v from catalogue.campuses where id=p_entity_id;
    elsif p_field_code='provider_id' then select to_jsonb(provider_id) into v from catalogue.campuses where id=p_entity_id;
    elsif p_field_code='source_id' then select to_jsonb(source_id) into v from catalogue.campuses where id=p_entity_id;
    elsif p_field_code='evidence_id' then select to_jsonb(evidence_id) into v from catalogue.campuses where id=p_entity_id;
    end if;
  elsif p_entity_type='scholarship' then
    if p_field_code='name' then select to_jsonb(name) into v from scholarship.scholarships where id=p_entity_id;
    elsif p_field_code='description' then select to_jsonb(description) into v from scholarship.scholarships where id=p_entity_id;
    elsif p_field_code='audience' then select to_jsonb(audience) into v from scholarship.scholarships where id=p_entity_id;
    elsif p_field_code='award_value_text' then select to_jsonb(award_value_text) into v from scholarship.scholarships where id=p_entity_id;
    elsif p_field_code='source_url' then select to_jsonb(source_url) into v from scholarship.scholarships where id=p_entity_id;
    elsif p_field_code='stable_key' then select to_jsonb(stable_key) into v from scholarship.scholarships where id=p_entity_id;
    elsif p_field_code='provider_id' then select to_jsonb(provider_id) into v from scholarship.scholarships where id=p_entity_id;
    elsif p_field_code='source_id' then select to_jsonb(source_id) into v from scholarship.scholarships where id=p_entity_id;
    elsif p_field_code='evidence_id' then select to_jsonb(evidence_id) into v from scholarship.scholarships where id=p_entity_id;
    end if;
  elsif p_entity_type='provider_contact' then
    if p_field_code='full_name' then select to_jsonb(full_name) into v from pipeline.provider_contact_observations where id=p_entity_id;
    elsif p_field_code='job_title' then select to_jsonb(job_title) into v from pipeline.provider_contact_observations where id=p_entity_id;
    elsif p_field_code='team_name' then select to_jsonb(team_name) into v from pipeline.provider_contact_observations where id=p_entity_id;
    elsif p_field_code='territory_text' then select to_jsonb(territory_text) into v from pipeline.provider_contact_observations where id=p_entity_id;
    elsif p_field_code='work_email' then select to_jsonb(work_email) into v from pipeline.provider_contact_observations where id=p_entity_id;
    elsif p_field_code='work_phone' then select to_jsonb(work_phone) into v from pipeline.provider_contact_observations where id=p_entity_id;
    elsif p_field_code='professional_profile_url' then select to_jsonb(professional_profile_url) into v from pipeline.provider_contact_observations where id=p_entity_id;
    elsif p_field_code='source_url' then select to_jsonb(source_url) into v from pipeline.provider_contact_observations where id=p_entity_id;
    elsif p_field_code='provider_id' then select to_jsonb(provider_id) into v from pipeline.provider_contact_observations where id=p_entity_id;
    elsif p_field_code='profile_id' then select to_jsonb(profile_id) into v from pipeline.provider_contact_observations where id=p_entity_id;
    elsif p_field_code='evidence_id' then select to_jsonb(evidence_id) into v from pipeline.provider_contact_observations where id=p_entity_id;
    elsif p_field_code='identity_hash' then select to_jsonb(identity_hash) into v from pipeline.provider_contact_observations where id=p_entity_id;
    end if;
  end if;
  return v;
end $$;

do $$
declare v_oid oid; v_def text;
begin
  select p.oid into v_oid from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.proname='admin_read' and pg_get_function_identity_arguments(p.oid)='p_operation text, p_args jsonb' limit 1;
  if v_oid is null then raise exception 'public.admin_read(text,jsonb) not found'; end if;
  select pg_get_functiondef(v_oid) into v_def;
  if position('layer4_effective_entity_read(''scholarship''' in v_def)=0 then
    v_def:=replace(v_def,
      'return v_result||jsonb_build_object(''semantic_summary'',security.admin_scholarship_semantic_summary(v_id));',
      'return v_result||jsonb_build_object(''semantic_summary'',security.admin_scholarship_semantic_summary(v_id))||jsonb_build_object(''layer4'',security.layer4_effective_entity_read(''scholarship'',v_id))||jsonb_build_object(''layer4_publication'',security.layer4_publication_state_read(''scholarship'',v_id));');
    execute v_def;
  end if;
end $$;

create or replace function security.admin_provider_contacts(p_provider_id uuid)
returns jsonb language plpgsql stable security definer
set search_path='pg_catalog','security','pipeline','catalogue','ref','public','auth'
as $$
declare v_rank integer:=0; v_profile jsonb; v_items jsonb; v_events jsonb;
begin
  if auth.uid() is null then raise exception 'authentication required' using errcode='42501'; end if;
  select security.current_role_rank() into v_rank;
  if v_rank<1 then raise exception 'assigned CourseFinder role required' using errcode='42501'; end if;
  select jsonb_build_object('profile_id',p.id,'enabled',p.enabled,'paused',p.paused,'base_url',p.base_url,'domain',p.domain,'last_run_at',p.last_run_at,'last_success_at',p.last_success_at,'last_error',p.last_error) into v_profile from pipeline.provider_contact_profiles p where p.provider_id=p_provider_id;
  select coalesce(jsonb_agg(row_json order by source_priority,lower(coalesce(row_json->>'territory_text','')),lower(coalesce(row_json->>'job_title','')),lower(coalesce(row_json->>'full_name',''))),'[]'::jsonb) into v_items from (
    select case o.source_class when 'first_party' then 1 when 'manual' then 2 else 3 end source_priority,
      jsonb_build_object('id',o.id,'source_class',o.source_class,'source_provider',o.source_provider,'full_name',o.full_name,'job_title',o.job_title,'team_name',o.team_name,'territory_text',o.territory_text,'territory_codes',o.territory_codes,'work_email',o.work_email,'work_phone',o.work_phone,'professional_profile_url',o.professional_profile_url,'source_url',o.source_url,'evidence_id',o.evidence_id,'verification_state',o.verification_state,'confidence',o.confidence,'observed_at',o.observed_at,'last_verified_at',o.last_verified_at,'source_priority',case o.source_class when 'first_party' then 'preferred' when 'manual' then 'governed_manual' else 'secondary_enrichment' end,'layer4',security.layer4_effective_entity_read('provider_contact',o.id)) row_json
    from pipeline.provider_contact_observations o
    where o.provider_id=p_provider_id and o.is_current=true and o.verification_state<>'rejected'
    order by 1,o.last_verified_at desc limit 50
  ) q;
  select coalesce(jsonb_agg(jsonb_build_object('id',e.id,'event_type',e.event_type,'source_class',e.source_class,'before_state',e.before_state,'after_state',e.after_state,'detected_at',e.detected_at,'acknowledged',e.acknowledged) order by e.detected_at desc),'[]'::jsonb) into v_events from (
    select * from pipeline.provider_contact_watch_events where provider_id=p_provider_id and event_type<>'new_contact' and coalesce(metadata->>'a15_quality_probe','false')<>'true' order by detected_at desc limit 20
  ) e;
  return jsonb_build_object('profile',coalesce(v_profile,'{}'::jsonb),'items',coalesce(v_items,'[]'::jsonb),'events',coalesce(v_events,'[]'::jsonb),'disposition',security.provider_contact_disposition_current(p_provider_id),'summary',jsonb_build_object(
      'current_contacts',(select count(*) from pipeline.provider_contact_observations where provider_id=p_provider_id and is_current=true and verification_state<>'rejected'),
      'first_party_contacts',(select count(*) from pipeline.provider_contact_observations where provider_id=p_provider_id and is_current=true and source_class='first_party' and verification_state<>'rejected'),
      'enriched_contacts',(select count(*) from pipeline.provider_contact_observations where provider_id=p_provider_id and is_current=true and source_class='licensed_enrichment' and verification_state<>'rejected'),
      'unacknowledged_changes',(select count(*) from pipeline.provider_contact_watch_events e where e.provider_id=p_provider_id and e.acknowledged=false and e.event_type<>'new_contact' and coalesce(e.metadata->>'a15_quality_probe','false')<>'true')));
end $$;

comment on function security.layer4_underlying_value(text,uuid,text) is
'A16 cross-platform underlying-value reader for Provider/Course/Campus/Scholarship/provider_contact. It reads but never mutates source/canonical/history rows.';