-- Guards: F-INT calendar re-read for every eligible provider, AFTER the change. Proves: the set-aside calendar of a provider outside the pilot scope is woken and read on the next
-- run; a provider whose rows all hold a date stays aside; a country outside calendar.countries stays aside; the Firecrawl refresh path is unchanged and still bounded by the pilot scope.
\set ON_ERROR_STOP on
\set QUIET on
do $$
declare k record; v jsonb; n int;
begin
  select * into k from public.cr where name = 'can';
  if not exists (select 1 from security.calendar_reread_relevant_v2() r where r.provider_id = k.provider_id) then raise exception 'v2 does not list the fixture university'; end if;
  if exists (select 1 from security.calendar_reread_relevant_v1() r where r.provider_id = k.provider_id) then raise exception 'v1 changed'; end if;
  -- countries: outside calendar.countries is not listed
  update pipeline.platform_toolset_settings set value = '["NZ"]'::jsonb where toolset_key = 'pipeline' and key = 'calendar.countries';
  if exists (select 1 from security.calendar_reread_relevant_v2() r where r.provider_id = k.provider_id) then raise exception 'an AU provider is listed when only NZ is set'; end if;
  update pipeline.platform_toolset_settings set value = 'null'::jsonb where toolset_key = 'pipeline' and key = 'calendar.countries';
  if exists (select 1 from security.calendar_reread_relevant_v2()) then raise exception 'a missing or malformed calendar.countries must list nothing'; end if;
  update pipeline.platform_toolset_settings set value = '["AU","NZ","CA"]'::jsonb where toolset_key = 'pipeline' and key = 'calendar.countries';
  -- the woken calendar is read on the next run
  v := public.svc_calendar_reread_next_v2(60, 'calendar-v2.1');
  if not v @> jsonb_build_array(jsonb_build_object('id', k.fact_source_id)) then
    raise exception 'the non-pilot calendar was not read: state %', (select s.state || '|' || s.reason from pipeline.calendar_reread_state s where s.fact_source_id = k.fact_source_id); end if;
  -- a provider whose rows all hold a date is not listed
  select count(*) into n from security.calendar_reread_relevant_v2() r
   where not exists (select 1 from catalogue.course_intakes i join catalogue.courses c on c.id = i.course_id where c.provider_id = r.provider_id and i.status = 'active' and c.lifecycle_status = 'active' and (i.start_date is null or i.intake_year is null));
  if n <> 0 then raise exception '% providers listed with no row missing a date', n; end if;
  -- the Firecrawl refresh path is unchanged
  if md5((select prosrc from pg_proc where oid = 'public.svc_calendar_refresh_v1(text)'::regprocedure)) <> (select md5 from public.cr_refresh_before) then raise exception 'svc_calendar_refresh_v1 changed'; end if;
  if (select prosrc from pg_proc where oid = 'public.svc_calendar_refresh_v1(text)'::regprocedure) not like '%security.calendar_reread_relevant_v1()%' then raise exception 'the refresh no longer reads the pilot scope'; end if;
  raise notice 'PASS CR after: the set-aside calendar of a university outside the pilot scope is woken and read on the next run; only providers in calendar.countries with rows missing a date are listed (none when the setting is missing); the Firecrawl refresh is unchanged and still bounded by the pilot scope';
end $$;
