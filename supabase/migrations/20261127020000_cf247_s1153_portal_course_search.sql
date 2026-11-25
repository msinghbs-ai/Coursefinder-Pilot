-- CF-247 s1153 (S2-Build; Platform Admin 25 Nov 2026 17:13 AEDT, "Portal Release 1 Search Activation"): plain-English course search for the
-- StudySearch Portal's Courses screen, built to the contract in coursefinder-admin docs/platform/2026-11-25-studysearch-portal-design-decisions-
-- and-plan.md ("Release 1 screens as built"), and the course embeddings it ranks with.
-- Read live before writing (rolled-back read-backs, head 20261127000000):
--   * search.course_embeddings (vector 1536, HNSW cosine; key course, profile, model), search.embedding_jobs and search.query_embedding_cache exist
--     with 0 rows; nothing processes embedding_jobs. search.course_candidates_v1 (reciprocal rank fusion, k from the profile) is called by
--     api.zoho_course_candidates_v1 (frozen G3), so portal vectors are kept under a NEW profile portal-default: the website-default and
--     zoho-default profiles get no vectors and Zoho results cannot change.
--   * 36,052 active courses; 34,362 have a search document (semantic_content_hash on every one). The 1,690 without one are sent to the existing
--     document refresh (search.course_refresh_request_v1, job search-refresh-requested) and are embedded when their document is built.
--   * SQL cannot call a model (no http extension; pg_net is asynchronous). Model calls go through OpenRouter, which the platform already uses
--     (OPENROUTER_API_KEY), with openai/text-embedding-3-small (US$0.02 per million tokens) and provider data collection denied.
-- What this adds (all new, beside what exists; nothing existing is altered or dropped):
--   1. Settings (G2, toolset portal_search): page size, relaxation rules (fewer than 3 exact matches; third-cheapest fee + 5% rounded up to
--      A$1,000; at most +30%), topic threshold, query cache hours and daily query limit, embedding model, price, batch, daily spend ceiling and
--      visibility scope (active now; published once publishing is live).
--   2. Search profile portal-default (channel admin; rrf_k 60 and the website weights).
--   3. Embedding queue wiring: every search document without a current portal vector is queued, in steps of portal_search.enqueue_chunk by
--      the lane (one statement for all 34,362 ran past the statement time-out in rehearsal); a statement trigger on
--      search.course_documents queues a course again whenever its semantic text changes (a description or career outcome admitted and
--      projected), so re-embedding needs no job of its own.
--   4. Edge function portal-search-embed (one-time nonce, allowlisted) and its service reads public.svc_portal_search_embed_next /
--      public.svc_portal_search_embed_record. Course batches run on the existing coverage-lane-dispatch as a new registry lane (no pg_cron job);
--      a typed query is embedded on demand when the search is called and cached for the next call.
--   5. catalogue.portal_course_search_v1(p_args) and the public entry public.portal_course_search_v1(p_args) (Viewer and above): Stage 1 turns the
--      words into filters from the live country, state, campus city and study level tables and a budget; Stage 2 ranks with
--      search.course_candidates_v1 (hybrid when the query vector is cached, keyword otherwise); fewer than 3 exact matches bring near misses and
--      relaxations that are never applied until the person chooses them.
-- Spend: about 9 million tokens for the backfill, about US$0.18, inside the US$5.00 daily cap; the batch read refuses when the day's logged AI
-- spend reaches the platform ceiling or this service's own ceiling.
-- G1: no cron job (a registry lane on the existing dispatcher). G2: every number is a setting below. G3: no consumer object changed (75/48 before
-- and after). Manual locks untouched. Nothing dropped or deleted.
-- Replaces: nothing (the Courses screen's "not switched on yet" notice gives way to results).
-- Retires: nothing.
set local lock_timeout = '5s';  -- fixed: lock wait for the trigger and registry rows

do $g$
declare v jsonb := security.consumer_api_check_v1();
begin
  if jsonb_array_length(coalesce(v->'drift', '[]'::jsonb)) <> 0 or (v->>'functions')::int <> 75 or (v->>'relations')::int <> 48 then
    raise exception 'guard: the consumer API is not at its baseline before this change: %', v;
  end if;
end $g$;
create temp table s1153_locks on commit drop as select count(*) n from pipeline.manual_locks;
create temp table s1153_cron on commit drop as select count(*) n from cron.job where active;

-- 1. Settings (G2). They show on Settings › Toolsets & limits.
insert into pipeline.platform_toolsets (key, label, kind, layers, help, sort, reason)
values ('portal_search', 'StudySearch Portal course search', 'platform', array[0],
        'How the portal''s plain-English course search filters, ranks and relaxes, and the model and budget used to give courses and typed queries their meaning vectors.',
        61, 'CF-247 s1153: Platform Admin 25 Nov 2026 17:13 (no operational value written into code)')
on conflict (key) do nothing;

insert into pipeline.platform_toolset_settings (toolset_key, key, label, help, kind, value, min_value, max_value, unit, sort, section, used_by, reason)
values
 ('portal_search', 'result_page_size', 'Courses: results per search', 'How many courses one search returns.', 'number', '20'::jsonb, 5, 50, 'courses', 6110, 'Portal search', 'catalogue.portal_course_search_v1', 'CF-247 s1153'),
 ('portal_search', 'relax_min_matches', 'Relaxation starts below', 'When fewer courses than this match every filter, near misses and relaxations are offered.', 'number', '3'::jsonb, 1, 10, 'courses', 6120, 'Portal search', 'catalogue.portal_course_search_v1', 'CF-247 s1153'),
 ('portal_search', 'relax_budget_headroom_pct', 'Suggested budget: headroom', 'Percentage added to the third-cheapest otherwise matching fee before rounding.', 'number', '5'::jsonb, 0, 25, '%', 6130, 'Portal search', 'catalogue.portal_course_search_v1', 'CF-247 s1153'),
 ('portal_search', 'relax_budget_round_to', 'Suggested budget: rounded up to', 'The suggested budget is rounded up to a multiple of this amount.', 'number', '1000'::jsonb, 100, 10000, 'dollars', 6140, 'Portal search', 'catalogue.portal_course_search_v1', 'CF-247 s1153'),
 ('portal_search', 'relax_budget_max_raise_pct', 'Suggested budget: largest raise', 'The largest budget raise offered; beyond it only "Remove the budget" is offered.', 'number', '30'::jsonb, 5, 100, '%', 6150, 'Portal search', 'catalogue.portal_course_search_v1', 'CF-247 s1153'),
 ('portal_search', 'topic_min_similarity', 'Topic match: least meaning similarity', 'A course counts as a topic match when its meaning similarity to the typed topic is at least this (or its words match).', 'number', '0.35'::jsonb, 0.1, 0.9, 'similarity', 6160, 'Portal search', 'catalogue.portal_course_search_v1', 'CF-247 s1153'),
 ('portal_search', 'query_cache_hours', 'Typed query meaning: reused for', 'How long a typed query''s meaning vector is reused before it is worked out again.', 'number', '24'::jsonb, 1, 720, 'hours', 6170, 'Portal search', 'catalogue.portal_course_search_v1', 'CF-247 s1153'),
 ('portal_search', 'query_embed_daily_max', 'Typed queries embedded a day', 'The most new typed queries given a meaning vector in one Melbourne day; beyond it searches rank by words only.', 'number', '5000'::jsonb, 100, 50000, 'queries', 6180, 'Portal search', 'catalogue.portal_course_search_v1', 'CF-247 s1153'),
 ('portal_search', 'embed_batch', 'Course embedding: courses per batch', 'How many courses one embedding request carries.', 'number', '150'::jsonb, 20, 500, 'courses', 6190, 'Portal search', 'public.svc_portal_search_embed_next; edge function portal-search-embed', 'CF-247 s1153'),
 ('portal_search', 'enqueue_chunk', 'Course embedding: courses queued at a time', 'How many courses without a current vector are added to the queue each time it runs low (the backfill is queued in these steps).', 'number', '1500'::jsonb, 100, 10000, 'courses', 6195, 'Portal search', 'security.portal_search_embed_fire_v1', 'CF-247 s1153'),
 ('portal_search', 'embed_daily_ceiling_usd', 'Course and query embedding: daily ceiling', 'The most this service may spend in one Melbourne day; the platform ceiling budgets.ai_daily_ceiling_usd also applies.', 'number', '1'::jsonb, 0.05, 5, 'USD', 6200, 'Portal search', 'public.svc_portal_search_embed_next', 'CF-247 s1153'),
 ('portal_search', 'embed_usd_per_mtok', 'Embedding model price', 'The model''s list price per million input tokens, used to log spend.', 'number', '0.02'::jsonb, 0, 1, 'USD per million tokens', 6210, 'Portal search', 'public.svc_portal_search_embed_record', 'CF-247 s1153: OpenRouter list price 25 Nov 2026'),
 ('portal_search', 'embedding_model', 'Embedding model', 'Model used for course and query vectors (1536 dimensions); changed only with a reason and a full re-embed.', 'text', '"openai/text-embedding-3-small"'::jsonb, null, null, null, 6220, 'Portal search', 'catalogue.portal_course_search_v1; edge function portal-search-embed', 'CF-247 s1153: Platform Admin 25 Nov 2026 (pinned)'),
 ('portal_search', 'visibility_scope', 'Courses searched', 'active: every active course; published: published courses only (set once publishing is live). Inactive, suspended and unknown-status courses are never searched.', 'text', '"active"'::jsonb, null, null, null, 6230, 'Portal search', 'catalogue.portal_course_search_v1', 'CF-247 s1153: Platform Admin 25 Nov 2026')
on conflict do nothing;

create or replace function security.portal_search_num_v1(p_key text, p_default numeric)
returns numeric language sql stable security definer set search_path = '' as $function$
  select coalesce((select (s.value #>> '{}')::numeric from pipeline.platform_toolset_settings s where s.toolset_key = 'portal_search' and s.key = p_key), p_default)
$function$;
create or replace function security.portal_search_text_v1(p_key text, p_default text)
returns text language sql stable security definer set search_path = '' as $function$
  select coalesce((select s.value #>> '{}' from pipeline.platform_toolset_settings s where s.toolset_key = 'portal_search' and s.key = p_key), p_default)
$function$;

-- 2. The portal's own search profile, so the website and Zoho profiles get no vectors.
insert into search.profiles (code, name, channel_code, version, config, status)
values ('portal-default', 'StudySearch Portal (Counsellor and Viewer search)', 'admin', 'v1', '{"rrf_k": 60, "fts_weight": 1, "vector_weight": 0.55}'::jsonb, 'active')
on conflict (code) do nothing;

-- 3. Embedding queue. A course is queued when its document has no portal vector for its current semantic text and no open job for it.
create or replace function security.portal_search_enqueue_v1(p_course_ids uuid[] default null, p_limit integer default null)
returns integer language plpgsql security definer set search_path = '' as $function$
declare v_profile uuid := (select id from search.profiles where code = 'portal-default'); v_model text := security.portal_search_text_v1('embedding_model', 'openai/text-embedding-3-small'); v_n integer;
begin
  insert into search.embedding_jobs (id, course_id, profile_id, model_name, content_hash, status, attempt_count, created_at)
  select gen_random_uuid(), d.course_id, v_profile, v_model, d.semantic_content_hash, 'pending', 0, now()
    from search.course_documents d
    join catalogue.courses c on c.id = d.course_id and c.lifecycle_status = 'active'
   where (p_course_ids is null or d.course_id = any(p_course_ids))
     and not exists (select 1 from search.course_embeddings e where e.course_id = d.course_id and e.profile_id = v_profile and e.model_name = v_model and e.content_hash = d.semantic_content_hash)
     and not exists (select 1 from search.embedding_jobs j where j.course_id = d.course_id and j.profile_id = v_profile and j.model_name = v_model and j.content_hash = d.semantic_content_hash and j.status in ('pending', 'leased'))
   limit p_limit;
  get diagnostics v_n = row_count;
  return v_n;
end $function$;

create or replace function security.portal_search_doc_changed_tg()
returns trigger language plpgsql security definer set search_path = '' as $function$
begin
  perform security.portal_search_enqueue_v1(array(select n.course_id from new_rows n), null);
  return null;
end $function$;
create or replace trigger portal_search_doc_inserted after insert on search.course_documents referencing new table as new_rows
  for each statement execute function security.portal_search_doc_changed_tg();
create or replace trigger portal_search_doc_updated after update on search.course_documents referencing new table as new_rows
  for each statement execute function security.portal_search_doc_changed_tg();

-- 4a. Service reads for edge function portal-search-embed (service role only). A leased job holds its lease in completed_at until it is recorded.
create or replace function public.svc_portal_search_embed_next(p_limit integer default null)
returns jsonb language plpgsql security definer set search_path = '' as $function$
declare v_profile uuid := (select id from search.profiles where code = 'portal-default');
        v_model text := security.portal_search_text_v1('embedding_model', 'openai/text-embedding-3-small');
        v_lim integer := least(greatest(coalesce(p_limit, security.portal_search_num_v1('embed_batch', 150)::int), 1), 500);  -- fixed: request size bound
        v_day timestamptz := date_trunc('day', now() at time zone 'Australia/Melbourne') at time zone 'Australia/Melbourne';  -- fixed: Melbourne day
        v_all numeric; v_own numeric; v_items jsonb;
begin
  select coalesce(sum(cost_usd), 0), coalesce(sum(cost_usd) filter (where service_code = 'portal_search_embedding'), 0) into v_all, v_own
    from pipeline.ai_invocations where at >= v_day;
  if v_all >= security.pipeline_num_v1('budgets.ai_daily_ceiling_usd', 5) or v_own >= security.portal_search_num_v1('embed_daily_ceiling_usd', 1) then
    return jsonb_build_object('allowed', false, 'reason', 'daily AI ceiling reached', 'spent_today_usd', v_all, 'service_today_usd', v_own, 'model', v_model, 'items', '[]'::jsonb);
  end if;
  with picked as (
    select j.id from search.embedding_jobs j
     where j.profile_id = v_profile and j.model_name = v_model
       and (j.status = 'pending' or (j.status = 'leased' and j.completed_at < now()))
       and j.attempt_count < 3  -- fixed: retry bound for one job
     order by j.created_at, j.id
     limit v_lim
     for update skip locked
  ), leased as (
    update search.embedding_jobs j set status = 'leased', attempt_count = j.attempt_count + 1, completed_at = now() + interval '10 minutes'  -- fixed: lease
      from picked p where j.id = p.id
    returning j.id, j.course_id, j.content_hash
  )
  select coalesce(jsonb_agg(jsonb_build_object('job_id', l.id, 'course_id', l.course_id, 'content_hash', l.content_hash,
           'text', left(concat_ws(E'\n', d.course_title,
                                  nullif(concat_ws(' ', initcap(replace(d.study_level_code, '_', ' ')), 'in', d.primary_field_name), ''),
                                  nullif(array_to_string(d.academic_option_names, ', '), ''),
                                  nullif(left(d.description, 1800), ''),
                                  nullif(left(d.enrichment_semantic_text, 1800), '')), 6000))), '[]'::jsonb)  -- fixed: input size bound
    into v_items
    from leased l join search.course_documents d on d.course_id = l.course_id;
  return jsonb_build_object('allowed', true, 'model', v_model, 'dimensions', 1536, 'items', v_items,  -- fixed: the vector column's dimensions
                            'pending', (select count(*) from search.embedding_jobs j where j.profile_id = v_profile and j.model_name = v_model and j.status = 'pending'));
end $function$;

create or replace function public.svc_portal_search_embed_record(p_payload jsonb)
returns jsonb language plpgsql security definer set search_path = '' as $function$
declare v_profile uuid := (select id from search.profiles where code = 'portal-default');
        v_model text := coalesce(p_payload->>'model', security.portal_search_text_v1('embedding_model', 'openai/text-embedding-3-small'));
        v_tokens bigint := coalesce((p_payload->>'tokens')::bigint, 0);
        v_cost numeric := round(coalesce((p_payload->>'tokens')::numeric, 0) * security.portal_search_num_v1('embed_usd_per_mtok', 0.02) / 1000000, 6);  -- fixed: per million
        v_ok integer := 0; v_failed integer := 0; v_q integer := 0; r jsonb;
begin
  for r in select x from jsonb_array_elements(coalesce(p_payload->'items', '[]'::jsonb)) x loop
    if r ? 'query_key' then
      insert into search.query_embedding_cache (cache_key, model_name, profile_version, embedding, created_at, last_used_at, hit_count, expires_at)
      values (r->>'query_key', v_model, 'portal-default:v1', (r->>'embedding')::extensions.vector, now(), now(), 0,
              now() + make_interval(hours => security.portal_search_num_v1('query_cache_hours', 24)::int))
      on conflict (cache_key) do update set embedding = excluded.embedding, model_name = excluded.model_name, created_at = now(), expires_at = excluded.expires_at;
      v_q := v_q + 1;
    elsif r ? 'embedding' then
      insert into search.course_embeddings (course_id, profile_id, model_name, dimensions, embedding, content_hash, embedded_at)
      values ((r->>'course_id')::uuid, v_profile, v_model, 1536, (r->>'embedding')::extensions.vector, r->>'content_hash', now())  -- fixed: the vector column's dimensions
      on conflict (course_id, profile_id, model_name) do update set embedding = excluded.embedding, content_hash = excluded.content_hash, embedded_at = now();
      update search.embedding_jobs set status = 'done', completed_at = now(), error_text = null where id = (r->>'job_id')::uuid;
      v_ok := v_ok + 1;
    else
      update search.embedding_jobs set status = case when attempt_count >= 3 then 'failed' else 'pending' end, completed_at = null,  -- fixed: retry bound for one job
             error_text = left(coalesce(r->>'error', 'no vector returned'), 500)
       where id = (r->>'job_id')::uuid;
      v_failed := v_failed + 1;
    end if;
  end loop;
  if v_tokens > 0 or v_failed > 0 then
    insert into pipeline.ai_invocations (at, service_code, model, attempt_no, outcome, failure_kind, input_tokens, output_tokens, cost_usd, source, source_id, worker)
    values (now(), 'portal_search_embedding', v_model, 1, case when v_failed > 0 and v_ok + v_q = 0 then 'failed' else 'answered' end,
            case when v_failed > 0 then 'http' end, v_tokens, 0, v_cost, 'portal-search-embed', null, p_payload->>'worker');
  end if;
  return jsonb_build_object('recorded', v_ok, 'queries', v_q, 'failed', v_failed, 'tokens', v_tokens, 'cost_usd', v_cost);
end $function$;

-- 4b. Lane call: tops the queue up by a bounded chunk (the backfill is queued this way, not in one statement), then starts the edge function
-- only when course jobs are waiting (no empty calls).
create or replace function security.portal_search_embed_fire_v1()
returns bigint language plpgsql security definer set search_path = '' as $function$
begin
  if (select count(*) from search.embedding_jobs j join search.profiles p on p.id = j.profile_id and p.code = 'portal-default' where j.status = 'pending')
       < security.portal_search_num_v1('embed_batch', 150) then
    perform security.portal_search_enqueue_v1(null, security.portal_search_num_v1('enqueue_chunk', 1500)::int);
  end if;
  if not exists (select 1 from search.embedding_jobs j join search.profiles p on p.id = j.profile_id and p.code = 'portal-default'
                  where j.status = 'pending' or (j.status = 'leased' and j.completed_at < now())) then
    return null;
  end if;
  return pipeline.svc_pilot_submit_nonce('portal-search-embed', jsonb_build_object('mode', 'courses'));
end $function$;

insert into pipeline.pilot_nonce_functions (function_name) values ('portal-search-embed') on conflict do nothing;

insert into pipeline.field_execution_registry (lane_code, kind, legacy_job, call_sql, call_md5, schedule, priority, enabled, mode, budget_ms, expected_ms, uses_ai, owner, note)
values ('portal-search-embed', 'worker_lane', 'portal-search-embed', 'select security.portal_search_embed_fire_v1()', md5('select security.portal_search_embed_fire_v1()'),
        '* * * * *', 50, true, 'live', 2000, 500, true, 'S2-Build',
        'CF-247 s1153: course meaning vectors for the portal search (edge function portal-search-embed); starts only when jobs wait; no pg_cron job')
on conflict (lane_code) do nothing;

-- 5. The search. Stage 1: words to filters (live vocabulary). Stage 2: rank with search.course_candidates_v1. Relaxations are offered, never applied.
create or replace function catalogue.portal_course_search_v1(p_args jsonb default '{}'::jsonb)
returns jsonb language plpgsql volatile security definer set search_path = '' as $function$
declare
  v_q_raw text := coalesce(trim(p_args->>'q'), '');
  v_t text;
  v_removed text[] := array(select jsonb_array_elements_text(coalesce(p_args->'removed', '[]'::jsonb)));
  v_countries text[] := array(select upper(jsonb_array_elements_text(coalesce(p_args->'countries', '[]'::jsonb))));
  v_provider uuid := nullif(p_args->>'provider_id', '')::uuid;
  v_page integer := security.portal_search_num_v1('result_page_size', 20)::int;
  v_min integer := security.portal_search_num_v1('relax_min_matches', 3)::int;
  v_head numeric := security.portal_search_num_v1('relax_budget_headroom_pct', 5);
  v_round numeric := security.portal_search_num_v1('relax_budget_round_to', 1000);
  v_maxraise numeric := security.portal_search_num_v1('relax_budget_max_raise_pct', 30);
  v_simmin numeric := security.portal_search_num_v1('topic_min_similarity', 0.35);
  v_model text := security.portal_search_text_v1('embedding_model', 'openai/text-embedding-3-small');
  v_scope text := security.portal_search_text_v1('visibility_scope', 'active');
  v_today date := (now() at time zone 'Australia/Melbourne')::date;  -- fixed: Melbourne calendar day
  v_qcountries text[] := '{}'; v_states text[] := '{}'; v_cities text[] := '{}'; v_city_states text[] := '{}'; v_levels text[] := '{}';
  v_level_label text; v_loc_label text; v_budget numeric; v_budget_cur text; v_budget_raw text; m text[]; r record;
  v_topic text; v_tsq text; v_vec extensions.vector; v_key text; v_hybrid boolean := false;
  v_chips jsonb := '[]'::jsonb; v_exact jsonb; v_near jsonb := '[]'::jsonb; v_relax jsonb := '[]'::jsonb; v_total integer; v_ids uuid[];
  v_relax_budget numeric; v_relax_budget_set boolean := false; v_relax_loc text[];
  v_cur_sym text;
begin
  v_t := ' ' || regexp_replace(lower(v_q_raw), '[^a-z0-9$.,'' -]+', ' ', 'g') || ' ';

  -- budget: "under $40,000", "below 40k", "up to A$35,000", "max 40000"
  m := regexp_match(v_t, '(under|below|less than|max(imum)?|up to|within|at most|cheaper than|no more than)\s*(a\$|au\$|aud|nz\$|nzd|c\$|cad|\$)?\s*([0-9][0-9,]*(\.[0-9]+)?)\s*(k|thousand)?');
  if m is not null then
    v_budget := replace(m[4], ',', '')::numeric * case when m[6] is not null then 1000 else 1 end;  -- fixed: "k" means thousands
    v_budget_cur := case when m[3] in ('nz$', 'nzd') then 'NZD' when m[3] in ('c$', 'cad') then 'CAD' else null end;
    v_budget_raw := m[1];
    v_t := regexp_replace(v_t, '(under|below|less than|max(imum)?|up to|within|at most|cheaper than|no more than)\s*(a\$|au\$|aud|nz\$|nzd|c\$|cad|\$)?\s*([0-9][0-9,]*(\.[0-9]+)?)\s*(k|thousand)?', ' ');
  end if;
  v_t := regexp_replace(v_t, '\m(per year|a year|per annum|annually|each year|a yr|per yr|p\.a\.|tuition|fees?)\M', ' ', 'g');

  -- countries (live names of countries with active courses)
  for r in select distinct co.iso_alpha2 code, lower(co.name) nm from ref.countries co
            where exists (select 1 from search.course_documents d where d.country_code = co.iso_alpha2) order by 2 loop
    if position(' ' || r.nm || ' ' in v_t) > 0 then v_qcountries := v_qcountries || r.code; v_t := replace(v_t, ' ' || r.nm || ' ', ' '); end if;
  end loop;

  -- states (live subdivision names, and AU short codes as whole words)
  for r in select s.code, lower(s.name) nm, lower(split_part(s.code, '-', 2)) short, co.iso_alpha2 cc
             from ref.subdivisions s join ref.countries co on co.id = s.country_id
            where s.code in (select unnest(subdivision_codes) from search.course_documents) order by length(s.name) desc loop
    if position(' ' || r.nm || ' ' in v_t) > 0 then v_states := v_states || r.code; v_t := replace(v_t, ' ' || r.nm || ' ', ' ');
    elsif r.cc = 'AU' and position(' ' || r.short || ' ' in v_t) > 0 then v_states := v_states || r.code; v_t := replace(v_t, ' ' || r.short || ' ', ' ');
    end if;
  end loop;

  -- campus cities (live campus table), longest names first
  for r in select lower(trim(ca.city)) nm, array_agg(distinct s.code) filter (where s.code is not null) sc
             from catalogue.campuses ca left join ref.subdivisions s on s.id = ca.subdivision_id
            where ca.city is not null and length(trim(ca.city)) >= 3 and coalesce(ca.status, 'active') = 'active'
            group by 1 order by length(lower(trim(ca.city))) desc loop
    if position(' ' || r.nm || ' ' in v_t) > 0 then
      v_cities := v_cities || r.nm; v_city_states := v_city_states || coalesce(r.sc, '{}'); v_t := replace(v_t, ' ' || r.nm || ' ', ' ');
    end if;
  end loop;

  -- study level (grammar words mapped onto the live level codes)
  for r in select * from (values
      (1, '\m(graduate|grad)\s+certificate\M', 'graduate_certificate', 'Graduate Certificate'),
      (2, '\m(graduate|grad)\s+diploma\M', 'graduate_diploma', 'Graduate Diploma'),
      (3, '\madvanced\s+diploma\M', 'advanced_diploma', 'Advanced Diploma'),
      (4, '\massociate\s+degree\M', 'associate_degree', 'Associate Degree'),
      (5, '\m(phd|doctorate|doctoral|doctor of philosophy)\M', 'doctorate', 'Doctorate'),
      (6, '\m(masters?|master''s|mba|msc)\M', 'masters%', 'Master'),
      (7, '\m(bachelors?|bachelor''s|undergraduate)\M', 'bachelor%', 'Bachelor'),
      (8, '\mcertificate\s+(iv|4)\M', 'certificate_iv', 'Certificate IV'),
      (9, '\mcertificate\s+(iii|3)\M', 'certificate_iii', 'Certificate III'),
      (10, '\mdiploma\M', 'diploma', 'Diploma'),
      (11, '\mfoundation\M', 'foundation', 'Foundation')) v(n, pat, code, label) order by n loop
    if v_level_label is null and v_t ~ r.pat then
      v_levels := array(select distinct d.study_level_code from search.course_documents d where d.study_level_code like r.code);
      v_level_label := r.label; v_t := regexp_replace(v_t, r.pat, ' ', 'g');
    end if;
  end loop;

  -- what is left is the topic (words only change the order)
  v_topic := trim(regexp_replace(regexp_replace(v_t, '\m(in|of|at|for|the|a|an|and|or|with|near|around|course|courses|degree|degrees|program|programme|programs|study|studying|studies|university|universities|uni|college|online|campus|international|students?|want|looking|find|me|my|i|to|on|from)\M', ' ', 'g'), '[^a-z0-9'' ]+|\s+', ' ', 'g'));
  if v_topic = '' then v_topic := null; end if;

  for r in select x->>'key' k, x->'to' t from jsonb_array_elements(coalesce(p_args->'relax', '[]'::jsonb)) x loop
    if r.k = 'budget' then v_relax_budget_set := true; v_relax_budget := case when jsonb_typeof(r.t) = 'number' then (r.t #>> '{}')::numeric end; end if;
    if r.k = 'location' and jsonb_typeof(r.t) = 'string' then v_cities := '{}'; v_states := array[r.t #>> '{}']; v_city_states := '{}'; end if;
    if r.k = 'location' and jsonb_typeof(r.t) = 'null' then v_cities := '{}'; v_states := '{}'; v_city_states := '{}'; end if;
  end loop;
  if v_relax_budget_set then v_budget := v_relax_budget; end if;
  -- the person's chosen relaxations first, then the chips for what is still applied (a removed chip is not returned), then the removals
  if cardinality(v_qcountries) > 0 and not 'country' = any(v_removed) then
    v_chips := v_chips || jsonb_build_object('key', 'country', 'label', (select string_agg(co.name, ' / ') from ref.countries co where co.iso_alpha2 = any(v_qcountries)), 'removable', true, 'kind', 'filter');
  end if;
  if (cardinality(v_cities) > 0 or cardinality(v_states) > 0) and not 'location' = any(v_removed) then
    v_loc_label := concat_ws(' / ', (select string_agg(initcap(c), ' / ') from unnest(v_cities) c), (select string_agg(s.name, ' / ') from ref.subdivisions s where s.code = any(v_states)));
    v_chips := v_chips || jsonb_build_object('key', 'location', 'label', v_loc_label, 'removable', true, 'kind', 'filter');
  end if;
  if v_level_label is not null and not 'level' = any(v_removed) then v_chips := v_chips || jsonb_build_object('key', 'level', 'label', v_level_label, 'removable', true, 'kind', 'filter'); end if;
  if v_budget is not null then
    v_cur_sym := case coalesce(v_budget_cur, case when v_qcountries = array['NZ'] or v_countries = array['NZ'] then 'NZD' when v_qcountries = array['CA'] or v_countries = array['CA'] then 'CAD' else 'AUD' end)
                   when 'NZD' then 'NZ$' when 'CAD' then 'C$' else 'A$' end;
    v_budget_cur := case v_cur_sym when 'NZ$' then 'NZD' when 'C$' then 'CAD' else 'AUD' end;
    if not 'budget' = any(v_removed) then v_chips := v_chips || jsonb_build_object('key', 'budget', 'label', 'Under ' || v_cur_sym || to_char(v_budget, 'FM999,999,999') || ' a year', 'removable', true, 'kind', 'filter'); end if;
  end if;
  if v_topic is not null and not 'topic' = any(v_removed) then v_chips := v_chips || jsonb_build_object('key', 'topic', 'label', initcap(v_topic), 'removable', true, 'kind', 'topic'); end if;

  if 'country' = any(v_removed) then v_qcountries := '{}'; end if;
  if 'location' = any(v_removed) then v_cities := '{}'; v_states := '{}'; v_city_states := '{}'; end if;
  if 'level' = any(v_removed) then v_levels := '{}'; end if;
  if 'budget' = any(v_removed) then v_budget := null; end if;
  if 'topic' = any(v_removed) then v_topic := null; end if;
  if cardinality(v_countries) > 0 then v_qcountries := case when cardinality(v_qcountries) > 0 then array(select unnest(v_qcountries) intersect select unnest(v_countries)) else v_countries end; end if;

  -- the typed topic's meaning vector: reuse a cached one, otherwise ask for it now and rank by words this time
  if v_topic is not null then
    v_key := 'portal:' || md5(v_model || '|' || v_topic);
    select c.embedding into v_vec from search.query_embedding_cache c where c.cache_key = v_key and c.model_name = v_model and c.expires_at > now();
    if v_vec is not null then
      update search.query_embedding_cache set hit_count = hit_count + 1, last_used_at = now() where cache_key = v_key;
      v_hybrid := true;
    elsif (select count(*) from search.query_embedding_cache c where c.cache_key like 'portal:%' and c.created_at >= v_today::timestamp at time zone 'Australia/Melbourne')
            < security.portal_search_num_v1('query_embed_daily_max', 5000) then
      perform pipeline.svc_pilot_submit_nonce('portal-search-embed', jsonb_build_object('mode', 'query', 'query_key', v_key, 'text', v_topic));
    end if;
    v_tsq := array_to_string(array(select w from unnest(string_to_array(v_topic, ' ')) w where length(w) >= 2), ' or ');
  end if;

  -- every course that passes the filters (topic never filters)
  create temp table if not exists portal_search_pass (course_id uuid primary key, fee numeric, fee_cur text, city_ok boolean, state_ok boolean, budget_ok boolean) on commit drop;
  truncate pg_temp.portal_search_pass;
  insert into pg_temp.portal_search_pass
  select d.course_id, d.provider_annual_tuition_amount, d.provider_annual_tuition_currency,
         cardinality(v_cities) = 0 or exists (select 1 from catalogue.course_campuses cc join catalogue.campuses ca on ca.id = cc.campus_id
                                               where cc.course_id = d.course_id and lower(trim(ca.city)) = any(v_cities))
                                    or (not exists (select 1 from catalogue.course_campuses cc where cc.course_id = d.course_id) and lower(trim(p.primary_city)) = any(v_cities)),
         cardinality(v_states) = 0 or d.subdivision_codes && v_states,
         v_budget is null or (d.provider_annual_tuition_amount is not null and d.provider_annual_tuition_currency = v_budget_cur and d.provider_annual_tuition_amount <= v_budget)
    from search.course_documents d
    join catalogue.courses c on c.id = d.course_id and c.lifecycle_status = 'active' and (v_scope <> 'published' or c.publication_status = 'published')
    join catalogue.providers p on p.id = d.provider_id
   where (cardinality(v_qcountries) = 0 or d.country_code = any(v_qcountries))
     and (cardinality(v_levels) = 0 or d.study_level_code = any(v_levels))
     and (v_provider is null or d.provider_id = v_provider)
     and (cardinality(v_city_states) = 0 or cardinality(v_cities) = 0 or d.subdivision_codes && v_city_states or not exists (select 1 from catalogue.course_campuses cc where cc.course_id = d.course_id));
  select count(*) into v_total from pg_temp.portal_search_pass where city_ok and state_ok and budget_ok;

  -- rank: the existing fusion function, then fill with the other passing courses by title
  create temp table if not exists portal_search_rank (course_id uuid primary key, pos integer, fts real, sim real) on commit drop;
  truncate pg_temp.portal_search_rank;
  insert into pg_temp.portal_search_rank
  select k.course_id, row_number() over (order by k.fused_score desc, k.course_id)::int, k.fts_rank, k.vector_similarity
    from search.course_candidates_v1(v_tsq, v_vec, v_model, 'portal-default', case when v_hybrid then 'hybrid' else 'keyword' end,
           nullif(v_qcountries, '{}'), nullif(case when cardinality(v_states) > 0 then v_states when cardinality(v_cities) > 0 then nullif(v_city_states, '{}') end, '{}'),
           nullif(v_levels, '{}'), null, null, null, null, null, 100) k  -- fixed: the fusion function's own largest page
   where k.course_id in (select course_id from pg_temp.portal_search_pass)
  on conflict do nothing;

  select array_agg(x.course_id order by x.ord, x.title) into v_ids from (
    select s.course_id, coalesce(rk.pos, 1000000) ord, coalesce(nullif(c.display_title, ''), c.canonical_title) title  -- fixed: unranked after ranked
      from pg_temp.portal_search_pass s join catalogue.courses c on c.id = s.course_id left join pg_temp.portal_search_rank rk on rk.course_id = s.course_id
     where s.city_ok and s.state_ok and s.budget_ok
     order by 2, 3 limit v_page) x;
  v_exact := catalogue.portal_course_cards_v1(coalesce(v_ids, '{}'), v_cities, v_simmin, null);

  -- fewer than the minimum: near misses and relaxations (never applied here)
  if v_total < v_min then
    if v_budget is not null then
      declare v_fees numeric[]; v_third numeric; v_to numeric; v_n integer; v_all integer;
      begin
        select array_agg(fee order by fee), count(*) into v_fees, v_all from pg_temp.portal_search_pass
         where city_ok and state_ok and fee is not null and fee_cur = v_budget_cur;
        if v_all > 0 then
          v_third := v_fees[least(3, v_all)];  -- fixed: the third-cheapest (or the dearest when fewer than three)
          v_to := ceil(v_third * (1 + v_head / 100) / v_round) * v_round;
          select count(*) into v_n from pg_temp.portal_search_pass where city_ok and state_ok and fee_cur = v_budget_cur and fee <= v_to;
          if v_to > v_budget and v_to <= v_budget * (1 + v_maxraise / 100) then
            v_relax := v_relax || jsonb_build_object('key', 'budget', 'to', v_to, 'label', 'Raise the budget to ' || v_cur_sym || to_char(v_to, 'FM999,999,999'), 'would_return', v_n,
              'note', 'The third-cheapest course matching everything else costs ' || v_cur_sym || to_char(v_third, 'FM999,999,999') || ' a year; ' || v_head || '% is added and the total rounded up to the nearest ' || v_cur_sym || to_char(v_round, 'FM999,999') || '.');
          end if;
        end if;
        select count(*) into v_n from pg_temp.portal_search_pass where city_ok and state_ok;
        v_relax := v_relax || jsonb_build_object('key', 'budget', 'to', null, 'label', 'Remove the budget', 'would_return', v_n, 'note', null);
        select coalesce(jsonb_agg(jsonb_build_object('misses', 'budget', 'miss_text', v_cur_sym || to_char(x.fee - v_budget, 'FM999,999,999') || ' over budget', 'course', x.card) order by x.fee), '[]'::jsonb)
          into v_near
          from (select s.fee, (catalogue.portal_course_cards_v1(array[s.course_id], v_cities, v_simmin, null))->0 card
                  from pg_temp.portal_search_pass s where s.city_ok and s.state_ok and s.fee_cur = v_budget_cur and s.fee > v_budget
                 order by s.fee limit v_page) x;
      end;
    end if;
    if cardinality(v_cities) > 0 and cardinality(v_city_states) > 0 then
      declare v_n integer;
      begin
        select count(*) into v_n from pg_temp.portal_search_pass s join search.course_documents d on d.course_id = s.course_id where s.budget_ok and d.subdivision_codes && v_city_states;
        v_relax := v_relax || jsonb_build_object('key', 'location', 'to', v_city_states[1],
          'label', 'Widen ' || initcap(v_cities[1]) || ' to ' || (select s.name from ref.subdivisions s where s.code = v_city_states[1]), 'would_return', v_n, 'note', null);
        v_near := v_near || coalesce((select jsonb_agg(jsonb_build_object('misses', 'location', 'miss_text', 'Outside ' || initcap(v_cities[1]), 'course', x.card))
          from (select (catalogue.portal_course_cards_v1(array[s.course_id], '{}', v_simmin, null))->0 card
                  from pg_temp.portal_search_pass s join search.course_documents d on d.course_id = s.course_id
                 where s.budget_ok and not s.city_ok and d.subdivision_codes && v_city_states limit v_page) x), '[]'::jsonb);
      end;
    end if;
  end if;

  return jsonb_build_object('understood', v_chips, 'exact', v_exact, 'near_misses', v_near,
                            'relaxations', v_relax, 'relaxation', case when jsonb_array_length(v_relax) > 0 then v_relax->0 end,
                            'total', v_total, 'ranking', case when v_hybrid then 'meaning' when v_topic is not null then 'words' else 'title' end);
end $function$;

-- Course cards in the contract's shape. A value not held is null, never a guess.
create or replace function catalogue.portal_course_cards_v1(p_ids uuid[], p_cities text[], p_simmin numeric, p_unused jsonb)
returns jsonb language plpgsql stable security definer set search_path = '' as $function$
begin
  return (select coalesce(jsonb_agg(jsonb_build_object(
      'course_id', c.id, 'title', coalesce(nullif(c.display_title, ''), c.canonical_title),
      'provider_id', p.id, 'provider_name', coalesce(nullif(p.display_name, ''), p.canonical_name),
      'level', sl.name, 'country_code', d.country_code,
      'state_code', coalesce(cam.state_code, ps.code), 'city', coalesce(cam.city, p.primary_city),
      'duration_value', c.duration_value, 'duration_unit', c.duration_unit,
      'fee', case when d.provider_annual_tuition_amount is not null then jsonb_build_object('per_year', d.provider_annual_tuition_amount, 'currency', d.provider_annual_tuition_currency,
               'year', (select (o->>'fee_year')::int from jsonb_array_elements(coalesce(d.provider_tuition_options, '[]'::jsonb)) o where o->>'basis' = 'annual' order by (o->>'fee_year') desc nulls last limit 1)) end,
      'next_intake', (select jsonb_build_object('label', i.intake_label, 'start_date', i.start_date) from catalogue.course_intakes i
                       where i.course_id = c.id and i.status = 'active' and (i.start_date is null or i.start_date >= (now() at time zone 'Australia/Melbourne')::date)  -- fixed: Melbourne day
                       order by i.start_date nulls last, i.id limit 1),
      'topic_match', coalesce(rk.fts > 0, false) or coalesce(rk.sim >= p_simmin, false),
      'topic_score', case when rk.sim is not null then round(rk.sim::numeric, 3) end,
      'why', to_jsonb(array_remove(array[
               case when rk.sim >= p_simmin then 'Topic match by meaning' end,
               case when rk.fts > 0 then 'Topic words in the course text' end,
               case when cam.city is not null and lower(cam.city) = any(p_cities) then 'Campus in ' || cam.city end], null)),
      'course_url', coalesce(d.official_course_url, c.course_url),
      'saved', exists (select 1 from portal.saved_courses sc where sc.course_id = c.id and sc.user_id = auth.uid()))
    order by x.ord), '[]'::jsonb)
  from unnest(p_ids) with ordinality x(id, ord)
  join catalogue.courses c on c.id = x.id
  join catalogue.providers p on p.id = c.provider_id
  left join search.course_documents d on d.course_id = c.id
  left join ref.study_levels sl on sl.id = c.study_level_id
  left join ref.subdivisions ps on ps.id = p.subdivision_id
  left join lateral (select ca.city, s.code state_code from catalogue.course_campuses cc join catalogue.campuses ca on ca.id = cc.campus_id left join ref.subdivisions s on s.id = ca.subdivision_id
                      where cc.course_id = c.id order by (lower(trim(ca.city)) = any(p_cities)) desc, cc.is_primary desc nulls last, ca.city limit 1) cam on true
  left join pg_temp.portal_search_rank rk on rk.course_id = c.id);
end $function$;

create or replace function public.portal_course_search_v1(p_args jsonb default '{}'::jsonb)
returns jsonb language plpgsql volatile security definer set search_path = '' as $function$
begin
  perform security.portal_rank_v1(1);  -- fixed: Viewer and above
  return catalogue.portal_course_search_v1(coalesce(p_args, '{}'::jsonb));
end $function$;

-- Who may call them.
revoke all on function public.portal_course_search_v1(jsonb) from public, anon;
grant execute on function public.portal_course_search_v1(jsonb) to authenticated;
revoke all on function catalogue.portal_course_search_v1(jsonb), catalogue.portal_course_cards_v1(uuid[], text[], numeric, jsonb),
                       security.portal_search_num_v1(text, numeric), security.portal_search_text_v1(text, text), security.portal_search_enqueue_v1(uuid[], integer),
                       security.portal_search_embed_fire_v1(), public.svc_portal_search_embed_next(integer), public.svc_portal_search_embed_record(jsonb)
  from public, anon, authenticated;
grant execute on function public.svc_portal_search_embed_next(integer), public.svc_portal_search_embed_record(jsonb) to service_role;

-- 6. A document refresh for active courses that have none yet (the embedding backfill itself is queued by the lane, 4b).
select search.course_refresh_request_v1(array(select c.id from catalogue.courses c where c.lifecycle_status = 'active'
                                               and not exists (select 1 from search.course_documents d where d.course_id = c.id)),
                                        'CF-247 s1153: portal search needs a document for every active course');

do $p$
declare v jsonb := security.consumer_api_check_v1();
begin
  if jsonb_array_length(coalesce(v->'drift', '[]'::jsonb)) <> 0 or (v->>'functions')::int <> 75 or (v->>'relations')::int <> 48 then
    raise exception 'post-check: the consumer API moved: %', v;
  end if;
  if (select count(*) from pipeline.manual_locks) <> (select n from s1153_locks) then raise exception 'post-check: manual locks changed'; end if;
  if (select count(*) from cron.job where active) <> (select n from s1153_cron) then raise exception 'post-check: the number of active cron jobs changed'; end if;
  if (select count(*) from pipeline.platform_toolset_settings where toolset_key = 'portal_search') <> 14 then raise exception 'post-check: the portal_search settings are not all present'; end if;
  if not exists (select 1 from search.profiles where code = 'portal-default' and status = 'active') then raise exception 'post-check: profile portal-default missing'; end if;
  if exists (select 1 from search.course_embeddings e join search.profiles p on p.id = e.profile_id where p.code in ('website-default', 'zoho-default')) then
    raise exception 'post-check: a website or Zoho profile holds vectors';
  end if;
  if not exists (select 1 from pipeline.field_execution_registry where lane_code = 'portal-search-embed' and kind = 'worker_lane') then raise exception 'post-check: lane missing'; end if;
end $p$;
