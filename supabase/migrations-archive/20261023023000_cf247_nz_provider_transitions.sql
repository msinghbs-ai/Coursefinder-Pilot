-- CF-247 (23 Oct 2026). NZ enrichment brief, Release 1 item 1 (Platform Admin decisions 20:42, conditions C1 and 20:56 F1):
-- the NZ polytechnic transition is recorded per provider from the Government's published pages, each row with its source, and a
-- daily job re-checks each flagged provider's website and asks the source finder to look again, because domains and brands move
-- during the transition. C1 closed 23 Oct 2026 20:52 (Beehive release 31 Mar 2026, TEC NZIST page 20 Jul 2026, Ministry of
-- Education VET redesign page): the seed ships as the next migration (20261023024000), every row with its Government source.
-- Replaces: nothing
-- Retires: nothing

create table pipeline.provider_transitions (
  provider_id uuid primary key references catalogue.providers(id) on delete cascade,
  -- standalone_from_2027 and operations_transfer_2027 added at 20:52 (addendum): the three 2027 standalones are not federation members
  risk text not null check (risk in ('none', 're_established_2026', 'standalone_from_2027', 'operations_transfer_2027', 'nzist_federation_until_2027', 'nzist_entity')),
  note text,
  recheck_days int check (recheck_days between 7 and 180),  -- per-provider override of transition.recheck_days (Tai Poutini 14)
  source_url text not null check (source_url ~* '^https://'),
  source_quote text,
  as_at date not null,
  decided_by uuid,
  last_checked_at timestamptz,
  last_check jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
comment on table pipeline.provider_transitions is 'CF-247 23 Oct 2026 (NZ brief C1): NZ providers in the polytechnic transition, each with the Government page it comes from (source_url, source_quote, as_at). risk is set by a person with a source; the daily transition-recheck job only records last_check and queues the website check and source finder.';
alter table pipeline.provider_transitions enable row level security;
revoke all on pipeline.provider_transitions from public, anon, authenticated;

insert into pipeline.platform_toolset_settings(toolset_key, key, label, help, kind, value, min_value, max_value, unit, sort, section, used_by, reason)
values ('pipeline', 'transition.recheck_days', 'Transition: re-check every',
        'How often a provider in the NZ polytechnic transition has its website checked and its course source found again (a provider row may set its own shorter interval).',
        'number', '30'::jsonb, '7', '180', 'days', 150, 'Job sizes', 'job transition-recheck', 'Platform Admin 23 Oct 2026 20:42: NZ brief Release 1')
on conflict (toolset_key, key) do nothing;
insert into pipeline.platform_toolset_settings(toolset_key, key, label, help, kind, value, min_value, max_value, unit, sort, section, used_by, reason)
values ('pipeline', 'batch.transition_recheck', 'Transition: providers re-checked a run', 'Providers the daily transition re-check handles in one run.', 'number', '5'::jsonb, '1', '50', 'providers', 151, 'Job sizes', 'job transition-recheck', 'Platform Admin 23 Oct 2026 20:42: NZ brief Release 1')
on conflict (toolset_key, key) do nothing;

-- the website check and the source finder already exist; this queues them for providers whose interval has passed
create or replace function security.transition_recheck_v1() returns jsonb
 language plpgsql security definer set search_path to '' as $f$
declare v_n int := 0; r record; v_site text;
begin
  for r in select t.provider_id, t.risk, coalesce(t.recheck_days, security.pipeline_num_v1('transition.recheck_days', 30)::int) every
             from pipeline.provider_transitions t
            where t.risk <> 'none'
              and coalesce(t.last_checked_at, '-infinity'::timestamptz) < now() - make_interval(days => coalesce(t.recheck_days, security.pipeline_num_v1('transition.recheck_days', 30)::int))
            order by t.last_checked_at nulls first
            limit security.pipeline_num_v1('batch.transition_recheck', 5)::int loop
    select (security.provider_website_list_v1(p.website))[1] into v_site from catalogue.providers p where p.id = r.provider_id;
    if v_site is not null and not exists (select 1 from pipeline.provider_website_checks w where w.provider_id = r.provider_id and w.state in ('queued', 'leased')) then
      -- requested_by: the job runs as the platform; the row carries the Platform Admin who decided the transition (decided_by)
      insert into pipeline.provider_website_checks(provider_id, url, action, reason, requested_by)
      select r.provider_id, v_site, 'check', 'NZ transition re-check (' || r.risk || ', every ' || r.every || ' days)', t.decided_by
        from pipeline.provider_transitions t where t.provider_id = r.provider_id and t.decided_by is not null;
    end if;
    -- the same "find again" as Course sources › Find again (admin_course_sources): a run row asked to look again
    update pipeline.source_find_runs set next_try_at = now(), step = null, leased_until = null, work = jsonb_build_object('again', true, 'reason', 'NZ transition re-check')
     where provider_id = r.provider_id;
    insert into pipeline.source_find_runs(provider_id, state, next_try_at, work)
    values (r.provider_id, 'none', now(), jsonb_build_object('again', true, 'reason', 'NZ transition re-check')) on conflict (provider_id) do nothing;
    update pipeline.provider_transitions set last_checked_at = now(), last_check = jsonb_build_object('at', now(), 'website', v_site, 'queued', true), updated_at = now()
     where provider_id = r.provider_id;
    v_n := v_n + 1;
  end loop;
  return jsonb_build_object('rechecked', v_n);
end $f$;
revoke execute on function security.transition_recheck_v1() from public, anon, authenticated;

insert into pipeline.automation_catalogue(jobname, area, sort, label, description, control_rank, batch_editable)
values ('transition-recheck', 'Layer 1 register', 9, 'New Zealand: polytechnic transition re-check',
        'Daily at 03:41: for each NZ provider in the polytechnic transition whose interval has passed (Transition: re-check every, or the provider''s own), queues a website check and asks the source finder to look again, so a moved domain or brand is found without a person. Handles Transition: providers re-checked a run providers each run.',
        6, true);
select cron.schedule('transition-recheck', '41 3 * * *', $$select security.transition_recheck_v1()$$);

insert into pipeline.component_register(kind, name, layer, purpose, status, replaces, introduced_in) values
 ('table', 'pipeline.provider_transitions', 'Layer 1', 'NZ polytechnic transition per provider, with the Government source', 'active', '{}', '20261023023000'),
 ('function', 'security.transition_recheck_v1', 'Layer 1', 'Daily re-check of transition providers (website check and source finder queued)', 'active', '{}', '20261023023000'),
 ('job', 'transition-recheck', 'Layer 1', 'Runs security.transition_recheck_v1 daily at 03:41', 'active', '{}', '20261023023000')
on conflict (kind, name) do nothing;

select 'NZ provider transitions: table, re-check job and settings' ok;
