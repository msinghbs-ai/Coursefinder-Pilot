-- CF-247 s693: every destination data source is a Layer 1 Register source (S2-Build; Platform Admin 18 Nov 2026 22:04, Architectural Alignment
-- Directive: "Register All Destination Data Sources in Layer 1 Register ... Route All Destination Downloads Through Standard Layer 1 Schedule,
-- Supabase Storage & Evidence Records").
--
-- Standing rule: all Destination Data sources must be registered in Layer 1 Register by country and ingest via standard Layer 1 schedule ->
-- Supabase Storage artifact -> Layer 1 Evidence record -> Destination Edition. Future countries (NZ, CA, UK, IE, US) follow the same pattern.
--
-- What it changes (no new table, no new function; G3 untouched at 75 functions and 48 tables)
--   * Five Australian sources in the existing Layer 1 registry (pipeline.sources + pipeline.layer1_source_operations), source system
--     DESTINATION, so they show under Layer 1 Register > Australia with their parser, schedule and health:
--       - ABS Regional Population (abs.gov.au; statistics; hard-coded parser, Table 2 ERP by SUA; loader mode load)
--       - BOM Climate Statistics (IDCJCM0037) (bom.gov.au; statistics; hard-coded parser per station page; mode climate)
--       - Jobs and Skills Australia (JSA) OSCA & Table 1 (jobsandskills.gov.au; statistics; workbook parser; mode facts, scope workbook)
--       - Department of Home Affairs Student & Graduate Visa Rules (immi.homeaffairs.gov.au; regulatory; Firecrawl page-facts reader; mode facts,
--         scope pages)
--       - Fair Work Ombudsman National Minimum Wage (fairwork.gov.au; regulatory; restricted, paused until commercial and automated-read terms
--         are cleared)
--     Each runs monthly through the standard Layer 1 scheduler (coursefinder-layer1-regulatory-scheduler -> layer1-operations-scheduled v1.6.0),
--     and the register's Run now goes through layer1-operations-control v1.11.0; both call layer1-destination-geo-loader v1.4.0 with the
--     internal service key.
--   * security.destination_source_evidence_v1 (md5-guarded edit): every destination artifact's evidence record names its Layer 1 source
--     (source_id, from the caller or by the artifact's host among the registered destination sources' authority domains) and carries
--     fetched_at and licence_terms. The artifact itself is already stored in Supabase Storage (bucket evidence, destination/...).
--   * The three side jobs destination-abs-load, destination-climate-load and destination-page-facts-load are switched off (cron.job
--     active = false) and marked retiring in pipeline.component_register (replaced by the Layer 1 scheduler); their cron.unschedule paste file
--     waits the 14-day retention window (hygiene.retire_after_days). Nothing is dropped or deleted.
-- Replaces: the side jobs destination-abs-load, destination-climate-load, destination-page-facts-load.
-- Retires: the same three jobs (retiring; unscheduled by paste file after the retention window).

-- 1. the five sources (existing registry; one per source, matched by its label and country)
with au as (select id from ref.countries where iso_alpha2 = 'AU'),
v(label, source_type, url, dataset_class, mode, scope, parser, publisher, licence, edition, sydney_day) as (values
  ('ABS Regional Population', 'spreadsheet_download', 'https://www.abs.gov.au/statistics/people/population/regional-population/latest-release', 'statistics', 'load', null,
   'Statistics / hard-coded parser (Table 2: estimated resident population by Significant Urban Area)', 'Australian Bureau of Statistics', 'CC BY 4.0', 'ABS Regional population 2024-25', 1),
  ('BOM Climate Statistics (IDCJCM0037)', 'web', 'https://www.bom.gov.au/climate/averages/', 'statistics', 'climate', null,
   'Statistics / hard-coded parser (one climate statistics page per station)', 'Bureau of Meteorology', 'CC BY 4.0 (Coat of Arms and logo excluded)', 'BOM Climate statistics for Australian locations (IDCJCM0037)', 2),
  ('Jobs and Skills Australia (JSA) OSCA & Table 1', 'spreadsheet_download', 'https://www.jobsandskills.gov.au/data/labour-market-insights', 'statistics', 'facts', 'workbook',
   'Statistics / workbook parser (OSCA Occupation data, Table 1, headings read over two rows)', 'Jobs and Skills Australia', 'CC BY 4.0', 'JSA OSCA Occupation data (2021 Census)', 3),
  ('Department of Home Affairs Student & Graduate Visa Rules', 'web', 'https://immi.homeaffairs.gov.au/visas/getting-a-visa/visa-listing/student-500', 'regulatory', 'facts', 'pages',
   'Regulatory / Firecrawl page-facts reader (rendered, main content; verbatim quotes)', 'Department of Home Affairs', 'CC BY 3.0 AU', 'Home Affairs Student visa (subclass 500) and Temporary Graduate visa (subclass 485) pages', 3),
  ('Fair Work Ombudsman National Minimum Wage', 'web', 'https://www.fairwork.gov.au/minimum-wages', 'regulatory', 'facts', 'pages',
   'Regulatory / restricted: paused until commercial and automated-read terms are cleared', 'Fair Work Ombudsman', 'CC BY-NC 4.0 (non-commercial); robots rules refuse automated reading', 'Fair Work Ombudsman National Minimum Wage', 3)
)
insert into pipeline.sources(source_type, country_id, url, label, trust_rank, status, metadata)
select v.source_type, (select id from au), v.url, v.label, 1, 'active',
       jsonb_strip_nulls(jsonb_build_object('layer', 'layer1', 'source_system', 'DESTINATION', 'dataset_class', v.dataset_class, 'destination_mode', v.mode,
         'destination_scope', v.scope, 'parser', v.parser, 'publisher', v.publisher, 'licence', v.licence, 'destination_edition', v.edition,
         'operational_surface', 'Destination data', 'schedule_day_sydney', v.sydney_day,
         'decision', 'Platform Admin 18 Nov 2026 22:04 (S2-Build, s693): destination data sources are Layer 1 Register sources'))
  from v
 where not exists (select 1 from pipeline.sources s where s.label = v.label and s.country_id = (select id from au) and s.metadata->>'source_system' = 'DESTINATION');

insert into pipeline.layer1_source_operations(source_id, authority_name, authority_domains, expected_format, expected_count_kind, active, paused,
       verification_cadence_days, ingestion_cadence_days, variance_warn_percent, variance_block_percent, auto_ingest, next_verification_at, change_reason)
select s.id, s.metadata->>'publisher', d.domains, d.fmt, d.kind, true, d.paused, 30, 30, 20, 60, not d.paused,  -- monthly; variance warn 20%, block 60%
       case when d.paused then null else
         ((date_trunc('month', now() at time zone 'Australia/Sydney') + interval '1 month' + make_interval(days => (s.metadata->>'schedule_day_sydney')::int - 1, hours => 5, mins => 30))
           at time zone 'Australia/Sydney') end,
       'Registered 18 Nov 2026 (20261118262000, s693): destination data source in the Layer 1 Register'
  from pipeline.sources s
  join (values
    ('ABS Regional Population', array['abs.gov.au', 'www.abs.gov.au'], 'ABS Regional population XLSX workbook (Table 2)', 'localities', false),
    ('BOM Climate Statistics (IDCJCM0037)', array['bom.gov.au', 'www.bom.gov.au'], 'BOM climate statistics HTML pages, one per station', 'climate figures', false),
    ('Jobs and Skills Australia (JSA) OSCA & Table 1', array['jobsandskills.gov.au', 'www.jobsandskills.gov.au'], 'JSA OSCA Occupation data XLSX workbook (Table 1)', 'occupations', false),
    ('Department of Home Affairs Student & Graduate Visa Rules', array['immi.homeaffairs.gov.au'], 'Home Affairs visa pages read rendered through Firecrawl (main content)', 'rules', false),
    ('Fair Work Ombudsman National Minimum Wage', array['fairwork.gov.au', 'www.fairwork.gov.au'], 'Fair Work minimum wages page (restricted; not read)', 'rules', true)
  ) d(label, domains, fmt, kind, paused) on d.label = s.label
 where s.metadata->>'source_system' = 'DESTINATION'
   and not exists (select 1 from pipeline.layer1_source_operations o where o.source_id = s.id);

-- 2. evidence of a destination artifact names its Layer 1 source, fetched_at and licence terms (guarded replacement of a short function)
do $g$
begin
  if md5((select prosrc from pg_proc where oid = 'security.destination_source_evidence_v1(text,text,text,text,jsonb)'::regprocedure)) not in
     ('ae54d39185112934b4457f3031f1f45a') and position('20261118262000' in (select prosrc from pg_proc where oid = 'security.destination_source_evidence_v1(text,text,text,text,jsonb)'::regprocedure)) = 0 then
    raise exception 'live security.destination_source_evidence_v1 differs from the definition this change replaces';
  end if;
end $g$;

create or replace function security.destination_source_evidence_v1(p_url text, p_hash text, p_mime text, p_storage_path text, p_metadata jsonb)
 returns uuid
 language plpgsql
 security definer
 set search_path to ''
as $function$
declare v_id uuid; v_src uuid; v_licence text;
begin
  if coalesce(btrim(p_url), '') = '' or coalesce(btrim(p_hash), '') = '' then raise exception 'source link and file hash are required'; end if;
  -- 20261118262000 (s693): the evidence names its Layer 1 source (the caller's, or the registered destination source whose authority domains
  -- hold the artifact's host), with fetched_at and licence_terms
  select s.id, s.metadata->>'licence' into v_src, v_licence
    from pipeline.sources s join pipeline.layer1_source_operations o on o.source_id = s.id
   where s.metadata->>'source_system' = 'DESTINATION'
     and (s.id = nullif(p_metadata->>'source_id', '')::uuid or lower(substring(p_url from '^https?://([^/:?#]+)')) = any (o.authority_domains))
   order by (s.id = nullif(p_metadata->>'source_id', '')::uuid) desc nulls last, s.created_at
   limit 1;
  select e.id into v_id from pipeline.evidence_artifacts e where e.source_url = p_url and e.content_hash = p_hash order by e.captured_at desc limit 1;
  if v_id is null then
    insert into pipeline.evidence_artifacts(evidence_type, source_url, storage_path, content_hash, mime_type, metadata, review_state, source_id)
    values ('dataset_file', p_url, nullif(btrim(p_storage_path), ''), p_hash, p_mime,
            coalesce(p_metadata, '{}'::jsonb) || jsonb_strip_nulls(jsonb_build_object('layer1_source_id', v_src, 'licence_terms', v_licence, 'fetched_at', now())),
            'captured', v_src)
    returning id into v_id;
  else
    update pipeline.evidence_artifacts
       set storage_path = coalesce(storage_path, nullif(btrim(p_storage_path), '')),
           source_id = coalesce(source_id, v_src),
           metadata = metadata || jsonb_strip_nulls(jsonb_build_object('layer1_source_id', coalesce(source_id, v_src), 'licence_terms', coalesce(metadata->>'licence_terms', v_licence)))
     where id = v_id;
  end if;
  return v_id;
end $function$;
revoke all on function security.destination_source_evidence_v1(text,text,text,text,jsonb) from public, anon, authenticated;

-- the destination evidence already captured names its source too (an update of evidence records; artifacts unchanged)
update pipeline.evidence_artifacts a
   set source_id = s.id,
       metadata = a.metadata || jsonb_strip_nulls(jsonb_build_object('layer1_source_id', s.id, 'licence_terms', coalesce(a.metadata->>'licence_terms', s.metadata->>'licence')))
  from pipeline.sources s join pipeline.layer1_source_operations o on o.source_id = s.id
 where s.metadata->>'source_system' = 'DESTINATION' and a.source_id is null
   and (a.metadata->>'capture' like 'destination%' or a.storage_path like 'destination/%')
   and lower(substring(a.source_url from '^https?://([^/:?#]+)')) = any (o.authority_domains);

-- 3. the side jobs off, retiring
do $j$
declare r record;
begin
  for r in select jobid, jobname from cron.job where jobname in ('destination-abs-load', 'destination-climate-load', 'destination-page-facts-load') and active loop
    perform cron.alter_job(job_id := r.jobid, active := false);
  end loop;
end $j$;
update pipeline.component_register
   set status = 'retiring', replaced_by = 'Layer 1 scheduler (coursefinder-layer1-regulatory-scheduler, source system DESTINATION)',
       retire_after = current_date + security.pipeline_num_v1('hygiene.retire_after_days', 14)::int,
       updated_at = now()
 where kind = 'job' and name in ('destination-abs-load', 'destination-climate-load', 'destination-page-facts-load') and status = 'active';
insert into pipeline.admin_control_events(area, action, target, detail, actor)
values ('layer1', 'destination_sources_registered', 'Layer 1 Register / AU',
        jsonb_build_object('sources', (select jsonb_agg(s.label order by s.label) from pipeline.sources s where s.metadata->>'source_system' = 'DESTINATION'),
          'side_jobs_off', jsonb_build_array('destination-abs-load', 'destination-climate-load', 'destination-page-facts-load'),
          'reason', 'Platform Admin 18 Nov 2026 22:04 (S2-Build, s693): register every destination data source in the Layer 1 Register by country; ingest via the standard Layer 1 schedule, Supabase Storage artifact, Layer 1 evidence record and destination edition',
          'by', 'migration 20261118262000'), '63ba56cb-48d4-4169-98c2-7c4d1f72925b');

-- 4. post-checks
do $$
declare v_def text := (select prosrc from pg_proc where oid = 'security.destination_source_evidence_v1(text,text,text,text,jsonb)'::regprocedure);
begin
  if (select count(*) from pipeline.sources s join pipeline.layer1_source_operations o on o.source_id = s.id
       where s.metadata->>'source_system' = 'DESTINATION' and s.country_id = (select id from ref.countries where iso_alpha2 = 'AU')) <> 5 then
    raise exception 'post-check: five Australian destination sources in the Layer 1 registry';
  end if;
  if not (select o.paused from pipeline.layer1_source_operations o join pipeline.sources s on s.id = o.source_id where s.label = 'Fair Work Ombudsman National Minimum Wage') then
    raise exception 'post-check: Fair Work stays paused';
  end if;
  if exists (select 1 from cron.job where jobname in ('destination-abs-load', 'destination-climate-load', 'destination-page-facts-load') and active) then
    raise exception 'post-check: the side jobs are off';
  end if;
  if position('source_id = coalesce(source_id, v_src)' in v_def) = 0 then raise exception 'post-check: evidence names its source'; end if;
  if (select count(*) from cron.job where jobname = 'coursefinder-layer1-regulatory-scheduler' and active) <> 1 then raise exception 'post-check: the Layer 1 scheduler stays active'; end if;
end $$;
