CREATE OR REPLACE FUNCTION public.admin_scholarship_layer_read(p_layer integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_rank int := security.current_role_rank(); v jsonb;
begin
  if auth.uid() is null or coalesce(v_rank, 0) < 3 then raise exception 'assigned StudySearch role required' using errcode = '42501'; end if;
  v := jsonb_build_object('layer', p_layer, 'can_manage', v_rank >= 6,
    'settings', (select coalesce(jsonb_agg(jsonb_build_object('key', s.key, 'label', s.label, 'help', s.help, 'value', s.value, 'min', s.min_value, 'max', s.max_value, 'unit', s.unit, 'updated_at', s.updated_at, 'reason', s.reason) order by s.key), '[]'::jsonb)
                   from pipeline.scholarship_layer_settings s where s.layer = p_layer),
    'jobs', (select coalesce(jsonb_agg(jsonb_build_object('jobname', j.jobname, 'label', j.label, 'what', j.what, 'settings', j.setting_keys, 'schedule', c.schedule, 'active', c.active,
                     'runs_7d', (select count(*) from cron.job_run_details d where d.jobid = c.jobid and d.start_time > now() - interval '7 days'),
                     'failed_7d', (select count(*) from cron.job_run_details d where d.jobid = c.jobid and d.start_time > now() - interval '7 days' and d.status <> 'succeeded'),
                     'last_run', (select max(d.start_time) from cron.job_run_details d where d.jobid = c.jobid),
                     'last_failure', (select left(d.return_message, 200) from cron.job_run_details d where d.jobid = c.jobid and d.status <> 'succeeded' order by d.start_time desc limit 1)) order by j.sort), '[]'::jsonb)
               from pipeline.scholarship_jobs j left join cron.job c on c.jobname = j.jobname where j.layer = p_layer));
  if p_layer = 1 then
    v := v || jsonb_build_object(
      'countries', (select coalesce(jsonb_agg(jsonb_build_object('code', k.iso_alpha2, 'name', k.name, 'enabled', k.scholarship_ingestion_enabled, 'currency', k.default_currency_code,
                       'providers', (select count(*) from catalogue.providers p where p.country_id = k.id),
                       'universities_queued', (select count(*) from pipeline.scholarship_discovery_providers d join catalogue.providers p on p.id = d.provider_id where p.country_id = k.id),
                       'scholarships', (select count(*) from scholarship.scholarships s join catalogue.providers p on p.id = s.provider_id where p.country_id = k.id and s.lifecycle_status = 'active'),
                       'published', (select count(*) from scholarship.scholarships s join catalogue.providers p on p.id = s.provider_id where p.country_id = k.id and s.lifecycle_status = 'active' and s.publication_status = 'published'),
                       'detail_sources', (select count(*) from pipeline.sources x where x.country_id = k.id and x.source_type = 'scholarship_detail')) order by k.iso_alpha2), '[]'::jsonb)
                     from ref.countries k where k.iso_alpha2 in ('AU', 'NZ', 'CA', 'GB', 'US')),
      'sources', (select coalesce(jsonb_agg(jsonb_build_object('id', x.id, 'country', coalesce(k.iso_alpha2, 'ALL'), 'type', x.source_type, 'role', coalesce(x.metadata->>'scholarship_role', 'reference'),
                     'label', x.label, 'url', x.url, 'status', x.status, 'use', x.metadata->>'use', 'ingestion', x.metadata->>'ingestion', 'reader', x.metadata->>'reader',
                     'qualification', (select q.qualification_status from pipeline.scholarship_source_qualifications q where q.source_key = x.metadata->>'scholarship_source_key' limit 1),
                     'records', (select count(*) from scholarship.scholarships s where s.source_id = x.id and s.lifecycle_status = 'active'),
                     'feed', (select jsonb_build_object('feed', e.feed, 'enabled', e.enabled, 'cadence_hours', e.cadence_hours, 'last_dispatched_at', e.last_dispatched_at, 'next_due_at', e.next_due_at, 'last_error', e.last_error)
                                from pipeline.scholarship_etl_schedules e where e.source_key = x.metadata->>'scholarship_source_key' limit 1))
                     order by coalesce(k.iso_alpha2, 'ZZ'), case coalesce(x.metadata->>'scholarship_role', 'reference') when 'ingest' then 1 when 'provider_pages' then 2 when 'validation' then 3 else 4 end, x.label), '[]'::jsonb)
                   from pipeline.sources x left join ref.countries k on k.id = x.country_id
                  where x.source_type in ('government_scholarship_program', 'scholarship_catalogue', 'scholarship_reference')));
  elsif p_layer = 2 then
    v := v || jsonb_build_object('countries', (
      select coalesce(jsonb_agg(jsonb_build_object('code', k.iso_alpha2,
        'discovery', (select coalesce(jsonb_object_agg(z.status, z.n), '{}'::jsonb) from (select d.status, count(*) n from pipeline.scholarship_discovery_providers d join catalogue.providers p on p.id = d.provider_id where p.country_id = k.id group by 1) z),
        'pages_found', (select count(*) from pipeline.scholarship_page_candidates c join catalogue.providers p on p.id = c.provider_id where p.country_id = k.id),
        'page_reads', (select coalesce(jsonb_object_agg(z.st, z.n), '{}'::jsonb) from (select coalesce(c.read_status, 'waiting') st, count(*) n from pipeline.scholarship_page_candidates c join catalogue.providers p on p.id = c.provider_id where p.country_id = k.id group by 1) z),
        'outcomes', (select coalesce(jsonb_object_agg(z.st, z.n), '{}'::jsonb) from (select coalesce(c.admit_status, case when c.matched_scholarship_id is not null then 'matched_existing' when c.read_status is null then 'waiting' else 'not_decided' end) st, count(*) n from pipeline.scholarship_page_candidates c join catalogue.providers p on p.id = c.provider_id where p.country_id = k.id group by 1) z),
        'refusals', (select coalesce(jsonb_agg(jsonb_build_object('reason', z.r, 'pages', z.n) order by z.n desc), '[]'::jsonb) from (select r, count(*) n from pipeline.scholarship_page_candidates c join catalogue.providers p on p.id = c.provider_id cross join unnest(c.admit_reasons) r where p.country_id = k.id and c.admit_status = 'rejected' group by 1 order by 2 desc limit 6) z),
        'rereads', (select coalesce(jsonb_object_agg(z.st, z.n), '{}'::jsonb) from (select coalesce(sp.read_status, 'waiting') st, count(*) n from pipeline.scholarship_pages sp join scholarship.scholarships s on s.id = sp.scholarship_id join catalogue.providers p on p.id = s.provider_id where p.country_id = k.id group by 1) z)
      ) order by case k.iso_alpha2 when 'AU' then 1 when 'NZ' then 2 when 'CA' then 3 else 4 end), '[]'::jsonb)
      from ref.countries k where k.scholarship_ingestion_enabled and exists (select 1 from catalogue.providers p where p.country_id = k.id)),
      'firecrawl', jsonb_build_object(
        'used', (select coalesce(sum(u.units), 0) from pipeline.coverage_vendor_usage u where u.purpose in ('sch_map', 'sch_search', 'sch_scrape')),
        'cap', (select s.value from pipeline.scholarship_layer_settings s where s.key = 'firecrawl_cap'),
        'reserve', (select s.value from pipeline.scholarship_layer_settings s where s.key = 'firecrawl_reserve'),
        'by_purpose', (select coalesce(jsonb_object_agg(z.purpose, jsonb_build_object('all', z.n, 'last_7_days', z.n7)), '{}'::jsonb)
                         from (select u.purpose, sum(u.units) n, coalesce(sum(u.units) filter (where u.at > now() - interval '7 days'), 0) n7 from pipeline.coverage_vendor_usage u where u.purpose in ('sch_map', 'sch_search', 'sch_scrape') group by 1) z)),
      'worker', (select coalesce(jsonb_agg(jsonb_build_object('mode', z.mode, 'sent', z.sent, 'answered', z.answered, 'ok', z.ok, 'failed', z.failed, 'last_failure', z.lf)), '[]'::jsonb) from (
        select l.mode, count(*) sent, count(r.id) answered, count(*) filter (where r.status_code between 200 and 299) ok,
               count(*) filter (where r.status_code >= 300 or r.timed_out or r.error_msg is not null) failed,
               (select left(coalesce(r2.error_msg, r2.content::text), 200) from pipeline.edge_request_log l2 join net._http_response r2 on r2.id = l2.request_id where l2.mode = l.mode and (r2.status_code >= 300 or r2.timed_out or r2.error_msg is not null) order by l2.created_at desc limit 1) lf
          from pipeline.edge_request_log l left join net._http_response r on r.id = l.request_id
         where l.mode like 'scholarship%' and l.created_at > now() - interval '6 hours' group by l.mode) z));
  elsif p_layer = 3 then
    v := v || jsonb_build_object(
      'ai', (select coalesce(jsonb_agg(jsonb_build_object('country', a.country_code, 'enabled', a.enabled, 'state', a.metadata->>'state', 'profile', (select p.code from pipeline.layer3_model_profiles p where p.id = a.default_profile_id),
                 'task', a.default_task_class, 'budget_usd', a.daily_budget_usd, 'max_records', a.max_records_per_run, 'on_change', a.schedule_on_change,
                 'runs', (select count(*) from pipeline.scholarship_ai_runs r where r.country_code = a.country_code)) order by a.country_code), '[]'::jsonb) from pipeline.scholarship_ai_settings a),
      'profiles', (select coalesce(jsonb_agg(jsonb_build_object('code', p.code, 'model', p.model_identifier, 'enabled', p.enabled, 'paused', p.paused, 'benchmark_pass', coalesce((p.quality_benchmark->>'pass')::boolean, false)) order by p.code), '[]'::jsonb)
                     from pipeline.layer3_model_profiles p where p.code like '%scholarship%' and p.retired_at is null));
  end if;
  return v;
end $function$
