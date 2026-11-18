-- CF-247 RM1I climate figures for destination cities (S2-Build, Platform Admin 18 Nov 2026 10:31: "build the non-breaking ingestion/refresh pipeline
-- into destination.locality_metrics (with source attribution and /destination API v3 exposure) so S1-RM-Design can display and approve it under
-- Destination data › City metrics & costs"). Request register REQ-65 (city weather) and REQ-67 / O38; Study Square ruling 13 Nov 2026: climate as
-- long-term averages, summer and winter averages and annual rainfall (admin docs/Roadmap/2026-01/RM1-AUSTRALIA-PAGE-TRACEABILITY.md rows 34-41).
-- The request is for climate averages, not a forecast: no forecast is read or stored.
--
-- What it builds
--   * destination.climate_stations: the Bureau of Meteorology station read for each destination city (data, changed by a Platform Admin), with the
--     season months of its hemisphere. Seeded for the eight capital-city localities (approved SUA rows).
--   * destination.editions row "BOM Climate statistics for Australian locations (IDCJCM0037)", status draft, terms_status pending. Platform Admin
--     18 Nov 2026 10:44 directed the RM1I load "into draft editions with full source attribution so the Platform Admin can review and publish them":
--     figures load as draft while the terms are pending; recording the terms and publishing the edition stay the Platform Admin's. A load is held
--     (writes nothing) only when the edition's terms are marked restricted.
--   * security.destination_climate_load_v1: from the monthly statistics of each station page, five draft figures per city
--     (climate_summer_mean_max_c, climate_summer_mean_min_c, climate_winter_mean_max_c, climate_winter_mean_min_c, climate_annual_rainfall_mm),
--     each with its unit, the years of record as reference period, the station page as source link, the attribution and the stored page as
--     evidence. Figures are written as draft for a person to approve on City metrics & costs (Bulk Approve Drafts included); a dry run
--     (payload dry_run) or an edition marked restricted writes nothing and returns a preview. A figure already approved, published or withdrawn
--     is never changed.
--   * job destination-climate-load (2nd of the month, 05:30 Sydney) and Run now, through edge function layer1-destination-geo-loader (mode climate).
--   * API v3: /destination already returns every approved or published locality figure with its category, key, unit, period, source and attribution
--     (public.website_v3_destination, section localities). Nothing in the consumer API changes (G3 untouched; v3 is read, not reshaped).
-- Nothing is approved or published by this change (a passing load never switches anything on by itself).
--
-- Replaces: nothing (destination cities had no climate loader).
-- Retires: nothing.

-- 1. stations
create table if not exists destination.climate_stations (
  id uuid primary key default gen_random_uuid(),
  locality_id uuid not null references destination.localities(id),
  country_code text not null check (country_code = upper(country_code) and length(country_code) = 2),
  publisher text not null default 'Bureau of Meteorology',
  product text not null default 'IDCJCM0037',
  station_id text not null check (station_id ~ '^[0-9]{4,6}$'),
  station_name text not null,
  page_url text not null check (page_url ~ '^https://'),
  summer_months smallint[] not null check (cardinality(summer_months) between 1 and 6 and summer_months <@ array[1,2,3,4,5,6,7,8,9,10,11,12]::smallint[]),
  winter_months smallint[] not null check (cardinality(winter_months) between 1 and 6 and winter_months <@ array[1,2,3,4,5,6,7,8,9,10,11,12]::smallint[]),
  status text not null default 'active' check (status in ('active', 'retired')),
  note text,
  created_at timestamptz not null default now(),
  updated_by uuid,
  updated_at timestamptz not null default now()
);
comment on table destination.climate_stations is 'CF-247 RM1I (18 Nov 2026): the weather station read for each destination city (one active station per locality and product), with the season months of its hemisphere. Data, changed by a Platform Admin; read by security.destination_climate_load_v1.';
create unique index if not exists climate_stations_active_uq on destination.climate_stations(locality_id, product) where status = 'active';
alter table destination.climate_stations enable row level security;
revoke all on destination.climate_stations from anon, authenticated;

-- southern-hemisphere seasons: summer December to February, winter June to August
insert into destination.climate_stations(locality_id, country_code, station_id, station_name, page_url, summer_months, winter_months, note)
select l.id, 'AU', s.station_id, s.station_name, 'https://www.bom.gov.au/climate/averages/tables/cw_' || s.station_id || '_All.shtml',
       array[12,1,2]::smallint[], array[6,7,8]::smallint[], 'Seeded 18 Nov 2026 (RM1I): the city''s long-record reference station'
  from (values
    ('1031', '066062', 'Sydney (Observatory Hill)'),
    ('2011', '086071', 'Melbourne Regional Office'),
    ('3002', '040913', 'Brisbane'),
    ('5009', '009021', 'Perth Airport'),
    ('4001', '023000', 'Adelaide (West Terrace / ngayirdapira)'),
    ('6003', '094029', 'Hobart (Ellerslie Road)'),
    ('7002', '014015', 'Darwin Airport'),
    ('8001', '070351', 'Canberra Airport')
  ) s(sua_code, station_id, station_name)
  join destination.localities l on l.country_code = 'AU' and l.geography_code = s.sua_code and l.status in ('approved', 'published')
 where not exists (select 1 from destination.climate_stations c where c.locality_id = l.id and c.product = 'IDCJCM0037' and c.status = 'active');

-- 2. the edition (draft; terms pending until the Platform Admin records them)
insert into destination.editions(country_id, domain, edition_label, effective_from, status, source_url, source_owner, attribution_text, terms_status, last_checked_at)
select c.id, 'city_profiles', 'BOM Climate statistics for Australian locations (IDCJCM0037)', current_date, 'draft', 'https://www.bom.gov.au/climate/averages/',
       'Bureau of Meteorology',
       'Source: Bureau of Meteorology, Climate statistics for Australian locations (all years of record). © Commonwealth of Australia.',
       'pending', now()
  from ref.countries c
 where c.iso_alpha2 = 'AU'
   and not exists (select 1 from destination.editions e where e.edition_label = 'BOM Climate statistics for Australian locations (IDCJCM0037)');

-- 3. stations the edge function reads
create or replace function public.svc_destination_climate_stations_v1()
 returns jsonb
 language plpgsql
 stable
 security definer
 set search_path to ''
as $function$
begin
  if current_user <> 'postgres' and coalesce(auth.role(), '') <> 'service_role' then raise exception 'service_role required'; end if;
  return jsonb_build_object(
    'edition', (select jsonb_build_object('id', e.id, 'label', e.edition_label, 'terms_status', e.terms_status, 'attribution', e.attribution_text)
                  from destination.editions e where e.edition_label = 'BOM Climate statistics for Australian locations (IDCJCM0037)'),
    'stations', coalesce((select jsonb_agg(jsonb_build_object('station_id', s.station_id, 'station_name', s.station_name, 'page_url', s.page_url,
                                   'locality_id', s.locality_id, 'locality', l.name) order by l.name)
                            from destination.climate_stations s join destination.localities l on l.id = s.locality_id
                           where s.status = 'active' and s.product = 'IDCJCM0037'), '[]'::jsonb));
end $function$;
comment on function public.svc_destination_climate_stations_v1() is 'RM1I: the climate edition and the active BOM stations (service entry of layer1-destination-geo-loader, mode climate).';

-- 4. the load
create or replace function security.destination_climate_load_v1(p_payload jsonb)
 returns jsonb
 language plpgsql
 security definer
 set search_path to ''
as $function$
declare v_run uuid := nullif(p_payload->>'run_id', '')::uuid; v_ed destination.editions; v_st destination.climate_stations; v_loc text;
        x jsonb; s jsonb; v_ev uuid; v_hold boolean; v_rows jsonb := '[]'::jsonb; v_skipped jsonb := '[]'::jsonb;
        v_written int := 0; v_unchanged int := 0; v_kept int := 0; v_result jsonb;
        m record; v_val numeric; v_period text; v_id uuid; v_status text; v_old numeric;
begin
  select * into v_ed from destination.editions where edition_label = 'BOM Climate statistics for Australian locations (IDCJCM0037)';
  if v_ed.id is null then raise exception 'the climate edition is missing'; end if;
  v_hold := v_ed.terms_status = 'restricted' or coalesce((p_payload->>'dry_run')::boolean, false);
  for x in select * from jsonb_array_elements(coalesce(p_payload->'stations', '[]'::jsonb)) loop
    select * into v_st from destination.climate_stations where station_id = x->>'station_id' and product = 'IDCJCM0037' and status = 'active';
    if v_st.id is null then v_skipped := v_skipped || jsonb_build_object('station_id', x->>'station_id', 'reason', 'not an active station'); continue; end if;
    select l.name into v_loc from destination.localities l where l.id = v_st.locality_id;
    s := x->'statistics';
    if x ? 'error' or s is null or coalesce(jsonb_array_length(x->'missing'), 0) > 0 then
      v_skipped := v_skipped || jsonb_build_object('station_id', v_st.station_id, 'locality', v_loc, 'reason', coalesce(x->>'error', 'statistics missing: ' || coalesce(x->>'missing', 'all')));
      continue;
    end if;
    v_ev := null;
    if not v_hold and coalesce(x->>'sha256', '') <> '' then
      v_ev := security.destination_source_evidence_v1(x->>'page_url', x->>'sha256', 'text/html', nullif(x->>'storage_path', ''),
                jsonb_build_object('capture', 'destination-climate-v1', 'station_id', v_st.station_id, 'prepared', x->>'prepared', 'edition', v_ed.edition_label));
    end if;
    for m in
      select k.key, k.stat, k.months, k.agg, k.unit
        from (values
          ('climate_summer_mean_max_c', 'mean_max_temp_c', v_st.summer_months, 'avg', '°C'),
          ('climate_summer_mean_min_c', 'mean_min_temp_c', v_st.summer_months, 'avg', '°C'),
          ('climate_winter_mean_max_c', 'mean_max_temp_c', v_st.winter_months, 'avg', '°C'),
          ('climate_winter_mean_min_c', 'mean_min_temp_c', v_st.winter_months, 'avg', '°C'),
          ('climate_annual_rainfall_mm', 'mean_rainfall_mm', null::smallint[], 'annual', 'mm')
        ) k(key, stat, months, agg, unit)
    loop
      if m.agg = 'annual' then
        v_val := nullif(s->m.stat->>'annual', '')::numeric;
      else
        select round(avg((s->m.stat->'months'->>(mo - 1))::numeric), 1) into v_val from unnest(m.months) mo;
      end if;
      if v_val is null then v_skipped := v_skipped || jsonb_build_object('station_id', v_st.station_id, 'locality', v_loc, 'reason', m.key || ': no value'); continue; end if;
      v_period := coalesce((s->m.stat->>'first_year') || '–' || (s->m.stat->>'last_year'), 'all years of record');
      v_rows := v_rows || jsonb_build_object('locality', v_loc, 'station_id', v_st.station_id, 'key', m.key, 'value', v_val, 'unit', m.unit, 'reference_period', v_period);
      if v_hold then continue; end if;
      select id, status, numeric_value into v_id, v_status, v_old from destination.locality_metrics
       where locality_id = v_st.locality_id and metric_key = m.key and reference_period = v_period and dataset_edition = v_ed.edition_label;
      if v_id is null then
        insert into destination.locality_metrics(locality_id, metric_category, metric_key, numeric_value, unit, reference_period, dataset_edition, source_url, attribution_text, status, evidence_id)
        values (v_st.locality_id, 'climate', m.key, v_val, m.unit, v_period, v_ed.edition_label, x->>'page_url',
                v_ed.attribution_text || ' Station ' || v_st.station_name || ' (' || v_st.station_id || ').', 'draft', v_ev);
        v_written := v_written + 1;
      elsif v_status <> 'draft' then
        v_kept := v_kept + 1;  -- approved, published, superseded or withdrawn: never changed by a load
      elsif v_old is distinct from v_val then
        update destination.locality_metrics set numeric_value = v_val, source_url = x->>'page_url', evidence_id = coalesce(v_ev, evidence_id), updated_at = now()
         where id = v_id;
        v_written := v_written + 1;
      else
        v_unchanged := v_unchanged + 1;
      end if;
    end loop;
  end loop;
  v_result := jsonb_build_object('edition', v_ed.edition_label, 'terms_status', v_ed.terms_status,
    'held', v_hold, 'held_reason', case when v_ed.terms_status = 'restricted' then 'The edition''s terms are marked restricted; nothing was written.' when v_hold then 'Dry run: nothing was written.' end,
    'figures', jsonb_array_length(v_rows), 'changed', v_written, 'unchanged', v_unchanged, 'kept_reviewed', v_kept,
    'skipped', v_skipped, 'preview', case when v_hold then v_rows end, 'trigger', p_payload->>'trigger');
  insert into pipeline.admin_control_events(area, action, target, detail, actor)
  values ('destination', case when v_hold then 'climate_load_held' else 'climate_load' end, 'destination-climate-load',
          jsonb_strip_nulls(v_result - 'preview' || jsonb_build_object('run_id', v_run)), null);
  perform security.destination_run_finish_v1(v_run, jsonb_strip_nulls(v_result), null);
  return jsonb_strip_nulls(v_result);
end $function$;
comment on function security.destination_climate_load_v1(jsonb) is 'RM1I: five draft climate figures per destination city from BOM monthly statistics (seasons from destination.climate_stations); a dry run or a restricted edition writes nothing (returns a preview); never changes a reviewed figure.';

create or replace function public.svc_destination_climate_load_v1(p_payload jsonb)
 returns jsonb
 language plpgsql
 security definer
 set search_path to ''
as $function$
declare v_run uuid := nullif(p_payload->>'run_id', '')::uuid;
begin
  if current_user <> 'postgres' and coalesce(auth.role(), '') <> 'service_role' then raise exception 'service_role required'; end if;
  if p_payload ? 'error' then
    insert into pipeline.admin_control_events(area, action, target, detail, actor)
    values ('destination', 'climate_load_failed', 'destination-climate-load', jsonb_build_object('error', left(p_payload->>'error', 500), 'run_id', v_run, 'trigger', p_payload->>'trigger'), null);
    perform security.destination_run_finish_v1(v_run, null, left(p_payload->>'error', 500));
    return jsonb_build_object('recorded', true);
  end if;
  return security.destination_climate_load_v1(p_payload);
end $function$;
comment on function public.svc_destination_climate_load_v1(jsonb) is 'RM1I: service entry of layer1-destination-geo-loader mode climate (a load, or the error of a failed one).';

-- 5. fire guard
create or replace function security.destination_climate_load_due_v1()
 returns boolean
 language sql
 stable
 set search_path to ''
as $function$
  -- fixed: fire guard. Scheduled at 18:30 and 19:30 UTC; exactly one is 05:30 in Sydney (AEDT or AEST), and only the 2nd of the month there runs (the ABS load has the 1st)
  select extract(day from (now() at time zone 'Australia/Sydney')) = 2 and extract(hour from (now() at time zone 'Australia/Sydney')) = 5 -- fixed: fire guard
$function$;
comment on function security.destination_climate_load_due_v1() is 'RM1I: true only on the 2nd of the month at 05:xx Sydney time (fire guard of job destination-climate-load).';

-- 6. Run now: the climate job's bounded runner (md5-guarded edit of security.destination_job_run_now_v1)
do $e$
declare
  v_sig constant regprocedure := 'security.destination_job_run_now_v1(text,text,jsonb,uuid)'::regprocedure;
  v_src text := (select p.prosrc from pg_proc p where p.oid = 'security.destination_job_run_now_v1(text,text,jsonb,uuid)'::regprocedure);
  v_def text; v_c int;
  v_old constant text := $o$    ('destination-abs-load', 'layer1-destination-geo-loader', jsonb_build_object('mode', 'load'))$o$;
  v_new constant text := $n$    ('destination-abs-load', 'layer1-destination-geo-loader', jsonb_build_object('mode', 'load')),
    ('destination-climate-load', 'layer1-destination-geo-loader', jsonb_build_object('mode', 'climate'))$n$;
begin
  if position('destination-climate-load' in v_src) > 0 then raise notice 'security.destination_job_run_now_v1: already applied'; return; end if;
  if md5(v_src) <> 'd16a59eddf235cbb23a8cefa0f69b1e6' then raise exception 'live security.destination_job_run_now_v1 differs from the definition this change edits (body md5 %)', md5(v_src); end if;
  v_def := replace(pg_get_functiondef(v_sig), chr(13), '');
  v_c := (length(v_def) - length(replace(v_def, v_old, ''))) / length(v_old);
  if v_c <> 1 then raise exception 'security.destination_job_run_now_v1: the edit must apply exactly once (found %)', v_c; end if;
  execute replace(v_def, v_old, v_new);
  if md5((select p.prosrc from pg_proc p where p.oid = v_sig)) <> md5(replace(v_src, v_old, v_new)) then
    raise exception 'security.destination_job_run_now_v1 after the edit is not the expected body';
  end if;
end $e$;

update pipeline.platform_toolset_settings
   set value = value || '["destination-climate-load"]'::jsonb, updated_at = now(),
       reason = 'RM1I: destination-climate-load added (S2-Build, Platform Admin 18 Nov 2026 10:31); earlier entries kept'
 where toolset_key = 'pipeline' and key = 'run_now.jobs' and not (value ? 'destination-climate-load');

-- grants
revoke all on function security.destination_climate_load_v1(jsonb) from public, anon, authenticated;
revoke all on function security.destination_climate_load_due_v1() from public, anon, authenticated;
revoke all on function public.svc_destination_climate_load_v1(jsonb) from public, anon, authenticated;
revoke all on function public.svc_destination_climate_stations_v1() from public, anon, authenticated;
grant execute on function public.svc_destination_climate_load_v1(jsonb) to service_role;
grant execute on function public.svc_destination_climate_stations_v1() to service_role;

-- 7. the job and the register (the edge function is already on the nonce allowlist)
insert into pipeline.automation_catalogue(jobname, area, sort, label, description, control_rank, batch_editable) values
 ('destination-climate-load', 'Layer 1 register', 301, 'Destination: BOM climate averages',
  'Reads the Bureau of Meteorology climate statistics page of each destination city''s station and loads summer and winter average temperatures and annual rainfall, with attribution, as draft figures for approval on City metrics & costs. Runs on the 2nd of the month at 05:30 Sydney time.',
  6, false)
on conflict (jobname) do nothing;

select cron.schedule('destination-climate-load', '30 18,19 * * *', 'select pipeline.svc_pilot_submit_nonce(''layer1-destination-geo-loader'', jsonb_build_object(''mode'', ''climate'', ''trigger'', ''schedule'')) where security.destination_climate_load_due_v1()');

insert into pipeline.component_register(kind, name, layer, area, purpose, status, introduced_in)
select v.kind, v.name, v.layer, 'Destination data', v.purpose, 'active', '20261118130000'
  from (values
    ('job', 'destination-climate-load', 'L1 register', 'BOM climate averages for destination cities, monthly (RM1I)'),
    ('table', 'destination.climate_stations', 'Reference', 'The weather station and season months of each destination city (RM1I)'),
    ('function', 'security.destination_climate_load_v1', 'Layer 1', 'Draft climate figures from BOM monthly statistics; held while terms are pending (RM1I)'),
    ('function', 'public.svc_destination_climate_load_v1', 'Layer 1', 'Service entry of layer1-destination-geo-loader mode climate (RM1I)'),
    ('function', 'public.svc_destination_climate_stations_v1', 'Layer 1', 'Climate edition and active stations for the loader (RM1I)')
  ) v(kind, name, layer, purpose)
 where not exists (select 1 from pipeline.component_register r where r.kind = v.kind and r.name = v.name);

-- 8. post-checks
do $$
declare v_prev jsonb;
begin
  if (select count(*) from destination.climate_stations where status = 'active') <> 8 then raise exception 'post-check: eight capital-city stations'; end if; -- fixed: the seeded capitals
  if (select terms_status from destination.editions where edition_label = 'BOM Climate statistics for Australian locations (IDCJCM0037)') <> 'pending' then
    raise exception 'post-check: the climate edition terms stay pending until the Platform Admin records them';
  end if;
  if not exists (select 1 from cron.job where jobname = 'destination-climate-load' and active) then raise exception 'post-check: job'; end if;
  if (select command from cron.job where jobname = 'destination-climate-load') ~ '\(\s*[0-9]+\s*[,)]' then raise exception 'post-check: a number in the job command'; end if;
  if not exists (select 1 from pipeline.automation_catalogue where jobname = 'destination-climate-load') then raise exception 'post-check: catalogue'; end if;
  if not (security.toolset_setting('pipeline', 'run_now.jobs') ? 'destination-climate-load') or not (security.toolset_setting('pipeline', 'run_now.jobs') ? 'destination-abs-load') then
    raise exception 'post-check: run_now.jobs';
  end if;
  -- a dry run writes nothing and previews the figures
  v_prev := security.destination_climate_load_v1(jsonb_build_object('trigger', 'post-check', 'dry_run', true, 'stations', jsonb_build_array(jsonb_build_object(
    'station_id', '066062', 'page_url', 'https://www.bom.gov.au/climate/averages/tables/cw_066062_All.shtml', 'missing', '[]'::jsonb,
    'statistics', jsonb_build_object(
      'mean_max_temp_c', jsonb_build_object('months', jsonb_build_array(26,25.8,24.8,22.5,19.6,17.1,16.5,17.8,20.2,22.2,23.7,25.3), 'annual', 21.8, 'first_year', 1859, 'last_year', 2026),
      'mean_min_temp_c', jsonb_build_object('months', jsonb_build_array(18.8,19,17.6,14.7,11.6,9.3,8.1,9,11.1,13.6,15.7,17.5), 'annual', 13.8, 'first_year', 1859, 'last_year', 2026),
      'mean_rainfall_mm', jsonb_build_object('months', jsonb_build_array(101,117.6,129.2,127.1,119.9,132,97.4,80.7,68.3,76.9,83.9,77.6), 'annual', 1213.8, 'first_year', 1858, 'last_year', 2026))))));
  if not (v_prev->>'held')::boolean or (v_prev->>'changed')::int <> 0 or (v_prev->>'figures')::int <> 5 then raise exception 'post-check: held preview %', v_prev; end if;
  if exists (select 1 from destination.locality_metrics where metric_category = 'climate') then raise exception 'post-check: a dry run wrote a figure'; end if;
  if (v_prev->'preview'->0->>'value')::numeric <> 25.7 then raise exception 'post-check: summer mean maximum (Dec, Jan, Feb) %', v_prev->'preview'->0; end if;
end $$;
