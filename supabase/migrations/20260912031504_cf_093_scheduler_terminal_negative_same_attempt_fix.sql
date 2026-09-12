-- CF-CHG-20260910-093
-- A discovery attempt can append both candidate rows and a terminal disposition at the
-- same timestamp. Freshness must therefore compare the latest terminal/selected
-- disposition timestamps rather than whichever same-attempt row happens to sort last.

create or replace function security.scheduler_workflow_recent_terminal_negative_v1(
  p_profile_id uuid,
  p_course_id uuid
) returns boolean
language sql
stable
security definer
set search_path to ''
as $function$
  with profile_ctx as (
    select lp.current_version_id,
           case
             when coalesce(pv.configuration->>'freshness_sla_hours','') ~ '^[0-9]+$'
               then (pv.configuration->>'freshness_sla_hours')::integer
             else null
           end as freshness_sla_hours
    from pipeline.layer2_source_profiles lp
    join pipeline.layer2_source_profile_versions pv on pv.id=lp.current_version_id
    where lp.id=p_profile_id
      and lp.domain='course_facts'
      and lp.enabled
      and not lp.paused
  ), disposition as (
    select
      max(d.created_at) filter (
        where d.selected=false
          and d.status in ('current_page_not_found','ambiguous','identity_mismatch')
      ) as terminal_at,
      max(d.created_at) filter (
        where d.selected=true and nullif(d.discovered_url,'') is not null
      ) as selected_at
    from profile_ctx p
    left join pipeline.layer2_course_discovery_candidates d
      on d.course_id=p_course_id
     and d.source_profile_version_id=p.current_version_id
  )
  select coalesce((
    select p.freshness_sla_hours is not null
       and p.freshness_sla_hours>0
       and x.terminal_at is not null
       and x.terminal_at>=now()-make_interval(hours=>p.freshness_sla_hours)
       and (x.selected_at is null or x.selected_at<x.terminal_at)
    from profile_ctx p cross join disposition x
  ),false)
$function$;

revoke all on function security.scheduler_workflow_recent_terminal_negative_v1(uuid,uuid) from public,anon,authenticated;
grant execute on function security.scheduler_workflow_recent_terminal_negative_v1(uuid,uuid) to service_role;
