-- CF-247 Decision 163, tuition route Option A (Platform Admin, 29 Sep 2026 09:56 IST): tuition found by the coverage
-- sweep on pages that print the course's CRICOS code is validated by the qualified Layer 3 model (Decision 160),
-- through the existing Layer 3 queue, dispatch and admission with no change to the qualified interpreter:
--  * the sweep records each hand-off as a Layer 2 run item (one batch per day under a dedicated, disabled profile);
--  * the page is saved again as plain text (the interpreter reads text evidence only), linked to the provider's
--    sweep source, which is qualified for provider tuition and has a Search gate;
--  * the Layer 3 target is the sweep's single international fee candidate (never a domestic or total figure);
--    other fees on the page go as competing context; identity_match is true (CRICOS code on the page);
--  * only courses without an active provider-current tuition fee are handed off; admission and Layer 4 holds are
--    the existing security.layer3_tuition_admit_validated_v1.
alter table pipeline.coverage_course_pages add column if not exists l3_work_item_id uuid, add column if not exists l3_handoff_at timestamptz;

insert into pipeline.sources(source_type,system_id,country_id,label,trust_rank,status,metadata)
select 'coverage_sweep_programme', s.system_id, s.country_id, 'Coverage sweep (all providers) - Layer 2 run records', 80, 'active',
       jsonb_build_object('decision','Decision 163 Option A','note','anchor for the sweep''s Layer 2 run profile; facts come from the per-provider sweep sources')
  from (select system_id, country_id from pipeline.sources where source_type='provider_course_page_sweep' limit 1) s
 where not exists (select 1 from pipeline.sources where source_type='coverage_sweep_programme');

insert into pipeline.layer2_source_profiles(source_id,profile_key,domain,acquisition_method,target_entity_type,authority_class,enabled,paused,operational_owner,schedule_text)
select id,'au-coverage-sweep-course-pages','course_facts','course_detail','course','first_party',false,true,'PIM/Data Operations','coverage sweep (records only; not run by the Layer 2 runner)'
  from pipeline.sources where source_type='coverage_sweep_programme'
on conflict (profile_key) do nothing;

insert into pipeline.layer2_source_profile_versions(profile_id,version_no,configuration,configuration_hash,validation_status,change_control_ref)
select p.id, 1, jsonb_build_object('decision','Decision 163 Option A','identity','CRICOS course code on page','worker','coverage-sweep'),
       md5('au-coverage-sweep-course-pages:v1'), 'valid', 'CF-CHG-20260915-247'
  from pipeline.layer2_source_profiles p where p.profile_key='au-coverage-sweep-course-pages'
on conflict do nothing;
update pipeline.layer2_source_profiles p set current_version_id=v.id, updated_at=now()
  from pipeline.layer2_source_profile_versions v where v.profile_id=p.id and p.profile_key='au-coverage-sweep-course-pages' and v.version_no=1 and p.current_version_id is null;

-- the Layer 3 target from the sweep's fee candidates (null when there is no single international candidate)
create or replace function security.coverage_tuition_target_v1(p_fee jsonb)
returns jsonb language sql immutable as $f$
  with c as (
    select x, row_number() over (order by (x->>'score')::numeric desc nulls last, (x->>'amount')::numeric desc) rk
      from jsonb_array_elements(coalesce(p_fee->'candidates','[]'::jsonb)) x
     where coalesce((x->>'international')::boolean,false) and not coalesce((x->>'domestic')::boolean,false)
       and not coalesce((x->>'total')::boolean,false) and (x->>'amount')::numeric > 0
       and ((p_fee->>'value') is null or (x->>'amount')::numeric=(p_fee->>'value')::numeric))
  select case when p_fee->>'basis'='total' then null else
         (select jsonb_build_object('amount',(x->>'amount')::numeric,'currency_code','AUD',
                   'basis',case when p_fee->>'basis'='annual' or coalesce((x->>'annualLocal')::boolean,false) then 'annual' else 'annual_or_indicative_requires_validation' end,
                   'fee_year',nullif(x->>'fee_year','')::int,'audience','international')
            from c where rk=1) end
$f$;

