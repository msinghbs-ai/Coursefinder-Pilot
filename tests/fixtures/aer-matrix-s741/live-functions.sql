-- Copied byte for byte from supabase/live-capture/baseline/schema.sql (canonical squash, cut-off 20261118272000) by tests/fixtures/aer-matrix-s741/run.sh's author;
-- run.sh checks that security.aer_matrix_machine_exclusions_v1 here has the live md5 of 19 Nov 2026 (51e0eb45...) before the S741 edit.
CREATE OR REPLACE FUNCTION "security"."entry_course_title_key_v1"("p" "text") RETURNS "text"
    LANGUAGE "sql" IMMUTABLE
    SET "search_path" TO ''
    AS $$
  select nullif(btrim(regexp_replace(regexp_replace(lower(
           regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(coalesce(p, ''),
             '[\^*#†‡]+', ' ', 'g'),
             '\(level [0-9]+\)', ' ', 'gi'),
             '\mB\M\.?(\s)', 'Bachelor of\1', 'g'),
             '\mM\M\.?(\s)', 'Master of\1', 'g'),
             '\mHons\M', 'Honours', 'g'),
             '[/&]', ' and ', 'g'),
             '\mof\s+of\M', 'of', 'gi')),
           '[^a-z0-9]+', ' ', 'g'), '\s+', ' ', 'g')), '')
$$;

CREATE OR REPLACE FUNCTION "security"."entry_matrix_row_hash_v1"("p_provider" "uuid", "p_course" "uuid", "p_country" "text", "p_level" "uuid", "p_band" "text", "p_qualification" "text", "p_conditions" "jsonb") RETURNS character
    LANGUAGE "sql" IMMUTABLE
    SET "search_path" TO ''
    AS $$
  select encode(sha256(convert_to(
    p_provider::text || '|' || coalesce(p_course::text, '') || '|' || coalesce(upper(p_country), '') || '|' || coalesce(p_level::text, '') || '|' ||
    coalesce(p_band, '') || '|' ||
    coalesce((select string_agg(k, '|' order by k)
                from (select distinct lower(btrim(coalesce(e->>'board', e->>'era', e->>'key'))) k
                        from jsonb_array_elements(case when jsonb_typeof(p_conditions) = 'array' then p_conditions else '[]'::jsonb end) e
                       where jsonb_typeof(e) = 'object' and nullif(btrim(coalesce(e->>'board', e->>'era', e->>'key')), '') is not null
                      union
                      select lower(btrim(p_qualification)) where nullif(btrim(p_qualification), '') is not null) z), ''),
    'UTF8')), 'hex')::char(64)
$$;

CREATE OR REPLACE FUNCTION "security"."entry_level_map_v1"("p_label" "text") RETURNS "uuid"
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
  select l.id from ref.study_levels l
   where l.code = case
     when p_label ~* 'phd|doctor' then 'doctorate'
     when p_label ~* 'master|postgrad' then 'masters'
     when p_label ~* 'graduate diploma' then 'graduate_diploma'
     when p_label ~* 'graduate certificate' then 'graduate_certificate'
     when p_label ~* 'associate degree' then 'associate_degree'
     when p_label ~* 'bachelor|degree|undergrad' then 'bachelor'
     when p_label ~* 'advanced diploma' then 'advanced_diploma'
     when p_label ~* 'diploma' then 'diploma'
     when p_label ~* 'foundation|pathway' then 'foundation'
     when p_label ~* 'certificate' then 'certificate'
   end
$$;

CREATE OR REPLACE FUNCTION "security"."aer_quote_has_value_v1"("p_quote" "text", "p_grade" "text", "p_value" numeric) RETURNS boolean
    LANGUAGE "sql" IMMUTABLE
    SET "search_path" TO ''
    AS $_$
  -- the published minimum is in the quote as a whole token: the grade text when the row has one, otherwise the value (70, 3.3; never 170 or 3.35)
  select case when nullif(btrim(coalesce(p_grade, '')), '') is not null
              then coalesce(p_quote, '') ~* ('(^|[^0-9A-Za-z.])' || regexp_replace(btrim(p_grade), '([.*+?^${}()|\[\]\\])', '\\\1', 'g') || '($|[^0-9A-Za-z])')
              when p_value is not null
              then coalesce(p_quote, '') ~ ('(^|[^0-9.])' || replace(trim_scale(p_value)::text, '.', '\.') || '($|[^0-9])')
              else false end
$_$;

