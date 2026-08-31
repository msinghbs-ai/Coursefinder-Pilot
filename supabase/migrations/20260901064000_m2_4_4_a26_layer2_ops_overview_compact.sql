-- CF-CHG-20260830-048
-- M2.4.4 A26/A28: compact Layer 2 operator overview.
-- The routine Layer 2 workspace does not use the full source-profile registry.
-- Returning all 900+ profiles made the operator RPC >700 KB and breached the
-- unchanged 250 KB / 3 s management-view budgets. Advanced source configuration
-- remains available through its dedicated Administration projection.

create or replace function security.admin_layer2_ops_read(p_operation text,p_args jsonb default '{}'::jsonb)
returns jsonb
language plpgsql
stable security definer
set search_path='pg_catalog','security','pipeline','catalogue','ref','public'
as $$
declare v_rank integer; v_result jsonb;
begin
  if auth.uid() is null then raise exception 'authentication required' using errcode='42501'; end if;
  select security.current_role_rank() into v_rank;
  if v_rank < 4 then raise exception 'pipeline_operator role required' using errcode='42501'; end if;

  if p_operation='layer2_ops_overview' then
    select jsonb_build_object(
      'health',jsonb_build_object(
        'enabled_profiles',(select count(*) from pipeline.layer2_source_profiles where enabled and not paused and domain in ('course_facts','scholarship')),
        'active_runs',(select count(*) from pipeline.layer2_run_batches where status in ('queued','running')),
        'stuck_runs',(select count(*) from pipeline.layer2_run_batches b join pipeline.layer2_execution_policies ep on ep.profile_id=b.profile_id where b.status='running' and coalesce(b.heartbeat_at,b.updated_at,b.started_at,b.created_at)<now()-make_interval(mins=>coalesce(ep.stale_after_minutes,30))),
        'layer3_candidates',(select count(*) from pipeline.layer2_run_items where status='layer3_required'),
        'blocked_items',(select count(*) from pipeline.layer2_run_items where status='blocked')
      ),
      'sources','[]'::jsonb,
      'providers',(select coalesce(jsonb_agg(jsonb_build_object(
        'id',ap.id,'provider_key',ap.provider_key,'display_name',ap.display_name,'enabled',ap.enabled,
        'credential_configured',ap.vault_secret_id is not null,'priority',ap.priority,'rate_limit_per_minute',ap.rate_limit_per_minute,
        'concurrency',ap.concurrency,'last_tested_at',ap.last_tested_at,'last_test_status',ap.last_test_status,
        'billing_config',security.layer2_provider_sanitise_json(ap.billing_config),
        'attempts',(select count(*) from pipeline.layer2_provider_attempts a where a.acquisition_provider_id=ap.id),
        'successes',(select count(*) from pipeline.layer2_provider_attempts a where a.acquisition_provider_id=ap.id and a.status in ('completed','success','succeeded')),
        'failures',(select count(*) from pipeline.layer2_provider_attempts a where a.acquisition_provider_id=ap.id and a.status in ('failed','error','blocked')),
        'http_429',(select count(*) from pipeline.layer2_provider_attempts a where a.acquisition_provider_id=ap.id and a.response_http_status=429),
        'avg_response_ms',(select round(avg(extract(epoch from (a.completed_at-a.started_at))*1000)) from pipeline.layer2_provider_attempts a where a.acquisition_provider_id=ap.id and a.completed_at is not null and a.started_at is not null),
        'last_success_at',(select max(a.completed_at) from pipeline.layer2_provider_attempts a where a.acquisition_provider_id=ap.id and a.status in ('completed','success','succeeded')),
        'recent_failure_streak',(select count(*) from (select a.status from pipeline.layer2_provider_attempts a where a.acquisition_provider_id=ap.id order by a.created_at desc limit 10) z where z.status in ('failed','error','blocked'))
      ) order by ap.priority,ap.display_name),'[]'::jsonb) from pipeline.layer2_acquisition_providers ap where ap.enabled=true),
      'recent_runs',(select coalesce(jsonb_agg(jsonb_build_object(
        'id',b.id,'profile_id',b.profile_id,'trigger_type',b.trigger_type,'status',b.status,'target_count',b.target_count,
        'processed_count',b.processed_count,'resolved_l2_count',b.resolved_l2_count,'escalated_l3_count',b.escalated_l3_count,
        'blocked_count',b.blocked_count,'vendor_units',b.vendor_units,'vendor_cost_usd',b.vendor_cost_usd,'created_at',b.created_at,
        'started_at',b.started_at,'completed_at',b.completed_at,'heartbeat_at',b.heartbeat_at,'updated_at',b.updated_at,
        'runtime_seconds',case when b.started_at is null then null else round(extract(epoch from (coalesce(b.completed_at,now())-b.started_at))) end,
        'progress_percent',case when b.target_count>0 then round((100.0*b.processed_count/b.target_count)::numeric,1) else 0 end
      ) order by b.created_at desc),'[]'::jsonb) from (select * from pipeline.layer2_run_batches order by created_at desc limit 20)b),
      'outcomes',(select jsonb_build_object(
        'queued',count(*) filter(where status='queued'),'processing',count(*) filter(where status in ('discovering','acquiring','extracting')),
        'enriched',count(*) filter(where status='resolved_l2'),'unresolved',count(*) filter(where status='layer3_required'),
        'failed',count(*) filter(where status='blocked'),'deferred',count(*) filter(where status='cancelled'),
        'fields_targeted',coalesce(sum(fields_targeted),0),'fields_resolved',coalesce(sum(fields_resolved),0)
      ) from pipeline.layer2_run_items),
      'evidence_summary',(select jsonb_build_object(
        'count',count(*),
        'unreviewed',count(*) filter(where review_state='unreviewed'),
        'retained_until_365',count(*) filter(where retention_class='standard_365'),
        'held',count(*) filter(where retention_class='hold'),
        'latest',max(captured_at)
      ) from pipeline.evidence_artifacts where coalesce(metadata->>'layer','')='2'),
      'scope_summary',jsonb_build_object(
        'authorised_country_codes',jsonb_build_array('AU'),
        'nz_layer2_course_status','DEFERRED — source qualification/onboarding required',
        'course_catalogue_total',(select count(*) from catalogue.courses cc join catalogue.providers cp2 on cp2.id=cc.provider_id where cp2.canonical_name in ('Federation University Australia','RMIT University (RMIT)','The University of Queensland')),
        'course_queueable_total',(select count(*) from catalogue.courses cc where exists(
          select 1 from pipeline.layer2_source_profiles p2 join pipeline.sources s2 on s2.id=p2.source_id
          where p2.domain='course_facts' and p2.enabled and not p2.paused and s2.provider_id=cc.provider_id
        ) and (
          nullif(cc.course_url,'') is not null
          or exists(select 1 from pipeline.layer2_course_discovery_candidates dc where dc.course_id=cc.id and dc.selected and nullif(dc.discovered_url,'') is not null)
        ))
      )
    ) into v_result;
    return v_result;
  end if;

  if p_operation='layer2_ops_run_detail' then
    return (
      select jsonb_build_object(
        'run',to_jsonb(b),
        'items',(select coalesce(jsonb_agg(to_jsonb(i) order by i.created_at),'[]'::jsonb) from pipeline.layer2_run_items i where i.batch_id=b.id)
      )
      from pipeline.layer2_run_batches b
      where b.id=nullif(p_args->>'id','')::uuid
    );
  end if;

  raise exception 'unsupported layer2 ops read operation: %',p_operation using errcode='22023';
end $$;

revoke all on function security.admin_layer2_ops_read(text,jsonb) from public,anon,authenticated;
grant execute on function security.admin_layer2_ops_read(text,jsonb) to authenticated,service_role;