create or replace function public.svc_coverage_tuition_handoff_next(p_limit int)
returns jsonb language plpgsql security definer set search_path to 'pg_catalog','catalogue','pipeline','security' as $f$
declare v jsonb;
begin
  if current_user<>'postgres' and coalesce(auth.role(),'')<>'service_role' then raise exception 'service_role required'; end if;
  if not exists (select 1 from pipeline.layer3_model_profiles where 'provider_current_tuition_validation'=any(allowed_task_classes) and enabled and not paused and coalesce((quality_benchmark->>'pass')::boolean,false)) then return '[]'::jsonb; end if;
  with pick as (
    select p.course_id
      from pipeline.coverage_course_pages p
      join pipeline.evidence_artifacts e on e.id=p.evidence_id and e.storage_path is not null
      join catalogue.courses co on co.id=p.course_id and co.lifecycle_status='active'
     where p.read_status='read' and p.identity_basis='cricos_code' and p.l3_work_item_id is null
       and (p.l3_handoff_at is null or p.l3_handoff_at < now()-interval '1 day')
       and security.coverage_tuition_target_v1(p.candidates->'fee') is not null
       and not exists (select 1 from catalogue.course_fees f where f.course_id=p.course_id and f.fee_type='provider_current_tuition' and f.status='active')
       and not security.layer4_entity_or_parent_blocked('course',p.course_id,'operational')
     order by p.read_at limit greatest(1,least(coalesce(p_limit,50),100)) for update of p skip locked),
  upd as (update pipeline.coverage_course_pages p set l3_handoff_at=now() from pick where p.course_id=pick.course_id returning p.course_id, p.url, p.evidence_id)
  select coalesce(jsonb_agg(jsonb_build_object('course_id',u.course_id,'storage_path',e.storage_path,'url',u.url)),'[]'::jsonb) into v
    from upd u join pipeline.evidence_artifacts e on e.id=u.evidence_id;
  return v;
end $f$;
revoke all on function public.svc_coverage_tuition_handoff_next(int) from public, anon, authenticated;
grant execute on function public.svc_coverage_tuition_handoff_next(int) to service_role;

