-- CF-247 s715: next-wave destination data sources in the Layer 1 Register, by country (S2-Build; Platform Admin 19 Nov 2026 06:45 and 06:50:
-- "Register the official Destination Data sources for NZ, CA, UK, IE, US (population/localities, climate, student/post-study visa rules + living
-- costs, and career wages/outlook) in Layer 1 Register by country"; mandatory rule: every source is registered first, with authority, authority
-- domains, file format, schedule, check and load cadence and licence terms, before any ingestion).
--
-- What was read live (19 Nov 2026 07:40 AEDT): no destination source is registered for NZ, CA, GB (UK), IE or US; the destination loader has
-- readers for page facts (official pages, static or rendered), the ABS workbook, BOM station pages and the JSA workbook only.
-- What it changes (rows in the existing registry; no new table or function; G3 75/48):
--   * Twenty sources, four per country, in pipeline.sources (source system DESTINATION) with their Layer 1 operations row
--     (pipeline.layer1_source_operations): authority, authority domains, expected format, count kind, check and load cadence, licence.
--   * The five visa-rules sources use the existing page-facts reader. NZ, GB and US carry facts (20261119082000) and are made due there; CA
--     (canada.ca: Crown copyright, reproduction terms not open) and IE (irishimmigration.ie: reuse terms not found) are paused until their terms
--     are cleared and their facts are written.
--   * The fifteen statistics sources (population, climate, careers) have no reader yet: they are registered paused with that reason, so the
--     Layer 1 Register shows them as Paused (not Needs attention) until a reader is written for each.
--   * Licence terms are recorded as the publisher states them; an edition is published only once its terms are approved (destination guard).
-- Nothing is dropped or deleted.
-- Replaces: nothing (new registrations).
-- Retires: nothing.

