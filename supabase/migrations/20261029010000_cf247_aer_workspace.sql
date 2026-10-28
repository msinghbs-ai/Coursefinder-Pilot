-- CF-247 AER operations workspace (Platform Admin mandate 29 Oct 2026 08:06; admin docs/platform/AER-OPERATIONS-WORKSPACE-DECISION-2026-10-29.md,
-- W1-W16). One governed admin RPC behind Catalogue › Entry requirements: bounded lists with server-side filters, sorting and pages, a summary,
-- the row drawer with its history, governed edits of active or unverified rows, add with stored evidence, withdraw / quarantine / restore,
-- a bounded source re-read through the existing mechanism, and a resolution inspector over the live resolver.
--   Reads: every assigned role. Edit, add, lifecycle: Curator and above (rank 3, as Scholarships › Edit in list). Re-read: Platform Admin.
--   Every write needs a reason, carries the row's updated_at as read (a stale value is refused), and writes one manual_edit_log row per field.
--   Proposed AI rows are never edited or activated here: admission stays in Layer 4 (W3). No new status, job, setting or table.
--   The consumer API (G3), the resolver (security.entry_resolve_v1) and the payload functions are not changed: active rows reach the course
--   `entry` and provider `entry_matrix` payloads as before, and nothing else does.
-- Replaces: nothing (the read-only drawer sections stay, as shortcuts into the workspace)
-- Retires: the read-only limit of the 28 Oct Step B decision (B5) for editing; no object is retired
-- Nothing dropped, deleted or renamed. No consumer object is touched.

-- the numbers a value states must be printed in the row's quote (source-supported, as the AI reader's quote gate)
create or replace function security.aer_numbers_in_quote_v1(p_text text, p_quote text) returns boolean
language sql immutable set search_path to '' as $$
  select coalesce(bool_and(exists (select 1 from regexp_matches(coalesce(p_quote, ''), '[0-9]+(?:\.[0-9]+)?', 'g') q where q[1]::numeric = t[1]::numeric)), true)
    from regexp_matches(coalesce(p_text, ''), '[0-9]+(?:\.[0-9]+)?', 'g') t
$$;
comment on function security.aer_numbers_in_quote_v1(text, text) is 'CF-247 AER workspace: every number in a value is printed in the quote (W7).';

create or replace function security.aer_band_in_quote_v1(p_band text, p_quote text) returns boolean
language sql immutable set search_path to '' as $$
  select p_band is null or position(lower(regexp_replace(p_band, '\s+', '', 'g')) in lower(regexp_replace(coalesce(p_quote, ''), '\s+', '', 'g'))) > 0
$$;
comment on function security.aer_band_in_quote_v1(text, text) is 'CF-247 AER workspace: a band is printed in the quote (W7).';

-- the structured conditions of a matrix row: best_n, subject_minimums [{subject, min_grade}], alternatives [{route, min_grade}]
create or replace function security.aer_conditions_v1(p jsonb) returns jsonb
language plpgsql immutable set search_path to '' as $$
declare v jsonb := coalesce(p, '{}'::jsonb); v_item jsonb;
begin
  if jsonb_typeof(v) <> 'object' then raise exception 'conditions must be a set of named parts' using errcode = '22023'; end if;
  if exists (select 1 from jsonb_object_keys(v) k where k not in ('best_n', 'subject_minimums', 'alternatives')) then
    raise exception 'conditions take only: best of N subjects, subject minimums, alternative routes' using errcode = '22023'; end if;
  if v ? 'best_n' and v->'best_n' <> 'null'::jsonb and (jsonb_typeof(v->'best_n') <> 'number' or (v->>'best_n')::numeric not between 1 and 20 or (v->>'best_n')::numeric % 1 <> 0) then
    raise exception 'best of N subjects must be a whole number from 1 to 20' using errcode = '22023'; end if;
  for v_item in select * from jsonb_array_elements(coalesce(v->'subject_minimums', '[]'::jsonb)) loop
    if jsonb_typeof(v_item) <> 'object' or nullif(btrim(v_item->>'subject'), '') is null then raise exception 'each subject minimum needs a subject' using errcode = '22023'; end if;
  end loop;
  for v_item in select * from jsonb_array_elements(coalesce(v->'alternatives', '[]'::jsonb)) loop
    if jsonb_typeof(v_item) <> 'object' or nullif(btrim(v_item->>'route'), '') is null then raise exception 'each alternative needs its route' using errcode = '22023'; end if;
  end loop;
  return jsonb_build_object('best_n', case when v->'best_n' is null or v->'best_n' = 'null'::jsonb then null else v->'best_n' end,
    'subject_minimums', coalesce((select jsonb_agg(jsonb_build_object('subject', btrim(x->>'subject'), 'min_grade', nullif(btrim(x->>'min_grade'), ''))) from jsonb_array_elements(coalesce(v->'subject_minimums', '[]'::jsonb)) x), '[]'::jsonb),
    'alternatives', coalesce((select jsonb_agg(jsonb_build_object('route', btrim(x->>'route'), 'min_grade', nullif(btrim(x->>'min_grade'), ''))) from jsonb_array_elements(coalesce(v->'alternatives', '[]'::jsonb)) x), '[]'::jsonb));
end $$;
comment on function security.aer_conditions_v1(jsonb) is 'CF-247 AER workspace: validates and normalises a matrix row''s structured conditions (W4).';

-- one row as the workspace shows it (list and drawer)
create or replace function security.aer_row_v1(p_kind text, p_id uuid) returns jsonb
language sql stable security definer set search_path to '' as $$
  select case when p_kind = 'matrix' then (
    select jsonb_build_object('kind', 'matrix', 'id', m.id, 'provider_id', m.provider_id, 'provider_name', coalesce(p.display_name, p.canonical_name),
      'country', m.country_code, 'country_name', k.name, 'level_label', m.level_label, 'level_code', l.short_code, 'level_name', l.name,
      'matrix_kind', m.matrix_kind, 'qualification', m.qualification_name, 'band', m.benchmark_band, 'min_grade', m.min_grade, 'min_value', m.min_value,
      'scale', m.grade_scale, 'conditions', m.conditions, 'audience', m.audience, 'edition', m.edition, 'intake_year', m.intake_year, 'as_at', m.as_at,
      'valid_to', m.valid_to, 'status', m.status, 'status_reason', m.status_reason, 'withdrawal_reason', m.withdrawal_reason, 'quote', m.quote,
      'source_url', m.source_url, 'source_id', m.source_id, 'evidence_id', m.evidence_id, 'confidence', m.confidence, 'version', m.version,
      'course_id', m.course_id, 'course_code', c.course_code, 'course_title', c.canonical_title, 'manual', m.provenance->>'reader' = 'manual',
      'provenance', m.provenance, 'run_id', m.run_id, 'run_state', r.state, 'run_error', left(r.error, 200), 'review_item_id', r.review_item_id,
      'review_status', li.status, 'created_at', m.created_at, 'updated_at', m.updated_at)
      from catalogue.provider_entry_matrix m join catalogue.providers p on p.id = m.provider_id left join ref.countries k on k.id = m.country_id
      left join ref.study_levels l on l.id = m.study_level_id left join catalogue.courses c on c.id = m.course_id
      left join pipeline.entry_matrix_runs r on r.id = m.run_id left join pipeline.layer4_review_items li on li.id = r.review_item_id
     where m.id = p_id)
  else (
    select jsonb_build_object('kind', 'course', 'id', x.id, 'course_id', x.course_id, 'course_title', c.canonical_title, 'course_code', c.course_code,
      'provider_id', c.provider_id, 'provider_name', coalesce(p.display_name, p.canonical_name), 'requirement_kind', x.kind, 'audience', x.audience,
      'country', k.iso_alpha2, 'country_name', k.name, 'description', x.description, 'min_grade', x.min_grade, 'min_value', x.min_value, 'scale', x.grade_scale,
      'min_entry_score', x.min_entry_score, 'min_entry_score_basis', x.min_entry_score_basis, 'band', x.benchmark_band, 'quote', x.quote,
      'source_url', x.source_url, 'evidence_id', x.evidence_id, 'confidence', x.confidence, 'as_at', x.as_at, 'status', x.status, 'status_reason', x.status_reason,
      'manual', x.provenance->>'reader' = 'manual', 'provenance', x.provenance, 'review_item_id', li.id, 'review_status', li.status,
      'created_at', x.created_at, 'updated_at', x.updated_at)
      from catalogue.course_entry_requirements x join catalogue.courses c on c.id = x.course_id join catalogue.providers p on p.id = c.provider_id
      left join ref.countries k on k.id = x.country_id
      left join pipeline.layer4_review_items li on li.id = nullif(x.provenance->>'review_item_id', '')::uuid
     where x.id = p_id) end
