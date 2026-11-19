insert into pim.attribute_definitions(code,name,entity_type,data_type,validation_rules,is_required_default,is_unique,is_filterable,is_searchable,include_in_vector,is_localisable,is_channel_scoped,is_multivalue,is_bulk_editable,display_order,status)
select 'course_description','Course Description','course','richtext',jsonb_build_object('source_rule','first_party_evidence_required','layer2_apply','fill_empty_only'),false,false,false,false,false,false,false,false,false,40,'active'
where not exists(select 1 from pim.attribute_definitions where code='course_description');

create or replace function public.layer2_apply_course_candidate(p_candidate_record_id uuid,p_apply boolean default false)
returns jsonb
language plpgsql
security definer
set search_path='pg_catalog','public','pipeline','catalogue','pim'
as $$
declare r pipeline.course_fact_source_records%rowtype; v jsonb; v_intakes jsonb:='[]'::jsonb; v_eng jsonb:='[]'::jsonb; v_fee_safe boolean; v_result jsonb; v_desc text; v_course uuid; v_field uuid; v_desc_applied int:=0; v_existing text;begin
 if current_user<>'postgres' and coalesce(auth.role(),'')<>'service_role' then raise exception 'service_role required';end if;
 select * into r from pipeline.course_fact_source_records where id=p_candidate_record_id;
 if not found then raise exception 'candidate record not found';end if;
 if coalesce((r.parsed_payload->>'identity_match')::boolean,false) is not true then raise exception 'candidate identity not matched';end if;
 if coalesce(r.provider_cricos,'')='' or coalesce(r.course_cricos,'')='' then raise exception 'regulatory identity required';end if;
 v:=r.parsed_payload;
 select coalesce(jsonb_agg(jsonb_build_object('intake_label',t.val,'status','active','source_intake_key',lower(r.course_cricos||':current:'||t.val))),'[]'::jsonb) into v_intakes from jsonb_array_elements_text(coalesce(v->'intakes','[]'::jsonb)) as t(val);
 if v->'english_requirements' ? 'ielts_overall' then v_eng:=v_eng||jsonb_build_array(jsonb_build_object('test_code','IELTS','overall_score',(v->'english_requirements'->>'ielts_overall')::numeric,'status','active','source_requirement_key',lower(r.course_cricos||':ielts')));end if;
 if v->'english_requirements' ? 'pte_overall' then v_eng:=v_eng||jsonb_build_array(jsonb_build_object('test_code','PTE','overall_score',(v->'english_requirements'->>'pte_overall')::numeric,'status','active','source_requirement_key',lower(r.course_cricos||':pte')));end if;
 if v->'english_requirements' ? 'toefl_overall' then v_eng:=v_eng||jsonb_build_array(jsonb_build_object('test_code','TOEFL','overall_score',(v->'english_requirements'->>'toefl_overall')::numeric,'status','active','source_requirement_key',lower(r.course_cricos||':toefl')));end if;
 v_fee_safe:=coalesce((v->>'fee_safe')::boolean,false) and v->'provider_current_tuition' is not null;
 v_desc:=nullif(btrim(v->>'description_candidate'),'');
 if v_desc is not null and (length(v_desc)<20 or length(v_desc)>2000) then v_desc:=null;end if;
 v:=v||jsonb_build_object('course_url',r.source_url,'link_type','official_course','audience','international','intakes',v_intakes,'english_requirements',v_eng,'layer2_candidate_record_id',r.id,'layer2_apply_contract','m2_1_v2');
 if v_fee_safe then v:=v||jsonb_build_object('fee_amount',(v->'provider_current_tuition'->>'amount')::numeric,'currency_code',coalesce(v->'provider_current_tuition'->>'currency_code','AUD'),'fee_basis','current indicative annual international tuition','fee_notes','Applied only after Layer 2 deterministic fee safety guard; fee year not promoted unless explicitly parsed'); else v:=v-'fee_amount'-'currency_code'-'fee_basis'-'fee_notes'; end if;
 v_result:=public.svc_coursefacts_apply_record(r.source_id,r.evidence_id,r.provider_cricos,r.course_cricos,r.source_record_id,r.source_url,r.content_hash,v,p_apply);
 v_course:=(v_result->>'course_id')::uuid;
 if v_course is null then raise exception 'course resolution missing from apply contract';end if;
 select description into v_existing from catalogue.courses where id=v_course;
 if p_apply and v_desc is not null and coalesce(btrim(v_existing),'')='' then
   update catalogue.courses set description=v_desc,updated_at=now() where id=v_course and coalesce(btrim(description),'')='';
   get diagnostics v_desc_applied=row_count;
   if v_desc_applied=1 then
     select id into v_field from pim.attribute_definitions where code='course_description' and entity_type='course' and status='active' limit 1;
     if v_field is null then raise exception 'course_description attribute definition missing';end if;
     insert into catalogue.course_field_observations(course_id,field_id,source_id,evidence_id,source_field_code,source_field_name,is_primary,status,observed_at,created_at,updated_at)
     values(v_course,v_field,r.source_id,r.evidence_id,'meta_description','First-party HTML meta description',true,'active',now(),now(),now())
     on conflict(course_id,source_id,source_field_code) do update set field_id=excluded.field_id,evidence_id=excluded.evidence_id,source_field_name=excluded.source_field_name,is_primary=true,status='active',observed_at=now(),updated_at=now();
   end if;
 end if;
 return v_result||jsonb_build_object('candidate_record_id',r.id,'fee_safe',v_fee_safe,'would_apply_description',v_desc is not null and coalesce(btrim(v_existing),'')='','description_applied',v_desc_applied,'description_strategy',v->>'description_strategy','search_mutation_authorised',false,'publication_mutation_authorised',false);
end$$;
revoke all on function public.layer2_apply_course_candidate(uuid,boolean) from public,anon,authenticated;
grant execute on function public.layer2_apply_course_candidate(uuid,boolean) to service_role;