create or replace function public.svc_coverage_tuition_handoff_record(p_course_id uuid, p_storage_path text, p_content_hash text, p_bytes int)
returns jsonb language plpgsql security definer set search_path to 'pg_catalog','catalogue','pipeline','security','search' as $f$
declare pg record; v_src uuid; v_ev uuid; v_batch uuid; v_item uuid; v_wi uuid; v_prof uuid; v_target jsonb; v_pc text; v_key text;
begin
  if current_user<>'postgres' and coalesce(auth.role(),'')<>'service_role' then raise exception 'service_role required'; end if;
  select p.*, co.course_code into pg from pipeline.coverage_course_pages p join catalogue.courses co on co.id=p.course_id where p.course_id=p_course_id for update of p;
  if pg.course_id is null or pg.identity_basis is distinct from 'cricos_code' then return jsonb_build_object('queued',false,'reason','not a CRICOS-code page'); end if;
  v_target:=security.coverage_tuition_target_v1(pg.candidates->'fee');
  if v_target is null then return jsonb_build_object('queued',false,'reason','no single international fee candidate'); end if;
  select id into v_prof from pipeline.layer3_model_profiles where 'provider_current_tuition_validation'=any(allowed_task_classes) and enabled and not paused and coalesce((quality_benchmark->>'pass')::boolean,false) order by updated_at desc, id limit 1;
  if v_prof is null then return jsonb_build_object('queued',false,'reason','no qualified Layer 3 profile'); end if;
  v_src:=security.coverage_sweep_source(pg.provider_id);
  select pr.registration_code into v_pc from catalogue.provider_registrations pr where pr.provider_id=pg.provider_id and lower(pr.registration_scheme)='cricos' and coalesce(pr.status,'active') not in ('inactive','cancelled','archived') order by pr.checked_at desc nulls last limit 1;

  -- the sweep source may carry provider tuition (Search gate included); admission itself stays with Layer 3
  if v_pc is not null and not exists (select 1 from pipeline.course_fact_source_qualifications q where q.source_id=v_src and q.provider_cricos=upper(v_pc)) then
    insert into pipeline.course_fact_source_qualifications(source_id,country_id,source_key,source_class,authority_name,provider_cricos,admitted_domains,mapping_strategy,evidence_strategy,qualification_status,notes,metadata)
    select v_src, s.country_id, 'au_'||lower(v_pc)||'_coverage_sweep','provider_first_party', coalesce(pv.display_name,pv.canonical_name), upper(v_pc),
           array['official_course_url','english_requirement','intake','international_fee'],
           'course page accepted only when it prints the course''s CRICOS code',
           'page stored gzipped and as plain text; tuition validated by the qualified Layer 3 model','bounded','Decision 163 admission rule and Option A (Platform Admin 29 Sep 2026)',
           jsonb_build_object('decision','Decision 163','apply_admitted',true,'search_admitted',true,'identity_authority',false,'change_control_ref','CF-CHG-20260915-247')
      from pipeline.sources s join catalogue.providers pv on pv.id=pg.provider_id where s.id=v_src;
  else
    update pipeline.course_fact_source_qualifications set admitted_domains=array(select distinct unnest(admitted_domains||array['international_fee'])), updated_at=now()
     where source_id=v_src and not ('international_fee'=any(admitted_domains));
  end if;
  insert into search.enrichment_source_gates(projection_code,domain_code,source_id,gate_status,approval_ref,approved_at,created_at,updated_at)
  select 'courses','provider_current_tuition',v_src,'approved','CF-CHG-20260915-247; Decision 163 Option A; Platform Admin approval 29 Sep 2026 09:56 IST; admission only through the qualified Layer 3 model',now(),now(),now()
   where not exists (select 1 from search.enrichment_source_gates g where g.projection_code='courses' and g.domain_code='provider_current_tuition' and g.source_id=v_src);

  insert into pipeline.evidence_artifacts(entity_id,source_id,evidence_type,source_url,storage_path,content_hash,mime_type,metadata,capture_version,evidence_group_key)
  values (p_course_id, v_src, 'provider_course_page_text', pg.url, p_storage_path, p_content_hash, 'text/plain',
          jsonb_build_object('derived_from_evidence_id',pg.evidence_id,'bytes',p_bytes,'identity_basis','cricos_code','decision','Decision 163 Option A','capture','coverage-sweep-text-v1'),
          1, 'coverage:'||p_course_id)
  returning id into v_ev;

  v_key:='coverage-sweep-l3:'||to_char(now() at time zone 'UTC','YYYY-MM-DD');
  -- one open batch for the sweep profile (the platform allows one active batch per profile); reused across days
  select b.id into v_batch from pipeline.layer2_run_batches b join pipeline.layer2_source_profiles p on p.id=b.profile_id
   where p.profile_key='au-coverage-sweep-course-pages' and b.status in ('queued','running') order by b.created_at limit 1 for update of b;
  if v_batch is null then
    perform pg_advisory_xact_lock(hashtext('coverage-sweep-l3-batch'));
    select b.id into v_batch from pipeline.layer2_run_batches b join pipeline.layer2_source_profiles p on p.id=b.profile_id
     where p.profile_key='au-coverage-sweep-course-pages' and b.status in ('queued','running') order by b.created_at limit 1;
  end if;
  if v_batch is null then
    insert into pipeline.layer2_run_batches(profile_id,profile_version_id,trigger_type,status,policy_snapshot,started_at,idempotency_key)
    select p.id, p.current_version_id, 'schedule', 'running', jsonb_build_object('decision','Decision 163 Option A','worker','coverage-sweep'), now(), v_key
      from pipeline.layer2_source_profiles p where p.profile_key='au-coverage-sweep-course-pages'
    returning id into v_batch;
  end if;
  insert into pipeline.layer2_run_items(batch_id,entity_type,entity_id,source_url,status,evidence_count,fields_targeted,fields_resolved,started_at,completed_at,outcome_code,evidence_bytes)
  values (v_batch,'course',p_course_id,pg.url,'layer3_required',1,1,0,pg.read_at,now(),'tuition_requires_layer3',p_bytes)
  returning id into v_item;
  update pipeline.layer2_run_batches set target_count=target_count+1, processed_count=processed_count+1, escalated_l3_count=escalated_l3_count+1, heartbeat_at=now(), updated_at=now() where id=v_batch;

  insert into pipeline.layer3_work_items(layer2_run_item_id,evidence_id,entity_type,entity_id,task_class,profile_id,reason,candidate_context)
  values (v_item, v_ev, 'course', p_course_id, 'provider_current_tuition_validation', v_prof, 'requires_layer3_fee_validation',
          jsonb_build_object('provider_current_tuition', v_target,
            'fee_candidates', coalesce((select jsonb_agg(jsonb_build_object('amount',(x->>'amount')::numeric,'currency_code','AUD',
                   'basis',case when coalesce((x->>'total')::boolean,false) then 'total' else 'annual_or_indicative_requires_validation' end,
                   'fee_year',nullif(x->>'fee_year','')::int,
                   'audience',case when coalesce((x->>'international')::boolean,false) then 'international' when coalesce((x->>'domestic')::boolean,false) then 'domestic' else null end))
                from jsonb_array_elements(coalesce(pg.candidates->'fee'->'candidates','[]'::jsonb)) x),'[]'::jsonb),
            'fee_ambiguous', coalesce((pg.candidates->'fee'->>'ambiguous')::boolean,false),
            'identity_match', true,
            'expected_course_code', pg.course_code,
            'extraction_worker', pg.candidates->>'extractor',
            'source_record_id', 'coverage:'||p_course_id))
  on conflict do nothing
  returning id into v_wi;
  update pipeline.coverage_course_pages set l3_work_item_id=v_wi where course_id=p_course_id;
  return jsonb_build_object('queued', v_wi is not null, 'work_item_id', v_wi, 'evidence_id', v_ev, 'run_item_id', v_item);
end $f$;
revoke all on function public.svc_coverage_tuition_handoff_record(uuid,text,text,int) from public, anon, authenticated;
grant execute on function public.svc_coverage_tuition_handoff_record(uuid,text,text,int) to service_role;

-- hand-off every 5 minutes, 50 pages (about 600 an hour); Layer 3 dispatch and admission run on their own schedules
select cron.schedule('coverage-tuition-handoff','*/5 * * * *',$$select pipeline.svc_pilot_submit_nonce('coverage-sweep','{"mode":"tuition_handoff","limit":50}'::jsonb)$$);
