-- CF-247 (Decision 228, 2 Oct 2026), part 3 of 3: Platform Admin calendar entry, read, approval report and the 10-minute job.

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
  -- the calendar page the months were taken from is kept as a source (and read as evidence by the reader)
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

-- 7. approving a parsed calendar reports how many reviews it will answer; the job answers them every 10 minutes
do $p$
declare s text; d text;
  o1 text := $o$if p_action = 'approve' and x.kind = 'english_policy' then v := jsonb_build_object('to_fill', coalesce((v_sum->>'write')::int, 0)); end if;$o$;
  n1 text := $n$if p_action = 'approve' and x.kind = 'english_policy' then v := jsonb_build_object('to_fill', coalesce((v_sum->>'write')::int, 0)); end if;
  if p_action = 'approve' and x.kind = 'intake_calendar' then
    v := jsonb_build_object('to_answer', (select count(*) from security.semester_intake_plan_v1(x.provider_id) r where r.outcome = 'answer'));
  end if;$n$;
begin
  select p.prosrc, pg_get_functiondef(p.oid) into s, d from pg_proc p join pg_namespace ns on ns.oid = p.pronamespace
   where ns.nspname = 'public' and p.proname = 'admin_provider_policy_decide';
  if md5(s) is distinct from '878f85c1a27d9f5aa16cac9504855a10' then raise exception 'admin_provider_policy_decide changed (md5 %); not replacing', md5(s); end if;
  if (length(d) - length(replace(d, o1, ''))) / length(o1) <> 1 then raise exception 'piece not found once'; end if;
  execute replace(d, o1, n1);
end $p$;

select cron.schedule('provider-calendar-intakes', '7-59/10 * * * *', $$select security.semester_intake_apply_v1(null)$$);
insert into pipeline.automation_catalogue(jobname, area, sort, label, description, control_rank, batch_editable)
values ('provider-calendar-intakes', 'Admission', 63, 'Answer semester-only intakes from calendars',
        'Every 10 minutes: answers a waiting intake review whose course page names only its study periods ("Semester 1", "Trimester 2") from the university''s approved calendar, where every period named has one start month. The course page stays the evidence; courses with intakes already, or set by hand, are left alone.', 5, false)
on conflict (jobname) do nothing;