CREATE OR REPLACE FUNCTION "security"."aer_matrix_machine_exclusions_v1"("p_run" "uuid") RETURNS "jsonb"
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO ''
    AS $_$
  -- the proposed rows of one read that fail a row rule of the machine check, each with its rule (the same rules, in the same order); S671 (18 Nov 2026): the level printed
  -- over the table, "Year N equivalent" labels and completion-only rows
  with cfg as materialized (select security.pipeline_num_v1('aer.matrix_machine_min_confidence', 0.9) conf, security.pipeline_num_v1('aer.machine_min_quote_chars', 8)::int qmin,
                                   security.pipeline_num_v1('aer.course_link_on', 1) >= 1 link_on,
                                   security.pipeline_num_v1('aer.matrix_level_inherit_on', 0) >= 1 inh_on,
                                   security.pipeline_num_v1('aer.matrix_completion_only_on', 0) >= 1 cmp_on,
                                   coalesce((select s.value from pipeline.platform_toolset_settings s where s.toolset_key = 'pipeline' and s.key = 'aer.matrix_level_inherit_codes'
                                              and jsonb_typeof(s.value) = 'array'), '[]'::jsonb) inh_codes),
  run as materialized (select r.id, r.source_id, coalesce(r.result->'completeness'->>'heading', '') heading,
                              regexp_replace(regexp_replace(rtrim(regexp_replace(coalesce(f.url, ''), '[?#].*$', ''), '/'), '^.*/', ''), '\.[A-Za-z0-9]{2,5}$', '') slug
                         from pipeline.entry_matrix_runs r left join pipeline.entry_matrix_sources f on f.id = r.source_id where r.id = p_run),
  words as materialized (select distinct l.id, l.code from run, regexp_split_to_table(lower(run.heading || ' ' || run.slug), '[^a-z]+') w
                           join ref.study_levels l on l.id = security.entry_level_map_v1(w) where w <> ''),
  m0 as materialized (select m.*, m.level_label is not null and m.level_label ~* '^\s*(australian\s+)?year\s*1[0-2]\s+equivalent\s*$' eqv
                        from catalogue.provider_entry_matrix m join run on m.run_id = run.id where m.status = 'proposed'),
  q0 as materialized (select q.*, q.level_label is not null and q.level_label ~* '^\s*(australian\s+)?year\s*1[0-2]\s+equivalent\s*$' eqv
                        from catalogue.provider_qualification_requirements q join run on q.run_id = run.id where q.status = 'proposed'),
  lvl as materialized (select case when cfg.inh_on and (select count(*) from words) = 1 and cfg.inh_codes ? (select min(w.code) from words w)
                                    and not exists (select 1 from m0 where m0.level_label is not null and not m0.eqv)
                                    and not exists (select 1 from q0 where q0.level_label is not null and not q0.eqv)
                               then (select (array_agg(w.id))[1] from words w) end id,
                              (select min(w.code) from words w) code, (select run.heading from run) heading, (select run.slug from run) slug
                         from cfg),
  -- a completion requirement with no score: completion words, no percentage, no number but a schooling year/grade/form/level or a duration, no score words
  m as materialized (select m0.*, (m0.study_level_id is null and (m0.level_label is null or m0.eqv) and lvl.id is not null) inh,
                            coalesce(cfg.cmp_on and m0.min_value is null and (nullif(btrim(coalesce(m0.min_grade, '')), '') is null or m0.min_grade ~* '^\s*(successful(ly)?\s+)?complet')
                             and m0.quote ~* '\m(successful(ly)?\s+)?complet(e|ed|ion)\M' and m0.quote !~ '%'
                             and regexp_replace(lower(m0.quote), '(year|yr|grade|form|level|class|standard|std)\s*\d+|\d+\s*(years?|semesters?|months?|terms?|sessions?)|\m(19|20)\d\d\M', ' ', 'g') !~ '\d'
                             and m0.quote !~* '\m(gpa|cgpa|average|aggregate|marks?|scores?|points?|pass(es)?|credits?|distinctions?|division|atar|percent(age)?)\M|\mgrade\s+[a-e]\M|\m[a-e]\s+grade|''[a-e]''', false) cmp,
                            case when m0.study_level_id is null and (m0.level_label is null or m0.eqv) and lvl.id is not null
                                 then security.entry_matrix_row_hash_v1(m0.provider_id, m0.course_id, m0.country_code, lvl.id, m0.benchmark_band, m0.qualification_name, m0.conditions)
                                 else m0.row_hash end h2
                       from m0, lvl, cfg),
  q as materialized (select q0.*, (q0.study_level_id is null and (q0.level_label is null or q0.eqv) and lvl.id is not null) inh,
                            coalesce(cfg.cmp_on and q0.min_value is null and (nullif(btrim(coalesce(q0.min_grade, '')), '') is null or q0.min_grade ~* '^\s*(successful(ly)?\s+)?complet')
                             and q0.quote ~* '\m(successful(ly)?\s+)?complet(e|ed|ion)\M' and q0.quote !~ '%'
                             and regexp_replace(lower(q0.quote), '(year|yr|grade|form|level|class|standard|std)\s*\d+|\d+\s*(years?|semesters?|months?|terms?|sessions?)|\m(19|20)\d\d\M', ' ', 'g') !~ '\d'
                             and q0.quote !~* '\m(gpa|cgpa|average|aggregate|marks?|scores?|points?|pass(es)?|credits?|distinctions?|division|atar|percent(age)?)\M|\mgrade\s+[a-e]\M|\m[a-e]\s+grade|''[a-e]''', false) cmp
                       from q0, lvl, cfg),
  why as (
    select m.id, case when coalesce(m.confidence, 0) < cfg.conf then 'low_confidence' when length(btrim(coalesce(m.quote, ''))) < cfg.qmin then 'short_quote'
                      when m.study_level_id is null and not m.inh and m.eqv then 'level_equivalence_only'
                      when m.study_level_id is null and not m.inh then 'level_unmapped'
                      when not m.cmp and not ((m.min_value is not null and coalesce(m.grade_scale, 'none') <> 'none') or nullif(btrim(coalesce(m.min_grade, '')), '') is not null) then 'no_minimum'
                      when not m.cmp and not security.aer_quote_has_value_v1(m.quote, m.min_grade, m.min_value) then 'minimum_not_in_quote'
                      when cfg.link_on and m.course_label is not null and m.course_id is null then 'course_unlinked'
                      when exists (select 1 from m m2 where m2.h2 = m.h2 and m2.id <> m.id) then 'duplicate_identity'
                      when exists (select 1 from catalogue.provider_entry_matrix a, run where a.row_hash = m.h2 and a.status = 'active' and a.id <> m.id
                                      and a.source_id is distinct from run.source_id) then 'conflicting_active' end w
      from m, cfg
    union all
    select q.id, case when q.applicability = 'unresolved' then 'applicability_unresolved' when coalesce(q.confidence, 0) < cfg.conf then 'low_confidence'
                      when length(btrim(coalesce(q.quote, ''))) < cfg.qmin then 'short_quote'
                      when q.study_level_id is null and not q.inh and q.eqv then 'level_equivalence_only'
                      when q.study_level_id is null and not q.inh then 'level_unmapped'
                      when not q.cmp and not ((q.min_value is not null and coalesce(q.grade_scale, 'none') <> 'none') or nullif(btrim(coalesce(q.min_grade, '')), '') is not null) then 'no_minimum'
                      when not q.cmp and not security.aer_quote_has_value_v1(q.quote, q.min_grade, q.min_value) then 'minimum_not_in_quote'
                      when cfg.link_on and q.course_label is not null and q.course_id is null then 'course_unlinked'
                      when exists (select 1 from q q2 where q2.qualification_code = q.qualification_code and q2.level_label is not distinct from q.level_label
                                      and q2.course_label is not distinct from q.course_label and q2.id <> q.id) then 'duplicate_identity'
                      when exists (select 1 from catalogue.provider_qualification_requirements a, run where a.provider_id = q.provider_id and a.qualification_code = q.qualification_code
                                      and a.level_label is not distinct from q.level_label and a.course_label is not distinct from q.course_label and a.status = 'active'
                                      and a.source_id is distinct from run.source_id) then 'conflicting_active' end
      from q, cfg)
  select jsonb_build_object('ids', coalesce(jsonb_agg(why.id order by why.id) filter (where why.w is not null), '[]'::jsonb),
                            'by_rule', coalesce((select jsonb_object_agg(z.w, z.n) from (select w, count(*) n from why where w is not null group by w) z), '{}'::jsonb),
                            'level_inherit_ids', coalesce((select jsonb_agg(x.id order by x.id) from (select id from m where inh union all select id from q where inh) x
                                                          where not exists (select 1 from why where why.id = x.id and why.w is not null)), '[]'::jsonb),
                            'completion_only_ids', coalesce((select jsonb_agg(x.id order by x.id) from (select id from m where cmp union all select id from q where cmp) x
                                                            where not exists (select 1 from why where why.id = x.id and why.w is not null)), '[]'::jsonb),
                            'inherit', (select case when lvl.id is not null then jsonb_build_object('study_level_id', lvl.id, 'code', lvl.code, 'rule', 'S671 level printed over the table',
                                                       'heading', nullif(lvl.heading, ''), 'file_title', nullif(lvl.slug, '')) end from lvl))
    from why
$_$;
