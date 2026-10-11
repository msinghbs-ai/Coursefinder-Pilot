CREATE OR REPLACE FUNCTION security.scholarship_sweep_apply_v1(p_scholarship_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'scholarship', 'catalogue', 'pipeline', 'security', 'search'
AS $function$
declare pg record; s record; v_codes text[]; v_fields text[]; v_old uuid[]; v_new uuid[]; v_changes text[]:='{}'; v_src uuid; f jsonb;
begin
  select * into pg from pipeline.scholarship_pages where scholarship_id=p_scholarship_id;
  select * into s from scholarship.scholarships where id=p_scholarship_id for update;
  if pg.read_status is distinct from 'read' or pg.facts is null or s.id is null then return jsonb_build_object('applied',false); end if;
  f:=pg.facts; v_src:=security.coverage_sweep_source(s.provider_id);

  if not (s.award_value_type in ('percentage','fixed_amount') and coalesce(s.award_percentage,s.award_amount) is not null) then
    if f->'value'->>'type'='percentage' and (f->'value'->>'percentage')::numeric between 5 and 100 then
      update scholarship.scholarships set award_value_type='percentage', award_percentage=(f->'value'->>'percentage')::numeric,
             award_applies_to_fee_type=coalesce(award_applies_to_fee_type,'tuition_fee'), award_value_text=coalesce(award_value_text,left(f->'value'->>'context',400)),
             evidence_id=pg.evidence_id, updated_at=now() where id=s.id;
      insert into pipeline.scholarship_sweep_changes(scholarship_id,field,before_value,after_value,evidence_id) values (s.id,'award_value',jsonb_build_object('type',s.award_value_type,'text',s.award_value_text),f->'value',pg.evidence_id);
      v_changes:=v_changes||'award_value'::text;
    elsif f->'value'->>'type'='fixed_amount' and (f->'value'->>'amount')::numeric > 0 then
      update scholarship.scholarships set award_value_type='fixed_amount', award_amount=(f->'value'->>'amount')::numeric, award_currency_code=scholarship.provider_currency(s.provider_id),
             award_value_text=coalesce(award_value_text,left(f->'value'->>'context',400)), evidence_id=pg.evidence_id, updated_at=now() where id=s.id;
      insert into pipeline.scholarship_sweep_changes(scholarship_id,field,before_value,after_value,evidence_id) values (s.id,'award_value',jsonb_build_object('type',s.award_value_type,'text',s.award_value_text),f->'value',pg.evidence_id);
      v_changes:=v_changes||'award_value'::text;
    end if;
  end if;

  if s.application_close_date is null and (f->'deadline'->>'date') is not null and (f->'deadline'->>'date')::date >= current_date then
    update scholarship.scholarships set application_close_date=(f->'deadline'->>'date')::date, updated_at=now() where id=s.id;
    insert into pipeline.scholarship_sweep_changes(scholarship_id,field,before_value,after_value,evidence_id) values (s.id,'application_close_date',null,f->'deadline',pg.evidence_id);
    v_changes:=v_changes||'application_close_date'::text;
  end if;

  -- a discovered provider page, confirmed by the reader to name this scholarship, replaces the Study Australia source
  if pg.url_source='discovered' and security.reference_url_has_use(coalesce(s.source_url,''), 'scholarship_placeholder') and not security.reference_url_has_use(coalesce(pg.final_url,pg.url), 'scholarship_placeholder')
     and coalesce((pg.name_check->>'ok')::boolean,false) then
    update scholarship.scholarships set source_url=pg.url, evidence_id=pg.evidence_id, updated_at=now() where id=s.id;
    insert into pipeline.scholarship_sweep_changes(scholarship_id,field,before_value,after_value,evidence_id)
    values (s.id,'source_url',jsonb_build_object('source_url',s.source_url,'evidence_id',s.evidence_id),jsonb_build_object('source_url',pg.url,'name_check',pg.name_check),pg.evidence_id);
    v_changes:=v_changes||'source_url'::text;
  end if;

  if not security.reference_url_has_use(coalesce(pg.final_url,pg.url), 'scholarship_placeholder') and not exists (select 1 from scholarship.identifiers i where i.scholarship_id=s.id and i.scheme='first_party_detail_url') then
    insert into scholarship.identifiers(scholarship_id,scheme,identifier_value,source_id,evidence_id,is_primary,status)
    values (s.id,'first_party_detail_url',pg.url,v_src,pg.evidence_id,true,'active') on conflict do nothing;
    v_changes:=v_changes||'first_party_url'::text;
  end if;

  -- Decision 211: eligibility criteria and award duration from the page
  v_changes:=v_changes||security.scholarship_criteria_apply_v1(s.id);

  -- v0.5.0: an English language course scholarship links only to the provider's English language courses
  if f ? 'english_course' then
    select coalesce(array_agg(c.id),'{}') into v_new
      from catalogue.courses c join ref.study_levels sl on sl.id=c.study_level_id
     where c.provider_id=s.provider_id and c.lifecycle_status='active' and sl.code='non_aqf_award' and coalesce(c.course_code,'')<>''
       and c.canonical_title ~* case f->'english_course'->>'course'
             when 'general english' then '\mgeneral english\M'
             when 'ielts preparation' then '\mielts\M'
             when 'academic english' then '(academic english|english for academic purposes|\meap\M)'
             else '(general english|academic english|english for academic purposes|\meap\M|\mielts\M|\melicos\M|english language)' end;
    select coalesce(array_agg(course_id),'{}') into v_old from scholarship.course_mappings
     where scholarship_id=s.id and mapping_basis in ('explicit_provider_scope','sweep_level_field_scope') and not (course_id=any(v_new));
    if cardinality(v_old)>0 then
      delete from scholarship.course_mappings where scholarship_id=s.id and course_id=any(v_old) and mapping_basis in ('explicit_provider_scope','sweep_level_field_scope');
      insert into pipeline.scholarship_sweep_changes(scholarship_id,field,before_value,after_value,evidence_id)
      values (s.id,'course_links_removed',jsonb_build_object('courses',cardinality(v_old),'course_ids',to_jsonb(v_old)),jsonb_build_object('reason','English language course scholarship: not linked to other courses','english_course',f->'english_course'),pg.evidence_id);
      v_changes:=v_changes||'course_links_removed'::text;
    end if;
    delete from scholarship.scopes sc using pipeline.sources src where sc.source_id=src.id and src.source_type='provider_course_page_sweep' and sc.scope_type='study_level' and sc.scholarship_id=s.id;
    if cardinality(v_new)>0 then
      insert into scholarship.course_mappings(scholarship_id,course_id,mapping_state,mapping_basis,evidence_id,mapped_by,mapped_at,updated_at)
      select s.id, x, 'mapped', 'sweep_level_field_scope', pg.evidence_id, null, now(), now() from unnest(v_new) x
      on conflict (scholarship_id,course_id) do update set mapping_basis='sweep_level_field_scope', mapping_state='mapped', evidence_id=excluded.evidence_id, updated_at=now();
      insert into pipeline.scholarship_sweep_changes(scholarship_id,field,before_value,after_value,evidence_id)
      values (s.id,'course_links',null,jsonb_build_object('courses',cardinality(v_new),'english_course',f->'english_course'),pg.evidence_id);
      v_changes:=v_changes||'course_links'::text;
    end if;
    if cardinality(v_old)+cardinality(v_new)>0 then perform search.refresh_course_enrichment_scoped_v1(array(select distinct unnest(v_old||v_new)),true); end if;
    update pipeline.scholarship_pages set applied_at=now(), apply_result=jsonb_build_object('changes',to_jsonb(v_changes),'english_course',f->'english_course') where scholarship_id=s.id;
    return jsonb_build_object('applied',true,'changes',to_jsonb(v_changes));
  end if;

  v_codes:=security.scholarship_level_codes(f->'levels');
  v_fields:=array(select jsonb_array_elements_text(coalesce(f->'fields','[]')));
  -- v2.15.239 (S2): a faculty or school the reader cannot match to a field (often a site-wide mention such as "WA School of Mines")
  -- no longer stops the course links; the levels the page states decide
  if coalesce((f->>'field_unmapped')::boolean,false) and cardinality(v_fields)=0 then
    v_changes:=v_changes||'course_links_faculty_unmatched'::text;
  end if;
  if cardinality(v_codes)>0 or cardinality(v_fields)>0 then
    select coalesce(array_agg(c.id),'{}') into v_new
      from catalogue.courses c left join ref.study_levels sl on sl.id=c.study_level_id left join ref.fields_of_study fos on fos.id=c.primary_field_id
     where c.provider_id=s.provider_id and c.lifecycle_status='active'
       and (cardinality(v_codes)=0 or sl.code=any(v_codes))
       and (cardinality(v_fields)=0 or exists (select 1 from unnest(v_fields) fp where fos.code like fp||'%'));
    if cardinality(v_new)>0 then
      select coalesce(array_agg(course_id),'{}') into v_old from scholarship.course_mappings where scholarship_id=s.id;
      delete from scholarship.course_mappings where scholarship_id=s.id and mapping_basis in ('explicit_provider_scope','sweep_level_field_scope') and not (course_id=any(v_new));
      insert into scholarship.course_mappings(scholarship_id,course_id,mapping_state,mapping_basis,evidence_id,mapped_by,mapped_at,updated_at)
      select s.id, x, 'mapped', 'sweep_level_field_scope', pg.evidence_id, null, now(), now() from unnest(v_new) x
      on conflict (scholarship_id,course_id) do update set mapping_basis='sweep_level_field_scope', mapping_state='mapped', evidence_id=excluded.evidence_id, updated_at=now();
      insert into scholarship.scopes(scholarship_id,scope_type,study_level_id,include_exclude,source_id,evidence_id)
      select s.id,'study_level',sl.id,'include',v_src,pg.evidence_id from ref.study_levels sl
       where sl.code=any(v_codes) and not exists (select 1 from scholarship.scopes x where x.scholarship_id=s.id and x.scope_type='study_level' and x.study_level_id=sl.id);
      insert into pipeline.scholarship_sweep_changes(scholarship_id,field,before_value,after_value,evidence_id)
      values (s.id,'course_links',jsonb_build_object('courses',cardinality(v_old)),jsonb_build_object('courses',cardinality(v_new),'levels',f->'levels','fields',f->'fields'),pg.evidence_id);
      v_changes:=v_changes||'course_links'::text;
      perform search.refresh_course_enrichment_scoped_v1(array(select distinct unnest(v_old||v_new)),true);
    end if;
  end if;

  -- v2.15.239 (S2, Platform Admin decision "Link all intl courses, marked"): a page that names no level, field or course places no
  -- restriction, so the scholarship links to all of the provider's active courses open to international students (marked
  -- course_links_all on the page record). A person's scope decision still governs through the mapping guard.
  if cardinality(v_codes)=0 and cardinality(v_fields)=0 then
    select coalesce(array_agg(c.id),'{}') into v_new from catalogue.courses c
     where c.provider_id=s.provider_id and c.lifecycle_status='active' and c.open_to_international is not false;
    if cardinality(v_new)>0 then
      select coalesce(array_agg(course_id),'{}') into v_old from scholarship.course_mappings where scholarship_id=s.id and mapping_basis='sweep_level_field_scope';
      delete from scholarship.course_mappings where scholarship_id=s.id and mapping_basis='sweep_level_field_scope' and not (course_id=any(v_new));
      insert into scholarship.course_mappings(scholarship_id,course_id,mapping_state,mapping_basis,evidence_id,mapped_by,mapped_at,updated_at)
      select s.id, x, 'mapped', 'sweep_level_field_scope', pg.evidence_id, null, now(), now() from unnest(v_new) x
      on conflict (scholarship_id,course_id) do update set mapping_state='mapped', evidence_id=excluded.evidence_id, updated_at=now()
       where scholarship.course_mappings.mapping_basis='sweep_level_field_scope';
      insert into pipeline.scholarship_sweep_changes(scholarship_id,field,before_value,after_value,evidence_id)
      values (s.id,'course_links',jsonb_build_object('courses',cardinality(v_old)),jsonb_build_object('courses',cardinality(v_new),'rule','all courses open to international students: the page names no level, field or course'),pg.evidence_id);
      v_changes:=v_changes||'course_links_all'::text;
      perform search.refresh_course_enrichment_scoped_v1(array(select distinct unnest(v_old||v_new)),true);
    end if;
  end if;
  update pipeline.scholarship_pages set applied_at=now(), apply_result=jsonb_build_object('changes',to_jsonb(v_changes)) where scholarship_id=s.id;
  return jsonb_build_object('applied',true,'changes',to_jsonb(v_changes));
end $function$