with v(cc, label, source_type, url, dataset_class, mode, scope, parser, publisher, licence, domains, fmt, count_kind, load_days, active_now, pause_reason) as (values
  -- New Zealand
  ('NZ', 'Stats NZ Subnational population estimates', 'spreadsheet_download', 'https://www.stats.govt.nz/topics/population-estimates-and-projections', 'statistics', 'load', null,
   'Statistics / no reader yet (CSV from Stats NZ)', 'Stats NZ Tatauranga Aotearoa', 'CC BY 4.0', array['stats.govt.nz', 'www.stats.govt.nz', 'infoshare.stats.govt.nz'],
   'Stats NZ population estimates CSV', 'localities', 90, false, 'Awaiting a reader: no parser for Stats NZ population estimates yet'),
  ('NZ', 'NIWA climate normals (CliFlo)', 'web', 'https://cliflo.niwa.co.nz/', 'statistics', 'climate', null,
   'Statistics / no reader yet (climate normals by station)', 'Earth Sciences New Zealand (formerly NIWA)', 'Pending: CliFlo terms require registration; reuse terms to be cleared',
   array['niwa.co.nz', 'cliflo.niwa.co.nz', 'www.niwa.co.nz'], 'Climate normals by station', 'climate figures', 90, false, 'Awaiting a reader and cleared reuse terms (CliFlo registration terms)'),
  ('NZ', 'Immigration New Zealand Student and Post-Study Work Visa rules', 'web', 'https://immigration.govt.nz/process-to-apply/applying-for-a-visa/providing-evidence-and-documents-to-support-your-visa-application/student-fund-requirements/', 'regulatory', 'facts', 'pages',
   'Regulatory / page-facts reader (rendered; verbatim quotes)', 'Immigration New Zealand (MBIE)', 'Pending: New Zealand Government reuse terms to be confirmed on the site',
   array['immigration.govt.nz', 'www.immigration.govt.nz'], 'Immigration New Zealand pages read rendered', 'rules', 30, true, null),
  ('NZ', 'MBIE Occupation Outlook', 'web', 'https://occupationoutlook.mbie.govt.nz/', 'statistics', 'facts', 'workbook',
   'Statistics / no reader yet (occupation outlook and pay)', 'Ministry of Business, Innovation and Employment', 'Pending: MBIE reuse terms to be confirmed',
   array['occupationoutlook.mbie.govt.nz', 'mbie.govt.nz', 'www.mbie.govt.nz'], 'Occupation outlook pages or data download', 'occupations', 90, false, 'Awaiting a reader: no parser for MBIE Occupation Outlook yet'),
  -- Canada
  ('CA', 'Statistics Canada population estimates (CMA and CA)', 'spreadsheet_download', 'https://www150.statcan.gc.ca/t1/tbl1/en/tv.action?pid=1710014801', 'statistics', 'load', null,
   'Statistics / no reader yet (CSV table download)', 'Statistics Canada', 'Statistics Canada Open Licence', array['statcan.gc.ca', 'www150.statcan.gc.ca', 'www.statcan.gc.ca'],
   'Statistics Canada table CSV', 'localities', 90, false, 'Awaiting a reader: no parser for the Statistics Canada population table yet'),
  ('CA', 'Environment and Climate Change Canada Canadian Climate Normals', 'web', 'https://climate.weather.gc.ca/climate_normals/', 'statistics', 'climate', null,
   'Statistics / no reader yet (climate normals by station)', 'Environment and Climate Change Canada', 'Open Government Licence – Canada', array['climate.weather.gc.ca', 'weather.gc.ca'],
   'Climate normals by station (CSV)', 'climate figures', 90, false, 'Awaiting a reader: no parser for Canadian Climate Normals yet'),
  ('CA', 'IRCC Study Permit and Post-Graduation Work Permit rules', 'web', 'https://www.canada.ca/en/immigration-refugees-citizenship/services/study-canada/study-permit/get-documents/financial-support.html', 'regulatory', 'facts', 'pages',
   'Regulatory / page-facts reader (verbatim quotes)', 'Immigration, Refugees and Citizenship Canada', 'Pending: canada.ca content is Crown copyright; reproduction terms are not an open licence',
   array['canada.ca', 'www.canada.ca'], 'canada.ca pages', 'rules', 30, false, 'Awaiting cleared reuse terms (canada.ca Crown copyright) before facts are written'),
  ('CA', 'Job Bank Canada wages and outlooks', 'spreadsheet_download', 'https://open.canada.ca/data/en/dataset/adad580f-76b0-4502-bd05-20c125de9116', 'statistics', 'facts', 'workbook',
   'Statistics / no reader yet (wages CSV)', 'Employment and Social Development Canada (Job Bank)', 'Open Government Licence – Canada', array['open.canada.ca', 'jobbank.gc.ca', 'www.jobbank.gc.ca'],
   'Job Bank wages CSV', 'occupations', 90, false, 'Awaiting a reader: no parser for Job Bank wages yet'),
  -- United Kingdom (ISO GB)
  ('GB', 'ONS mid-year population estimates', 'spreadsheet_download', 'https://www.ons.gov.uk/peoplepopulationandcommunity/populationandmigration/populationestimates', 'statistics', 'load', null,
   'Statistics / no reader yet (ONS workbook)', 'Office for National Statistics', 'Open Government Licence v3.0', array['ons.gov.uk', 'www.ons.gov.uk'],
   'ONS population estimates workbook', 'localities', 90, false, 'Awaiting a reader: no parser for ONS population estimates yet'),
  ('GB', 'Met Office UK climate averages', 'web', 'https://www.metoffice.gov.uk/research/climate/maps-and-data/uk-climate-averages', 'statistics', 'climate', null,
   'Statistics / no reader yet (climate averages by station)', 'Met Office', 'Pending: Met Office page terms to be confirmed (Crown copyright)', array['metoffice.gov.uk', 'www.metoffice.gov.uk'],
   'Climate averages by station', 'climate figures', 90, false, 'Awaiting a reader and confirmed reuse terms'),
  ('GB', 'UKVI Student visa and Graduate route (GOV.UK)', 'web', 'https://www.gov.uk/student-visa/money', 'regulatory', 'facts', 'pages',
   'Regulatory / page-facts reader (static; verbatim quotes)', 'UK Visas and Immigration (Home Office)', 'Open Government Licence v3.0', array['gov.uk', 'www.gov.uk'],
   'GOV.UK pages', 'rules', 30, true, null),
  ('GB', 'ONS Annual Survey of Hours and Earnings (ASHE)', 'spreadsheet_download', 'https://www.ons.gov.uk/employmentandlabourmarket/peopleinwork/earningsandworkinghours/datasets/occupation4digitsoc2010ashetable14', 'statistics', 'facts', 'workbook',
   'Statistics / no reader yet (ASHE workbook)', 'Office for National Statistics', 'Open Government Licence v3.0', array['ons.gov.uk', 'www.ons.gov.uk'],
   'ASHE occupation workbook', 'occupations', 365, false, 'Awaiting a reader: no parser for ASHE yet'),
  -- Ireland
  ('IE', 'CSO Census population by town', 'spreadsheet_download', 'https://data.cso.ie/', 'statistics', 'load', null,
   'Statistics / no reader yet (PxStat table)', 'Central Statistics Office', 'CC BY 4.0', array['cso.ie', 'www.cso.ie', 'data.cso.ie'],
   'CSO PxStat table', 'localities', 365, false, 'Awaiting a reader: no parser for CSO PxStat yet'),
  ('IE', 'Met Éireann climate averages', 'web', 'https://www.met.ie/climate/30-year-averages', 'statistics', 'climate', null,
   'Statistics / no reader yet (30-year averages by station)', 'Met Éireann', 'CC BY 4.0', array['met.ie', 'www.met.ie'],
   '30-year averages by station', 'climate figures', 90, false, 'Awaiting a reader: no parser for Met Éireann averages yet'),
  ('IE', 'Immigration Service Delivery Stamp 2 and Stamp 1G rules', 'web', 'https://www.irishimmigration.ie/my-situation-has-changed-since-i-arrived-in-ireland/third-level-graduate-programme/', 'regulatory', 'facts', 'pages',
   'Regulatory / page-facts reader (verbatim quotes)', 'Immigration Service Delivery (Department of Justice)', 'Pending: reuse terms not found on irishimmigration.ie',
   array['irishimmigration.ie', 'www.irishimmigration.ie'], 'irishimmigration.ie pages', 'rules', 30, false, 'Awaiting cleared reuse terms before facts are written'),
  ('IE', 'CSO Graduate Outcomes (earnings)', 'spreadsheet_download', 'https://www.cso.ie/en/statistics/education/graduateoutcomes/', 'statistics', 'facts', 'workbook',
   'Statistics / no reader yet (PxStat table)', 'Central Statistics Office', 'CC BY 4.0', array['cso.ie', 'www.cso.ie', 'data.cso.ie'],
   'CSO PxStat table', 'occupations', 365, false, 'Awaiting a reader: no parser for CSO Graduate Outcomes yet'),
  -- United States
  ('US', 'U.S. Census Bureau population estimates (metro and city)', 'spreadsheet_download', 'https://www.census.gov/programs-surveys/popest.html', 'statistics', 'load', null,
   'Statistics / no reader yet (CSV)', 'U.S. Census Bureau', 'U.S. Government work (public domain, 17 U.S.C. 105)', array['census.gov', 'www.census.gov', 'www2.census.gov'],
   'Population estimates CSV', 'localities', 365, false, 'Awaiting a reader: no parser for Census population estimates yet'),
  ('US', 'NOAA NCEI U.S. Climate Normals', 'spreadsheet_download', 'https://www.ncei.noaa.gov/products/land-based-station/us-climate-normals', 'statistics', 'climate', null,
   'Statistics / no reader yet (normals CSV by station)', 'NOAA National Centers for Environmental Information', 'U.S. Government work (public domain, 17 U.S.C. 105)',
   array['ncei.noaa.gov', 'www.ncei.noaa.gov'], 'Normals CSV by station', 'climate figures', 365, false, 'Awaiting a reader: no parser for U.S. Climate Normals yet'),
  ('US', 'USCIS and Department of State F-1 and OPT rules', 'web', 'https://www.uscis.gov/node/50597', 'regulatory', 'facts', 'pages',
   'Regulatory / page-facts reader (static; verbatim quotes)', 'U.S. Citizenship and Immigration Services; U.S. Department of State', 'U.S. Government work (public domain, 17 U.S.C. 105)',
   array['uscis.gov', 'www.uscis.gov', 'travel.state.gov'], 'USCIS and travel.state.gov pages', 'rules', 30, true, null),
  ('US', 'BLS Occupational Employment and Wage Statistics (OEWS)', 'spreadsheet_download', 'https://www.bls.gov/oes/tables.htm', 'statistics', 'facts', 'workbook',
   'Statistics / no reader yet (OEWS workbook)', 'U.S. Bureau of Labor Statistics', 'U.S. Government work (public domain, 17 U.S.C. 105)', array['bls.gov', 'www.bls.gov'],
   'OEWS workbook', 'occupations', 365, false, 'Awaiting a reader: no parser for OEWS yet')
),
ins as (
  insert into pipeline.sources(source_type, country_id, url, label, trust_rank, status, metadata)
  select v.source_type, c.id, v.url, v.label, 1, 'active',
         jsonb_strip_nulls(jsonb_build_object('layer', 'layer1', 'source_system', 'DESTINATION', 'dataset_class', v.dataset_class, 'destination_mode', v.mode,
           'destination_scope', v.scope, 'parser', v.parser, 'publisher', v.publisher, 'licence', v.licence, 'operational_surface', 'Destination data', 'wave', 'next-wave 19 Nov 2026',
           'decision', 'Platform Admin 19 Nov 2026 06:45 and 06:50 (S2-Build, s715): next-wave destination sources registered in the Layer 1 Register first, by country'))
    from v join ref.countries c on c.iso_alpha2 = v.cc
   where not exists (select 1 from pipeline.sources s where s.label = v.label and s.country_id = c.id and s.metadata->>'source_system' = 'DESTINATION')
  returning id, label)
