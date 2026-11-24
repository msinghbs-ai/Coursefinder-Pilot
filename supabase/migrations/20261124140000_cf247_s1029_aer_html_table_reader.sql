-- CF-247 s1029 (S1-RM-Design, run as the S2-RM-Design AER v2 Batch 1 lane; Standing Authority Charter 23 Nov 2026 item 1: HTML_TABLE proven-structure readers are
-- pre-authorised; Platform Admin 24 Nov 2026 05:33 AEDT: "$0 deterministic cell-to-row adapter for proven PDF_TABLE / HTML_TABLE grids"). No model, no Firecrawl, $0.
-- While the entry_matrices route has no qualified model (gpt-4.1-mini is the setting entry.matrix_model but has no qualification row; qualifying it is the
-- Platform Admin's own act), stored HTML entry pages wait without a read. This change reads the ones whose markup proves their structure.
-- 1. Settings (G2) for the worker's HTML_TABLE reader (coverage-sweep-worker-v1.0.37, entry-html-table.ts): reading.entry_html_table_reader_on (on) and
--    reading.entry_html_table_min_rows.
-- 2. public.svc_entry_matrix_next: while the route has no usable model, stored HTML pages are leased beside stored PDFs (det_only, no model); the worker
--    holds a page that no deterministic reader proves and never sends it to a model. With a usable model the function behaves exactly as before.
--    Replaced only from the definition it was written against (md5 checked).
-- 3. Batch 1 re-read through public.admin_entry_matrix_reread (logged in pipeline.admin_control_events): Lincoln University (stored page read offline by the
--    new reader: 47 rows, all through entryMatrixParsed), Macquarie University's HTML page (its last run failed on the model's key limit, no Layer 4 item) and
--    Victoria University 02475D (0 rows, no Layer 4 item). Only proposed rows and a pending item of each run are superseded; active rows stay live, and a
--    re-read row of the same identity replaces its predecessor through the existing admission path. University of Waikato's HTML run is already queued and is
--    leased by item 2. Massey University keeps its pending page-change item for a person (not re-read).
-- Rows still go through svc_entry_matrix_record and the machine admission rules unchanged; anything a rule does not admit stays in Layer 4 for a person.
-- G1: no job. G3: no consumer object (75/48 checked). Manual locks and active cron jobs checked unchanged. Nothing dropped or deleted.
-- Replaces: nothing (the det_only lease of s1017 is extended, not replaced)
-- Retires: nothing
set local lock_timeout = '5s';  -- fixed: lock wait for the function replace

do $g$
declare v jsonb := security.consumer_api_check_v1();
begin
  if jsonb_array_length(coalesce(v->'drift', '[]'::jsonb)) <> 0 or (v->>'functions')::int <> 75 or (v->>'relations')::int <> 48 then
    raise exception 'guard: the consumer API is not at its baseline before this change: %', v;
  end if;
  if md5(pg_get_functiondef('public.svc_entry_matrix_next(integer)'::regprocedure)) <> '51f11c9ed46f2333f325d4a0821062c2' then
    raise exception 'guard: svc_entry_matrix_next is not the definition this change was written against (s1017)';
  end if;
end $g$;
create temp table s1029_locks on commit drop as select count(*) n from pipeline.manual_locks;
create temp table s1029_cron on commit drop as select count(*) n from cron.job where active;
create temp table s1029_active on commit drop as select count(*) n from catalogue.provider_entry_matrix where status = 'active';

insert into pipeline.platform_toolset_settings (toolset_key, key, label, help, kind, value, min_value, max_value, unit, sort, reason, section, used_by)
values
 ('pipeline', 'reading.entry_html_table_reader_on', 'HTML entry table reader',
  '1 reads a stored HTML entry page without the model when its table markup proves the structure: a worded header row, a first column naming the country or qualification, and a study level named by a column header or by the heading above the table. Each cell gives a row through the same checks as the PDF cell reader. A table it cannot prove is left out and named. 0 leaves HTML pages to the model (or held while there is none).',
  'number', to_jsonb(1), 0, 1, 'switch', 1539, 'S2-RM-Design brief (Batch 1) under the Standing Authority Charter 23 Nov 2026 item 1 (s1029): $0 HTML_TABLE reader', 'Entry requirements', 'coverage-sweep entry_ai (entry-html-table.ts); public.svc_entry_matrix_next'),
 ('pipeline', 'reading.entry_html_table_min_rows', 'HTML entry table: fewest rows',
  'An HTML table is read this way only when it has at least this many body rows (otherwise it is not read this way).',
  'number', to_jsonb(5), 2, 200, 'rows', 1540, 'CF-247 s1029: Lincoln University prints 64, 35 and 35 rows', 'Entry requirements', 'coverage-sweep entry_ai (entry-html-table.ts)')
