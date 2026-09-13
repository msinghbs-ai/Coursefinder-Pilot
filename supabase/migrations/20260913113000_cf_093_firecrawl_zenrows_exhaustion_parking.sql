begin;

-- CF-CHG-20260910-093
-- Stop provider-specific perfection loops for UQ discovery.
-- The bounded acquisition route is Firecrawl -> ZenRows only.
-- If all unresolved preview-bound discovery courses exhaust their governed attempts,
-- park only those unresolved courses into Layer 3 as blocked/pending Evidence and
-- Layer 4 Human Resolution. A course with a selected post-activation discovery URL
-- is resolved and must never be re-escalated.

-- Route priority is unique per profile. Move the existing UQ route set out of the
-- active range first, then assign the final deterministic order without transient
-- collisions: Firecrawl 10 -> ZenRows 20; legacy routes remain disabled at 110+.
with uq as (
  select id from pipeline.layer2_source_profiles where profile_key='au-uq-course-catalogue'
), providers as (
  select id from pipeline.layer2_acquisition_providers
  where provider_key in ('direct-http','firecrawl','scrape-do','scraperapi','zenrows')
)
update pipeline.layer2_profile_provider_routes r
set priority=priority+1000,updated_at=now()
from uq,providers p
where r.profile_id=uq.id and r.acquisition_provider_id=p.id;

with uq as (
  select id from pipeline.layer2_source_profiles where profile_key='au-uq-course-catalogue'
), providers as (
  select id,provider_key from pipeline.layer2_acquisition_providers
  where provider_key in ('direct-http','firecrawl','scrape-do','scraperapi','zenrows')
)
update pipeline.layer2_profile_provider_routes r
set enabled = p.provider_key in ('firecrawl','zenrows'),
    priority = case p.provider_key
      when 'firecrawl' then 10
      when 'zenrows' then 20
      when 'direct-http' then 110
      when 'scrape-do' then 120
      when 'scraperapi' then 130
      else r.priority
    end,
    updated_at = now()
from uq,providers p
where r.profile_id=uq.id and r.acquisition_provider_id=p.id;

create or replace function security.cf093_park_exhausted_discovery_v1()
returns trigger
language plpgsql
security definer
set search_path='pg_catalog','pipeline','security','catalogue'
as $function$
declare
  v_preview uuid;
  v_profile uuid;
  v_binding pipeline.scheduler_workflow_async_bindings%rowtype;
  v_retry_max integer:=3;
  v_exhausted integer:=0;
  v_total integer:=0;
  v_unresolved uuid[]:='{}'::uuid[];
  v_source uuid;
  v_l3_profile uuid;
  v_rr uuid;
  v_course uuid;
