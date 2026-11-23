-- CF-247 s1017 (S1-RM-Design; Platform Admin 24 Nov 2026 05:33 AEDT: "proceed immediately with your $0 deterministic cell-to-row adapter for proven PDF_TABLE /
-- HTML_TABLE grids ... run Auckland"). AER v2 proven-structure source (Standing Authority Charter 23 Nov 2026 item 1); no model, no Firecrawl, $0.
-- 1. Settings (G2) for the worker's new ruled-grid reader (coverage-sweep-worker-v1.0.36, entry-ruled-grid.ts): reading.entry_ruled_grid_reader_on (on),
--    reading.entry_ruled_grid_min_rows, reading.entry_ruled_grid_min_columns, and reading.entry_det_only_lease_on (on).
-- 2. reading.entry_grid_headings names "Additional programme entry" a course fact (University of Auckland's column of extra programme requirements: a
--    portfolio, an audition; never a minimum of a qualification), so the grid reader does not hold the read for an unmapped heading.
-- 3. public.svc_entry_matrix_next: while the entry_matrices route has no usable model (switched off, no qualified model, or held with no open on-demand
--    request), stored PDFs are still leased, with det_only true and no model, for the deterministic readers (cell, aligned grid, ruled grid); the worker
--    holds a PDF none of them proves and never sends it to a model. Pages that are not PDFs are not leased while there is no model, as before.
--    With a usable model the function behaves exactly as before. Replaced only from the definition it was written against (md5 checked).
-- Rows still go through svc_entry_matrix_record unchanged: a provider's first matrix read is a Layer 4 item a person approves before any row is admitted.
-- G1: no job. G3: no consumer object (75/48 checked). Manual locks and active cron jobs checked unchanged.
-- Replaces: nothing
-- Retires: nothing
set local lock_timeout = '5s';  -- fixed: lock wait for the function replace

do $g$
declare v jsonb := security.consumer_api_check_v1();
begin
  if jsonb_array_length(coalesce(v->'drift', '[]'::jsonb)) <> 0 or (v->>'functions')::int <> 75 or (v->>'relations')::int <> 48 then
    raise exception 'guard: the consumer API is not at its baseline before this change: %', v;
  end if;
  if md5(pg_get_functiondef('public.svc_entry_matrix_next(integer)'::regprocedure)) <> 'edc670b607489b5b4a372ddc83c73f9f' then
    raise exception 'guard: svc_entry_matrix_next is not the definition this change was written against';
  end if;
end $g$;
create temp table s1017_locks on commit drop as select count(*) n from pipeline.manual_locks;
create temp table s1017_cron on commit drop as select count(*) n from cron.job where active;

insert into pipeline.platform_toolset_settings (toolset_key, key, label, help, kind, value, min_value, max_value, unit, sort, reason, section, used_by)
values
 ('pipeline', 'reading.entry_ruled_grid_reader_on', 'Ruled PDF course grid reader',
  '1 reads a proven ruled PDF entry table that is a course-by-qualification grid (one programme per row; a country, education board or international qualification per column; University of Auckland) without the model: each cell gives one row for its course, through the same checks as the aligned-grid reader. A table piece with no course column is not read. 0 leaves such PDFs to the model (or held while there is none).',
  'number', to_jsonb(1), 0, 1, 'switch', 1535, 'Platform Admin 24 Nov 2026 05:33 AEDT (s1017): $0 deterministic cell-to-row reader for proven grids', 'Entry requirements', 'coverage-sweep entry_ai (entry-ruled-grid.ts)'),
 ('pipeline', 'reading.entry_ruled_grid_min_rows', 'Ruled grid: fewest courses',
  'A ruled PDF table is read as a course grid only when it lists at least this many courses (otherwise it is not read this way).',
  'number', to_jsonb(5), 2, 200, 'courses', 1536, 'CF-247 s1017: University of Auckland lists 17 and 25 per table', 'Entry requirements', 'coverage-sweep entry_ai (entry-ruled-grid.ts)'),
 ('pipeline', 'reading.entry_ruled_grid_min_columns', 'Ruled grid: fewest requirement columns',
  'A ruled PDF table is read as a course grid only when at least this many of its columns hold values (otherwise it is not read this way).',
  'number', to_jsonb(3), 2, 50, 'columns', 1537, 'CF-247 s1017: University of Auckland has 11 per table', 'Entry requirements', 'coverage-sweep entry_ai (entry-ruled-grid.ts)'),
 ('pipeline', 'reading.entry_det_only_lease_on', 'Read stored PDFs without a model',
  '1: while the entry requirement matrices service has no usable model, stored PDFs are still read by the deterministic readers (no model, no cost); a PDF none of them proves is held. 0: nothing is read while there is no model.',
  'number', to_jsonb(1), 0, 1, 'switch', 1538, 'Platform Admin 24 Nov 2026 05:33 AEDT (s1017): do not wait for a model qualification', 'Entry requirements', 'public.svc_entry_matrix_next')
on conflict do nothing;

update pipeline.platform_toolset_settings
   set value = value || '["Additional programme entry=fact"]'::jsonb,
       reason = 'CF-247 s1017 (Platform Admin 24 Nov 2026 05:33): University of Auckland''s "Additional programme entry requirements" column is a course fact; earlier: ' || coalesce(reason, ''),
       updated_at = now()
 where toolset_key = 'pipeline' and key = 'reading.entry_grid_headings' and not value @> '["Additional programme entry=fact"]'::jsonb;

CREATE OR REPLACE FUNCTION public.svc_entry_matrix_next(p_limit integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v jsonb; v_route jsonb := security.ai_route_v1('entry_matrices'); v_model text := v_route->>'model';  -- 13 Nov 2026: the route (pipeline.ai_service_routes)
        v_od uuid[] := security.ai_on_demand_providers_v1('entry_matrices'); v_det boolean;
begin
  if current_user <> 'postgres' and coalesce(auth.role(), '') <> 'service_role' then raise exception 'service_role required'; end if;
  if security.pipeline_num_v1('entry.matrix_enabled', 0) < 1 or not security.ai_use_allowed_v1('entry_matrix') then return '[]'::jsonb; end if;
  -- the route: switched off, no allowed model or the credit floor holds everything; a cap or the daily ceiling holds all but on-demand providers
  -- s1017 (24 Nov 2026): with no usable model, stored PDFs are still leased for the deterministic readers (det_only, no model); other pages wait as before
  v_det := v_model is null or (coalesce((v_route->>'held')::boolean, true) and not (coalesce((v_route->>'on_demand_exempt')::boolean, false) and cardinality(v_od) > 0));
  if v_det and security.pipeline_num_v1('reading.entry_det_only_lease_on', 1) < 1 then return '[]'::jsonb; end if;
  with pick as (select r.id from pipeline.entry_matrix_runs r
                 where (r.state = 'queued' or (r.state = 'leased' and r.leased_until < now()))
                   and r.attempts < security.pipeline_num_v1('entry.matrix_attempts', 3)
                   and security.entry_matrix_enabled_v1(r.provider_id)
                   and (v_det or not (v_route->>'held')::boolean or r.provider_id = any(v_od))
                   and (not v_det or exists (select 1 from pipeline.entry_matrix_sources s0 join pipeline.evidence_artifacts e0 on e0.id = s0.evidence_id
                                              where s0.id = r.source_id and e0.mime_type = 'application/pdf'))
                 order by r.created_at limit greatest(1, least(coalesce(p_limit, 4), 20)) for update skip locked),
  upd as (update pipeline.entry_matrix_runs r set state = 'leased', leased_until = now() + interval '5 minutes',  -- fixed: lease timer
                 attempts = r.attempts + 1, model_code = case when v_det then null else v_model end, updated_at = now() from pick where r.id = pick.id returning r.*)
  select coalesce(jsonb_agg(jsonb_build_object('run_id', u.id, 'source_id', u.source_id, 'provider_id', u.provider_id,
           'provider', coalesce(p.display_name, p.canonical_name), 'country', k.iso_alpha2, 'url', s.url, 'storage_path', e.storage_path, 'mime', e.mime_type,
           'model', case when v_det then null else v_model end, 'model_code', case when v_det then null else split_part(v_model, '/', 2) end,
           'models', case when v_det then '[]'::jsonb else v_route->'models' end, 'det_only', v_det,
           'max_rows', security.pipeline_num_v1('entry.matrix_max_rows_per_page', 400)::int,
           'max_tokens', security.pipeline_num_v1('entry.matrix_max_tokens', 8000)::int,
           'slice_chars', security.pipeline_num_v1('entry.matrix_slice_chars', 24000)::int,
           'slice_concurrency', security.pipeline_num_v1('entry.matrix_slice_concurrency', 1)::int,
           'pdf_max_pages', security.pipeline_num_v1('entry.pdf_max_pages', 40)::int,
           'completeness_required', security.entry_completeness_required_v1(u.provider_id))), '[]'::jsonb) into v
    from upd u join pipeline.entry_matrix_sources s on s.id = u.source_id join pipeline.evidence_artifacts e on e.id = s.evidence_id
    join catalogue.providers p on p.id = u.provider_id left join ref.countries k on k.id = p.country_id;
  return v;
end $function$;

do $post$
declare v_api jsonb := security.consumer_api_check_v1();
begin
  if jsonb_array_length(coalesce(v_api->'drift', '[]'::jsonb)) <> 0 or (v_api->>'functions')::int <> 75 or (v_api->>'relations')::int <> 48 then
    raise exception 'post-check: the consumer API moved: %', v_api;
  end if;
  if (select count(*) from pipeline.manual_locks) <> (select n from s1017_locks) then raise exception 'post-check: manual locks changed'; end if;
  if (select count(*) from cron.job where active) <> (select n from s1017_cron) then raise exception 'post-check: the number of active cron jobs changed'; end if;
  if (select count(*) from pipeline.platform_toolset_settings where toolset_key = 'pipeline' and key in ('reading.entry_ruled_grid_reader_on', 'reading.entry_ruled_grid_min_rows',
      'reading.entry_ruled_grid_min_columns', 'reading.entry_det_only_lease_on')) <> 4 then raise exception 'post-check: a setting is missing'; end if;
  if not (select value @> '["Additional programme entry=fact"]'::jsonb from pipeline.platform_toolset_settings where toolset_key = 'pipeline' and key = 'reading.entry_grid_headings') then
    raise exception 'post-check: the heading list does not name Additional programme entry';
  end if;
  if pg_get_functiondef('public.svc_entry_matrix_next(integer)'::regprocedure) !~ 'det_only' then raise exception 'post-check: svc_entry_matrix_next was not replaced'; end if;
end $post$;
