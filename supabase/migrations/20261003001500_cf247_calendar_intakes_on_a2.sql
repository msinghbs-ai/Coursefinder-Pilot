-- CF-247 (Decision 228 switched on, 3 Oct 2026; Platform Admin "yes calendars", "Try again now"). Part A2 of
-- 20261003000500: the Platform Admin's set-by-hand function and the read of waiting semester-only intake reviews.
-- 5. Platform Admin: set a university's start months by hand (from its calendar); the job answers its waiting reviews
create or replace function public.admin_provider_calendar_set(p_provider_id uuid, p_periods jsonb, p_url text, p_note text default null)
returns jsonb language plpgsql security definer set search_path to '' as $f$
declare v_id uuid; v_src uuid; v_clean jsonb;
begin
  if auth.uid() is null or security.current_role_rank() < 6 then raise exception 'Platform Admin role required' using errcode = '42501'; end if;
  if not exists (select 1 from catalogue.providers where id = p_provider_id) then raise exception 'provider not found'; end if;
  if coalesce(btrim(p_url), '') !~* '^https?://' then raise exception 'the calendar page address is required'; end if;
  select jsonb_agg(jsonb_build_object('period', lower(btrim(e->>'period')), 'months', jsonb_build_array((e->>'month')::int)))
    into v_clean
    from jsonb_array_elements(coalesce(p_periods, '[]'::jsonb)) e
   where lower(btrim(e->>'period')) ~ '^(semester|trimester|term|session|study_period|teaching_period) [1-6]$' and (e->>'month') ~ '^([1-9]|1[0-2])$';
  if v_clean is null then raise exception 'give at least one period (for example semester 1) with a month from 1 to 12'; end if;
  insert into pipeline.provider_fact_sources(provider_id, kind, url, title, rank, found_via, status)
  values (p_provider_id, 'intake_calendar', btrim(p_url), 'Calendar page given by a Platform Admin', 9, 'manual', 'found')
  on conflict on constraint provider_fact_sources_key do nothing;
  select id into v_src from pipeline.provider_fact_sources where provider_id = p_provider_id and kind = 'intake_calendar' and url = btrim(p_url);
  insert into pipeline.provider_policy_proposals(provider_id, fact_source_id, kind, parser, url, style, proposal, status, decided_by, decided_at, decision_note)
  values (p_provider_id, v_src, 'intake_calendar', 'set by hand', btrim(p_url), 'by_hand', jsonb_build_object('periods', v_clean), 'approved', auth.uid(), now(), left(p_note, 500))
  returning id into v_id;
  insert into pipeline.admin_control_events(area, action, target, detail, actor)
  values ('policies', 'calendar_set', btrim(p_url), jsonb_build_object('decision', 'Decision 228', 'proposal_id', v_id, 'provider_id', p_provider_id, 'periods', v_clean), auth.uid());
  return jsonb_build_object('id', v_id, 'to_answer', (select count(*) from security.semester_intake_plan_v1(p_provider_id) r where r.outcome = 'answer'));
end $f$;
revoke all on function public.admin_provider_calendar_set(uuid, jsonb, text, text) from public, anon;
grant execute on function public.admin_provider_calendar_set(uuid, jsonb, text, text) to authenticated;

-- 6. read (Pipeline Operator and above): waiting semester-only intake reviews by university
create or replace function public.admin_semester_intakes_read()
returns jsonb language plpgsql stable security definer set search_path to '' as $f$
begin
  if auth.uid() is null or security.current_role_rank() < 4 then raise exception 'Pipeline Operator role required' using errcode = '42501'; end if;
  return (with pl as materialized (select * from security.semester_intake_plan_v1(null)),
          bo as (select pl.provider_id, jsonb_object_agg(pl.outcome, pl.n) o from (select provider_id, outcome, count(*) n from pl group by 1, 2) pl group by 1),
          pe as (select pl.provider_id, array_agg(distinct x order by x) per from pl, unnest(pl.periods) x group by 1)
    select jsonb_build_object('can_set', security.current_role_rank() >= 6,
      'providers', coalesce(jsonb_agg(x order by (x->>'reviews')::int desc), '[]'::jsonb)) from (
      select jsonb_build_object('provider_id', pl.provider_id, 'provider', coalesce(pv.display_name, pv.canonical_name),
               'reviews', count(*), 'answerable', count(*) filter (where pl.outcome = 'answer'),
               'by_outcome', (select bo.o from bo where bo.provider_id = pl.provider_id),
               'periods', (select pe.per from pe where pe.provider_id = pl.provider_id),
               'months', security.calendar_period_months(pl.provider_id),
               'calendar_url', (select f.url from pipeline.provider_fact_sources f where f.provider_id = pl.provider_id and f.kind = 'intake_calendar' order by f.rank limit 1),
               'sample', min(pl.quotes)) x
        from pl join catalogue.providers pv on pv.id = pl.provider_id
       group by pl.provider_id, pv.display_name, pv.canonical_name) s);
end $f$;
revoke all on function public.admin_semester_intakes_read() from public, anon;
grant execute on function public.admin_semester_intakes_read() to authenticated;
