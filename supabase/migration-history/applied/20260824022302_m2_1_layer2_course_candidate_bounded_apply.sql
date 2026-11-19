create or replace function public.layer2_apply_course_candidate(p_candidate_record_id uuid,p_apply boolean default false)
returns jsonb
language plpgsql
security definer
set search_path='pg_catalog','public','pipeline'
as $$
declare r pipeline.course_fact_source_records%rowtype; v jsonb; v_intakes jsonb:='[]'::jsonb; v_eng jsonb:='[]'::jsonb; x text; v_fee_safe boolean; v_result jsonb;begin
 if current_user<>'postgres' and coalesce(auth.role(),'')<>'service_role' then raise exception 'service_role required';end if;
 select * into r from pipeline.course_fact_source_records where id=p_candidate_record_id;
 if not found then raise exception 'candidate record not found';end if;
 if coalesce((r.parsed_payload->>'identity_match')::boolean,false) is not true then raise exception 'candidate identity not matched';end if;
 if coalesce(r.provider_cricos,'')='' or coalesce(r.course_cricos,'')='' then raise exception 'regulatory identity required';end if;
 v:=r.parsed_payload;
 select coalesce(jsonb_agg(jsonb_build_object('intake_label',x,'status','active','source_intake_key',lower(r.course_cricos||':current:'||x))),'[]'::jsonb) into v_intakes from jsonb_array_elements_text(coalesce(v->'intakes','[]'::jsonb)) t(x);
 if v->'english_requirements' ? 'ielts_overall' then v_eng:=v_eng||jsonb_build_array(jsonb_build_object('test_code','IELTS','overall_score',(v->'english_requirements'->>'ielts_overall')::numeric,'status','active','source_requirement_key',lower(r.course_cricos||':ielts')));end if;
 if v->'english_requirements' ? 'pte_overall' then v_eng:=v_eng||jsonb_build_array(jsonb_build_object('test_code','PTE','overall_score',(v->'english_requirements'->>'pte_overall')::numeric,'status','active','source_requirement_key',lower(r.course_cricos||':pte')));end if;
 if v->'english_requirements' ? 'toefl_overall' then v_eng:=v_eng||jsonb_build_array(jsonb_build_object('test_code','TOEFL','overall_score',(v->'english_requirements'->>'toefl_overall')::numeric,'status','active','source_requirement_key',lower(r.course_cricos||':toefl')));end if;
 v_fee_safe:=coalesce((v->>'fee_safe')::boolean,false) and v->'provider_current_tuition' is not null;
 v:=v||jsonb_build_object('course_url',r.source_url,'link_type','official_course','audience','international','intakes',v_intakes,'english_requirements',v_eng,'layer2_candidate_record_id',r.id,'layer2_apply_contract','m2_1_v1');
 if v_fee_safe then v:=v||jsonb_build_object('fee_amount',(v->'provider_current_tuition'->>'amount')::numeric,'currency_code',coalesce(v->'provider_current_tuition'->>'currency_code','AUD'),'fee_basis','current indicative annual international tuition','fee_notes','Applied only after Layer 2 deterministic fee safety guard; fee year not promoted unless explicitly parsed'); else v:=v-'fee_amount'-'currency_code'-'fee_basis'-'fee_notes'; end if;
 v_result:=public.svc_coursefacts_apply_record(r.source_id,r.evidence_id,r.provider_cricos,r.course_cricos,r.source_record_id,r.source_url,r.content_hash,v,p_apply);
 return v_result||jsonb_build_object('candidate_record_id',r.id,'fee_safe',v_fee_safe,'description_candidate_not_applied',v->>'description_candidate','search_mutation_authorised',false,'publication_mutation_authorised',false);
end$$;
revoke all on function public.layer2_apply_course_candidate(uuid,boolean) from public,anon,authenticated;
grant execute on function public.layer2_apply_course_candidate(uuid,boolean) to service_role;