begin
  if new.job_type<>'layer2_discovery' or new.status not in ('failed','completed','cancelled','blocked','succeeded','success') then
    return new;
  end if;

  begin v_preview:=nullif(new.payload->>'scheduler_preview_token','')::uuid; exception when others then v_preview:=null; end;
  begin v_profile:=nullif(new.payload->>'profile_id','')::uuid; exception when others then v_profile:=null; end;
  if v_preview is null or v_profile is null then return new; end if;

  select * into v_binding
  from pipeline.scheduler_workflow_async_bindings b
  where b.preview_token=v_preview and b.profile_id=v_profile
  for update;
  if not found or v_binding.status<>'active' then return new; end if;

  begin
    select greatest(coalesce(nullif(pv.configuration#>>'{retry,max_attempts}','')::integer,3),1)
    into v_retry_max
    from pipeline.layer2_source_profile_versions pv
    where pv.id=v_binding.profile_version_id;
  exception when others then v_retry_max:=3; end;
  v_retry_max:=coalesce(v_retry_max,3);

  -- Reuse the established resolution rule from bounded discovery: a course is no
  -- longer unresolved once a selected non-null discovery candidate exists for the
  -- same profile version, same Preview token and this binding activation window.
  select coalesce(array_agg(c order by c),'{}'::uuid[])
  into v_unresolved
  from unnest(v_binding.discovery_course_ids) c
  where not exists(
    select 1
    from pipeline.layer2_course_discovery_candidates dc
    join pipeline.layer2_provider_attempts pa on pa.id=dc.provider_attempt_id
    join pipeline.jobs j on j.id=pa.job_id
    where dc.course_id=c
      and dc.source_profile_version_id=v_binding.profile_version_id
      and dc.selected=true
      and nullif(dc.discovered_url,'') is not null
      and dc.created_at>=v_binding.activated_at
      and coalesce(j.payload->>'scheduler_preview_token','')=v_preview::text
  );

  v_total:=cardinality(v_unresolved);
  if v_total<=0 then return new; end if;

  with attempts as (
    select (r->>'course_id')::uuid course_id,count(*)::integer n
    from pipeline.jobs j
    cross join lateral jsonb_array_elements(coalesce(j.result->'results','[]'::jsonb)) r
    where j.job_type='layer2_discovery'
      and j.payload->>'scheduler_preview_token'=v_preview::text
      and j.payload->>'profile_id'=v_profile::text
      and nullif(r->>'course_id','') is not null
      and (r->>'course_id')::uuid=any(v_unresolved)
      and r->>'status' in ('failed','candidate')
    group by (r->>'course_id')::uuid
  )
  select count(*)::integer into v_exhausted
  from attempts where n>=v_retry_max;

  if v_exhausted<v_total then return new; end if;

  select source_id into v_source from pipeline.layer2_source_profiles where id=v_profile;
  select id into v_l3_profile
  from pipeline.layer3_model_profiles
  where enabled and not paused
    and 'official_course_url'=any(allowed_task_classes)
    and coalesce((quality_benchmark->>'pass')::boolean,false)=true
  order by updated_at desc,id
  limit 1;

  foreach v_course in array v_unresolved loop
    select id into v_rr
    from pipeline.refresh_requests
    where requested_layer=3
      and entity_type='course'
      and entity_id=v_course
      and revalidation_ref='CF093-DISCOVERY-PARK:'||v_preview::text||':'||v_course::text
    limit 1;

    if v_rr is null then
      insert into pipeline.refresh_requests(
        requested_layer,country_code,source_profile_id,entity_type,entity_id,reason,trigger_type,status,
        requested_by,change_control_ref,source_id,evidence_id,layer3_profile_id,revalidation_ref,schedule_error
      ) values(
        3,'AU',v_profile,'course',v_course,
        'Layer 2 URL discovery exhausted Firecrawl/ZenRows; park for governed Layer 3 when course-specific Evidence is available',
        'manual_governed','blocked',v_binding.actor_id,'CF-CHG-20260910-093',v_source,null,v_l3_profile,
        'CF093-DISCOVERY-PARK:'||v_preview::text||':'||v_course::text,
        'Layer 3 is evidence-gated; no course-specific retained Evidence was produced by bounded discovery'
      ) returning id into v_rr;
    end if;

    if not exists(
      select 1 from pipeline.layer4_review_items li
      where li.entity_type='course' and li.entity_id=v_course and li.field_code='official_course_url'
        and li.status='pending'
        and li.layer2_state->>'scheduler_preview_token'=v_preview::text
    ) then
      insert into pipeline.layer4_review_items(
        entity_type,entity_id,field_code,evidence_id,layer3_interpretation_id,before_value,proposed_value,
        layer2_state,layer3_state,status,escalation_reason,change_control_ref
      ) values(
        'course',v_course,'official_course_url',null,null,null,null,
        jsonb_build_object(
          'status','scraper_exhausted','scheduler_preview_token',v_preview,'source_profile_id',v_profile,
          'retry_max_attempts',v_retry_max,'route','firecrawl_then_zenrows','canonical_mutation_authorised',false
        ),
        jsonb_build_object(
          'status','blocked_pending_evidence','refresh_request_id',v_rr,'profile_id',v_l3_profile,
          'reason','Layer 3 requires governed course-specific Evidence; none was retained by bounded URL discovery'
        ),
        'pending',
        'Firecrawl/ZenRows URL discovery exhausted. Do not perfect site-specific gatekeeper mechanics; resolve through governed Layer 3 when Evidence is available or Layer 4 human review.',
        'CF-CHG-20260910-093'
      );
    end if;
  end loop;

  update pipeline.scheduler_workflow_async_bindings
  set status='handoff_started',handoff_started_at=coalesce(handoff_started_at,now())
  where preview_token=v_preview and profile_id=v_profile and status='active';

  return new;
end
$function$;

revoke all on function security.cf093_park_exhausted_discovery_v1() from public,anon,authenticated;

drop trigger if exists cf093_park_exhausted_discovery_v1 on pipeline.jobs;
create trigger cf093_park_exhausted_discovery_v1
after insert or update of status,completed_at,result on pipeline.jobs
for each row execute function security.cf093_park_exhausted_discovery_v1();

commit;
