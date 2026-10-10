begin;

-- CF-CHG-20260910-093
-- Runtime-reconciled forward correction: scheduler search must match the same
-- resolved creator/owner display values returned to operators.

create or replace function security.scheduler_policies_list_v1_browser_bridge(
  p_limit integer default 50,
  p_offset integer default 0,
  p_query text default ''
) returns jsonb
language plpgsql
stable
security definer
set search_path=''
as $function$
declare
  v_limit integer:=least(greatest(coalesce(p_limit,50),1),100);
  v_offset integer:=greatest(coalesce(p_offset,0),0);
  v_query text:=lower(trim(coalesce(p_query,'')));
begin
  if auth.uid() is null or security.current_role_rank() < 3 then
    raise exception 'curator role required' using errcode='42501';
  end if;

  return jsonb_build_object(
    'total',(
      select count(*)
      from pipeline.refresh_policies p
      left join pipeline.sources s on s.id=p.source_id
      left join pipeline.layer2_source_profiles lp on lp.id=p.source_profile_id
      left join pipeline.sources ps on ps.id=lp.source_id
      where p.layer between 1 and 3
        and (p.source_id is not null or p.source_profile_id is not null or p.entity_id is not null)
        and (
          v_query=''
          or lower(coalesce(s.label,'')) like '%'||v_query||'%'
          or lower(coalesce(ps.label,'')) like '%'||v_query||'%'
          or lower(coalesce(lp.profile_key,'')) like '%'||v_query||'%'
          or lower(coalesce(lp.domain,'')) like '%'||v_query||'%'
          or lower(coalesce(lp.acquisition_method,'')) like '%'||v_query||'%'
          or lower(coalesce(p.country_code,'')) like '%'||v_query||'%'
          or lower(coalesce(p.entity_type,'')) like '%'||v_query||'%'
          or lower(coalesce(p.entity_id::text,'')) like '%'||v_query||'%'
          or lower(coalesce(p.source_id::text,'')) like '%'||v_query||'%'
          or lower(coalesce(p.source_profile_id::text,'')) like '%'||v_query||'%'
          or lower(coalesce(
               p.created_by_display_snapshot,
               case
                 when p.created_by is null then 'System / legacy'
                 when exists(select 1 from auth.users au where au.id=p.created_by and au.deleted_at is null and (au.banned_until is null or au.banned_until <= now())) then security.scheduler_actor_display(p.created_by)
                 else 'Former user'
               end,'')) like '%'||v_query||'%'
          or lower(coalesce(
               p.owner_display_snapshot,
               case
                 when p.owner_user_id is null then null
                 when exists(select 1 from auth.users au where au.id=p.owner_user_id and au.deleted_at is null and (au.banned_until is null or au.banned_until <= now())) then security.scheduler_actor_display(p.owner_user_id)
                 else 'Former user'
               end,'')) like '%'||v_query||'%'
          or lower(coalesce(p.freshness_class,'')) like '%'||v_query||'%'
          or lower(coalesce(p.cadence_interval::text,'')) like '%'||v_query||'%'
          or lower('layer '||p.layer::text) like '%'||v_query||'%'
          or (v_query='enabled' and p.enabled)
          or (v_query='disabled' and not p.enabled)
        )
    ),
    'items',coalesce((
      select jsonb_agg(to_jsonb(x) order by x.next_due_at nulls last,x.id)
      from (
        select p.id,p.country_code,p.layer,p.source_id,p.source_profile_id,p.entity_type,p.entity_id,
               p.freshness_class,p.cadence_interval,p.next_due_at,p.hash_sensitive,p.important_date_sensitive,
               p.enabled,p.change_control_ref,p.updated_at,
               coalesce(s.label,ps.label,lp.profile_key,
                 case when p.entity_id is not null then initcap(replace(coalesce(p.entity_type,'entity'),'_',' ')) else null end,
                 'Scheduled task') as task_label,
               coalesce(s.label,ps.label) as source_label,
               lp.profile_key as source_profile_key,
               lp.domain as dataset_domain,
               lp.acquisition_method,
               p.created_by,
               coalesce(
                 p.created_by_display_snapshot,
                 case
                   when p.created_by is null then 'System / legacy'
                   when exists(select 1 from auth.users au where au.id=p.created_by and au.deleted_at is null and (au.banned_until is null or au.banned_until <= now())) then security.scheduler_actor_display(p.created_by)
                   else 'Former user'
                 end
               ) as created_by_display,
               case
                 when p.created_by is null then 'system_or_legacy'
                 when exists(select 1 from auth.users au where au.id=p.created_by and au.deleted_at is null and (au.banned_until is null or au.banned_until <= now())) then 'active'
                 else 'former_user'
               end as created_by_state,
               p.owner_user_id,
               coalesce(
                 p.owner_display_snapshot,
                 case
                   when p.owner_user_id is null then null
                   when exists(select 1 from auth.users au where au.id=p.owner_user_id and au.deleted_at is null and (au.banned_until is null or au.banned_until <= now())) then security.scheduler_actor_display(p.owner_user_id)
                   else 'Former user'
                 end
               ) as owner_display,
               case
                 when p.owner_user_id is null then 'unassigned'
                 when exists(select 1 from auth.users au where au.id=p.owner_user_id and au.deleted_at is null and (au.banned_until is null or au.banned_until <= now())) then 'active'
                 else 'former_user'
               end as owner_state
        from pipeline.refresh_policies p
        left join pipeline.sources s on s.id=p.source_id
        left join pipeline.layer2_source_profiles lp on lp.id=p.source_profile_id
        left join pipeline.sources ps on ps.id=lp.source_id
        where p.layer between 1 and 3
          and (p.source_id is not null or p.source_profile_id is not null or p.entity_id is not null)
          and (
            v_query=''
            or lower(coalesce(s.label,'')) like '%'||v_query||'%'
            or lower(coalesce(ps.label,'')) like '%'||v_query||'%'
            or lower(coalesce(lp.profile_key,'')) like '%'||v_query||'%'
            or lower(coalesce(lp.domain,'')) like '%'||v_query||'%'
            or lower(coalesce(lp.acquisition_method,'')) like '%'||v_query||'%'
            or lower(coalesce(p.country_code,'')) like '%'||v_query||'%'
            or lower(coalesce(p.entity_type,'')) like '%'||v_query||'%'
            or lower(coalesce(p.entity_id::text,'')) like '%'||v_query||'%'
            or lower(coalesce(p.source_id::text,'')) like '%'||v_query||'%'
            or lower(coalesce(p.source_profile_id::text,'')) like '%'||v_query||'%'
            or lower(coalesce(
                 p.created_by_display_snapshot,
                 case
                   when p.created_by is null then 'System / legacy'
                   when exists(select 1 from auth.users au where au.id=p.created_by and au.deleted_at is null and (au.banned_until is null or au.banned_until <= now())) then security.scheduler_actor_display(p.created_by)
                   else 'Former user'
                 end,'')) like '%'||v_query||'%'
            or lower(coalesce(
                 p.owner_display_snapshot,
                 case
                   when p.owner_user_id is null then null
                   when exists(select 1 from auth.users au where au.id=p.owner_user_id and au.deleted_at is null and (au.banned_until is null or au.banned_until <= now())) then security.scheduler_actor_display(p.owner_user_id)
                   else 'Former user'
                 end,'')) like '%'||v_query||'%'
            or lower(coalesce(p.freshness_class,'')) like '%'||v_query||'%'
            or lower(coalesce(p.cadence_interval::text,'')) like '%'||v_query||'%'
            or lower('layer '||p.layer::text) like '%'||v_query||'%'
            or (v_query='enabled' and p.enabled)
            or (v_query='disabled' and not p.enabled)
          )
        order by p.next_due_at nulls last,p.id
        limit v_limit offset v_offset
      ) x
    ),'[]'::jsonb)
  );
end
$function$;

commit;
