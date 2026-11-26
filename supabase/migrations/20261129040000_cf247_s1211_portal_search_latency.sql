-- CF-247 s1211 (S2-Build; Atlas brief 26 Nov 2026 09:30 AEDT: the Platform Admin found course search slow in UAT, most on first-time or broad
-- phrases). Version above main's 20261129020000 (S1-Build #1648).
-- Measured on live data (rolled back), each step timed inside catalogue.portal_course_search_v1, and from the API gateway log:
--   UAT 26 Nov 08:45 to 08:47 AEDT: 3.7 s, 1.1 s, 3.9 s, 0.55 s and 0.34 s (database time 3.1 s, 0.5 s, 3.8 s, 0.35 s, 0.12 s).
--   A first search on a new database session: 1.96 s and 3.26 s; the same search warm: 0.13 s to 0.46 s.
--   1.94 s of the cold search was the meaning step: the full-vector HNSW index (255 MB; shared memory is 1 GB and the pipeline's own work
--   pushes it out) read about 2,000 blocks from disk. The rest: listing the countries and levels that have documents read every document
--   (0.17 s and 0.19 s cold), the city filter folded every campus and provider city name (0.17 s to 0.44 s), and the filter step (0.12 s to
--   0.55 s) estimated the topic set blind.
--   A phrase not yet embedded never waits: its meaning vector is requested in the background (pg_net, about 1 s) and that search ranks by
--   words (a cold "marine archaeology courses in Perth" answered in 0.27 s). Only one typed phrase was cached, because a phrase's meaning was
--   kept for 24 hours.
-- Fix (the reply shape is unchanged; the Courses screen needs no change). Rehearsed against the s1181 search on live data, each phrase run
-- three times turn about: the same totals, chips and near misses on every phrase, and the same top 20 except up to three of "nursing"'s,
-- whose meaning positions sit at the cut-off. "Master of Nursing in Victoria" 0.16 to 0.18 s (s1181: 1.52 s cold, 0.16 s warm); city
-- searches 0.2 to 0.48 s (s1181: 0.38 to 1.05 s); broad one-word searches within the noise of the shared database; a first search on a
-- new session through public.portal_course_search_v1 0.27 s (s1181: 1.96 s).
--   1. A compact one-bit copy of each course's meaning vector is indexed (search.course_embeddings_bq_hnsw_idx, binary quantisation,
--      16 MB, so it stays in memory; built with ef_construction 32). The search takes its nearest portal_search.topic_vector_candidates (new setting, 300), scores them
--      exactly with their full vectors and keeps the nearest topic_vector_pool (100), as before. Against the full index on 7 phrases: the
--      same top 20 in every case, 92 to 100 of the top 100, cold 0.2 to 0.47 s instead of 0.31 to 1.9 s.
--   2. The countries and levels that have documents are read through their indexes (one probe a value).
--   3. A typed city's campuses and providers are found once (a cheap first look before each name is folded); their courses come from one
--      read of the campus index, and with a topic only the topic's courses are kept. Before, a city search read every course campus three
--      times (55,922 rows each) and every course (44,743).
--   4. The topic set is analysed once filled, so the city and filter steps read its courses by key, and a typed city name gets a substring
--      look before the pattern work on each campus name. Courses with the same title keep one order.
--   5. A typed phrase's meaning is kept for 30 days (portal_search.query_cache_hours 24 -> 720, its range's top), and each use renews it.
--   6. The Dashboard example searches are pre-warmed: they are a setting (portal_search.prewarm_phrases, the same text as the Dashboard's
--      EXAMPLE_PROMPTS, held to it by spec s1211), each is searched once here, so a phrase not yet cached is sent for its meaning vector
--      (about 20 tokens of openai/text-embedding-3-small, under US$0.000001, logged in pipeline.ai_invocations as every typed phrase is).
-- The live function is replaced only if its body is the s1181 text (md5 af093059e6e787bbf53b082ca08a4eab). Not the consumer API (G3 checked;
-- search.course_embeddings is the portal's own). G1: no job. G2: two settings with label, range, unit and used_by (topic_vector_candidates
-- read through security.portal_search_num_v1; prewarm_phrases read by this release); query_cache_hours changed with its reason. Locks untouched. Nothing dropped.
-- Replaces: the portal search's meaning step on the full-vector index (catalogue.portal_course_search_v1, s1181 body).
-- Retires: nothing (search.course_embeddings_hnsw_idx stays: search.course_candidates_v1's hybrid path reads it).
set local lock_timeout = '5s';  -- fixed: lock wait for the function replace and the index build
set local maintenance_work_mem = '256MB';  -- fixed: memory for the one-off index build (11 to 35 s)
set local max_parallel_maintenance_workers = 2;  -- fixed: workers for the one-off index build

create temp table s1211_guard on commit drop as
select (select count(*) from cron.job where active) as cron_before, (select count(*) from pipeline.manual_locks) as locks_before;

do $pre$
declare v jsonb := security.consumer_api_check_v1();
begin
  if (select md5(prosrc) from pg_proc where oid = 'catalogue.portal_course_search_v1(jsonb)'::regprocedure) <> 'af093059e6e787bbf53b082ca08a4eab' then
    raise exception 'pre-check: catalogue.portal_course_search_v1 is not the s1181 body this change was written against';
  end if;
  if (v->>'functions')::int <> 75 or (v->>'relations')::int <> 48 or jsonb_array_length(coalesce(v->'drift', '[]'::jsonb)) > 0 then
    raise exception 'pre-check: consumer API baseline is not 75/48 with no drift: %', v;
  end if;
end $pre$;

insert into pipeline.platform_toolset_settings (toolset_key, key, label, help, kind, value, min_value, max_value, unit, sort, section, used_by, reason)
values
 ('portal_search', 'topic_vector_candidates', 'Courses: meaning candidates scored exactly', 'How many of the nearest courses by the compact meaning index are scored exactly with their full meaning vectors (at least the courses checked by meaning). More finds slightly more; fewer is faster on a cold database.', 'number', '300'::jsonb, 100, 1000, 'courses', 6265, 'Portal search', 'catalogue.portal_course_search_v1', 'CF-247 s1211'),
 ('portal_search', 'prewarm_phrases', 'Courses: example searches kept warm', 'The Dashboard''s example searches. Each is searched once when this list is released, so its meaning is cached before a counsellor clicks it; a phrase in use stays cached.', 'list', '["Master of Data Science with internship in Sydney or Brisbane", "Bachelor of Nursing in Melbourne under $40,000 per year", "Diploma of Business starting February, IELTS 6.0", "MBA in Canada with scholarships"]'::jsonb, null, null, 'phrases', 6275, 'Portal search', 'migration 20261129040000 (pre-warm); portal Dashboard EXAMPLE_PROMPTS', 'CF-247 s1211')
on conflict do nothing;

update pipeline.platform_toolset_settings set value = to_jsonb(720), updated_at = now(),
       help = 'How long a typed query''s meaning vector is reused before it is worked out again; each use renews it.',
       reason = 'CF-247 s1211 (Atlas brief 26 Nov 2026 09:30 AEDT, search slow in UAT): a phrase is worked out the same way every time for the pinned model, and at 24 hours only one phrase was cached, so nearly every search ranked by words; was 24'
 where toolset_key = 'portal_search' and key = 'query_cache_hours';

create index if not exists course_embeddings_bq_hnsw_idx on search.course_embeddings
  using hnsw ((extensions.binary_quantize(embedding)::bit(1536)) extensions.bit_hamming_ops) with (m = 16, ef_construction = 32);  -- fixed: the vector column's dimensions; a lighter build (exact scoring follows)
comment on index search.course_embeddings_bq_hnsw_idx is 'CF-247 s1211: compact one-bit meaning index for the portal search (nearest candidates, then exact scoring with the full vectors).';

create or replace function catalogue.portal_course_search_v1(p_args jsonb default '{}'::jsonb)
returns jsonb language plpgsql volatile security definer set search_path = '' as $function$
declare
  v_q_raw text := left(coalesce(p_args->>'q', ''), least(greatest(security.portal_search_num_v1('query_max_chars', 200)::int, 20), 1000));  -- s1181: bounded; fixed: hard limits of the setting
  v_t text;
  v_removed text[] := array(select jsonb_array_elements_text(case when jsonb_typeof(p_args->'removed') = 'array' then p_args->'removed' else '[]'::jsonb end));  -- s1181: any other shape is ignored
  v_countries text[] := array(select distinct upper(trim(x)) from jsonb_array_elements_text(case when jsonb_typeof(p_args->'countries') = 'array' then p_args->'countries' else '[]'::jsonb end) x where trim(x) ~ '^[A-Za-z]{2}$');  -- s1181: two-letter codes only
  v_provider uuid := case when trim(coalesce(p_args->>'provider_id', '')) ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then trim(p_args->>'provider_id')::uuid end;  -- s1181: not a UUID means no provider filter
  v_page integer := security.portal_search_num_v1('result_page_size', 20)::int;
  v_min integer := security.portal_search_num_v1('relax_min_matches', 3)::int;
  v_head numeric := security.portal_search_num_v1('relax_budget_headroom_pct', 5);
  v_round numeric := security.portal_search_num_v1('relax_budget_round_to', 1000);
  v_maxraise numeric := security.portal_search_num_v1('relax_budget_max_raise_pct', 30);
  v_simmin numeric := security.portal_search_num_v1('topic_min_similarity', 0.35);
  v_model text := security.portal_search_text_v1('embedding_model', 'openai/text-embedding-3-small');
  v_scope text := security.portal_search_text_v1('visibility_scope', 'active');
  v_today date := (now() at time zone 'Australia/Melbourne')::date;  -- fixed: Melbourne calendar day
  v_qcountries text[] := '{}'; v_states text[] := '{}'; v_cities text[] := '{}'; v_city_states text[] := '{}'; v_levels text[] := '{}'; v_city_pcs text[] := '{}';
  v_share numeric := security.portal_search_num_v1('city_postcode_min_share', 0.5);
  v_level_label text; v_loc_label text; v_budget numeric; v_budget_cur text; v_budget_raw text; m text[]; r record;
  v_topic text; v_tsq text; v_words text[] := '{}'; v_need integer := 0; v_profile uuid := (select id from search.profiles where code = 'portal-default'); v_vec extensions.vector; v_key text; v_hybrid boolean := false;
  v_chips jsonb := '[]'::jsonb; v_exact jsonb; v_near jsonb := '[]'::jsonb; v_relax jsonb := '[]'::jsonb; v_total integer; v_ids uuid[];
  v_relax_budget numeric; v_relax_budget_set boolean := false; v_relax_loc text[];
  v_cur_sym text;
  v_pool integer := least(greatest(security.portal_search_num_v1('topic_vector_pool', 100)::int, 40), 1000);  -- s1181; fixed: the vector index search list bounds
  v_maxwords integer := least(greatest(security.portal_search_num_v1('topic_max_words', 8)::int, 1), 30);  -- s1181; fixed: hard limits of the setting
  -- s1211: the countries and levels that have documents are read through their indexes (one probe per value), not by reading every document
  v_doc_countries text[] := array(with recursive t(c) as (select min(d.country_code) from search.course_documents d
                                    union all select (select min(d.country_code) from search.course_documents d where d.country_code > t.c) from t where t.c is not null)
                                  select t.c from t where t.c is not null);
  v_doc_levels text[] := array(with recursive t(c) as (select min(d.study_level_code) from search.course_documents d
                                 union all select (select min(d.study_level_code) from search.course_documents d where d.study_level_code > t.c) from t where t.c is not null)
                               select t.c from t where t.c is not null);
  v_cand integer := least(greatest(security.portal_search_num_v1('topic_vector_candidates', 300)::int, least(greatest(security.portal_search_num_v1('topic_vector_pool', 100)::int, 40), 1000)), 1000);  -- s1211; fixed: the vector index search list bounds
  v_w text; v_like text[]; v_rrf_k double precision; v_fts_w double precision; v_vec_w double precision;
  v_city_campuses uuid[] := '{}'; v_city_providers uuid[] := '{}';  -- s1211
begin
  -- s1181: case, accents, smart quotes, tabs, line breaks, non-breaking or zero-width spaces and runs of spaces all read the same
  v_t := ' ' || trim(regexp_replace(regexp_replace(translate(lower(v_q_raw), 'àáâãäåāçćčèéêëēěìíîïīñńòóôõöøōùúûüūýÿžšř’‘`', 'aaaaaaaccceeeeeeiiiiinnooooooouuuuuyyzsr'''''''), '[^a-z0-9$.,'' -]+', ' ', 'g'), '\s+', ' ', 'g')) || ' ';

  -- budget: "under $40,000", "below 40k", "up to A$35,000", "max 40000"
  m := regexp_match(v_t, '(under|below|less than|max(imum)?|up to|within|at most|cheaper than|no more than)\s*(a\$|au\$|aud|nz\$|nzd|c\$|cad|\$)?\s*([0-9][0-9,]*(\.[0-9]+)?)\s*(k|thousand)?');
  if m is not null then
    v_budget := replace(m[4], ',', '')::numeric * case when m[6] is not null then 1000 else 1 end;  -- fixed: "k" means thousands
    v_budget_cur := case when m[3] in ('nz$', 'nzd') then 'NZD' when m[3] in ('c$', 'cad') then 'CAD' else null end;
    v_budget_raw := m[1];
    v_t := regexp_replace(v_t, '(under|below|less than|max(imum)?|up to|within|at most|cheaper than|no more than)\s*(a\$|au\$|aud|nz\$|nzd|c\$|cad|\$)?\s*([0-9][0-9,]*(\.[0-9]+)?)\s*(k|thousand)?', ' ');
  end if;
  v_t := regexp_replace(v_t, '\m(per year|a year|per annum|annually|each year|a yr|per yr|p\.a\.?|pa|tuition|fees?)(?![a-z])', ' ', 'g');
  -- s1181: after the budget is read, punctuation and hyphens become spaces, so place names match however they are typed
  v_t := ' ' || security.portal_fold_v1(v_t) || ' ';

  -- countries (live names of countries with active courses)
  for r in select distinct co.iso_alpha2 code, security.portal_fold_v1(co.name) nm from ref.countries co
            where co.iso_alpha2 = any(v_doc_countries) order by 2 loop  -- s1181: one read of the document countries
    if position(' ' || r.nm || ' ' in v_t) > 0 then v_qcountries := v_qcountries || r.code; v_t := replace(v_t, ' ' || r.nm || ' ', ' '); end if;
  end loop;

  -- states (live subdivision names, and AU short codes as whole words)
  for r in select s.code, security.portal_fold_v1(s.name) nm, lower(split_part(s.code, '-', 2)) short, co.iso_alpha2 cc
             from ref.subdivisions s join ref.countries co on co.id = s.country_id
            where co.iso_alpha2 = any(v_doc_countries)
              and (s.id in (select ca.subdivision_id from catalogue.campuses ca where ca.subdivision_id is not null)
                   or s.id in (select pr.subdivision_id from catalogue.providers pr where pr.subdivision_id is not null))  -- s1181: states with a campus or provider, not every document unpacked
            order by length(s.name) desc loop
    if position(' ' || r.nm || ' ' in v_t) > 0 then v_states := v_states || r.code; v_t := replace(v_t, ' ' || r.nm || ' ', ' ');
    elsif r.cc = 'AU' and position(' ' || r.short || ' ' in v_t) > 0 then v_states := v_states || r.code; v_t := replace(v_t, ' ' || r.short || ' ', ' ');
    end if;
  end loop;

  -- campus cities (live campus table), longest names first
  for r in select y.nm, y.sc from (
             select security.portal_fold_v1(z.city) nm, array_agg(distinct z.code) filter (where z.code is not null) sc
               from (select distinct trim(ca.city) city, s.code from catalogue.campuses ca left join ref.subdivisions s on s.id = ca.subdivision_id
                      where ca.city is not null and length(trim(ca.city)) >= 3 and coalesce(ca.status, 'active') = 'active'
                        -- s1181: a cheap first look: the name's first word is a word of the text, or the name has accents (folded below)
                        and (ca.city ~ '[^[:ascii:]]'
                             or (lower(ca.city) like any (array(select '%' || w || '%' from unnest(string_to_array(btrim(v_t), ' ')) w where w <> ''))  -- s1211: a substring look before the pattern work on each name
                                 and split_part(btrim(regexp_replace(lower(ca.city), '[^a-z0-9'']+', ' ', 'g')), ' ', 1) = any(string_to_array(btrim(v_t), ' '))))) z
              group by 1) y
            where y.nm <> '' and position(' ' || y.nm || ' ' in v_t) > 0 order by length(y.nm) desc loop  -- s1181: only the names that occur in the text; longest first
    if position(' ' || r.nm || ' ' in v_t) > 0 then
      v_cities := v_cities || r.nm; v_city_states := v_city_states || coalesce(r.sc, '{}'); v_t := replace(v_t, ' ' || r.nm || ' ', ' ');
      v_city_pcs := v_city_pcs || array(select a.postcode from destination.abs_postcode_sua_shares a
                                         where a.sua_name ilike '%' || replace(r.nm, ' ', '%') || '%'  -- s1181: cheap first look, then the exact folded name
                                           and (security.portal_fold_v1(a.sua_name) = r.nm or security.portal_fold_v1(split_part(a.sua_name, ' - ', 1)) = r.nm) and a.share >= v_share);
    end if;
  end loop;

  -- study level (grammar words mapped onto the live level codes)
  for r in select * from (values
      (1, '\m(graduate|grad)\s*(certificate|cert)\M', 'graduate_certificate', 'Graduate Certificate'),
      (2, '\m(graduate|grad)\s*(diploma|dip)\M', 'graduate_diploma', 'Graduate Diploma'),
      (3, '\m(advanced|adv)\s*(diploma|dip)\M', 'advanced_diploma', 'Advanced Diploma'),
      (4, '\m(associate|assoc)\s+degree\M', 'associate_degree', 'Associate Degree'),
      (5, '\m(phd|doctorate|doctoral|doctor of philosophy)\M', 'doctorate', 'Doctorate'),
      (6, '\m(masters?|master''s|mba|msc)\M', 'masters%', 'Master'),
      (7, '\m(bachelors?|bachelor''s|undergraduate)\M', 'bachelor%', 'Bachelor'),
      (8, '\mcertificate\s+(iv|4)\M', 'certificate_iv', 'Certificate IV'),
      (9, '\mcertificate\s+(iii|3)\M', 'certificate_iii', 'Certificate III'),
      (10, '\mdiploma\M', 'diploma', 'Diploma'),
      (11, '\mfoundation\M', 'foundation', 'Foundation')) v(n, pat, code, label) order by n loop
    if v_level_label is null and v_t ~ r.pat then
      v_levels := array(select l from unnest(v_doc_levels) l where l like r.code);  -- s1211: from the indexed list of levels
      v_level_label := r.label; v_t := regexp_replace(v_t, r.pat, ' ', 'g');
    end if;
  end loop;

  -- what is left is the topic (words only change the order)
  v_topic := trim(regexp_replace(regexp_replace(v_t, '\m(in|of|at|for|the|a|an|and|or|with|near|around|course|courses|degree|degrees|program|programme|programs|study|studying|studies|university|universities|uni|college|online|campus|international|students?|want|looking|find|me|my|i|to|on|from)\M', ' ', 'g'), '[^a-z0-9'' ]+|\s+', ' ', 'g'));
  v_topic := trim(regexp_replace(regexp_replace(' ' || v_topic || ' ', '\s''+|''+\s', ' ', 'g'), '\s+', ' ', 'g'));  -- s1181: no apostrophe at a word edge
  -- s1181: each topic word once, in typed order, at most topic_max_words (the label, the words and the meaning text all use this)
  v_topic := (select string_agg(z.w, ' ' order by z.n) from (select u.w, min(u.n) n from unnest(string_to_array(v_topic, ' ')) with ordinality u(w, n) where u.w <> '' group by u.w order by 2 limit v_maxwords) z);
  if coalesce(v_topic, '') = '' then v_topic := null; end if;

  for r in select x->>'key' k, x->'to' t from jsonb_array_elements(case when jsonb_typeof(p_args->'relax') = 'array' then p_args->'relax' else '[]'::jsonb end) x
            where jsonb_typeof(x) = 'object' loop  -- s1181: any other shape is ignored
    if r.k = 'budget' then v_relax_budget_set := true; v_relax_budget := case when jsonb_typeof(r.t) = 'number' then (r.t #>> '{}')::numeric end; end if;
    if r.k = 'location' and jsonb_typeof(r.t) = 'string' then v_cities := '{}'; v_states := array[r.t #>> '{}']; v_city_states := '{}'; v_city_pcs := '{}'; end if;
    if r.k = 'location' and jsonb_typeof(r.t) = 'null' then v_cities := '{}'; v_states := '{}'; v_city_states := '{}'; v_city_pcs := '{}'; end if;
  end loop;
  if v_relax_budget_set then v_budget := v_relax_budget; end if;
  -- s1181: a search with nothing to go on (empty, only spaces, only small words or symbols) and no Study in or provider choice answers at once
  if v_topic is null and v_level_label is null and v_budget is null and cardinality(v_qcountries) = 0 and cardinality(v_states) = 0
     and cardinality(v_cities) = 0 and cardinality(v_countries) = 0 and v_provider is null then
    return jsonb_build_object('understood', '[]'::jsonb, 'exact', '[]'::jsonb, 'near_misses', '[]'::jsonb, 'relaxations', '[]'::jsonb, 'relaxation', null, 'total', 0, 'ranking', 'title');
  end if;

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
  if 'location' = any(v_removed) then v_cities := '{}'; v_states := '{}'; v_city_states := '{}'; v_city_pcs := '{}'; end if;
  if 'level' = any(v_removed) then v_levels := '{}'; end if;
  if 'budget' = any(v_removed) then v_budget := null; end if;
  if 'topic' = any(v_removed) then v_topic := null; end if;
  if cardinality(v_countries) > 0 then
    v_qcountries := case when cardinality(v_qcountries) > 0 then array(select unnest(v_qcountries) intersect select unnest(v_countries)) else v_countries end;
    if cardinality(v_qcountries) = 0 then v_qcountries := array['--']; end if;  -- s1181: a typed country outside Study in matches nothing (it was read as every country); fixed: a code no country has
  end if;

  -- the typed topic's meaning vector: reuse a cached one, otherwise ask for it now and rank by words this time
  if v_topic is not null then
    v_key := 'portal:' || md5(v_model || '|' || v_topic);
    select c.embedding into v_vec from search.query_embedding_cache c where c.cache_key = v_key and c.model_name = v_model and c.expires_at > now();
    if v_vec is not null then
      update search.query_embedding_cache set hit_count = hit_count + 1, last_used_at = now(),
             expires_at = greatest(expires_at, now() + make_interval(hours => security.portal_search_num_v1('query_cache_hours', 720)::int))  -- s1211: a phrase in use stays cached
       where cache_key = v_key;
      v_hybrid := true;
    elsif (select count(*) from search.query_embedding_cache c where c.cache_key like 'portal:%' and c.created_at >= v_today::timestamp at time zone 'Australia/Melbourne')
            < security.portal_search_num_v1('query_embed_daily_max', 5000) then
      perform pipeline.svc_pilot_submit_nonce('coverage-sweep', jsonb_build_object('mode', 'portal_search_embed', 'query_key', v_key, 'text', v_topic));
    end if;
    v_words := array(select w from (select w, min(n) n from unnest(string_to_array(v_topic, ' ')) with ordinality u(w, n) where length(w) >= 2 and plainto_tsquery('english', w)::text <> '' group by w) z order by n limit v_maxwords);  -- s1181: each word once, at most topic_max_words
    v_need := ceil(cardinality(v_words) / 2.0)::int;  -- fixed: at least half the topic words
    v_tsq := array_to_string(v_words, ' or ');
  end if;

  -- s1181: the topic is matched once per word through the text index and once by meaning through the vector index; the filters and the
  -- ranking reuse both. The ranking is the shared ranker's own fusion (reciprocal rank, k and weights from the portal-default profile),
  -- worked out over the matching courses (the words position counts the topic words a course matches, plus one for a title match), so the
  -- vector index is searched once per search and no course text or vector is read row by row.
  create temp table if not exists portal_search_words (course_id uuid primary key, hits integer) on commit drop;
  truncate pg_temp.portal_search_words;
  if v_topic is not null and cardinality(v_words) > 0 then
    foreach v_w in array v_words loop
      insert into pg_temp.portal_search_words (course_id, hits)
      select d.course_id, 1 from search.course_documents d where d.search_tsv @@ plainto_tsquery('english', v_w)
      on conflict (course_id) do update set hits = pg_temp.portal_search_words.hits + 1;
    end loop;
  end if;

  create temp table if not exists portal_search_vec (course_id uuid primary key, sim real, vpos integer) on commit drop;
  truncate pg_temp.portal_search_vec;
  -- s1211: the nearest courses by meaning come from the compact one-bit index (search.course_embeddings_bq_hnsw_idx, 16 MB, so it stays in
  -- memory), topic_vector_candidates of them; their full vectors then give the exact similarity and the nearest topic_vector_pool are kept.
  -- The full-vector index (255 MB) was read from disk on most searches (about 2,000 blocks, 1.9 s).
  if v_vec is not null then
    perform set_config('hnsw.ef_search', v_cand::text, true);
    perform set_config('hnsw.iterative_scan', 'relaxed_order', true);
    insert into pg_temp.portal_search_vec
    select x.course_id, (1 - x.dist)::real, row_number() over (order by x.dist, x.course_id)::int
      from (select e.course_id, e.content_hash, e.embedding operator(extensions.<=>) v_vec dist
              from (select b.course_id from search.course_embeddings b
                     where b.profile_id = v_profile and b.model_name = v_model
                     order by (extensions.binary_quantize(b.embedding)::bit(1536)) operator(extensions.<~>) extensions.binary_quantize(v_vec) limit v_cand) k  -- fixed: the vector column's dimensions
              join search.course_embeddings e on e.course_id = k.course_id and e.profile_id = v_profile and e.model_name = v_model
             order by 3 limit v_pool) x
      join search.course_documents d on d.course_id = x.course_id and d.semantic_content_hash = x.content_hash
    on conflict do nothing;
  end if;

  -- the courses that match the topic (at least half its words, or close enough in meaning): every later step reads only these
  create temp table if not exists portal_search_topic (course_id uuid primary key) on commit drop;
  truncate pg_temp.portal_search_topic;
  if v_topic is not null and cardinality(v_words) > 0 then
    insert into pg_temp.portal_search_topic select w.course_id from pg_temp.portal_search_words w where w.hits >= v_need on conflict do nothing;
    insert into pg_temp.portal_search_topic select v.course_id from pg_temp.portal_search_vec v where v.sim >= v_simmin on conflict do nothing;
    analyze pg_temp.portal_search_topic;  -- s1211: the filter step then reads only these courses through the document key
  end if;

  create temp table if not exists portal_search_city (course_id uuid primary key) on commit drop;
  truncate pg_temp.portal_search_city;
  if cardinality(v_cities) > 0 then
    -- s1211: the campuses and providers in the typed city are found once (a cheap first look before each name is folded); their courses
    -- come from one read of the campus index, and with a topic only the topic's courses are kept (the provider check read all 44,743
    -- courses and every course campus, three times a search).
    v_city_campuses := array(select ca.id from catalogue.campuses ca
                              where ca.postcode in (select unnest(v_city_pcs))  -- s1181: postcodes as a set
                                 or ((ca.city ~ '[^[:ascii:]]|`' or exists (select 1 from unnest(v_cities) vc where lower(ca.city) like '%' || replace(vc, ' ', '%') || '%'))
                                     and security.portal_fold_v1(ca.city) = any(v_cities)));
    v_city_providers := array(select p.id from catalogue.providers p
                               where p.postcode in (select unnest(v_city_pcs))
                                  or ((p.primary_city ~ '[^[:ascii:]]|`' or exists (select 1 from unnest(v_cities) vc where lower(p.primary_city) like '%' || replace(vc, ' ', '%') || '%'))
                                      and security.portal_fold_v1(p.primary_city) = any(v_cities)));
    insert into pg_temp.portal_search_city
    select distinct cc.course_id from catalogue.course_campuses cc
     where cc.campus_id = any(v_city_campuses)  -- one read of the campus index
       and (v_topic is null or cardinality(v_words) = 0 or cc.course_id in (select t.course_id from pg_temp.portal_search_topic t))
    on conflict do nothing;
    if v_topic is not null and cardinality(v_words) > 0 then
      insert into pg_temp.portal_search_city
      select t.course_id from pg_temp.portal_search_topic t join catalogue.courses c on c.id = t.course_id
       where c.provider_id = any(v_city_providers)
         and (select true from catalogue.course_campuses cc where cc.course_id = t.course_id limit 1) is null  -- fixed: one is enough
      on conflict do nothing;
    else
      insert into pg_temp.portal_search_city
      select c.id from catalogue.courses c
       where c.provider_id = any(v_city_providers) and not exists (select 1 from catalogue.course_campuses cc where cc.course_id = c.id)
      on conflict do nothing;
    end if;
  end if;

  -- every course that passes the hard filters, with whether it matches the topic (at least half its words, or by meaning)
  create temp table if not exists portal_search_pass (course_id uuid primary key, fee numeric, fee_cur text, city_ok boolean, state_ok boolean, budget_ok boolean, topic_ok boolean) on commit drop;
  truncate pg_temp.portal_search_pass;
  insert into pg_temp.portal_search_pass
  select d.course_id, d.provider_annual_tuition_amount, d.provider_annual_tuition_currency,
         cardinality(v_cities) = 0 or ci.course_id is not null,
         cardinality(v_states) = 0 or d.subdivision_codes && v_states,
         v_budget is null or (d.provider_annual_tuition_amount is not null and d.provider_annual_tuition_currency = v_budget_cur and d.provider_annual_tuition_amount <= v_budget),
         true  -- s1181: only topic-matching courses are kept (every later step needs the topic), so topic_ok is true for each row
    from search.course_documents d
    join catalogue.courses c on c.id = d.course_id and c.lifecycle_status = 'active' and (v_scope <> 'published' or c.publication_status = 'published')
    left join pg_temp.portal_search_city ci on ci.course_id = d.course_id
   where (v_topic is null or cardinality(v_words) = 0 or d.course_id in (select t.course_id from pg_temp.portal_search_topic t))
     and (cardinality(v_qcountries) = 0 or d.country_code = any(v_qcountries))
     and (cardinality(v_levels) = 0 or d.study_level_code = any(v_levels))
     and (v_provider is null or d.provider_id = v_provider)
     and (cardinality(v_city_states) = 0 or cardinality(v_cities) = 0 or d.subdivision_codes && v_city_states
          or (select true from catalogue.course_campuses cc where cc.course_id = d.course_id limit 1) is null);  -- s1211: by the course's key; fixed: one is enough
  select count(*) into v_total from pg_temp.portal_search_pass where city_ok and state_ok and budget_ok and topic_ok;

  -- rank the courses that match the topic: words position and meaning position fused as the shared ranker does; the rest by title
  create temp table if not exists portal_search_rank (course_id uuid primary key, pos integer, fts real, sim real) on commit drop;
  truncate pg_temp.portal_search_rank;
  if v_topic is not null then
    select coalesce((pr.config->>'rrf_k')::double precision, 60), coalesce((pr.config->>'fts_weight')::double precision, 1.0),
           coalesce((pr.config->>'vector_weight')::double precision, 0.55)  -- fixed: the shared ranker's own defaults
      into v_rrf_k, v_fts_w, v_vec_w from search.profiles pr where pr.id = v_profile;
    v_like := array(select '%' || replace(replace(w, '%', ''), '_', '') || '%' from unnest(v_words) w);
    insert into pg_temp.portal_search_rank
    select z.course_id, row_number() over (order by z.score desc, z.fts desc nulls last, z.sim desc nulls last, z.course_id)::int, z.fts, z.sim
      from (select f.course_id, f.fts, f.sim,
                   case when f.fts > 0 then coalesce(v_fts_w, 1.0) / (coalesce(v_rrf_k, 60) + f.fpos) else 0 end
                   + case when f.vpos is not null then coalesce(v_vec_w, 0.55) / (coalesce(v_rrf_k, 60) + f.vpos) else 0 end score  -- fixed: the shared ranker's own defaults
              from (select t.course_id, t.fts, t.sim, t.vpos, row_number() over (order by t.fts desc nulls last, t.course_id) fpos
                      from (select s.course_id, v.sim, v.vpos,
                                   case when w.course_id is not null then (w.hits + case when lower(coalesce(d.course_title, '')) like any (v_like) then 1 else 0 end)::real end fts  -- s1181: words matched, plus one when the title holds a topic word; no course text is unpacked
                              from pg_temp.portal_search_pass s
                              join search.course_documents d on d.course_id = s.course_id
                              left join pg_temp.portal_search_words w on w.course_id = s.course_id
                              left join pg_temp.portal_search_vec v on v.course_id = s.course_id
                             where s.topic_ok) t) f) z;
  end if;

  select array_agg(x.course_id order by x.ord, x.title, x.course_id) into v_ids from (
    select s.course_id, coalesce(rk.pos, 1000000) ord, coalesce(nullif(c.display_title, ''), c.canonical_title) title  -- fixed: unranked after ranked
      from pg_temp.portal_search_pass s join catalogue.courses c on c.id = s.course_id left join pg_temp.portal_search_rank rk on rk.course_id = s.course_id
     where s.city_ok and s.state_ok and s.budget_ok and s.topic_ok
     order by 2, 3, 1 limit v_page) x;  -- s1211: courses with the same title keep one order
  v_exact := catalogue.portal_course_cards_v1(coalesce(v_ids, '{}'), v_cities, v_simmin, jsonb_build_object('postcodes', to_jsonb(v_city_pcs)));

  -- fewer than the minimum: near misses and relaxations (never applied here)
  if v_total < v_min then
    if v_budget is not null then
      declare v_fees numeric[]; v_third numeric; v_to numeric; v_n integer; v_all integer;
      begin
        select array_agg(fee order by fee), count(*) into v_fees, v_all from pg_temp.portal_search_pass
         where city_ok and state_ok and topic_ok and fee is not null and fee_cur = v_budget_cur;
        if v_all > 0 then
          v_third := v_fees[least(3, v_all)];  -- fixed: the third-cheapest (or the dearest when fewer than three)
          v_to := ceil(v_third * (1 + v_head / 100) / v_round) * v_round;
          select count(*) into v_n from pg_temp.portal_search_pass where city_ok and state_ok and topic_ok and fee_cur = v_budget_cur and fee <= v_to;
          if v_to > v_budget and v_to <= v_budget * (1 + v_maxraise / 100) then
            v_relax := v_relax || jsonb_build_object('key', 'budget', 'to', v_to, 'label', 'Raise the budget to ' || v_cur_sym || to_char(v_to, 'FM999,999,999'), 'would_return', v_n,
              'note', 'The third-cheapest course matching everything else costs ' || v_cur_sym || to_char(v_third, 'FM999,999,999') || ' a year; ' || v_head || '% is added and the total rounded up to the nearest ' || v_cur_sym || to_char(v_round, 'FM999,999') || '.');
          end if;
        end if;
        select count(*) into v_n from pg_temp.portal_search_pass where city_ok and state_ok and topic_ok;
        v_relax := v_relax || jsonb_build_object('key', 'budget', 'to', null, 'label', 'Remove the budget', 'would_return', v_n, 'note', null);
        select coalesce(jsonb_agg(jsonb_build_object('misses', 'budget', 'miss_text', v_cur_sym || to_char(x.fee - v_budget, 'FM999,999,999') || ' over budget', 'course', x.card) order by x.fee), '[]'::jsonb)
          into v_near
          from (select s.fee, (catalogue.portal_course_cards_v1(array[s.course_id], v_cities, v_simmin, jsonb_build_object('postcodes', to_jsonb(v_city_pcs))))->0 card
                  from pg_temp.portal_search_pass s where s.city_ok and s.state_ok and s.topic_ok and s.fee_cur = v_budget_cur and s.fee > v_budget
                 order by s.fee limit v_page) x;
      end;
    end if;
    if cardinality(v_cities) > 0 and cardinality(v_city_states) > 0 then
      declare v_n integer;
      begin
        select count(*) into v_n from pg_temp.portal_search_pass s join search.course_documents d on d.course_id = s.course_id where s.budget_ok and s.topic_ok and d.subdivision_codes && v_city_states;
        v_relax := v_relax || jsonb_build_object('key', 'location', 'to', v_city_states[1],
          'label', 'Widen ' || initcap(v_cities[1]) || ' to ' || (select s.name from ref.subdivisions s where s.code = v_city_states[1]), 'would_return', v_n, 'note', null);
        v_near := v_near || coalesce((select jsonb_agg(jsonb_build_object('misses', 'location', 'miss_text', 'Outside ' || initcap(v_cities[1]), 'course', x.card))
          from (select (catalogue.portal_course_cards_v1(array[s.course_id], '{}', v_simmin, null))->0 card
                  from pg_temp.portal_search_pass s join search.course_documents d on d.course_id = s.course_id
                 where s.budget_ok and s.topic_ok and not s.city_ok and d.subdivision_codes && v_city_states limit v_page) x), '[]'::jsonb);
      end;
    end if;
  end if;

  return jsonb_build_object('understood', v_chips, 'exact', v_exact, 'near_misses', v_near,
                            'relaxations', v_relax, 'relaxation', case when jsonb_array_length(v_relax) > 0 then v_relax->0 end,
                            'total', v_total, 'ranking', case when v_hybrid then 'meaning' when v_topic is not null then 'words' else 'title' end);
end $function$;

-- pre-warm: each example search once, so a phrase not yet cached is sent for its meaning vector when this change commits
create temp table s1211_prewarm (phrase text, ranking text, total integer) on commit drop;
do $warm$
declare p text; x jsonb;
begin
  for p in select jsonb_array_elements_text(value) from pipeline.platform_toolset_settings where toolset_key = 'portal_search' and key = 'prewarm_phrases' loop
    x := catalogue.portal_course_search_v1(jsonb_build_object('q', p));
    insert into pg_temp.s1211_prewarm values (p, x->>'ranking', (x->>'total')::int);
  end loop;
end $warm$;

do $post$
declare v jsonb := security.consumer_api_check_v1(); x jsonb; q text; v_vec text; v_plan text;
begin
  if (v->>'functions')::int <> 75 or (v->>'relations')::int <> 48 or jsonb_array_length(coalesce(v->'drift', '[]'::jsonb)) > 0 then
    raise exception 'post-check: consumer API baseline changed: %', v;
  end if;
  if (select count(*) from cron.job where active) <> (select cron_before from s1211_guard) then raise exception 'post-check: the number of active cron jobs changed'; end if;
  if (select count(*) from pipeline.manual_locks) <> (select locks_before from s1211_guard) then raise exception 'post-check: manual locks changed'; end if;
  if (select count(*) from pipeline.platform_toolset_settings where toolset_key = 'portal_search' and key in ('topic_vector_candidates', 'prewarm_phrases')) <> 2
     or security.portal_search_num_v1('query_cache_hours', 0) <> 720 then
    raise exception 'post-check: the s1211 settings are not as released';
  end if;
  if not exists (select 1 from pg_index i join pg_class c on c.oid = i.indexrelid where c.relname = 'course_embeddings_bq_hnsw_idx' and i.indisvalid) then
    raise exception 'post-check: the compact meaning index is not valid';
  end if;
  -- the meaning step's candidate read uses the compact index
  select e.embedding::text into v_vec from search.course_embeddings e limit 1;
  execute format('explain (format json) select b.course_id from search.course_embeddings b order by (extensions.binary_quantize(b.embedding)::bit(1536)) operator(extensions.<~>) extensions.binary_quantize(%L::extensions.vector) limit 300', v_vec) into v_plan;
  if v_plan not like '%course_embeddings_bq_hnsw_idx%' then raise exception 'post-check: the candidate read does not use the compact index: %', left(v_plan, 300); end if;
  if (select count(*) from pg_temp.s1211_prewarm) <> (select jsonb_array_length(value) from pipeline.platform_toolset_settings where toolset_key = 'portal_search' and key = 'prewarm_phrases') then
    raise exception 'post-check: not every example search was pre-warmed';
  end if;
  -- the same request in messy spellings reads the same (topic removed, so no phrase is sent for embedding)
  foreach q in array array['Master of Nursing in New South Wales', E'  MASTER   of\tnursing in new  south  wales  ', 'master''s of nursing, New-South-Wales.'] loop
    x := catalogue.portal_course_search_v1(jsonb_build_object('q', q, 'countries', 'AU', 'removed', jsonb_build_array('topic'), 'relax', '{}'::jsonb, 'provider_id', 'not-a-uuid'));
    if not (x->'understood') @> '[{"key": "location", "label": "New South Wales"}]' or not (x->'understood') @> '[{"key": "level", "label": "Master"}]' then
      raise exception 'post-check: "%" was understood as %', q, x->'understood';
    end if;
  end loop;
  -- a typed city still filters by campus and suburb postcodes (topic removed)
  x := catalogue.portal_course_search_v1(jsonb_build_object('q', 'Bachelor of Nursing in Melbourne', 'countries', jsonb_build_array('AU'), 'removed', jsonb_build_array('topic')));
  if not (x->'understood') @> '[{"key": "location"}]' or coalesce((x->>'total')::int, 0) = 0 then
    raise exception 'post-check: a typed city found no courses: %', left(x::text, 300);
  end if;
end $post$;