on conflict do nothing;

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
  -- s1029 (24 Nov 2026): and stored HTML pages, for the HTML_TABLE reader (reading.entry_html_table_reader_on); a page no deterministic reader proves is held
  v_det := v_model is null or (coalesce((v_route->>'held')::boolean, true) and not (coalesce((v_route->>'on_demand_exempt')::boolean, false) and cardinality(v_od) > 0));
  if v_det and security.pipeline_num_v1('reading.entry_det_only_lease_on', 1) < 1 then return '[]'::jsonb; end if;
  with pick as (select r.id from pipeline.entry_matrix_runs r
                 where (r.state = 'queued' or (r.state = 'leased' and r.leased_until < now()))
                   and r.attempts < security.pipeline_num_v1('entry.matrix_attempts', 3)
                   and security.entry_matrix_enabled_v1(r.provider_id)
                   and (v_det or not (v_route->>'held')::boolean or r.provider_id = any(v_od))
                   and (not v_det or exists (select 1 from pipeline.entry_matrix_sources s0 join pipeline.evidence_artifacts e0 on e0.id = s0.evidence_id
                                              where s0.id = r.source_id and (e0.mime_type = 'application/pdf'
                                                or (e0.mime_type ~* 'html' and security.pipeline_num_v1('reading.entry_html_table_reader_on', 1) >= 1))))
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

-- 3. Batch 1 re-read (the newest stored copy's run of each source; only proposed rows and pending items are superseded)
create temp table s1029_reread on commit drop as
select public.admin_entry_matrix_reread(array['3a111cd8-14d4-4243-afed-cc5e46a3d224', '59c8fd5b-8c81-4505-9bea-cd3f80fcd042', 'a287adee-4d7c-4fdc-aff7-38a330e6c383']::uuid[],
  'CF-247 s1029 AER v2 Batch 1: read again by the $0 HTML_TABLE reader (Lincoln University, Macquarie University HTML page, Victoria University 02475D)') r;

do $post$
declare v_api jsonb := security.consumer_api_check_v1(); v_r jsonb := (select r from s1029_reread);
begin
  if jsonb_array_length(coalesce(v_api->'drift', '[]'::jsonb)) <> 0 or (v_api->>'functions')::int <> 75 or (v_api->>'relations')::int <> 48 then
    raise exception 'post-check: the consumer API moved: %', v_api;
  end if;
  if (select count(*) from pipeline.manual_locks) <> (select n from s1029_locks) then raise exception 'post-check: manual locks changed'; end if;
  if (select count(*) from cron.job where active) <> (select n from s1029_cron) then raise exception 'post-check: the number of active cron jobs changed'; end if;
  if (select count(*) from catalogue.provider_entry_matrix where status = 'active') <> (select n from s1029_active) then raise exception 'post-check: an active entry row changed'; end if;
  if (select count(*) from pipeline.platform_toolset_settings where toolset_key = 'pipeline' and key in ('reading.entry_html_table_reader_on', 'reading.entry_html_table_min_rows')) <> 2 then
    raise exception 'post-check: a setting is missing';
  end if;
  if pg_get_functiondef('public.svc_entry_matrix_next(integer)'::regprocedure) !~ 'entry_html_table_reader_on' then raise exception 'post-check: svc_entry_matrix_next was not replaced'; end if;
  if coalesce((v_r->>'runs')::int, 0) < 1 then raise exception 'post-check: no Batch 1 source was queued for a re-read: %', v_r; end if;
  raise notice 's1029: re-read %', v_r;
end $post$;