$$;
revoke all on function security.aer_row_v1(text, uuid) from public, anon, authenticated;
comment on function security.aer_row_v1(text, uuid) is 'CF-247 AER workspace: one provider-matrix or course-requirement row as the workspace shows it.';

create or replace function public.admin_aer(p_action text, p_args jsonb default '{}'::jsonb) returns jsonb
language plpgsql security definer set search_path to '' as $$
declare v_rank int := coalesce(security.current_role_rank(), 0); a jsonb; v_size int; v_off int; v_sort text; v_dir text; v_sql text; v_total int; v_rows jsonb;
        v_kind text; v_id uuid; v_reason text; v_exp timestamptz; v_cur jsonb; v_new jsonb; ch jsonb; v_key text; v_txt text; v_num numeric; v_lvl uuid;
        m catalogue.provider_entry_matrix%rowtype; x catalogue.course_entry_requirements%rowtype; v_out jsonb; v_cc text; v_ev pipeline.evidence_artifacts%rowtype;
        v_src pipeline.entry_matrix_sources%rowtype; v_run pipeline.entry_matrix_runs%rowtype; v_c record; v_levels uuid[]; v_band text; v_last text; v_n int;
        v_editable text[]; v_fields jsonb := '{}'::jsonb;
begin
  if auth.uid() is null or v_rank < 1 then raise exception 'assigned StudySearch role required' using errcode = '42501'; end if;
  -- empty filter values mean "any"
  a := coalesce((select jsonb_object_agg(e.key, e.value) from jsonb_each(coalesce(p_args, '{}'::jsonb)) e
                  where e.value not in ('null'::jsonb, '""'::jsonb) and not (jsonb_typeof(e.value) = 'string' and btrim(e.value #>> '{}') = '')), '{}'::jsonb);
  v_size := greatest(1, least(coalesce((a->>'page_size')::int, 50), 100));  -- fixed: a page is at most 100 rows (W11)
  v_off := greatest(0, coalesce((a->>'offset')::int, 0));
  v_dir := case when lower(coalesce(a->>'direction', 'asc')) = 'desc' then 'desc' else 'asc' end;
  v_reason := btrim(coalesce(p_args->>'reason', ''));
  v_kind := coalesce(a->>'kind', 'matrix');

  -- ---------------------------------------------------------------- reads
  if p_action = 'summary' then
    return jsonb_build_object(
      'matrix', (select coalesce(jsonb_object_agg(s, n), '{}'::jsonb) from (select m0.status s, count(*) n from catalogue.provider_entry_matrix m0
                  where (a->>'provider_id' is null or m0.provider_id = (a->>'provider_id')::uuid) and (a->>'country' is null or m0.country_code = upper(a->>'country')) group by 1) z),
      'course', (select coalesce(jsonb_object_agg(s, n), '{}'::jsonb) from (select x0.status s, count(*) n from catalogue.course_entry_requirements x0
                  join catalogue.courses c0 on c0.id = x0.course_id where (a->>'provider_id' is null or c0.provider_id = (a->>'provider_id')::uuid) group by 1) z),
      'sources', (select jsonb_build_object('total', count(*), 'fetch_failed', count(*) filter (where s0.status = 'failed'),
                    'held', count(*) filter (where r0.state = 'failed'), 'reading', count(*) filter (where r0.state in ('queued', 'leased') or s0.status in ('found', 'reading')),
                    'read', count(*) filter (where r0.state = 'done'))
                   from pipeline.entry_matrix_sources s0
                   left join lateral (select r1.state from pipeline.entry_matrix_runs r1 where r1.source_id = s0.id order by r1.created_at desc limit 1) r0 on true
                  where a->>'provider_id' is null or s0.provider_id = (a->>'provider_id')::uuid),
      'providers_with_active', (select count(distinct m1.provider_id) from catalogue.provider_entry_matrix m1 where m1.status = 'active'),
      'providers_in_scope', (select jsonb_array_length(coalesce(security.toolset_setting('pipeline', 'entry.providers'), '[]'::jsonb))),
      'courses_with_active', (select count(distinct x1.course_id) from catalogue.course_entry_requirements x1 join catalogue.courses c1 on c1.id = x1.course_id
                               where x1.status = 'active' and (a->>'provider_id' is null or c1.provider_id = (a->>'provider_id')::uuid)),
      'courses_waiting', (select count(distinct x2.course_id) from catalogue.course_entry_requirements x2 join catalogue.courses c2 on c2.id = x2.course_id
                           where x2.status = 'proposed' and (a->>'provider_id' is null or c2.provider_id = (a->>'provider_id')::uuid)),
      'can_edit', v_rank >= 3, 'can_reread', v_rank >= 6);

  elsif p_action = 'options' then
    return jsonb_build_object(
      'providers', (select coalesce(jsonb_agg(jsonb_build_object('id', z.id, 'name', z.n) order by z.n), '[]'::jsonb) from (
                     select p.id, coalesce(p.display_name, p.canonical_name) n from catalogue.providers p
                      where exists (select 1 from catalogue.provider_entry_matrix m0 where m0.provider_id = p.id)
                         or exists (select 1 from pipeline.entry_matrix_sources s0 where s0.provider_id = p.id)
                         or exists (select 1 from catalogue.course_entry_requirements x0 join catalogue.courses c0 on c0.id = x0.course_id where c0.provider_id = p.id)
                      limit 300) z),  -- fixed: option list bound (W11)
      'countries', (select coalesce(jsonb_agg(jsonb_build_object('code', z.cc, 'name', z.n) order by z.n), '[]'::jsonb) from (
                     select distinct m0.country_code cc, k0.name n from catalogue.provider_entry_matrix m0 join ref.countries k0 on k0.id = m0.country_id) z),
      'all_countries', (select coalesce(jsonb_agg(jsonb_build_object('code', k0.iso_alpha2, 'name', k0.name) order by k0.name), '[]'::jsonb) from ref.countries k0 where k0.iso_alpha2 ~ '^[A-Z]{2}$'),
      'levels', (select coalesce(jsonb_agg(jsonb_build_object('code', l0.short_code, 'name', l0.name) order by l0.sort_order), '[]'::jsonb) from ref.study_levels l0),
      'level_labels', (select coalesce(jsonb_agg(z.v order by z.v), '[]'::jsonb) from (select distinct m0.level_label v from catalogue.provider_entry_matrix m0 where m0.level_label is not null limit 300) z),
      'bands', (select coalesce(jsonb_agg(z.v order by z.v), '[]'::jsonb) from (select distinct b v from (select m0.benchmark_band b from catalogue.provider_entry_matrix m0 union select x0.benchmark_band from catalogue.course_entry_requirements x0) u where b is not null limit 300) z),
      'editions', (select coalesce(jsonb_agg(z.v order by z.v), '[]'::jsonb) from (select distinct m0.edition v from catalogue.provider_entry_matrix m0 where m0.edition is not null limit 100) z),
      'intake_years', (select coalesce(jsonb_agg(z.v order by z.v), '[]'::jsonb) from (select distinct m0.intake_year v from catalogue.provider_entry_matrix m0 where m0.intake_year is not null) z),
      'matrix_kinds', '["provider_minimum", "band_ladder", "course_minimum", "rank_band"]'::jsonb,
      'requirement_kinds', '["prior_qualification", "minimum_grade", "subject_prerequisite", "portfolio_interview", "work_experience", "other", "override", "general_note"]'::jsonb,
      'scales', '["percentage", "points", "aggregate", "gpa", "letter", "rank", "none"]'::jsonb,
      'audiences', '["international", "domestic", "all"]'::jsonb,
      'statuses', '["active", "proposed", "unverified", "inactive", "superseded"]'::jsonb);

  elsif p_action = 'matrix_list' then
    v_sort := case a->>'sort' when 'provider' then 'f.provider_name' when 'country' then 'f.country_code' when 'level' then 'f.level_label'
                when 'qualification' then 'f.qualification_name' when 'band' then 'f.benchmark_band' when 'min' then 'f.min_value'
                when 'status' then 'f.status' when 'as_at' then 'f.as_at' when 'updated' then 'f.updated_at' when 'edition' then 'f.edition'
                else 'f.provider_name' end;
    v_sql := format($q$
      with f as (
        select m.*, coalesce(p.display_name, p.canonical_name) provider_name, r.state run_state
          from catalogue.provider_entry_matrix m join catalogue.providers p on p.id = m.provider_id
          left join ref.study_levels l on l.id = m.study_level_id left join pipeline.entry_matrix_runs r on r.id = m.run_id
         where ($1->>'provider_id' is null or m.provider_id = ($1->>'provider_id')::uuid)
           and ($1->>'country' is null or m.country_code = upper($1->>'country'))
           and ($1->>'level' is null or l.short_code = $1->>'level' or m.level_label = $1->>'level')
           and ($1->>'status' is null or m.status = $1->>'status')
           and ($1->>'matrix_kind' is null or m.matrix_kind = $1->>'matrix_kind')
           and ($1->>'band' is null or m.benchmark_band = $1->>'band')
           and ($1->>'edition' is null or m.edition = $1->>'edition')
           and ($1->>'intake_year' is null or m.intake_year = ($1->>'intake_year')::int)
           and ($1->>'read_state' is null or coalesce(r.state, 'manual') = $1->>'read_state')
           and ($1->>'q' is null or m.qualification_name ilike '%%' || left($1->>'q', 100) || '%%' or m.quote ilike '%%' || left($1->>'q', 100) || '%%'
                or m.level_label ilike '%%' || left($1->>'q', 100) || '%%'))
      select (select count(*) from f)::int,
             (select coalesce(jsonb_agg(security.aer_row_v1('matrix', z.id) order by z.o), '[]'::jsonb)
                from (select f.id, row_number() over (order by %s %s nulls last, f.provider_name, f.country_code, f.qualification_name, f.id) o
                        from f order by %s %s nulls last, f.provider_name, f.country_code, f.qualification_name, f.id limit $2 offset $3) z)
    $q$, v_sort, v_dir, v_sort, v_dir);
    execute v_sql into v_total, v_rows using a, v_size, v_off;
    return jsonb_build_object('total', v_total, 'offset', v_off, 'page_size', v_size, 'rows', v_rows);

  elsif p_action = 'course_list' then
    v_sort := case a->>'sort' when 'provider' then 'f.provider_name' when 'course' then 'f.course_title' when 'kind' then 'f.kind'
                when 'status' then 'f.status' when 'as_at' then 'f.as_at' when 'updated' then 'f.updated_at' when 'score' then 'f.min_entry_score'
                else 'f.provider_name' end;
    v_sql := format($q$
      with f as (
        select x.*, c.canonical_title course_title, c.course_code, coalesce(p.display_name, p.canonical_name) provider_name
          from catalogue.course_entry_requirements x join catalogue.courses c on c.id = x.course_id join catalogue.providers p on p.id = c.provider_id
         where ($1->>'provider_id' is null or c.provider_id = ($1->>'provider_id')::uuid)
           and ($1->>'course' is null or c.course_code ilike left($1->>'course', 60) || '%%' or c.canonical_title ilike '%%' || left($1->>'course', 100) || '%%' or c.id::text = $1->>'course')
           and ($1->>'requirement_kind' is null or x.kind = $1->>'requirement_kind')
           and ($1->>'audience' is null or x.audience = $1->>'audience')
           and ($1->>'status' is null or x.status = $1->>'status')
           and ($1->>'band' is null or x.benchmark_band = $1->>'band')
           and ($1->>'as_at_from' is null or x.as_at >= ($1->>'as_at_from')::date)
           and ($1->>'as_at_to' is null or x.as_at <= ($1->>'as_at_to')::date)
           and ($1->>'q' is null or x.description ilike '%%' || left($1->>'q', 100) || '%%' or x.quote ilike '%%' || left($1->>'q', 100) || '%%'))
      select (select count(*) from f)::int,
             (select coalesce(jsonb_agg(security.aer_row_v1('course', z.id) order by z.o), '[]'::jsonb)
                from (select f.id, row_number() over (order by %s %s nulls last, f.provider_name, f.course_title, f.id) o
                        from f order by %s %s nulls last, f.provider_name, f.course_title, f.id limit $2 offset $3) z)
    $q$, v_sort, v_dir, v_sort, v_dir);
    execute v_sql into v_total, v_rows using a, v_size, v_off;
    return jsonb_build_object('total', v_total, 'offset', v_off, 'page_size', v_size, 'rows', v_rows);

  elsif p_action = 'sources_list' then
    v_sort := case a->>'sort' when 'provider' then 'f.provider_name' when 'status' then 'f.status' when 'read' then 'f.run_state'
                when 'read_at' then 'f.read_at' when 'cost' then 'f.cost_usd' else 'f.provider_name' end;
    v_sql := format($q$
      with f as (
        select s.*, coalesce(p.display_name, p.canonical_name) provider_name, r.id run_id, r.state run_state, r.cost_usd, r.error run_error,
               case when r.state = 'failed' then 'held' when r.state in ('queued', 'leased') or s.status in ('found', 'reading') then 'reading'
                    when s.status = 'failed' then 'fetch_failed' when r.state = 'done' then 'read' else 'none' end hold_state
          from pipeline.entry_matrix_sources s join catalogue.providers p on p.id = s.provider_id
          left join lateral (select r1.* from pipeline.entry_matrix_runs r1 where r1.source_id = s.id order by r1.created_at desc limit 1) r on true
         where ($1->>'provider_id' is null or s.provider_id = ($1->>'provider_id')::uuid)
           and ($1->>'status' is null or s.status = $1->>'status')
           and ($1->>'hold_state' is null or (case when r.state = 'failed' then 'held' when r.state in ('queued', 'leased') or s.status in ('found', 'reading') then 'reading'
                    when s.status = 'failed' then 'fetch_failed' when r.state = 'done' then 'read' else 'none' end) = $1->>'hold_state')
           and ($1->>'q' is null or s.url ilike '%%' || left($1->>'q', 100) || '%%' or coalesce(r.error, s.error, '') ilike '%%' || left($1->>'q', 100) || '%%'))
      select (select count(*) from f)::int,
             (select coalesce(jsonb_agg(jsonb_build_object('id', z.id, 'provider_id', z.provider_id, 'provider_name', z.provider_name, 'url', z.url, 'title', z.title,
                  'found_via', z.found_via, 'status', z.status, 'read_via', z.read_via, 'http', z.http_status, 'attempts', z.attempts, 'read_at', z.read_at,
                  'error', left(z.error, 300), 'evidence_id', z.evidence_id, 'content_hash', left(z.content_hash, 16), 'hold_state', z.hold_state,
                  'type', case when z.url ~* '\.pdf($|[?#])' then 'PDF' when z.read_via = 'firecrawl' and e.mime_type = 'text/html' then 'Rendered page' else 'Web page' end,
                  'mime', e.mime_type, 'captured_at', e.captured_at, 'stored', e.storage_path is not null,
                  'in_scope', security.entry_matrix_enabled_v1(z.provider_id),
                  'next_refresh', case when z.read_at is not null and coalesce(z.read_via, '') <> 'stored'
                                       then z.read_at + make_interval(days => security.pipeline_num_v1('entry.matrix_refresh_days', 30)::int) end,
                  'last_success', (select max(r2.done_at) from pipeline.entry_matrix_runs r2 where r2.source_id = z.id and r2.state = 'done'),
                  'run', case when z.run_id is null then null else (select jsonb_build_object('id', r3.id, 'state', r3.state, 'attempts', r3.attempts, 'rows', r3.rows_admitted,
                      'not_kept', r3.rows_dropped, 'cost_usd', r3.cost_usd, 'error', left(r3.error, 300), 'done_at', r3.done_at, 'basis', r3.result->>'page_basis',
                      'worker', r3.result->>'worker', 'review_item_id', r3.review_item_id, 'review_status', (select li.status from pipeline.layer4_review_items li where li.id = r3.review_item_id),
                      'dropped', (select coalesce(jsonb_object_agg(d.k, d.n), '{}'::jsonb) from (select dx->>'reason' k, count(*) n from jsonb_array_elements(coalesce(r3.result->'dropped', '[]'::jsonb)) dx group by 1) d))
                    from pipeline.entry_matrix_runs r3 where r3.id = z.run_id) end) order by z.o), '[]'::jsonb)
                from (select f.*, row_number() over (order by %s %s nulls last, f.provider_name, f.url) o from f order by %s %s nulls last, f.provider_name, f.url limit $2 offset $3) z
                left join pipeline.evidence_artifacts e on e.id = z.evidence_id)
    $q$, v_sort, v_dir, v_sort, v_dir);
    execute v_sql into v_total, v_rows using a, v_size, v_off;
    return jsonb_build_object('total', v_total, 'offset', v_off, 'page_size', v_size, 'rows', v_rows, 'can_reread', v_rank >= 6,
      'ai_allowed', security.ai_use_allowed_v1('entry_matrix'));

  elsif p_action = 'row' then
    v_id := (a->>'id')::uuid; v_out := security.aer_row_v1(v_kind, v_id);
    if v_out is null then raise exception 'row not found'; end if;
    return v_out || jsonb_build_object(
      'evidence', (select jsonb_build_object('id', e.id, 'source_url', e.source_url, 'captured_at', e.captured_at, 'mime', e.mime_type, 'stored', e.storage_path is not null,
                     'content_hash', left(e.content_hash, 16)) from pipeline.evidence_artifacts e where e.id = (v_out->>'evidence_id')::uuid),
      'run', (select jsonb_build_object('id', r.id, 'state', r.state, 'model', r.model_code, 'worker', r.result->>'worker', 'prompt', r.result->>'prompt_version',
                'basis', r.result->>'page_basis', 'cost_usd', r.cost_usd, 'done_at', r.done_at) from pipeline.entry_matrix_runs r where r.id = (v_out->>'run_id')::uuid),
      'history', (select coalesce(jsonb_agg(jsonb_build_object('at', h.at, 'field', h.field, 'action', h.action, 'before', h.before, 'after', h.after, 'reason', h.reason,
                    'actor', coalesce(u.email, h.actor::text)) order by h.at desc, h.id desc), '[]'::jsonb)
                    from (select * from pipeline.manual_edit_log h0 where h0.entity = case v_kind when 'matrix' then 'entry_matrix' else 'course_entry' end
                           and h0.entity_id = v_id order by h0.at desc, h0.id desc limit 50) h left join auth.users u on u.id = h.actor),  -- fixed: 50 history entries
      'can_edit', v_rank >= 3 and v_out->>'status' in ('active', 'unverified'),
      'can_restore', v_rank >= 3 and v_out->>'status' in ('inactive', 'unverified')
                     and (select h.action from pipeline.manual_edit_log h where h.entity = case v_kind when 'matrix' then 'entry_matrix' else 'course_entry' end
                           and h.entity_id = v_id and h.action in ('withdraw', 'quarantine', 'restore') order by h.at desc, h.id desc limit 1) in ('withdraw', 'quarantine'));

  elsif p_action = 'course_search' then
    return (select coalesce(jsonb_agg(jsonb_build_object('id', z.id, 'title', z.canonical_title, 'code', z.course_code, 'provider', z.pn, 'provider_id', z.provider_id) order by z.canonical_title), '[]'::jsonb)
              from (select c.id, c.canonical_title, c.course_code, c.provider_id, coalesce(p.display_name, p.canonical_name) pn
                      from catalogue.courses c join catalogue.providers p on p.id = c.provider_id
                     where length(coalesce(a->>'q', '')) >= 2
                       and (a->>'provider_id' is null or c.provider_id = (a->>'provider_id')::uuid)
                       and (c.course_code ilike left(a->>'q', 60) || '%' or c.canonical_title ilike '%' || left(a->>'q', 100) || '%')
                     limit 20) z);  -- fixed: 20 suggestions

  elsif p_action = 'evidence_options' then
    return (select coalesce(jsonb_agg(jsonb_build_object('id', e.id, 'source_url', e.source_url, 'captured_at', e.captured_at, 'mime', e.mime_type) order by e.captured_at desc), '[]'::jsonb)
              from (select e0.* from pipeline.evidence_artifacts e0
                     where e0.storage_path is not null
                       and (e0.id in (select s0.evidence_id from pipeline.entry_matrix_sources s0 where s0.provider_id = (a->>'provider_id')::uuid)
                            or e0.id in (select g.evidence_id from pipeline.coverage_course_pages g where g.course_id = (a->>'course_id')::uuid)
                            or (a->>'url' is not null and rtrim(e0.source_url, '/') = rtrim(a->>'url', '/')))
                     order by e0.captured_at desc nulls last limit 20) e);  -- fixed: 20 stored copies

  elsif p_action = 'resolve' then
    v_id := (a->>'course_id')::uuid; v_cc := upper(coalesce(a->>'country', ''));
    v_out := security.entry_resolve_v1(v_id, v_cc);  -- the live resolver, unchanged (W13)
    select x0.id, x0.provider_id, x0.study_level_id, l.short_code, x0.canonical_title, x0.course_code, coalesce(p.display_name, p.canonical_name) pn into v_c
      from catalogue.courses x0 left join ref.study_levels l on l.id = x0.study_level_id join catalogue.providers p on p.id = x0.provider_id where x0.id = v_id;
    v_levels := array_remove(array[v_c.study_level_id] || array(
                  select l2.id from jsonb_array_elements_text(coalesce(security.toolset_setting('pipeline', 'entry.level_equivalents'), '[]'::jsonb)) q
                    join ref.study_levels l2 on l2.short_code = split_part(q, '=', 2) where split_part(q, '=', 1) = v_c.short_code), null);
    select r.benchmark_band into v_band from catalogue.course_entry_requirements r
     where r.course_id = v_c.id and r.status = 'active' and r.benchmark_band is not null and r.audience in ('international', 'all') order by r.updated_at desc limit 1;
    return jsonb_build_object('course', jsonb_build_object('id', v_c.id, 'title', v_c.canonical_title, 'code', v_c.course_code, 'provider', v_c.pn, 'level', v_c.short_code),
      'resolution', v_out,
      'steps', jsonb_build_array(
        jsonb_build_object('step', 1, 'rule', 'course_override', 'active_rows', (select count(*) from catalogue.course_entry_requirements r left join ref.countries k5 on k5.id = r.country_id
            where r.course_id = v_c.id and r.status = 'active' and r.kind = 'override' and r.audience in ('international', 'all') and (r.country_id is null or k5.iso_alpha2 = v_cc))),
        jsonb_build_object('step', 2, 'rule', 'course_country_row', 'active_rows', (select count(*) from catalogue.provider_entry_matrix m0
            where m0.provider_id = v_c.provider_id and m0.status = 'active' and m0.country_code = v_cc and m0.course_id = v_c.id)),
        jsonb_build_object('step', 3, 'rule', 'band_ladder', 'band', v_band, 'active_rows', case when v_band is null then 0 else (select count(*) from catalogue.provider_entry_matrix m0
            where m0.provider_id = v_c.provider_id and m0.status = 'active' and m0.country_code = v_cc and m0.course_id is null and m0.matrix_kind = 'band_ladder'
              and m0.benchmark_band = v_band and m0.study_level_id = any (v_levels)) end,
            'band_table_rows', (select count(*) from catalogue.provider_entry_matrix m0 where m0.provider_id = v_c.provider_id and m0.status = 'active' and m0.country_code = v_cc
              and m0.matrix_kind = 'band_ladder' and m0.study_level_id = any (v_levels))),
        jsonb_build_object('step', 4, 'rule', 'provider_minimum', 'active_rows', (select count(*) from catalogue.provider_entry_matrix m0
            where m0.provider_id = v_c.provider_id and m0.status = 'active' and m0.country_code = v_cc and m0.course_id is null and m0.matrix_kind = 'provider_minimum'
              and m0.study_level_id = any (v_levels))),
        jsonb_build_object('step', 5, 'rule', 'contact_provider', 'active_rows', 0)),
      'not_used', jsonb_build_object(
        'proposed_matrix', (select count(*) from catalogue.provider_entry_matrix m0 where m0.provider_id = v_c.provider_id and m0.country_code = v_cc and m0.status = 'proposed'),
        'unverified_matrix', (select count(*) from catalogue.provider_entry_matrix m0 where m0.provider_id = v_c.provider_id and m0.country_code = v_cc and m0.status = 'unverified'),
        'proposed_course', (select count(*) from catalogue.course_entry_requirements r where r.course_id = v_c.id and r.status = 'proposed'),
        'levels', (select coalesce(jsonb_agg(l3.short_code), '[]'::jsonb) from ref.study_levels l3 where l3.id = any (v_levels))));
  end if;

  -- ---------------------------------------------------------------- writes (W4-W10): Curator and above, a reason, the row as read
  if p_action not in ('update', 'add', 'lifecycle', 'reread') then raise exception 'unknown action %', p_action; end if;
  if p_action = 'reread' then
    if v_rank < 6 then raise exception 'Platform Admin role required' using errcode = '42501'; end if;
  elsif v_rank < 3 then raise exception 'Curator role or above required' using errcode = '42501'; end if;
  if length(v_reason) < 5 then raise exception 'give a reason (kept in the history)' using errcode = '22023'; end if;
  if v_kind not in ('matrix', 'course') then raise exception 'unknown kind' using errcode = '22023'; end if;

  if p_action = 'reread' then
    -- W12: one source, bounded, through the existing mechanisms; never past a terminal evidence hold
    select * into v_src from pipeline.entry_matrix_sources where id = (a->>'source_id')::uuid;
    if v_src.id is null then raise exception 'source not found'; end if;
    if not security.entry_matrix_enabled_v1(v_src.provider_id) then raise exception 'this provider is outside the reading scope (entry.providers)' using errcode = '22023'; end if;
    if not security.ai_use_allowed_v1('entry_matrix') then raise exception 'AI reading is stopped (AI limits); nothing was asked' using errcode = '22023'; end if;
    select * into v_run from pipeline.entry_matrix_runs where source_id = v_src.id order by created_at desc limit 1;
    if v_run.id is null then raise exception 'this source has not been read yet; it is read by the scheduled job' using errcode = '22023'; end if;
    if v_run.state in ('queued', 'leased') then raise exception 'a read of this source is already waiting or running' using errcode = '22023'; end if;
    if v_run.state = 'failed' and v_run.error like 'held_unparsed%' then
      raise exception 'this source is held as unreadable (%); only a reader change under change control reads it again', left(v_run.error, 120) using errcode = '22023'; end if;
    if v_run.state = 'done' then
      v_out := public.admin_entry_matrix_reread(array[v_src.id], v_reason);
    else
      update pipeline.entry_matrix_runs set previous_results = previous_results || jsonb_build_array(jsonb_build_object('held', v_run.error like 'held_%',
               'reason', 'read again from the workspace: ' || v_reason, 'error', left(coalesce(v_run.error, ''), 300), 'attempt', attempts, 'model', model_code, 'at', now(), 'result', result)),
             state = 'queued', attempts = 0, leased_until = null, error = null, updated_at = now()
       where id = v_run.id;
      insert into pipeline.admin_control_events(area, action, target, detail, actor)
      values ('entry_matrix', 'reread_failed', 'pipeline.entry_matrix_runs', jsonb_build_object('source', v_src.id, 'run', v_run.id, 'reason', v_reason), auth.uid());
      v_out := jsonb_build_object('ok', true, 'runs', 1);
    end if;
    return v_out;
  end if;

  if p_action = 'add' then
    -- W5: a row an operator supplies from official evidence: active, provenance manual, audited
    if coalesce(btrim(a->>'quote'), '') = '' or length(a->>'quote') > 300 then raise exception 'give the exact quote from the source (up to 300 characters)' using errcode = '22023'; end if;
    if coalesce(a->>'source_url', '') !~* '^https?://[^[:space:]]+\.[^[:space:]]+$' then raise exception 'give the official source address, starting with https://' using errcode = '22023'; end if;
    select * into v_ev from pipeline.evidence_artifacts where id = (a->>'evidence_id')::uuid;
    if v_ev.id is null or v_ev.storage_path is null then raise exception 'choose the stored copy of the source page' using errcode = '22023'; end if;
    if lower(rtrim(regexp_replace(v_ev.source_url, '^https?://(www\.)?', ''), '/')) <> lower(rtrim(regexp_replace(a->>'source_url', '^https?://(www\.)?', ''), '/')) then
      raise exception 'the stored copy is of another address (%); store the source page first', v_ev.source_url using errcode = '22023'; end if;
    v_new := a;
  else
    v_id := (a->>'id')::uuid;
    begin v_exp := (p_args->>'expected_updated_at')::timestamptz; exception when others then v_exp := null; end;
    if v_exp is null then raise exception 'reload the row before changing it' using errcode = '22023'; end if;
  end if;

  if v_kind = 'matrix' then
    if p_action = 'add' then
      v_cc := upper(coalesce(a->>'country', ''));
      if not exists (select 1 from ref.countries k0 where k0.iso_alpha2 = v_cc) then raise exception 'choose the country of prior education' using errcode = '22023'; end if;
      if not exists (select 1 from catalogue.providers p0 where p0.id = (a->>'provider_id')::uuid) then raise exception 'choose the provider' using errcode = '22023'; end if;
      m.id := gen_random_uuid(); m.provider_id := (a->>'provider_id')::uuid; m.country_code := v_cc; m.country_id := (select k0.id from ref.countries k0 where k0.iso_alpha2 = v_cc);
      m.matrix_kind := coalesce(a->>'matrix_kind', 'provider_minimum'); m.audience := coalesce(a->>'audience', 'international');
      m.quote := btrim(a->>'quote'); m.source_url := btrim(a->>'source_url'); m.evidence_id := v_ev.id; m.content_hash := v_ev.content_hash;
      m.status := 'active'; m.as_at := coalesce((a->>'as_at')::date, current_date); m.conditions := '{}'::jsonb;
      m.course_id := (a->>'course_id')::uuid; m.created_at := now(); m.updated_at := now(); m.version := 1;
      if m.matrix_kind not in ('provider_minimum', 'band_ladder', 'course_minimum', 'rank_band') then raise exception 'unknown matrix kind' using errcode = '22023'; end if;
      if m.matrix_kind = 'course_minimum' and (m.course_id is null or not exists (select 1 from catalogue.courses c0 where c0.id = m.course_id and c0.provider_id = m.provider_id)) then
        raise exception 'a course minimum needs one of this provider''s courses' using errcode = '22023'; end if;
      m.provenance := jsonb_build_object('reader', 'manual', 'actor', auth.uid(), 'reason', v_reason, 'at', now(), 'evidence_id', v_ev.id);
      v_editable := array['qualification', 'level_label', 'level_code', 'band', 'min_grade', 'min_value', 'scale', 'conditions', 'edition', 'intake_year', 'as_at'];
      ch := a; v_cur := '{}'::jsonb;
    else
      select * into m from catalogue.provider_entry_matrix where id = v_id for update;
      if m.id is null then raise exception 'row not found'; end if;
      if m.updated_at is distinct from v_exp then raise exception 'this row was changed by someone else since you opened it; reload and try again' using errcode = '40001'; end if;
      v_cur := security.aer_row_v1('matrix', v_id);
      if p_action = 'update' then
        if m.status = 'proposed' then raise exception 'a proposed row is decided in Layer 4, not edited here' using errcode = '22023'; end if;
        if m.status not in ('active', 'unverified') then raise exception 'only an active or quarantined row can be corrected; restore it first' using errcode = '22023'; end if;
        v_editable := array['qualification', 'level_label', 'level_code', 'band', 'min_grade', 'min_value', 'scale', 'conditions', 'edition', 'intake_year', 'as_at'];
        ch := coalesce(p_args->'changes', '{}'::jsonb);
        if exists (select 1 from jsonb_object_keys(ch) k0 where not (k0 = any (v_editable))) then raise exception 'this field cannot be changed here' using errcode = '22023'; end if;
        if ch = '{}'::jsonb then return jsonb_build_object('ok', true, 'row', v_cur, 'changed', 0); end if;
      end if;
    end if;
    if p_action in ('update', 'add') then
      for v_key in select * from jsonb_object_keys(ch) loop
        if not (v_key = any (v_editable)) then continue; end if;
        v_txt := nullif(btrim(ch->>v_key), '');
        if v_key = 'qualification' then
          if v_txt is null or length(v_txt) > 300 then raise exception 'give the qualification as published (up to 300 characters)' using errcode = '22023'; end if; m.qualification_name := v_txt;
        elsif v_key = 'level_label' then m.level_label := left(v_txt, 120);
        elsif v_key = 'level_code' then
          if v_txt is null then m.study_level_id := null;
          else select l0.id into v_lvl from ref.study_levels l0 where l0.short_code = v_txt; if v_lvl is null then raise exception 'unknown study level' using errcode = '22023'; end if; m.study_level_id := v_lvl; end if;
        elsif v_key = 'band' then m.benchmark_band := left(v_txt, 60);
        elsif v_key = 'min_grade' then m.min_grade := left(v_txt, 120);
        elsif v_key = 'min_value' then
          if v_txt is not null and v_txt !~ '^[0-9]+(\.[0-9]+)?$' then raise exception 'the numeric value is a number, for example 65 or 3.5' using errcode = '22023'; end if; m.min_value := v_txt::numeric;
        elsif v_key = 'scale' then
          if coalesce(v_txt, 'none') not in ('percentage', 'points', 'aggregate', 'gpa', 'letter', 'rank', 'none') then raise exception 'unknown scale' using errcode = '22023'; end if; m.grade_scale := coalesce(v_txt, 'none');
        elsif v_key = 'conditions' then m.conditions := security.aer_conditions_v1(ch->'conditions');
        elsif v_key = 'edition' then m.edition := left(v_txt, 100);
        elsif v_key = 'intake_year' then
          if v_txt is not null and (v_txt !~ '^\d{4}$' or v_txt::int not between 2000 and 2100) then raise exception 'the intake year is a year, for example 2027' using errcode = '22023'; end if; m.intake_year := v_txt::int;
        elsif v_key = 'as_at' then
          begin m.as_at := coalesce(v_txt::date, m.as_at); exception when others then raise exception 'the as-at date is a date, for example 29/10/2026' using errcode = '22023'; end;
        end if;
      end loop;
      if m.qualification_name is null then raise exception 'give the qualification as published' using errcode = '22023'; end if;
      -- W7: source-supported values, a value with its scale
      if m.min_value is not null and coalesce(m.grade_scale, 'none') = 'none' then raise exception 'a numeric value needs its scale (percentage, points, GPA, ...)' using errcode = '22023'; end if;
      if not security.aer_band_in_quote_v1(m.benchmark_band, m.quote) then raise exception 'the band "%" is not printed in the row''s quote', m.benchmark_band using errcode = '22023'; end if;
      if not security.aer_numbers_in_quote_v1(m.min_grade, m.quote) then raise exception 'the minimum "%" is not printed in the row''s quote', m.min_grade using errcode = '22023'; end if;
      if m.min_value is not null and not security.aer_numbers_in_quote_v1(m.min_value::text, m.quote) then raise exception 'the value % is not printed in the row''s quote', m.min_value using errcode = '22023'; end if;
    end if;
    begin
      if p_action = 'add' then
        insert into catalogue.provider_entry_matrix select m.*;
        v_id := m.id;
      elsif p_action = 'update' then
        update catalogue.provider_entry_matrix set qualification_name = m.qualification_name, level_label = m.level_label, study_level_id = m.study_level_id,
               benchmark_band = m.benchmark_band, min_grade = m.min_grade, min_value = m.min_value, grade_scale = m.grade_scale, conditions = m.conditions,
               edition = m.edition, intake_year = m.intake_year, as_at = m.as_at, version = coalesce(version, 1) + 1, updated_at = clock_timestamp()
         where id = v_id;
      else  -- lifecycle
        if a->>'lifecycle' = 'withdraw' then
          if m.status <> 'active' then raise exception 'only an active row can be withdrawn' using errcode = '22023'; end if;
          update catalogue.provider_entry_matrix set status = 'inactive', status_reason = 'withdrawn: ' || v_reason, withdrawal_reason = left(v_reason, 500),
                 valid_to = current_date, updated_at = clock_timestamp() where id = v_id;
        elsif a->>'lifecycle' = 'quarantine' then
          if m.status <> 'active' then raise exception 'only an active row can be quarantined' using errcode = '22023'; end if;
          update catalogue.provider_entry_matrix set status = 'unverified', status_reason = 'quarantined: ' || v_reason, updated_at = clock_timestamp() where id = v_id;
        elsif a->>'lifecycle' = 'restore' then
          select h.action into v_last from pipeline.manual_edit_log h where h.entity = 'entry_matrix' and h.entity_id = v_id and h.action in ('withdraw', 'quarantine', 'restore')
           order by h.at desc, h.id desc limit 1;
          if m.status not in ('inactive', 'unverified') or coalesce(v_last, '') not in ('withdraw', 'quarantine') then
            raise exception 'only a row withdrawn or quarantined here can be restored; a row never admitted is decided in Layer 4' using errcode = '22023'; end if;
          update catalogue.provider_entry_matrix set status = 'active', status_reason = null, withdrawal_reason = null, valid_to = null, updated_at = clock_timestamp() where id = v_id;
        else raise exception 'unknown lifecycle action' using errcode = '22023'; end if;
      end if;
    exception when unique_violation then
      raise exception 'another active row already has this provider, country, level, band and qualification; correct that row instead' using errcode = '23505';
    end;
  else  -- course requirement rows
    if p_action = 'add' then
      if not exists (select 1 from catalogue.courses c0 where c0.id = (a->>'course_id')::uuid) then raise exception 'choose the course' using errcode = '22023'; end if;
      x.id := gen_random_uuid(); x.course_id := (a->>'course_id')::uuid; x.kind := coalesce(a->>'requirement_kind', 'minimum_grade'); x.audience := coalesce(a->>'audience', 'international');
      if x.kind not in ('prior_qualification', 'minimum_grade', 'subject_prerequisite', 'portfolio_interview', 'work_experience', 'other', 'override', 'general_note') then raise exception 'unknown requirement kind' using errcode = '22023'; end if;
      if x.audience not in ('international', 'domestic', 'all') then raise exception 'unknown audience' using errcode = '22023'; end if;
      if a->>'country' is not null then x.country_id := (select k0.id from ref.countries k0 where k0.iso_alpha2 = upper(a->>'country')); if x.country_id is null then raise exception 'unknown country' using errcode = '22023'; end if; end if;
      x.quote := btrim(a->>'quote'); x.source_url := btrim(a->>'source_url'); x.evidence_id := v_ev.id; x.status := 'active'; x.as_at := coalesce((a->>'as_at')::date, current_date);
      x.provenance := jsonb_build_object('reader', 'manual', 'actor', auth.uid(), 'reason', v_reason, 'at', now(), 'evidence_id', v_ev.id);
      x.description := btrim(coalesce(a->>'description', '')); x.created_at := now(); x.updated_at := now();
      v_editable := array['description', 'min_grade', 'min_value', 'scale', 'min_entry_score', 'min_entry_score_basis', 'band', 'as_at'];
      ch := a; v_cur := '{}'::jsonb;
    else
      select * into x from catalogue.course_entry_requirements where id = v_id for update;
      if x.id is null then raise exception 'row not found'; end if;
      if x.updated_at is distinct from v_exp then raise exception 'this row was changed by someone else since you opened it; reload and try again' using errcode = '40001'; end if;
      v_cur := security.aer_row_v1('course', v_id);
      if p_action = 'update' then
        if x.status = 'proposed' then raise exception 'a proposed row is decided in Layer 4, not edited here' using errcode = '22023'; end if;
        if x.status not in ('active', 'unverified') then raise exception 'only an active or quarantined row can be corrected; restore it first' using errcode = '22023'; end if;
        v_editable := array['description', 'min_grade', 'min_value', 'scale', 'min_entry_score', 'min_entry_score_basis', 'band', 'as_at'];
        ch := coalesce(p_args->'changes', '{}'::jsonb);
        if exists (select 1 from jsonb_object_keys(ch) k0 where not (k0 = any (v_editable))) then raise exception 'this field cannot be changed here' using errcode = '22023'; end if;
        if ch = '{}'::jsonb then return jsonb_build_object('ok', true, 'row', v_cur, 'changed', 0); end if;
      end if;
    end if;
    if p_action in ('update', 'add') then
      for v_key in select * from jsonb_object_keys(ch) loop
        if not (v_key = any (v_editable)) then continue; end if;
        v_txt := nullif(btrim(ch->>v_key), '');
        if v_key = 'description' then if v_txt is null then raise exception 'give the requirement as published' using errcode = '22023'; end if; x.description := left(v_txt, 1000);
        elsif v_key = 'min_grade' then x.min_grade := left(v_txt, 120);
        elsif v_key = 'min_value' then
          if v_txt is not null and v_txt !~ '^[0-9]+(\.[0-9]+)?$' then raise exception 'the numeric value is a number, for example 65 or 3.5' using errcode = '22023'; end if; x.min_value := v_txt::numeric;
        elsif v_key = 'scale' then
          if coalesce(v_txt, 'none') not in ('percentage', 'points', 'aggregate', 'gpa', 'letter', 'rank', 'none') then raise exception 'unknown scale' using errcode = '22023'; end if; x.grade_scale := coalesce(v_txt, 'none');
        elsif v_key = 'min_entry_score' then
          if v_txt is not null and v_txt !~ '^[0-9]+(\.[0-9]+)?$' then raise exception 'the course score is a number, for example 75' using errcode = '22023'; end if; x.min_entry_score := v_txt::numeric;
        elsif v_key = 'min_entry_score_basis' then x.min_entry_score_basis := left(v_txt, 120);
        elsif v_key = 'band' then x.benchmark_band := left(v_txt, 60);
        elsif v_key = 'as_at' then
          begin x.as_at := coalesce(v_txt::date, x.as_at); exception when others then raise exception 'the as-at date is a date, for example 29/10/2026' using errcode = '22023'; end;
        end if;
      end loop;
      if coalesce(x.description, '') = '' then raise exception 'give the requirement as published' using errcode = '22023'; end if;
      if x.min_value is not null and coalesce(x.grade_scale, 'none') = 'none' then raise exception 'a numeric value needs its scale (percentage, points, GPA, ...)' using errcode = '22023'; end if;
      if x.min_entry_score is not null and nullif(btrim(x.min_entry_score_basis), '') is null then raise exception 'a course score needs its printed basis (for example "2027 Guaranteed ATAR")' using errcode = '22023'; end if;
      if not security.aer_band_in_quote_v1(x.benchmark_band, x.quote) then raise exception 'the band "%" is not printed in the row''s quote', x.benchmark_band using errcode = '22023'; end if;
      if not security.aer_numbers_in_quote_v1(x.min_grade, x.quote) then raise exception 'the minimum "%" is not printed in the row''s quote', x.min_grade using errcode = '22023'; end if;
      if x.min_value is not null and not security.aer_numbers_in_quote_v1(x.min_value::text, x.quote) then raise exception 'the value % is not printed in the row''s quote', x.min_value using errcode = '22023'; end if;
      if x.min_entry_score is not null and not security.aer_numbers_in_quote_v1(x.min_entry_score::text, x.quote) then raise exception 'the course score % is not printed in the row''s quote', x.min_entry_score using errcode = '22023'; end if;
    end if;
    if p_action = 'add' then
      insert into catalogue.course_entry_requirements select x.*;
      v_id := x.id;
    elsif p_action = 'update' then
      update catalogue.course_entry_requirements set description = x.description, min_grade = x.min_grade, min_value = x.min_value, grade_scale = x.grade_scale,
             min_entry_score = x.min_entry_score, min_entry_score_basis = x.min_entry_score_basis, benchmark_band = x.benchmark_band, as_at = x.as_at, updated_at = clock_timestamp()
       where id = v_id;
    else
      if a->>'lifecycle' = 'withdraw' then
        if x.status <> 'active' then raise exception 'only an active row can be withdrawn' using errcode = '22023'; end if;
        update catalogue.course_entry_requirements set status = 'inactive', status_reason = 'withdrawn: ' || v_reason, updated_at = clock_timestamp() where id = v_id;
      elsif a->>'lifecycle' = 'quarantine' then
        if x.status <> 'active' then raise exception 'only an active row can be quarantined' using errcode = '22023'; end if;
        update catalogue.course_entry_requirements set status = 'unverified', status_reason = 'quarantined: ' || v_reason, updated_at = clock_timestamp() where id = v_id;
      elsif a->>'lifecycle' = 'restore' then
        select h.action into v_last from pipeline.manual_edit_log h where h.entity = 'course_entry' and h.entity_id = v_id and h.action in ('withdraw', 'quarantine', 'restore')
         order by h.at desc, h.id desc limit 1;
        if x.status not in ('inactive', 'unverified') or coalesce(v_last, '') not in ('withdraw', 'quarantine') then
          raise exception 'only a row withdrawn or quarantined here can be restored; a row never admitted is decided in Layer 4' using errcode = '22023'; end if;
        update catalogue.course_entry_requirements set status = 'active', status_reason = null, updated_at = clock_timestamp() where id = v_id;
      else raise exception 'unknown lifecycle action' using errcode = '22023'; end if;
    end if;
  end if;

  -- W10: one history entry per changed field (before and after), the actor, the time and the reason
  v_new := security.aer_row_v1(v_kind, v_id);
  if p_action = 'update' then
    insert into pipeline.manual_edit_log(entity, entity_id, field, action, before, after, reason, actor)
    select case v_kind when 'matrix' then 'entry_matrix' else 'course_entry' end, v_id, f.key, 'edit', v_cur->f.key, v_new->f.key, v_reason, auth.uid()
      from jsonb_each(v_new) f
     where f.key in ('qualification', 'level_label', 'level_code', 'band', 'min_grade', 'min_value', 'scale', 'conditions', 'edition', 'intake_year', 'as_at',
                     'description', 'min_entry_score', 'min_entry_score_basis')
       and (v_cur->f.key) is distinct from f.value;
    get diagnostics v_n = row_count;
  elsif p_action = 'add' then
    insert into pipeline.manual_edit_log(entity, entity_id, field, action, before, after, reason, actor)
    values (case v_kind when 'matrix' then 'entry_matrix' else 'course_entry' end, v_id, '*', 'add', null, v_new - 'provenance', v_reason, auth.uid());
    v_n := 1;
  else
    insert into pipeline.manual_edit_log(entity, entity_id, field, action, before, after, reason, actor)
    values (case v_kind when 'matrix' then 'entry_matrix' else 'course_entry' end, v_id, 'status', a->>'lifecycle', v_cur->'status', v_new->'status', v_reason, auth.uid());
    v_n := 1;
  end if;
  return jsonb_build_object('ok', true, 'row', v_new, 'changed', v_n);
end $$;
revoke all on function public.admin_aer(text, jsonb) from public, anon;
grant execute on function public.admin_aer(text, jsonb) to authenticated;
comment on function public.admin_aer(text, jsonb) is 'CF-247 AER operations workspace (Catalogue › Entry requirements): bounded lists, summary, row history, governed edit / add / withdraw / quarantine / restore with reason, concurrency and audit (manual_edit_log), bounded source re-read, resolution inspection. Admission of AI rows stays in Layer 4.';

revoke all on function security.aer_numbers_in_quote_v1(text, text) from public, anon;
revoke all on function security.aer_band_in_quote_v1(text, text) from public, anon;
revoke all on function security.aer_conditions_v1(jsonb) from public, anon;