insert into pipeline.layer1_source_operations(source_id, authority_name, authority_domains, expected_format, expected_count_kind, active, paused,
       verification_cadence_days, ingestion_cadence_days, variance_warn_percent, variance_block_percent, auto_ingest, next_verification_at, change_reason)
select ins.id, v.publisher, v.domains, v.fmt, v.count_kind, true, not v.active_now, 30, v.load_days, 20, 60, v.active_now, null,  -- check monthly; variance warn 20%, block 60%
       case when v.active_now then 'Registered 19 Nov 2026 (20261119081000, s715): visa-rules source; facts and first run in 20261119082000'
            else 'Registered 19 Nov 2026 (20261119081000, s715), paused: ' || v.pause_reason end
  from ins join v on v.label = ins.label;

-- post-checks (rolled back with the dry run if any fails)
do $chk$
declare v_n int; v_drift jsonb;
begin
  select count(*) into v_n from pipeline.sources s join pipeline.layer1_source_operations o on o.source_id = s.id join ref.countries c on c.id = s.country_id
   where s.metadata->>'source_system' = 'DESTINATION' and c.iso_alpha2 in ('NZ', 'CA', 'GB', 'IE', 'US');
  if v_n <> 20 then raise exception 'post-check: expected 20 next-wave sources in the Layer 1 Register, found %', v_n; end if;
  if exists (select 1 from pipeline.sources s join pipeline.layer1_source_operations o on o.source_id = s.id
              where s.metadata->>'wave' = 'next-wave 19 Nov 2026' and (coalesce(o.authority_name, '') = '' or cardinality(o.authority_domains) = 0
                    or coalesce(o.expected_format, '') = '' or coalesce(s.metadata->>'licence', '') = '' or o.verification_cadence_days is null or o.ingestion_cadence_days is null)) then
    raise exception 'post-check: a next-wave source lacks authority, domains, format, cadence or licence';
  end if;
  v_drift := security.consumer_api_check_v1();
  if jsonb_typeof(v_drift) = 'array' then
    if jsonb_array_length(v_drift) > 0 then raise exception 'consumer API drift %', v_drift; end if;
  elsif jsonb_array_length(coalesce(v_drift->'drift', '[]'::jsonb)) > 0 then raise exception 'consumer API drift %', v_drift->'drift';
  end if;
end $chk$;
