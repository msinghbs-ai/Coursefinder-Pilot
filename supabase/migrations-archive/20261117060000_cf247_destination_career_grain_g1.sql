-- CF-247 destination data, decision G-1 (Platform Admin 17 Nov 2026 11:52 AEDT; run now, before the squash, 17 Nov 13:12 S2-Build): career outcomes
-- are held one row per edition, country, occupation scheme, occupation code and area, where the area is national, a state or a locality.
-- Replaces: the unique key career_outcomes_edition_id_country_id_occupation_code_key (replaced in the constraint block, as approved; the table is empty)
-- Retires: nothing
--
-- Admin design: docs/Roadmap/2026-01/DESTINATION-DATA-UI-AND-INGESTION-SPEC.md section 2.5.
--   1. destination.career_outcomes gains geography_level ('national', 'state', 'locality'; default 'national') and state_code; occupation_scheme becomes
--      required (it is part of the key). Rule: national has no state and no locality; state has a state code and no locality; locality has a locality.
--      New key: unique, nulls not distinct, on (edition_id, country_id, occupation_scheme, occupation_code, geography_level, state_code, locality_id).
--   2. security.destination_import_v1 upserts career outcomes on the new key and takes the scheme, area, reference period, dataset edition and
--      attribution from the payload (md5-guarded edit of the career branch only; every other domain unchanged).
--   3. security.destination_read_v1 (API v3 action destination) adds geography_level and state_code to each outcome (additive; v3 is open to additions,
--      Decision 277). No v2 object is touched: G3 stays at 75 functions and 48 relations.
-- G1: no job. G2: no setting. Nothing dropped but the replaced key.

set local lock_timeout = '5s'; -- fixed: lock wait guard for the table and function changes below

do $$ begin
  if to_regclass('destination.career_outcomes') is null or to_regprocedure('security.destination_import_v1(jsonb)') is null
     or to_regprocedure('security.destination_read_v1(jsonb,integer,integer)') is null then
    raise exception 'an object this change builds on is missing';
  end if;
end $$;

-- 1. Columns, rule and key (constraint block)
alter table destination.career_outcomes
  add column if not exists geography_level text not null default 'national',
  add column if not exists state_code text;
do $$ begin
  if exists (select 1 from pg_constraint where conrelid = 'destination.career_outcomes'::regclass and conname = 'career_outcomes_edition_id_country_id_occupation_code_key') then
    if exists (select 1 from destination.career_outcomes) then
      raise exception 'destination.career_outcomes holds rows: the key replacement was approved for an empty table';
    end if;
    alter table destination.career_outcomes drop constraint career_outcomes_edition_id_country_id_occupation_code_key;
  end if;
  if not exists (select 1 from pg_constraint where conrelid = 'destination.career_outcomes'::regclass and conname = 'career_outcomes_area_key') then
    alter table destination.career_outcomes
      alter column occupation_scheme set not null,
      add constraint career_outcomes_geography_level_check check (geography_level in ('national', 'state', 'locality')),
      add constraint career_outcomes_area_check check (
        (geography_level = 'national' and state_code is null and locality_id is null)
        or (geography_level = 'state' and state_code is not null and locality_id is null)
        or (geography_level = 'locality' and locality_id is not null)),
      add constraint career_outcomes_state_code_check check (state_code is null or state_code ~ '^[A-Z]{2,3}$'),
      add constraint career_outcomes_area_key unique nulls not distinct
        (edition_id, country_id, occupation_scheme, occupation_code, geography_level, state_code, locality_id);
  end if;
end $$;
comment on column destination.career_outcomes.geography_level is 'G-1 (17 Nov 2026): the area the figure is for: national, state (state_code set) or locality (locality_id set).';
comment on column destination.career_outcomes.state_code is 'G-1 (17 Nov 2026): state or territory code (for example NSW) when geography_level is state.';

-- 2 and 3. Importer and read path (md5-guarded edits of the live function bodies)
create or replace function pg_temp.edit_all(p_sig text, p_before text, p_after text, p_olds text[], p_news text[]) returns text language plpgsql as $f$
declare v_def text := pg_get_functiondef(p_sig::regprocedure); v_src text := (select p.prosrc from pg_proc p where p.oid = p_sig::regprocedure); v_c int; i int;
begin
  -- the guard is the md5 of the function body (pg_proc.prosrc), the same text on PostgreSQL 16 and 17
  if md5(v_src) = p_after then raise notice '%: already applied', p_sig; return p_sig || ': already applied'; end if;
  if md5(v_src) <> p_before then raise exception 'live % differs from the definition this change edits (body md5 %)', p_sig, md5(v_src); end if;
  v_def := replace(v_def, chr(13), '');
  for i in 1 .. array_length(p_olds, 1) loop
    v_c := (length(v_def) - length(replace(v_def, p_olds[i], ''))) / length(p_olds[i]);
    if v_c <> 1 then raise exception '%: edit % must apply exactly once (found %)', p_sig, i, v_c; end if;
    v_def := replace(v_def, p_olds[i], p_news[i]);
  end loop;
  execute v_def;
  v_src := (select p.prosrc from pg_proc p where p.oid = p_sig::regprocedure);
  if md5(v_src) <> p_after then raise exception '% after the edit has body md5 %, expected %', p_sig, md5(v_src), p_after; end if;
  raise notice '%: applied', p_sig;
  return p_sig || ': applied';
end $f$;

