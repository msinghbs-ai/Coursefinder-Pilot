-- CF-247 Track C Step B, B2/B3: additive entry keys on the EXISTING course and provider payloads, and edu_country.
-- Consumer API change approved: Platform Admin, 25 Oct 2026 14:36 and 14:50 (decision 7: "additive fields on the EXISTING course and provider payloads; no separate function. The mandate is the explicit frozen-API approval"); shape and edu_country per admin docs/platform/ENTRY-REQUIREMENTS-STEP-B-DECISION-2026-10-28.md section 7 (mandate 28 Oct 2026 20:36); applied by the Platform Admin through the paste-reviewed consumer-change process (paste docs/platform/pastes/PASTE-20261028-entry-consumer-api.sql), never auto-merged
-- Record: admin docs/platform/ENTRY-REQUIREMENTS-STEP-B-DECISION-2026-10-28.md (sections 5 and 7), ENTRY-REQUIREMENTS-IMPLEMENTATION.md 2.4, decision 10.
--
-- 1. public.website_v2_course(text): item gains `entry` {min_score, min_score_basis, benchmark_band, prerequisites[], selection_tasks[],
--    requirements_note, resolution}; resolution null without a country. Every existing key is unchanged (md5-guarded edit adds one key).
-- 2. public.website_v2_provider(text): item gains `entry_matrix` [{country, study_level, qualification, min_grade, scale, band, course_code?,
--    conditions, as_at}], active rows only; a row without a minimum has min_grade null and scale 'none' (case by case, decision 10).
-- 3. edu_country: public.website_v2_course(text, text) and public.website_v2_provider(text, text) return the same payload with the
--    resolution for that country (course) or the matrix narrowed to it (provider). The website-api-v2 edge function passes edu_country.
-- 4. The consumer baseline is re-taken (security.consumer_api_rebaseline_v1) and tests/uat/consumer-api-baseline.json updated.
-- Replaces: nothing
-- Retires: nothing
-- Nothing dropped, deleted, renamed or retyped.

create or replace function pg_temp.edit_n(p_sig text, p_md5 text, p_edits text[][], p_times int[]) returns void language plpgsql as $f$
declare v_def text := pg_get_functiondef(p_sig::regprocedure); i int; v_c int;
begin
  if md5(v_def) <> p_md5 then raise exception 'live % differs from the definition this change edits (md5 %)', p_sig, md5(v_def); end if;
  for i in 1 .. array_length(p_edits, 1) loop
    v_c := (length(v_def) - length(replace(v_def, p_edits[i][1], ''))) / length(p_edits[i][1]);
    if v_c <> p_times[i] then raise exception '%: edit % must apply exactly % times (found %)', p_sig, i, p_times[i], v_c; end if;
    v_def := replace(v_def, p_edits[i][1], p_edits[i][2]);
  end loop;
  execute v_def;
end $f$;

-- ---------------------------------------------------------------- the payload parts (internal; read only)
create or replace function security.entry_course_payload_v1(p_course uuid, p_country text) returns jsonb
language sql stable security definer set search_path to '' as $$
  with r as (select * from catalogue.course_entry_requirements x where x.course_id = p_course and x.status = 'active'),
  s as (select r.min_entry_score, r.min_entry_score_basis from r where r.kind = 'minimum_grade' and r.min_entry_score is not null
         order by (r.audience = 'international') desc, r.updated_at desc limit 1)
  select jsonb_build_object(
    'min_score', (select s.min_entry_score from s),
    'min_score_basis', (select s.min_entry_score_basis from s),
    'benchmark_band', (select r.benchmark_band from r where r.benchmark_band is not null and r.audience in ('international', 'all') order by r.updated_at desc limit 1),
    'prerequisites', coalesce((select jsonb_agg(jsonb_build_object('text', r.description, 'quote', r.quote) order by r.created_at) from r where r.kind = 'subject_prerequisite'), '[]'::jsonb),
    'selection_tasks', coalesce((select jsonb_agg(jsonb_build_object('text', r.description, 'quote', r.quote) order by r.created_at) from r where r.kind = 'portfolio_interview'), '[]'::jsonb),
    'requirements_note', (select string_agg(r.description, ' · ' order by r.created_at) from r where r.kind in ('override', 'general_note', 'prior_qualification', 'work_experience')),
    'resolution', case when p_country is null then null else security.entry_resolve_v1(p_course, p_country) end)
$$;
revoke all on function security.entry_course_payload_v1(uuid, text) from public, anon, authenticated;
comment on function security.entry_course_payload_v1(uuid, text) is 'CF-247 Track C Step B (B2): the course payload''s entry object from active course rows, with the five-rule resolution for a country.';

create or replace function security.entry_matrix_payload_v1(p_provider uuid, p_country text) returns jsonb
language sql stable security definer set search_path to '' as $$
  select coalesce(jsonb_agg(jsonb_strip_nulls(jsonb_build_object('course_code', k.course_code)) || jsonb_build_object(
           'country', m.country_code, 'study_level', m.level_label, 'qualification', m.qualification_name, 'min_grade', m.min_grade,
           'scale', case when m.min_grade is null then 'none' else m.grade_scale end, 'band', m.benchmark_band, 'conditions', m.conditions, 'as_at', m.as_at)
           order by m.country_code, m.level_label, m.benchmark_band, m.qualification_name), '[]'::jsonb)
    from catalogue.provider_entry_matrix m left join catalogue.courses k on k.id = m.course_id
   where m.provider_id = p_provider and m.status = 'active' and (p_country is null or m.country_code = upper(p_country))
