create or replace function security.layer2_auto_discovery_tick_v1()
returns jsonb language plpgsql security definer
set search_path to 'pg_catalog','security','pipeline','catalogue','public'
as $function$
declare s pipeline.layer2_auto_discovery_settings%rowtype; r record; a record; c jsonb; v_actor uuid; v_in_flight int; v_today int;
  v_settled int:=0; v_started int:=0; v_url text; v_tried int; v_res jsonb; v_status text;
begin
  select * into s from pipeline.layer2_auto_discovery_settings where id=1;
  if not coalesce(s.enabled,false) then return jsonb_build_object('enabled',false); end if;

  for r in select distinct run_id from pipeline.layer2_auto_discovery_attempts where status='checking' and run_id is not null loop
    perform public.layer2_scale_pattern_reconcile(r.run_id);
  end loop;
  for a in select * from pipeline.layer2_auto_discovery_attempts where status='checking' loop
    select case when bool_or(qi.status='profile_qualified') then 'passed'
                when bool_or(qi.status='source_pattern_candidate') then 'checking' else 'failed' end
      into v_status from pipeline.layer2_scale_qualification_items qi where qi.run_id=a.run_id and qi.provider_id=a.provider_id;
    if v_status in ('passed','failed') then
      update pipeline.layer2_auto_discovery_attempts set status=v_status, resolved_at=now(),
        detail=detail||jsonb_build_object('reconciled_at',now()) where id=a.id;
      v_settled := v_settled+1;
    end if;
  end loop;

  select count(distinct provider_id) into v_in_flight from pipeline.layer2_auto_discovery_attempts where status='checking';
  select count(distinct provider_id) into v_today from pipeline.layer2_auto_discovery_attempts
   where created_at >= date_trunc('day', now() at time zone 'Australia/Melbourne') at time zone 'Australia/Melbourne' and status<>'needs_person';
  v_actor := public.layer2_automation_actor();
  for r in
    select w.provider_id, w.courses_waiting waiting, w.candidates snap from pipeline.layer2_onboarding_snapshot w
    where w.country_code='AU'
      and exists(select 1 from pipeline.layer2_scale_qualification_items qi where qi.provider_id=w.provider_id and qi.status in ('layer3_required','layer4_required'))
      and not exists(select 1 from pipeline.layer2_auto_discovery_attempts x where x.provider_id=w.provider_id and x.status in ('checking','passed','needs_person'))
    order by w.rank_no
  loop
    exit when v_in_flight >= s.providers_in_flight or v_today >= s.daily_provider_cap or v_actor is null;
    select count(*) into v_tried from pipeline.layer2_auto_discovery_attempts x where x.provider_id=r.provider_id and x.status in ('failed','error');
    if v_tried >= s.candidates_per_provider then
      insert into pipeline.layer2_auto_discovery_attempts(provider_id,status,detail,resolved_at)
      values (r.provider_id,'needs_person',jsonb_build_object('reason','candidates exhausted','tried',v_tried),now());
      continue;
    end if;
    select x into c from jsonb_array_elements(case when jsonb_array_length(coalesce(r.snap,'[]'::jsonb))>0 then r.snap else security.layer2_catalogue_candidates_v1(r.provider_id, 10) end) x
     where not exists(select 1 from pipeline.layer2_auto_discovery_attempts t where t.provider_id=r.provider_id
                      and t.candidate_url=regexp_replace(x->>'url','^http://','https://'))
     order by (x->>'score')::int desc limit 1;
    if c is null and jsonb_array_length(coalesce(r.snap,'[]'::jsonb))>0 then
      select x into c from jsonb_array_elements(security.layer2_catalogue_candidates_v1(r.provider_id, 10)) x
       where not exists(select 1 from pipeline.layer2_auto_discovery_attempts t where t.provider_id=r.provider_id
                        and t.candidate_url=regexp_replace(x->>'url','^http://','https://'))
       order by (x->>'score')::int desc limit 1;
    end if;
    if c is null then
      insert into pipeline.layer2_auto_discovery_attempts(provider_id,status,detail,resolved_at)
      values (r.provider_id,'needs_person',jsonb_build_object('reason', case when v_tried=0 then 'no candidate in stored evidence' else 'no further candidates' end,'tried',v_tried),now());
      continue;
    end if;
    v_url := regexp_replace(c->>'url','^http://','https://');
    begin
      v_res := security.layer2_provider_catalogue_submit_impl(v_actor, r.provider_id, v_url,
        'Automatic discovery: ranked candidate from stored evidence (score '||(c->>'score')||')', false, 'automatic');
      insert into pipeline.layer2_auto_discovery_attempts(provider_id,run_id,candidate_url,score,evidence_id,status,detail)
      values (r.provider_id,(v_res->>'run_id')::uuid,v_url,(c->>'score')::int,(c->>'evidence_id')::uuid,'checking',
              jsonb_build_object('link_text',c->>'link_text','profile_version_id',v_res->>'profile_version_id','waiting_courses',r.waiting));
      v_in_flight := v_in_flight+1; v_today := v_today+1; v_started := v_started+1;
    exception when others then
      insert into pipeline.layer2_auto_discovery_attempts(provider_id,candidate_url,score,evidence_id,status,detail,resolved_at)
      values (r.provider_id,v_url,(c->>'score')::int,(c->>'evidence_id')::uuid,'error',jsonb_build_object('error',left(sqlerrm,300)),now());
    end;
  end loop;
  return jsonb_build_object('enabled',true,'settled',v_settled,'started',v_started,'in_flight',v_in_flight,'started_today',v_today,
    'limits',jsonb_build_object('per_day',s.daily_provider_cap,'in_flight',s.providers_in_flight,'candidates',s.candidates_per_provider));
end $function$;
revoke all on function security.layer2_auto_discovery_tick_v1() from public, anon, authenticated;
