-- CF-247 S741 AER provider matrices: completion-only rows read without the English-language clause, and course rows linked by printed title or printed award (session S2-BOOST-AER;
-- Platform Admin full-steam directive 19 Nov 2026 05:42 AEDT, item 2: "deterministic ... normalisers ... while keeping variant twins strictly separated per Decision 276 ... re-evaluate
-- existing stored matrix ... readings (zero LLM spend) so newly complete, quote-verified rows admit immediately (no-overwrite enforced)").
-- Guards: AER matrix machine admission (rule aer-matrix-machine-v1), Decision 276 (no reader, prompt or threshold change: aer.matrix_machine_min_confidence 0.9 and aer.machine_min_quote_chars 8
--   unchanged; variant twins never linked), G2 (three settings), G3 (no consumer API object; CREATE OR REPLACE of three security functions only; 75 functions and 48 relations post-checked),
--   Decision 260 (housekeeping), "a passing qualification never switches anything on by itself" (aer.matrix_machine_mode is not touched).
-- Replaces: security.aer_matrix_machine_exclusions_v1, security.aer_matrix_machine_check_v1, security.aer_matrix_machine_admit_v1 (same names and signatures; md5-guarded edits, each exactly once)
-- Retires: nothing
--
-- Live evidence (project fxcwkweaxjtknorudmwp, read only, 19 Nov 2026 05:45 to 06:20 AEDT). 81 entry-matrix items wait in Layer 4: 54 fail the D-R3 completeness gate (the reader
-- dropped printed rows; only a new read fixes that), 13 are held by policy (host, change of an admitted table, audit sample, earlier rejection), and 14 have every row held by a row rule:
-- level_unmapped 7 items (294 rows), no_minimum 4 (12 rows), course_unlinked 3 (22 rows). This change reaches the last two:
--   1 no_minimum: Alfa College, Gamma College and AIDC print "Completion of Year 12 or equivalent", but the quote the reader kept runs on into the English requirement
--     ("IELTS (Academic): minimum overall band of 6.0"), states an age ("18-years of Age or Older") or a CRICOS or training package code, so the S671 completion test saw digits.
--     With aer.matrix_completion_clauses_on the academic part is read up to the English-language clause; ages ("18-years", "18 years of age"), durations in weeks, CRICOS codes and
--     training package codes are not scores; the English clause itself may hold no percentage or academic score word (a score printed after it keeps the row held).
--   2 course_unlinked: the insert-time linker (security.entry_course_link_v1) needs the level in the label. AIDC prints "CPC30620 – Certificate III in Painting and Decorating";
--     Curtin College and SIBT print the award once in the level column ("Diploma Program") and the field in the row ("Business"). With aer.matrix_course_link_rules_on a row links to
--     exactly one active course of the provider whose title (the linker's own title key) is the label less a leading training package code, or "<award> of|in <label>" where the printed
--     level names one award of aer.matrix_course_link_awards and the label names no stream ([...] or (...)). Never where a person recorded "no catalogue course" for the label, never two
--     candidates, never a course with an active twin ("<title> (...)", "<title> - ...", "<title> [...]": Standard/Accelerated, weeks, Pass/Honours). The admit function writes the course
--     only on a row that has none (no overwrite); the identity trigger re-keys the row.
-- Not reached, by design: the 294 rows with no level (UWA, UTAS's second page, ANU HKDSE, unimelb, EEI, JPIC) print no level in the row, heading or address, and no provider of them offers
--   a single study level; the 54 gate items need a new read (S744 chunker, then a qualified model).
-- Reversal without code: aer.matrix_completion_clauses_on 0 and aer.matrix_course_link_rules_on 0 restore the rules of 18 Nov exactly (fixture scenario OFF).
-- Then the matrix validation is re-run on the edited rule (it fails this migration unless it passes); aer.matrix_machine_mode is not changed.
-- Before -> after (pg_get_functiondef md5):
--   security.aer_matrix_machine_exclusions_v1(uuid)      51e0eb454501a4b87e419b1125bcf8c3 -> 969e88394398c025d30c2e66fec3dfbe
--   security.aer_matrix_machine_check_v1(uuid)           80636b9af550a5896cfbb95ab1bd264c -> d3d038ebe92f4c3b81c088ed0fbc4169
--   security.aer_matrix_machine_admit_v1(uuid, text)     debe928ff881340e4712606d34e3e61d -> 6597688eaf41e43b45c0bf63a9096299

do $g$
begin
  if to_regprocedure('security.aer_matrix_machine_exclusions_v1(uuid)') is null or to_regprocedure('security.entry_course_title_key_v1(text)') is null
     or to_regclass('catalogue.entry_course_links') is null then
    raise exception 'needs the S671 matrix machine functions, security.entry_course_title_key_v1 and catalogue.entry_course_links';
  end if;
end $g$;

-- 1 settings (G2) -----------------------------------------------------------------------------------------------------------------------------
insert into pipeline.platform_toolset_settings(toolset_key, key, label, help, kind, value, min_value, max_value, unit, sort, section, used_by, reason) values
 ('pipeline', 'aer.matrix_completion_clauses_on', 'Entry requirements: completion rows read without the English clause',
  '1: a completion requirement is judged on its academic part, up to the English-language clause; an age, a duration in weeks, a CRICOS code or a training package code is not a score, and the English clause may hold no percentage or academic score word. 0: the rule of 18 Nov 2026.',
  'number', '1'::jsonb, 0, 1, 'on/off', 1498, 'Entry requirements', 'security.aer_matrix_machine_exclusions_v1',
  'CF-247 S741 (Platform Admin 19 Nov 2026 05:42, S2-BOOST-AER): the reader''s quote runs on into the English requirement'),
 ('pipeline', 'aer.matrix_course_link_rules_on', 'Entry requirements: link course rows by printed title or printed award',
  '1: a course row the insert-time linker left unlinked links to exactly one active course whose title is the label less a training package code, or the printed award with the label; never a stream label, two candidates, a course with an active twin, or a label a person decided has no catalogue course. 0: the rule of 18 Nov 2026.',
  'number', '1'::jsonb, 0, 1, 'on/off', 1499, 'Entry requirements', 'security.aer_matrix_machine_exclusions_v1, security.aer_matrix_machine_admit_v1, security.aer_matrix_machine_check_v1',
  'CF-247 S741 (Platform Admin 19 Nov 2026 05:42, S2-BOOST-AER): the award is printed once in the level column'),
 ('pipeline', 'aer.matrix_course_link_awards', 'Entry requirements: awards a printed level may give a course row',
  'Awards whose printed level ("Diploma Program", "Bachelor") with the row''s label forms a course title ("Diploma of Business"). Graduate and research awards are left out: their pages name streams, not courses.',
  'list', '["diploma", "advanced diploma", "associate degree", "bachelor", "certificate iii", "certificate iv"]'::jsonb, null, null, 'award words', 1500, 'Entry requirements',
  'security.aer_matrix_machine_exclusions_v1', 'CF-247 S741 (Platform Admin 19 Nov 2026 05:42, S2-BOOST-AER)')
on conflict (toolset_key, key) do nothing;

-- 2 the edits, md5-guarded --------------------------------------------------------------------------------------------------------------------
do $ex$
declare v_sig constant text := 'security.aer_matrix_machine_exclusions_v1(uuid)'; v_before constant text := '51e0eb454501a4b87e419b1125bcf8c3';
        v_def text := pg_get_functiondef('security.aer_matrix_machine_exclusions_v1(uuid)'::regprocedure); v_old text; v_new text; v_c int;
begin
  if v_def like '%S741 (19 Nov 2026%' then raise notice '%: already applied', v_sig; return; end if;
  if md5(v_def) <> v_before then raise exception '% differs from the definition this change edits (md5 %)', v_sig, md5(v_def); end if;
  v_old := $o0$                                   security.pipeline_num_v1('aer.matrix_completion_only_on', 0) >= 1 cmp_on,
$o0$;
  v_new := $n0$                                   security.pipeline_num_v1('aer.matrix_completion_only_on', 0) >= 1 cmp_on,
                                   security.pipeline_num_v1('aer.matrix_completion_clauses_on', 0) >= 1 cl_on,
                                   security.pipeline_num_v1('aer.matrix_course_link_rules_on', 0) >= 1 clk_on,
                                   coalesce((select s.value from pipeline.platform_toolset_settings s where s.toolset_key = 'pipeline' and s.key = 'aer.matrix_course_link_awards'
                                              and jsonb_typeof(s.value) = 'array'), '[]'::jsonb) awards,
$n0$;
  v_c := (length(v_def) - length(replace(v_def, v_old, ''))) / length(v_old);
  if v_c <> 1 then raise exception '%: edit 1 must apply exactly once (found %)', v_sig, v_c; end if;
  v_def := replace(v_def, v_old, v_new);
  v_old := $o1$  -- a completion requirement with no score: completion words$o1$;
  v_new := $n1$  -- S741 (19 Nov 2026, aer.matrix_course_link_rules_on): a course row the insert-time linker left unlinked links to exactly one active course of the provider when
  --   (a) its label, less a leading national training package code ("CPC30220 – "), is that course's exact title, or
  --   (b) the level printed for it names one award of aer.matrix_course_link_awards and "<award> of|in <label>" is that course's exact title, the label naming no stream ([...] or (...));
  -- never where a person recorded "no catalogue course" for the label, and never where a twin of the course is active ("<title> (...)", "<title> - ...", "<title> [...]"), so
  -- variant twins stay apart (Decision 276). The title key is the insert-time linker's own (security.entry_course_title_key_v1).
  lk0 as materialized (select m0.id, c.id course_id, b.basis
                         from m0 cross join cfg
                         cross join lateral (select 'title' basis, security.entry_course_title_key_v1(regexp_replace(m0.course_label, '^\s*[A-Za-z]{3}[0-9]{5}\s*[–-]\s*', '')) k
                                             union all
                                             select 'award_field', security.entry_course_title_key_v1(a.aw || ' ' || p.pre || ' ' || m0.course_label)
                                               from jsonb_array_elements_text(cfg.awards) a(aw) cross join (values ('of'), ('in')) p(pre)
                                              where m0.level_label ~* ('^\s*' || a.aw || '(\s+(program(me)?s?|courses?))?\s*$') and m0.course_label !~ '[\[\]()]') b
                         join catalogue.courses c on c.provider_id = m0.provider_id and c.lifecycle_status = 'active'
                                                 and (security.entry_course_title_key_v1(c.canonical_title) = b.k or security.entry_course_title_key_v1(c.display_title) = b.k)
                        where cfg.clk_on and cfg.link_on and m0.course_id is null and nullif(btrim(m0.course_label), '') is not null and b.k is not null
                          and not exists (select 1 from catalogue.entry_course_links x where x.provider_id = m0.provider_id
                                             and x.label_key = security.entry_course_title_key_v1(m0.course_label) and x.state = 'rejected')
                          and not exists (select 1 from catalogue.courses t where t.provider_id = m0.provider_id and t.lifecycle_status = 'active' and t.id <> c.id
                                             and (lower(t.canonical_title) like lower(c.canonical_title) || ' (%' or lower(t.canonical_title) like lower(c.canonical_title) || ' - %'
                                                  or lower(t.canonical_title) like lower(c.canonical_title) || ' [%'))),
  lnk as materialized (select id, min(course_id::text)::uuid course_id, min(basis) basis from lk0 group by id having count(distinct course_id) = 1),
  -- a completion requirement with no score: completion words$n1$;
  v_c := (length(v_def) - length(replace(v_def, v_old, ''))) / length(v_old);
  if v_c <> 1 then raise exception '%: edit 2 must apply exactly once (found %)', v_sig, v_c; end if;
  v_def := replace(v_def, v_old, v_new);
  v_old := $o2$                            coalesce(cfg.cmp_on and m0.min_value is null and (nullif(btrim(coalesce(m0.min_grade, '')), '') is null or m0.min_grade ~* '^\s*(successful(ly)?\s+)?complet')
                             and m0.quote ~* '\m(successful(ly)?\s+)?complet(e|ed|ion)\M' and m0.quote !~ '%'
                             and regexp_replace(lower(m0.quote), '(year|yr|grade|form|level|class|standard|std)\s*\d+|\d+\s*(years?|semesters?|months?|terms?|sessions?)|\m(19|20)\d\d\M', ' ', 'g') !~ '\d'
                             and m0.quote !~* '\m(gpa|cgpa|average|aggregate|marks?|scores?|points?|pass(es)?|credits?|distinctions?|division|atar|percent(age)?)\M|\mgrade\s+[a-e]\M|\m[a-e]\s+grade|''[a-e]''', false) cmp$o2$;
  v_new := $n2$                            -- S741 (19 Nov 2026, aer.matrix_completion_clauses_on): the academic part is read without the English-language clause the reader carried into the quote; an age,
                            -- a CRICOS code or a training package code is not a score; the English clause itself may hold no percentage or academic score word
                            coalesce(cfg.cmp_on and m0.min_value is null and (nullif(btrim(coalesce(m0.min_grade, '')), '') is null or m0.min_grade ~* '^\s*(successful(ly)?\s+)?complet')
                             and (case when cfg.cl_on then regexp_replace(m0.quote, '(?i)\m(english\s+(language\s+)?(requirements?|proficiency)|ielts|toefl|pte|duolingo)\M.*$', '') else m0.quote end) ~* '\m(successful(ly)?\s+)?complet(e|ed|ion)\M' and (case when cfg.cl_on then regexp_replace(m0.quote, '(?i)\m(english\s+(language\s+)?(requirements?|proficiency)|ielts|toefl|pte|duolingo)\M.*$', '') else m0.quote end) !~ '%'
                             and regexp_replace(lower((case when cfg.cl_on then regexp_replace(m0.quote, '(?i)\m(english\s+(language\s+)?(requirements?|proficiency)|ielts|toefl|pte|duolingo)\M.*$', '') else m0.quote end)), case when cfg.cl_on then '(year|yr|grade|form|level|class|standard|std)\s*\d+|\d+[\s-]*(years?|semesters?|months?|terms?|sessions?|weeks?)|\m(19|20)\d\d\M|cricos(\s+course)?\s+code\s*:?\s*\d{5,6}[a-z]?|\m[a-z]{3}\d{5}\M' else '(year|yr|grade|form|level|class|standard|std)\s*\d+|\d+\s*(years?|semesters?|months?|terms?|sessions?)|\m(19|20)\d\d\M' end, ' ', 'g') !~ '\d'
                             and (case when cfg.cl_on then regexp_replace(m0.quote, '(?i)\m(english\s+(language\s+)?(requirements?|proficiency)|ielts|toefl|pte|duolingo)\M.*$', '') else m0.quote end) !~* '\m(gpa|cgpa|average|aggregate|marks?|scores?|points?|pass(es)?|credits?|distinctions?|division|atar|percent(age)?)\M|\mgrade\s+[a-e]\M|\m[a-e]\s+grade|''[a-e]'''
                             and (not cfg.cl_on or ((case when cfg.cl_on then coalesce(substring(m0.quote from '(?i)(\m(english\s+(language\s+)?(requirements?|proficiency)|ielts|toefl|pte|duolingo)\M.*)$'), '') else '' end) !~ '%' and (case when cfg.cl_on then coalesce(substring(m0.quote from '(?i)(\m(english\s+(language\s+)?(requirements?|proficiency)|ielts|toefl|pte|duolingo)\M.*)$'), '') else '' end) !~* '\m(gpa|cgpa|average|aggregate|marks?|atar|percent(age)?)\M|\mgrade\s+[a-e]\M|''[a-e]''')), false) cmp$n2$;
  v_c := (length(v_def) - length(replace(v_def, v_old, ''))) / length(v_old);
  if v_c <> 1 then raise exception '%: edit 3 must apply exactly once (found %)', v_sig, v_c; end if;
  v_def := replace(v_def, v_old, v_new);
  v_old := $o3$                            case when m0.study_level_id is null and (m0.level_label is null or m0.eqv) and lvl.id is not null
                                 then security.entry_matrix_row_hash_v1(m0.provider_id, m0.course_id, m0.country_code, lvl.id, m0.benchmark_band, m0.qualification_name, m0.conditions)
                                 else m0.row_hash end h2
                       from m0, lvl, cfg),$o3$;
  v_new := $n3$                            -- S741: a linked row's identity is the one the identity trigger will give it with its course (same keys as security.entry_matrix_identity_tg)
                            case when lnk.course_id is not null
                                 then security.entry_matrix_row_hash_v1(m0.provider_id, lnk.course_id, m0.country_code,
                                        coalesce(m0.study_level_id, case when (m0.level_label is null or m0.eqv) then lvl.id end), m0.benchmark_band, m0.qualification_name,
                                        (case when jsonb_typeof(m0.conditions) = 'array' then m0.conditions else '[]'::jsonb end)
                                        || case when nullif(btrim(m0.level_label), '') is not null then jsonb_build_array(jsonb_build_object('key', 'level: ' || btrim(m0.level_label))) else '[]'::jsonb end
                                        || case when nullif(btrim(m0.course_label), '') is not null then jsonb_build_array(jsonb_build_object('key', 'course: ' || btrim(m0.course_label))) else '[]'::jsonb end)
                                 when m0.study_level_id is null and (m0.level_label is null or m0.eqv) and lvl.id is not null
                                 then security.entry_matrix_row_hash_v1(m0.provider_id, m0.course_id, m0.country_code, lvl.id, m0.benchmark_band, m0.qualification_name, m0.conditions)
                                 else m0.row_hash end h2,
                            lnk.course_id link, lnk.basis link_basis
                       from m0 cross join lvl cross join cfg left join lnk on lnk.id = m0.id),$n3$;
  v_c := (length(v_def) - length(replace(v_def, v_old, ''))) / length(v_old);
  if v_c <> 1 then raise exception '%: edit 4 must apply exactly once (found %)', v_sig, v_c; end if;
  v_def := replace(v_def, v_old, v_new);
  v_old := $o4$                            coalesce(cfg.cmp_on and q0.min_value is null and (nullif(btrim(coalesce(q0.min_grade, '')), '') is null or q0.min_grade ~* '^\s*(successful(ly)?\s+)?complet')
                             and q0.quote ~* '\m(successful(ly)?\s+)?complet(e|ed|ion)\M' and q0.quote !~ '%'
                             and regexp_replace(lower(q0.quote), '(year|yr|grade|form|level|class|standard|std)\s*\d+|\d+\s*(years?|semesters?|months?|terms?|sessions?)|\m(19|20)\d\d\M', ' ', 'g') !~ '\d'
                             and q0.quote !~* '\m(gpa|cgpa|average|aggregate|marks?|scores?|points?|pass(es)?|credits?|distinctions?|division|atar|percent(age)?)\M|\mgrade\s+[a-e]\M|\m[a-e]\s+grade|''[a-e]''', false) cmp$o4$;
  v_new := $n4$                            -- S741 (19 Nov 2026, aer.matrix_completion_clauses_on): the academic part is read without the English-language clause the reader carried into the quote; an age,
                            -- a CRICOS code or a training package code is not a score; the English clause itself may hold no percentage or academic score word
                            coalesce(cfg.cmp_on and q0.min_value is null and (nullif(btrim(coalesce(q0.min_grade, '')), '') is null or q0.min_grade ~* '^\s*(successful(ly)?\s+)?complet')
                             and (case when cfg.cl_on then regexp_replace(q0.quote, '(?i)\m(english\s+(language\s+)?(requirements?|proficiency)|ielts|toefl|pte|duolingo)\M.*$', '') else q0.quote end) ~* '\m(successful(ly)?\s+)?complet(e|ed|ion)\M' and (case when cfg.cl_on then regexp_replace(q0.quote, '(?i)\m(english\s+(language\s+)?(requirements?|proficiency)|ielts|toefl|pte|duolingo)\M.*$', '') else q0.quote end) !~ '%'
                             and regexp_replace(lower((case when cfg.cl_on then regexp_replace(q0.quote, '(?i)\m(english\s+(language\s+)?(requirements?|proficiency)|ielts|toefl|pte|duolingo)\M.*$', '') else q0.quote end)), case when cfg.cl_on then '(year|yr|grade|form|level|class|standard|std)\s*\d+|\d+[\s-]*(years?|semesters?|months?|terms?|sessions?|weeks?)|\m(19|20)\d\d\M|cricos(\s+course)?\s+code\s*:?\s*\d{5,6}[a-z]?|\m[a-z]{3}\d{5}\M' else '(year|yr|grade|form|level|class|standard|std)\s*\d+|\d+\s*(years?|semesters?|months?|terms?|sessions?)|\m(19|20)\d\d\M' end, ' ', 'g') !~ '\d'
                             and (case when cfg.cl_on then regexp_replace(q0.quote, '(?i)\m(english\s+(language\s+)?(requirements?|proficiency)|ielts|toefl|pte|duolingo)\M.*$', '') else q0.quote end) !~* '\m(gpa|cgpa|average|aggregate|marks?|scores?|points?|pass(es)?|credits?|distinctions?|division|atar|percent(age)?)\M|\mgrade\s+[a-e]\M|\m[a-e]\s+grade|''[a-e]'''
                             and (not cfg.cl_on or ((case when cfg.cl_on then coalesce(substring(q0.quote from '(?i)(\m(english\s+(language\s+)?(requirements?|proficiency)|ielts|toefl|pte|duolingo)\M.*)$'), '') else '' end) !~ '%' and (case when cfg.cl_on then coalesce(substring(q0.quote from '(?i)(\m(english\s+(language\s+)?(requirements?|proficiency)|ielts|toefl|pte|duolingo)\M.*)$'), '') else '' end) !~* '\m(gpa|cgpa|average|aggregate|marks?|atar|percent(age)?)\M|\mgrade\s+[a-e]\M|''[a-e]''')), false) cmp$n4$;
  v_c := (length(v_def) - length(replace(v_def, v_old, ''))) / length(v_old);
  if v_c <> 1 then raise exception '%: edit 5 must apply exactly once (found %)', v_sig, v_c; end if;
  v_def := replace(v_def, v_old, v_new);
  v_old := $o5$                      when cfg.link_on and m.course_label is not null and m.course_id is null then 'course_unlinked'$o5$;
  v_new := $n5$                      when cfg.link_on and m.course_label is not null and m.course_id is null and m.link is null then 'course_unlinked'$n5$;
  v_c := (length(v_def) - length(replace(v_def, v_old, ''))) / length(v_old);
  if v_c <> 1 then raise exception '%: edit 6 must apply exactly once (found %)', v_sig, v_c; end if;
  v_def := replace(v_def, v_old, v_new);
  v_old := $o6$                            'inherit', (select case when lvl.id is not null$o6$;
  v_new := $n6$                            'course_links', coalesce((select jsonb_agg(jsonb_build_object('id', m.id, 'course_id', m.link, 'basis', m.link_basis, 'rule', 'S741') order by m.id) from m
                                                       where m.link is not null and not exists (select 1 from why where why.id = m.id and why.w is not null)), '[]'::jsonb),
                            'inherit', (select case when lvl.id is not null$n6$;
  v_c := (length(v_def) - length(replace(v_def, v_old, ''))) / length(v_old);
  if v_c <> 1 then raise exception '%: edit 7 must apply exactly once (found %)', v_sig, v_c; end if;
  v_def := replace(v_def, v_old, v_new);
  execute v_def;
  raise notice '%: applied, md5 now %', v_sig, md5(pg_get_functiondef('security.aer_matrix_machine_exclusions_v1(uuid)'::regprocedure));
end $ex$;

do $ch$
declare v_sig constant text := 'security.aer_matrix_machine_check_v1(uuid)'; v_before constant text := '80636b9af550a5896cfbb95ab1bd264c';
        v_def text := pg_get_functiondef('security.aer_matrix_machine_check_v1(uuid)'::regprocedure); v_old text; v_new text; v_c int;
begin
  if v_def like '%S741 (19 Nov 2026%' then raise notice '%: already applied', v_sig; return; end if;
  if md5(v_def) <> v_before then raise exception '% differs from the definition this change edits (md5 %)', v_sig, md5(v_def); end if;
  v_old := $o0$'level_inherited', cardinality(v_inh), 'completion_only', cardinality(v_cmp), 'level_from', v_inf->'inherit')$o0$;
  v_new := $n0$'level_inherited', cardinality(v_inh), 'completion_only', cardinality(v_cmp), 'level_from', v_inf->'inherit',
                                          'course_linked', jsonb_array_length(coalesce(v_inf->'course_links', '[]'::jsonb)))$n0$;
  v_c := (length(v_def) - length(replace(v_def, v_old, ''))) / length(v_old);
  if v_c <> 1 then raise exception '%: edit 1 must apply exactly once (found %)', v_sig, v_c; end if;
  v_def := replace(v_def, v_old, v_new);
  execute v_def;
  raise notice '%: applied, md5 now %', v_sig, md5(pg_get_functiondef('security.aer_matrix_machine_check_v1(uuid)'::regprocedure));
end $ch$;

do $ad$
declare v_sig constant text := 'security.aer_matrix_machine_admit_v1(uuid, text)'; v_before constant text := 'debe928ff881340e4712606d34e3e61d';
        v_def text := pg_get_functiondef('security.aer_matrix_machine_admit_v1(uuid, text)'::regprocedure); v_old text; v_new text; v_c int;
begin
  if v_def like '%S741 (19 Nov 2026%' then raise notice '%: already applied', v_sig; return; end if;
  if md5(v_def) <> v_before then raise exception '% differs from the definition this change edits (md5 %)', v_sig, md5(v_def); end if;
  v_old := $o0$  update catalogue.provider_entry_matrix m set provenance = coalesce(m.provenance, '{}'::jsonb) || jsonb_build_object('completion_only', true, 'completion_rule', 'S671'), updated_at = now()$o0$;
  v_new := $n0$  -- S741 (19 Nov 2026): a row the machine check linked to one catalogue course takes it, only where it has none (never overwritten); the identity trigger re-keys it
  update catalogue.provider_entry_matrix m set course_id = (l->>'course_id')::uuid, provenance = coalesce(m.provenance, '{}'::jsonb) || jsonb_build_object('course_from', l), updated_at = now()
    from jsonb_array_elements(coalesce(v_inf->'course_links', '[]'::jsonb)) l
   where m.id = (l->>'id')::uuid and m.run_id = v_run and m.status = 'proposed' and m.course_id is null and not (m.id = any(v_ex));
  update catalogue.provider_entry_matrix m set provenance = coalesce(m.provenance, '{}'::jsonb) || jsonb_build_object('completion_only', true, 'completion_rule', 'S671'), updated_at = now()$n0$;
  v_c := (length(v_def) - length(replace(v_def, v_old, ''))) / length(v_old);
  if v_c <> 1 then raise exception '%: edit 1 must apply exactly once (found %)', v_sig, v_c; end if;
  v_def := replace(v_def, v_old, v_new);
  execute v_def;
  raise notice '%: applied, md5 now %', v_sig, md5(pg_get_functiondef('security.aer_matrix_machine_admit_v1(uuid, text)'::regprocedure));
end $ad$;

comment on function security.aer_matrix_machine_exclusions_v1(uuid) is 'CF-247 matrix machine row rules (S671 18 Nov, S741 19 Nov 2026): the proposed rows of one read that fail a row rule, with the rows given a level from the heading, completion-only rows (read without the English-language clause, aer.matrix_completion_clauses_on) and course rows linked by printed title or printed award (aer.matrix_course_link_rules_on, never a twin).';

-- 3 audit ---------------------------------------------------------------------------------------------------------------------------------------
insert into pipeline.admin_control_events(area, action, target, detail)
select 'aer', 'matrix_machine_rules', 'security.aer_matrix_machine_exclusions_v1',
       jsonb_build_object('change', 'completion rows read without the English clause; course rows linked by printed title or printed award; twins never linked',
                          'settings', jsonb_build_array('aer.matrix_completion_clauses_on', 'aer.matrix_course_link_rules_on', 'aer.matrix_course_link_awards'),
                          'authority', 'Platform Admin 19 Nov 2026 05:42 (S2-BOOST-AER)', 'migration', '20261119052500')
 where not exists (select 1 from pipeline.admin_control_events e where e.area = 'aer' and e.action = 'matrix_machine_rules' and e.detail->>'migration' = '20261119052500');

-- 4 the matrix validation on the edited rule (it must pass; the mode is not touched) -------------------------------------------------------------
do $val$
declare v jsonb; vid bigint; t timestamptz := clock_timestamp();
begin
  if exists (select 1 from pipeline.admin_control_events e where e.area = 'aer' and e.action = 'matrix_machine_validate' and e.detail->>'migration' = '20261119052500') then
    raise notice 'S741: validation already recorded'; return; end if;
  v := security.aer_matrix_machine_validate_v1();
  if not coalesce((v->>'passed')::boolean, false) then raise exception 'S741: the matrix validation did not pass on the edited rule: %', left(v::text, 600); end if;
  select max(id) into vid from pipeline.aer_matrix_machine_validations;
  insert into pipeline.admin_control_events(area, action, target, detail)
  values ('aer', 'matrix_machine_validate', 'aer.matrix_machine_mode', (v - 'history') || jsonb_build_object('validation_id', vid,
          'history', (v->'history') - 'disagreements', 'secs', round(extract(epoch from clock_timestamp() - t)::numeric, 1),
          'authority', 'Platform Admin 19 Nov 2026 05:42 (S2-BOOST-AER)', 'by', 'Integration Controller', 'migration', '20261119052500'));
  raise notice 'S741: matrix validation % passed', vid;
end $val$;

-- 5 post-checks ---------------------------------------------------------------------------------------------------------------------------------
do $p$
begin
  if pg_catalog.pg_get_functiondef('security.aer_matrix_machine_exclusions_v1(uuid)'::regprocedure) not like '%S741 (19 Nov 2026, aer.matrix_course_link_rules_on)%'
     or pg_catalog.pg_get_functiondef('security.aer_matrix_machine_admit_v1(uuid,text)'::regprocedure) not like '%S741 (19 Nov 2026): a row the machine check linked%'
     or pg_catalog.pg_get_functiondef('security.aer_matrix_machine_check_v1(uuid)'::regprocedure) not like '%''course_linked''%' then
    raise exception 'post-check: S741 edits missing';
  end if;
  if security.pipeline_num_v1('aer.matrix_machine_min_confidence', -1) <> 0.9 or security.pipeline_num_v1('aer.machine_min_quote_chars', -1) <> 8
     or security.pipeline_num_v1('aer.machine_min_confidence', -1) <> 0.8 then
    raise exception 'post-check: AER v1 thresholds must stay unchanged (Decision 276)';
  end if;
  if (select count(*) from security.consumer_api_functions_v1()) <> 75 or (select count(*) from security.consumer_api_relations_v1()) <> 48 then
    raise exception 'post-check: G3 must stay 75 functions and 48 relations';
  end if;
end $p$;