$$;
revoke all on function security.entry_matrix_payload_v1(uuid, text) from public, anon, authenticated;
comment on function security.entry_matrix_payload_v1(uuid, text) is 'CF-247 Track C Step B (B2): the provider payload''s entry_matrix from active matrix rows, optionally one country.';

-- ---------------------------------------------------------------- 1, 2: one key each on the existing payloads (md5-guarded)
select pg_temp.edit_n('public.website_v2_course(text)', 'ad9ba3889ac6a1a7ed0b68ef08c8b507', array[
  array[$o$    'other_matches', greatest(v_matches - 1, 0));$o$,
        $n$    'other_matches', greatest(v_matches - 1, 0),
    'entry', security.entry_course_payload_v1(v_id, null));  -- CF-247 Track C Step B (B2): additive$n$]], array[1]);

select pg_temp.edit_n('public.website_v2_provider(text)', '2411c7e4c30b0a04fcc9d159764327da', array[
  array[$o$    'rankings', public.website_v2_provider_rankings(v_pid),$o$,
        $n$    'rankings', public.website_v2_provider_rankings(v_pid),
    'entry_matrix', security.entry_matrix_payload_v1(v_pid, null),  -- CF-247 Track C Step B (B2): additive$n$]], array[1]);

-- ---------------------------------------------------------------- 3: edu_country (same payloads, one more argument)
create or replace function public.website_v2_course(p_identifier text, p_edu_country text) returns jsonb
language plpgsql stable security definer set search_path to '' as $$
declare v jsonb; v_id uuid; v_cc text := upper(btrim(coalesce(p_edu_country, '')));
begin
  if v_cc !~ '^[A-Z]{2}$' or not exists (select 1 from ref.countries k where k.iso_alpha2 = v_cc) then
    raise exception 'INVALID_INPUT: edu_country must be a known ISO 3166 alpha-2 country code' using errcode = '22023';
  end if;
  v := public.website_v2_course(p_identifier);
  if v ? 'error' then return v; end if;
  -- the same course the one-argument form chose (same match and order)
  select d.course_id into v_id from search.course_documents d
   where lower(d.course_stable_key) = lower(btrim(p_identifier)) or lower(d.course_code) = lower(btrim(p_identifier))
      or d.course_id in (select i.course_id from catalogue.course_identifiers i where i.scheme = 'studysearch' and upper(i.identifier) = upper(btrim(p_identifier)))
   order by (lower(d.course_stable_key) = lower(btrim(p_identifier))) desc, d.course_stable_key limit 1;
  return jsonb_set(v, '{item,entry}', security.entry_course_payload_v1(v_id, v_cc));
end $$;
revoke all on function public.website_v2_course(text, text) from public, anon, authenticated;
grant execute on function public.website_v2_course(text, text) to service_role;
comment on function public.website_v2_course(text, text) is 'CF-247 Track C Step B (B3): the course payload with entry.resolution for the student''s country of prior education (edu_country).';

create or replace function public.website_v2_provider(p_provider_id text, p_edu_country text) returns jsonb
language plpgsql stable security definer set search_path to '' as $$
declare v jsonb; v_pid uuid; v_cc text := upper(btrim(coalesce(p_edu_country, '')));
begin
  if v_cc !~ '^[A-Z]{2}$' or not exists (select 1 from ref.countries k where k.iso_alpha2 = v_cc) then
    raise exception 'INVALID_INPUT: edu_country must be a known ISO 3166 alpha-2 country code' using errcode = '22023';
  end if;
  v := public.website_v2_provider(p_provider_id);
  if v ? 'error' then return v; end if;
  select p.id into v_pid from catalogue.providers p where lower(p.stable_key) = lower(btrim(p_provider_id)) limit 1;
  return jsonb_set(v, '{item,entry_matrix}', security.entry_matrix_payload_v1(v_pid, v_cc));
end $$;
revoke all on function public.website_v2_provider(text, text) from public, anon, authenticated;
grant execute on function public.website_v2_provider(text, text) to service_role;
comment on function public.website_v2_provider(text, text) is 'CF-247 Track C Step B (B3): the provider payload with entry_matrix narrowed to the student''s country of prior education (edu_country).';

insert into pipeline.component_register(kind, name, layer, purpose, status, replaces, introduced_in) values
 ('function', 'security.entry_course_payload_v1', 'Search and API', 'Track C Step B (B2): course payload entry object', 'active', '{}', '20261028005000'),
 ('function', 'security.entry_matrix_payload_v1', 'Search and API', 'Track C Step B (B2): provider payload entry_matrix', 'active', '{}', '20261028005000')
on conflict do nothing;

-- ---------------------------------------------------------------- 4: the consumer baseline re-taken (approved change)
select security.consumer_api_rebaseline_v1('Track C Step B (28 Oct 2026): additive entry and entry_matrix keys and the edu_country forms of website_v2_course / website_v2_provider; approved 25 Oct 2026 14:36/14:50, mandate 28 Oct 2026 20:36');