select pg_temp.edit_all('security.destination_import_v1(jsonb)', '974b8dcebd6125197d5012a8c52f1378', 'abf584051fa4d9e7c5d6201425878f6d',
  array[
$o1$        insert into destination.career_outcomes as t(edition_id, country_id, occupation_code, occupation_title, study_area_code, skill_shortage_status, median_salary,
               salary_currency, salary_period, employment_rate_pct, job_outlook_rating, outlook_horizon_years, source_url)
        values (v_ed.id, v_country, btrim(r->>'occupation_code'), btrim(r->>'occupation_title'), nullif(btrim(r->>'study_area_code'), ''),$o1$,
$o2$               (r->>'outlook_horizon_years')::int, coalesce(nullif(btrim(r->>'source_url'), ''), v_ed.source_url))
        on conflict (edition_id, country_id, occupation_code) do update set$o2$,
$o3$               outlook_horizon_years = excluded.outlook_horizon_years, source_url = excluded.source_url, last_checked_at = now()
         where (t.occupation_title, t.study_area_code, t.skill_shortage_status, t.median_salary, t.salary_currency, t.salary_period, t.employment_rate_pct,
                t.job_outlook_rating, t.outlook_horizon_years, t.source_url)
               is distinct from
               (excluded.occupation_title, excluded.study_area_code, excluded.skill_shortage_status, excluded.median_salary, excluded.salary_currency,
                excluded.salary_period, excluded.employment_rate_pct, excluded.job_outlook_rating, excluded.outlook_horizon_years, excluded.source_url)$o3$
  ],
  array[
$n1$        -- G-1 (17 Nov 2026): one row per scheme, occupation and area; the scheme is required, the area defaults to national
        insert into destination.career_outcomes as t(edition_id, country_id, occupation_scheme, occupation_code, geography_level, state_code, locality_id,
               occupation_title, study_area_code, skill_shortage_status, median_salary,
               salary_currency, salary_period, employment_rate_pct, job_outlook_rating, outlook_horizon_years, source_url, reference_period, dataset_edition, attribution_text)
        values (v_ed.id, v_country, upper(btrim(r->>'occupation_scheme')), btrim(r->>'occupation_code'), coalesce(nullif(btrim(r->>'geography_level'), ''), 'national'),
               upper(nullif(btrim(r->>'state_code'), '')), nullif(r->>'locality_id', '')::uuid,
               btrim(r->>'occupation_title'), nullif(btrim(r->>'study_area_code'), ''),$n1$,
$n2$               (r->>'outlook_horizon_years')::int, coalesce(nullif(btrim(r->>'source_url'), ''), v_ed.source_url),
               nullif(btrim(r->>'reference_period'), ''), nullif(btrim(r->>'dataset_edition'), ''), nullif(btrim(r->>'attribution_text'), ''))
        on conflict (edition_id, country_id, occupation_scheme, occupation_code, geography_level, state_code, locality_id) do update set$n2$,
$n3$               outlook_horizon_years = excluded.outlook_horizon_years, source_url = excluded.source_url, reference_period = excluded.reference_period,
               dataset_edition = excluded.dataset_edition, attribution_text = excluded.attribution_text, last_checked_at = now()
         where (t.occupation_title, t.study_area_code, t.skill_shortage_status, t.median_salary, t.salary_currency, t.salary_period, t.employment_rate_pct,
                t.job_outlook_rating, t.outlook_horizon_years, t.source_url, t.reference_period, t.dataset_edition, t.attribution_text)
               is distinct from
               (excluded.occupation_title, excluded.study_area_code, excluded.skill_shortage_status, excluded.median_salary, excluded.salary_currency,
                excluded.salary_period, excluded.employment_rate_pct, excluded.job_outlook_rating, excluded.outlook_horizon_years, excluded.source_url,
                excluded.reference_period, excluded.dataset_edition, excluded.attribution_text)$n3$
  ]);

select pg_temp.edit_all('security.destination_read_v1(jsonb,integer,integer)', 'f89256d82bb43f9f16868b126c3586f4', '40b256e6aed77969fac06c2b15249626',
  array[$r1$      select q.cc, q.occupation_code, q.id, jsonb_build_object('outcome_id', q.id, 'country_code', q.cc, 'locality_id', q.locality_id, 'occupation_scheme', q.occupation_scheme,$r1$],
  array[$s1$      select q.cc, q.occupation_code, q.id, jsonb_build_object('outcome_id', q.id, 'country_code', q.cc, 'locality_id', q.locality_id, 'occupation_scheme', q.occupation_scheme,
               'geography_level', q.geography_level, 'state_code', q.state_code,$s1$]);

-- 4. Post-checks
do $k$ begin
  if not exists (select 1 from pg_constraint where conrelid = 'destination.career_outcomes'::regclass and conname = 'career_outcomes_area_key'
                   and pg_get_constraintdef(oid) = 'UNIQUE NULLS NOT DISTINCT (edition_id, country_id, occupation_scheme, occupation_code, geography_level, state_code, locality_id)') then
    raise exception 'post-check: the G-1 key';
  end if;
  if exists (select 1 from pg_constraint where conrelid = 'destination.career_outcomes'::regclass and conname = 'career_outcomes_edition_id_country_id_occupation_code_key') then
    raise exception 'post-check: the old key is replaced';
  end if;
  if position('on conflict (edition_id, country_id, occupation_scheme, occupation_code, geography_level, state_code, locality_id)' in
              pg_get_functiondef('security.destination_import_v1(jsonb)'::regprocedure)) = 0 then
    raise exception 'post-check: the importer upserts on the G-1 key';
  end if;
end $k$;
