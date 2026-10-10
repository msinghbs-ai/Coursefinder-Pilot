begin;

-- CF-CHG-20260910-093
-- Durable scheduler attribution for operator-facing task management.
-- Identity snapshots are retained so schedule/action history remains intelligible
-- after an account is disabled or removed. Browser reads expose display labels only.

alter table pipeline.refresh_policies
  add column if not exists created_by uuid,
  add column if not exists created_by_display_snapshot text,
  add column if not exists created_by_email_snapshot text,
  add column if not exists owner_user_id uuid,
  add column if not exists owner_display_snapshot text;

alter table pipeline.refresh_policy_action_events
  add column if not exists actor_display_snapshot text,
  add column if not exists actor_email_snapshot text;

create or replace function security.scheduler_actor_display(p_actor uuid)
returns text
language sql
stable
security definer
set search_path=''
as $function$
  select coalesce(
    nullif(trim(u.raw_user_meta_data->>'full_name'),''),
    nullif(trim(u.raw_user_meta_data->>'name'),''),
    nullif(trim(u.email),''),
    case when p_actor is null then null else 'User '||left(p_actor::text,8) end
  )
  from auth.users u
  where u.id=p_actor
$function$;

revoke all on function security.scheduler_actor_display(uuid) from public,anon,authenticated;
grant execute on function security.scheduler_actor_display(uuid) to service_role;

create or replace function security.scheduler_capture_policy_creator()
returns trigger
language plpgsql
security definer
set search_path=''
as $function$
declare
  v_actor uuid:=auth.uid();
  v_email text;
  v_display text;
begin
  if new.created_by is null and v_actor is not null then
    new.created_by:=v_actor;
  end if;
  if new.created_by is not null and (new.created_by_display_snapshot is null or new.created_by_email_snapshot is null) then
    select
      coalesce(nullif(trim(u.raw_user_meta_data->>'full_name'),''),nullif(trim(u.raw_user_meta_data->>'name'),''),nullif(trim(u.email),''),'User '||left(u.id::text,8)),
      nullif(trim(u.email),'')
    into v_display,v_email
    from auth.users u where u.id=new.created_by;
    new.created_by_display_snapshot:=coalesce(new.created_by_display_snapshot,v_display,'User '||left(new.created_by::text,8));
    new.created_by_email_snapshot:=coalesce(new.created_by_email_snapshot,v_email);
  elsif new.created_by is null and new.created_by_display_snapshot is null then
    new.created_by_display_snapshot:='System / automation';
  end if;
  return new;
end
$function$;

create or replace function security.scheduler_capture_action_actor()
returns trigger
language plpgsql
security definer
set search_path=''
as $function$
declare
  v_email text;
  v_display text;
begin
  if new.actor_id is not null and (new.actor_display_snapshot is null or new.actor_email_snapshot is null) then
    select
      coalesce(nullif(trim(u.raw_user_meta_data->>'full_name'),''),nullif(trim(u.raw_user_meta_data->>'name'),''),nullif(trim(u.email),''),'User '||left(u.id::text,8)),
      nullif(trim(u.email),'')
    into v_display,v_email
    from auth.users u where u.id=new.actor_id;
    new.actor_display_snapshot:=coalesce(new.actor_display_snapshot,v_display,'User '||left(new.actor_id::text,8));
    new.actor_email_snapshot:=coalesce(new.actor_email_snapshot,v_email);
  end if;
  return new;
end
$function$;

revoke all on function security.scheduler_capture_policy_creator() from public,anon,authenticated;
revoke all on function security.scheduler_capture_action_actor() from public,anon,authenticated;

drop trigger if exists refresh_policies_capture_creator on pipeline.refresh_policies;
create trigger refresh_policies_capture_creator
before insert on pipeline.refresh_policies
for each row execute function security.scheduler_capture_policy_creator();

