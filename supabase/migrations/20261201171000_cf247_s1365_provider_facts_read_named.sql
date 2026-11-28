-- CF-247 s1365 (S2-Intakes, for integration by S1-Build; PC-20261128-CONTINUOUS-BUILD-EXECUTE and PC-20261128-NO-ROUTINE-DATA-PR:
-- "If route is missing, record one reusable technical gap for S1-Build (configuration-first)"). Spec s1365, migration 20261201171000 and
-- worker v1.0.66 confirmed by S1-Build (renumbered from the lane's provisional s1363, 28 Nov 2026).
-- Gap: a provider page added with public.admin_provider_central_page (kind intake_calendar, english_policy or fee_schedule), for example
-- a university's next-year (2027) academic calendar, stays 'found' and is never read: its only reader is mode provider_facts of the
-- provider-facts job (83), which is off and also runs paid discovery searches. 1,347 month-only intakes at 15 universities wait for a
-- next-year calendar edition (S2-Intakes, 28 Nov 2026 20:15 AEDT).
-- What it does: public.svc_provider_facts_read_ids_v1 claims only the named sources, with exactly the claim rules of
-- public.svc_provider_facts_read_next (same kinds and fee-chase guard, same statuses, attempts limit, refusal wait, hidden providers),
-- for the worker's new on-demand mode provider_facts_read. The read, storage, parse and proposal path is the existing one, and every
-- Firecrawl call still needs an open on-demand request covering the provider (security.on_demand_open_v1); approval stays with a person.
-- No table, job, schedule, setting or data change. D11: calendar-reread (378) and provider-facts (83) stay as they are.
-- G3: not the consumer API (a new service function outside every frozen name pattern). Locks and active cron asserted unchanged.
-- Replaces: nothing.
-- Retires: nothing.
set local lock_timeout = '5s';  -- fixed: lock wait for the function create

create or replace function public.svc_provider_facts_read_ids_v1(p_ids uuid[])
 returns jsonb
 language plpgsql
 security definer
 set search_path to ''
as $function$
declare v jsonb;
begin
  if current_user <> 'postgres' and coalesce(auth.role(), '') <> 'service_role' then raise exception 'service_role required'; end if;
  if p_ids is null or cardinality(p_ids) = 0 then return '[]'::jsonb; end if;
  with pick as (
    select f.id from pipeline.provider_fact_sources f
     where f.id = any(p_ids)
       and ((f.kind = 'fee_schedule' and security.tuition_chase_enabled(f.provider_id))
            or f.kind in ('english_policy', 'intake_calendar'))
       and (f.status = 'found' or (f.status = 'reading' and f.updated_at < now() - interval '20 minutes'))  -- fixed: stale-lease timer, as read_next
       and f.attempts < security.pipeline_num_v1('retry.provider_facts_attempts', 3)
       and not (f.status = 'found' and security.provider_fact_refusal_v1(f.parse_summary->>'error')
                and f.updated_at > now() - make_interval(hours => security.pipeline_num_v1('retry.provider_facts_refusal_hours', 6)::int))
       and not exists (select 1 from security.provider_hidden_v1 h where h.provider_id = f.provider_id)
     order by f.created_at
     for update skip locked),
  upd as (update pipeline.provider_fact_sources f set status = 'reading', attempts = f.attempts + 1, updated_at = now() from pick where f.id = pick.id
          returning f.id, f.provider_id, f.kind, f.url)
  select coalesce(jsonb_agg(jsonb_build_object('id', u.id, 'provider_id', u.provider_id, 'kind', u.kind, 'url', u.url,
           'country', (select k.iso_alpha2 from catalogue.providers p join ref.countries k on k.id = p.country_id where p.id = u.provider_id),
           'currency', (select a.currency_code from catalogue.providers p join pipeline.coverage_admission_countries a on a.country_id = p.country_id where p.id = u.provider_id))), '[]'::jsonb)
    into v from upd u;
  return v;
end $function$;

comment on function public.svc_provider_facts_read_ids_v1(uuid[]) is
  'CF-247 s1365: claims only the named provider fact sources for the on-demand worker mode provider_facts_read, with the claim rules of svc_provider_facts_read_next. Service role only.';

revoke all on function public.svc_provider_facts_read_ids_v1(uuid[]) from public, anon, authenticated;
grant execute on function public.svc_provider_facts_read_ids_v1(uuid[]) to service_role;

do $t$
declare v_locks bigint := (select count(*) from pipeline.manual_locks); v_jobs bigint := (select count(*) from cron.job where active);
begin
  if not exists (select 1 from pg_proc where oid = 'public.svc_provider_facts_read_ids_v1(uuid[])'::regprocedure) then
    raise exception 's1365: function missing after create';
  end if;
  if (select count(*) from cron.job where active) <> v_jobs or (select count(*) from pipeline.manual_locks) <> v_locks then
    raise exception 's1365: active jobs or manual locks changed';
  end if;
end $t$;
