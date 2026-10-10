-- L4-D: Layer 4 team and forecast (read-only).
-- Built from data already recorded: pipeline.layer4_review_items (created, status, claims),
-- pipeline.layer4_decisions (who, when, action). Managers (rank 5+) see every person;
-- others see only their own row (decision 23 Sep 2026). Time per decision = decision time
-- minus claimed_at (L4-B), counted only when the claim was within 12 hours before it.
-- Forecast = waiting / (decisions per day - arrivals per day) over the chosen window.
create or replace function security.layer4_team_forecast_v1_impl(p_days integer default 7)
returns jsonb language plpgsql stable security definer
set search_path to 'pg_catalog','security','pipeline','auth'
as $function$
declare v_actor uuid:=auth.uid(); v_rank int; v_days int:=case when p_days>=30 then 30 else 7 end; v_since timestamptz;
  v_waiting int; v_in int; v_out int; v_net numeric; v_clear jsonb; v_people jsonb; v_daily jsonb; v_ages jsonb; v_outcomes jsonb;
begin
  if v_actor is null then raise exception 'authentication required' using errcode='42501'; end if;
  v_rank:=security.current_role_rank();
  if v_rank<3 then raise exception 'curator role required' using errcode='42501'; end if;
  v_since := date_trunc('day', now()) - make_interval(days=>v_days-1);

  select count(*) into v_waiting from pipeline.layer4_review_items where status='pending';
  select count(*) into v_in from pipeline.layer4_review_items where created_at>=v_since;
  select count(*) into v_out from pipeline.layer4_decisions where created_at>=v_since;
  v_net := (v_out - v_in)::numeric / v_days;
  v_clear := case
    when v_waiting=0 then jsonb_build_object('state','clear','text','Nothing waiting.')
    when v_net<=0 then jsonb_build_object('state','growing','text',format('Not clearing at the current pace: about %s more arrive than are decided each day.', round(-v_net,1)),'per_day',round(v_net,1))
    else jsonb_build_object('state','clearing','days',ceil(v_waiting/v_net),'date',(current_date + ceil(v_waiting/v_net)::int),'text',format('At the current pace the queue clears in about %s days.', ceil(v_waiting/v_net)),'per_day',round(v_net,1)) end;

  select coalesce(jsonb_agg(jsonb_build_object('day',d::date,'arrived',(select count(*) from pipeline.layer4_review_items i where i.created_at>=d and i.created_at<d+interval '1 day'),
         'decided',(select count(*) from pipeline.layer4_decisions x where x.created_at>=d and x.created_at<d+interval '1 day')) order by d),'[]'::jsonb)
    into v_daily from generate_series(v_since, date_trunc('day',now()), interval '1 day') d;

  select jsonb_build_object('0-2',count(*) filter (where now()-created_at<interval '3 days'),
    '3-7',count(*) filter (where now()-created_at>=interval '3 days' and now()-created_at<interval '8 days'),
    '8-14',count(*) filter (where now()-created_at>=interval '8 days' and now()-created_at<interval '15 days'),
    '15+',count(*) filter (where now()-created_at>=interval '15 days'),
    'over_target',count(*) filter (where now()-created_at>interval '7 days'))
    into v_ages from pipeline.layer4_review_items where status='pending';

  select coalesce(jsonb_object_agg(action,n),'{}'::jsonb) into v_outcomes
    from (select action, count(*) n from pipeline.layer4_decisions where created_at>=v_since and (v_rank>=5 or actor_id=v_actor) group by 1) o;

  select coalesce(jsonb_agg(p order by (p->>'decided')::int desc),'[]'::jsonb) into v_people from (
    select jsonb_build_object('actor_id',d.actor_id,'who',coalesce(u.email,'Unknown'),'is_me',d.actor_id=v_actor,'decided',count(*),
      'median_minutes',round((percentile_cont(0.5) within group (order by extract(epoch from d.created_at-i.claimed_at)/60)
          filter (where i.claimed_at is not null and i.claimed_at<=d.created_at and d.created_at-i.claimed_at<interval '12 hours'))::numeric,1),
      'approved',count(*) filter (where d.action in ('approve','edit_and_approve')),'rejected',count(*) filter (where d.action='reject'),
      'sent_back',count(*) filter (where d.action in ('request_more_evidence','return_layer2','return_layer3')),
      'last_at',max(d.created_at)) p
    from pipeline.layer4_decisions d join pipeline.layer4_review_items i on i.id=d.review_item_id left join auth.users u on u.id=d.actor_id
    where d.created_at>=v_since and (v_rank>=5 or d.actor_id=v_actor)
    group by d.actor_id,u.email) x;

  return jsonb_build_object('days',v_days,'scope',case when v_rank>=5 then 'team' else 'me' end,'target_days',7,
    'waiting',v_waiting,'arrived',v_in,'decided',v_out,'forecast',v_clear,'daily',v_daily,'ages',v_ages,'outcomes',v_outcomes,'people',v_people,
    'computed_at',now());
end $function$;
create or replace function public.layer4_team_forecast_v1(p_days integer default 7) returns jsonb language sql stable set search_path to 'pg_catalog','security'
as $function$ select security.layer4_team_forecast_v1_impl(p_days) $function$;
revoke all on function security.layer4_team_forecast_v1_impl(integer) from public, anon;
revoke all on function public.layer4_team_forecast_v1(integer) from public, anon;
grant execute on function security.layer4_team_forecast_v1_impl(integer) to authenticated, service_role;
grant execute on function public.layer4_team_forecast_v1(integer) to authenticated, service_role;