drop trigger if exists refresh_policy_actions_capture_actor on pipeline.refresh_policy_action_events;
create trigger refresh_policy_actions_capture_actor
before insert on pipeline.refresh_policy_action_events
for each row execute function security.scheduler_capture_action_actor();

-- Existing schedules pre-date durable creator capture. Do not manufacture a person.
update pipeline.refresh_policies
set created_by_display_snapshot='System / legacy'
where created_by is null and created_by_display_snapshot is null;

-- Preserve any still-resolvable historical action identity before future account deletion.
update pipeline.refresh_policy_action_events e
set actor_display_snapshot=coalesce(e.actor_display_snapshot,security.scheduler_actor_display(e.actor_id)),
    actor_email_snapshot=coalesce(e.actor_email_snapshot,(select nullif(trim(u.email),'') from auth.users u where u.id=e.actor_id))
where e.actor_id is not null
  and (e.actor_display_snapshot is null or e.actor_email_snapshot is null);

create or replace function security.scheduler_policies_list_v1_browser_bridge(
  p_limit integer default 50,
  p_offset integer default 0
) returns jsonb
language plpgsql
stable
security definer
set search_path=''
as $function$
declare
  v_limit integer:=least(greatest(coalesce(p_limit,50),1),100);
  v_offset integer:=greatest(coalesce(p_offset,0),0);
begin
  if auth.uid() is null or security.current_role_rank() < 3 then
    raise exception 'curator role required' using errcode='42501';
  end if;
  return jsonb_build_object(
    'total',(select count(*) from pipeline.refresh_policies p where p.layer between 1 and 3 and (p.source_id is not null or p.source_profile_id is not null or p.entity_id is not null)),
    'items',coalesce((select jsonb_agg(to_jsonb(x) order by x.next_due_at nulls last,x.id) from (
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
             coalesce(p.created_by_display_snapshot,
               case when p.created_by is null then 'System / legacy'
                    when exists(select 1 from auth.users au where au.id=p.created_by) then security.scheduler_actor_display(p.created_by)
                    else 'Former user'
               end) as created_by_display,
             case when p.created_by is null then 'system_or_legacy'
                  when exists(select 1 from auth.users au where au.id=p.created_by) then 'active'
                  else 'former_user' end as created_by_state,
             p.owner_user_id,
             coalesce(p.owner_display_snapshot,
               case when p.owner_user_id is null then null
                    when exists(select 1 from auth.users au where au.id=p.owner_user_id) then security.scheduler_actor_display(p.owner_user_id)
                    else 'Former user' end) as owner_display,
             case when p.owner_user_id is null then 'unassigned'
                  when exists(select 1 from auth.users au where au.id=p.owner_user_id) then 'active'
                  else 'former_user' end as owner_state
      from pipeline.refresh_policies p
      left join pipeline.sources s on s.id=p.source_id
      left join pipeline.layer2_source_profiles lp on lp.id=p.source_profile_id
      left join pipeline.sources ps on ps.id=lp.source_id
      where p.layer between 1 and 3
        and (p.source_id is not null or p.source_profile_id is not null or p.entity_id is not null)
      order by p.next_due_at nulls last,p.id
      limit v_limit offset v_offset
    ) x),'[]'::jsonb)
  );
end
$function$;

-- Public wrapper remains SECURITY INVOKER; the private bridge independently rank-gates.
create or replace function public.scheduler_policies_list_v1(p_limit integer default 50,p_offset integer default 0)
returns jsonb
language sql
stable
security invoker
set search_path=''
as $function$
  select security.scheduler_policies_list_v1_browser_bridge(p_limit,p_offset)
$function$;

revoke all on function security.scheduler_policies_list_v1_browser_bridge(integer,integer) from public,anon;
grant execute on function security.scheduler_policies_list_v1_browser_bridge(integer,integer) to authenticated,service_role;
revoke all on function public.scheduler_policies_list_v1(integer,integer) from public,anon;
grant execute on function public.scheduler_policies_list_v1(integer,integer) to authenticated,service_role;

commit;
