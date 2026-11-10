-- Guards: F-INT calendar re-read for every eligible provider (Platform Admin 10 Nov 2026 ~23:40, "Re-read and column fix first"; Decisions 273, 274): the setup and the
-- baseline BEFORE the change, on the picker as production holds it (svc_calendar_reread_next_v2 body md5 755ef3b77c797c89fa2caa215e33d4ee). A provider outside the 5 Nov pilot
-- scope, with intake rows missing a date and a stored main-teaching calendar, is set aside as "not needed"; the defect.
\set ON_ERROR_STOP on
\set QUIET on
-- settings as production (10 Nov 2026): calendar.countries AU, NZ, CA
insert into pipeline.platform_toolset_settings
select (jsonb_populate_record(null::pipeline.platform_toolset_settings, to_jsonb(s) || jsonb_build_object('key', 'calendar.countries', 'value', '["AU","NZ","CA"]'::jsonb))).*
  from pipeline.platform_toolset_settings s where s.toolset_key = 'pipeline' limit 1
on conflict do nothing;
update pipeline.platform_toolset_settings set value = '["AU","NZ","CA"]'::jsonb where toolset_key = 'pipeline' and key = 'calendar.countries';
-- the fixture university's stored calendar copy (a production-shaped fact source with evidence)
update pipeline.provider_fact_sources f set evidence_id = (select id from pipeline.evidence_artifacts order by id limit 1), content_hash = 'fixture-cr-1'
 where f.kind = 'intake_calendar' and f.provider_id = (select provider_id from public.pr_d1_prov where name = 'Canberra');
create table public.cr (name text primary key, fact_source_id uuid, provider_id uuid);
insert into public.cr select 'can', f.id, f.provider_id from pipeline.provider_fact_sources f where f.kind = 'intake_calendar' and f.provider_id = (select provider_id from public.pr_d1_prov where name = 'Canberra');
do $$
declare k record; v jsonb;
begin
  select * into k from public.cr where name = 'can';
  if k.fact_source_id is null then raise exception 'no fixture calendar source'; end if;
  if exists (select 1 from security.calendar_reread_relevant_v1() r where r.provider_id = k.provider_id) then raise exception 'the fixture university is in the pilot scope'; end if;
  if not exists (select 1 from catalogue.course_intakes i join catalogue.courses c on c.id = i.course_id where c.provider_id = k.provider_id and i.status = 'active' and c.lifecycle_status = 'active' and i.start_date is null) then
    raise exception 'the fixture university has no intake row missing a date'; end if;
  v := public.svc_calendar_reread_next_v2(60, 'calendar-v2.1');
  if v @> jsonb_build_array(jsonb_build_object('id', k.fact_source_id)) then raise exception 'the pilot-scope picker read a non-pilot calendar'; end if;
  if (select s.state || '|' || s.reason from pipeline.calendar_reread_state s where s.fact_source_id = k.fact_source_id) not like 'no_dates|not needed: no intake row%' then
    raise exception 'the non-pilot calendar was not set aside: %', (select s.state || '|' || s.reason from pipeline.calendar_reread_state s where s.fact_source_id = k.fact_source_id); end if;
  raise notice 'PASS CR baseline (production picker): a calendar of a university outside the 5 Nov pilot scope, whose intake rows miss dates, is set aside as "not needed" and never read (production: 337 copies at 136 providers)';
end $$;
