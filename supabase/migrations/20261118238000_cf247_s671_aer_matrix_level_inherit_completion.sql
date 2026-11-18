-- CF-247 S671 provider matrix rows: study level from the page heading or file title, "Year N equivalent" labels, and completion-only rows (session S1-AER, Platform Admin standing
--   mandate of 18 Nov 2026 19:28 AEDT, step 2; evidence docs/platform/2026-11-18-aer-held-items-classification.md section 4, admin repo).
-- Guards: G1 (no job), G2 (each new rule is a setting with a reason), G3 (no consumer API object; CREATE OR REPLACE of existing security functions only, no new function or
--   table: 75 functions and 48 relations stay, post-checked), Decision 276 (AER v1 thresholds unchanged: aer.matrix_machine_min_confidence, aer.machine_min_quote_chars,
--   the D-R3 gate, the completeness guard and the apply are not edited), Decision D1 (never infer equivalencies, applicability, eligibility or missing scores).
-- Findings (live, read only, 18 Nov 2026 19:35 to 19:50 AEDT; rolled-back probes): 77 first matrix reads wait; 1,142 of their 3,100 proposed rows have no study level, almost
--   all with no level read at all (the level is printed once over the table, not in the row); 562 have no minimum, mostly completion requirements ("Successful completion
--   of ..."). Rows the reader did map show the platform already maps "undergraduate" to bachelor (security.entry_level_map_v1, 384 active rows).
-- Rules (deterministic, from the stored read only; nothing fetched, no AI):
--   1. Level from the heading or file title. The level words of the read's stored page heading (result.completeness.heading) and of the source address's last path segment
--      (the file title of a PDF) are mapped word by word with security.entry_level_map_v1. When exactly one level is named, it is in aer.matrix_level_inherit_codes
--      (bachelor, masters, doctorate, foundation: "diploma" and "certificate" in a heading are usually the overseas qualification's own name), and no row of the read
--      carries a level of its own, every row with no level read takes that level. The basis is written to the row's provenance (not its conditions, so the row
--      identity is the one the trigger computes from the level). Rows with a level label the platform cannot map are never given one.
--   2. "Year 10/11/12 equivalent" (and "Australian Year N equivalent") labels say what the overseas qualification equals, not the level of study: such a row counts as
--      having no level read (rule 1 may give it the heading's level, with the label kept in provenance as equivalent_to); otherwise it is held as level_equivalence_only.
--   3. Completion-only rows. A row whose minimum is empty (or the words "successful completion"), whose quote states a completion requirement and carries no score
--      (no percentage, no number other than a year, grade, form or level of schooling or a duration, and none of the score words below) is a published requirement
--      with no minimum: it is not held as no_minimum or minimum_not_in_quote, and provenance.completion_only is recorded. Nothing is written into its minimum.
--   The exclusions (security.aer_matrix_machine_exclusions_v1) apply these rules; the check (security.aer_matrix_machine_check_v1) takes the same sets for its row loop and
--   reports them; the admission (security.aer_matrix_machine_admit_v1) writes the inherited level and provenance to the proposed rows just before the unchanged apply, which
--   then runs D-R3, D4 and the completeness guard again on the rows as written. Shadow changes nothing.
-- Live definitions this change edits (md5 of pg_get_functiondef, read 18 Nov 2026 19:36 AEDT by Database function snapshot runs 44268409505 and 44268897760):
--   security.aer_matrix_machine_exclusions_v1(uuid) 48ddc65416bcdcb87dc7a6ea8ecfe9c5 (replaced whole)
--   security.aer_matrix_machine_check_v1(uuid) 590e309e6e795162de19aceafc3b7488 (md5-guarded text edits)
--   security.aer_matrix_machine_admit_v1(uuid,text) 5770adca4ca3ff162a5fbceb6ad1885e (md5-guarded text edit)
-- Then: security.aer_matrix_machine_validate_v1() (md5 162cfa24e35bfcc9100c1bea81c61b6a) runs once and is recorded; its only passing validation (11 Nov 2026 21:48 AEDT)
--   lapses at 21:48 tonight, after which matrix admission would run as shadow. aer.matrix_machine_mode is not changed (already 2).
-- Replaces: security.aer_matrix_machine_exclusions_v1, security.aer_matrix_machine_check_v1, security.aer_matrix_machine_admit_v1 (same names, in place).
-- Retires: nothing.
-- Reversal without code: aer.matrix_level_inherit_on 0 and aer.matrix_completion_only_on 0 restore the rules of 12 Nov exactly; aer.matrix_machine_mode 1 for shadow;
--   an admitted item is reversed by security.aer_matrix_machine_withdraw_v1.

set local statement_timeout = '300s'; -- fixed: the validation re-checks every waiting read; one run, inside the deploy's transaction

-- 0 prerequisites and live md5 ---------------------------------------------------------------------------------------------------------------------
do $g$
declare r record;
begin
  for r in select * from (values ('security.aer_matrix_machine_exclusions_v1(uuid)', '48ddc65416bcdcb87dc7a6ea8ecfe9c5'),
                                 ('security.aer_matrix_machine_check_v1(uuid)', '590e309e6e795162de19aceafc3b7488'),
                                 ('security.aer_matrix_machine_admit_v1(uuid,text)', '5770adca4ca3ff162a5fbceb6ad1885e'),
                                 ('security.aer_matrix_machine_validate_v1()', '162cfa24e35bfcc9100c1bea81c61b6a')) v(sig, md5) loop
    if to_regprocedure(r.sig) is null then raise exception 'S671: % is missing', r.sig; end if;
    if md5(pg_catalog.pg_get_functiondef(to_regprocedure(r.sig))) <> r.md5
       and not (pg_catalog.pg_get_functiondef(to_regprocedure(r.sig)) like '%S671%') then
      raise exception 'S671: % differs from the definition this change edits (md5 %, live %)', r.sig, r.md5, md5(pg_catalog.pg_get_functiondef(to_regprocedure(r.sig)));
    end if;
  end loop;
  if to_regprocedure('security.entry_level_map_v1(text)') is null or to_regprocedure('security.entry_matrix_row_hash_v1(uuid,uuid,text,uuid,text,text,jsonb)') is null then
    raise exception 'S671: needs security.entry_level_map_v1 and security.entry_matrix_row_hash_v1';
  end if;
end $g$;

-- 1 settings (G2) -----------------------------------------------------------------------------------------------------------------------------------
insert into pipeline.platform_toolset_settings(toolset_key, key, label, help, kind, value, min_value, max_value, unit, sort, section, used_by, reason) values
 ('pipeline', 'aer.matrix_level_inherit_on', 'Entry requirements: country tables take the level printed over the table',
  '1: a country-table row with no level read takes the one level named in the stored page heading or the file title, when the read names no level on any row. 0: such rows are held (the rule of 12 Nov 2026).',
  'number', '1'::jsonb, 0, 1, 'on/off', 1496, 'Entry requirements', 'security.aer_matrix_machine_exclusions_v1, security.aer_matrix_machine_admit_v1',
  'CF-247 S671 (Platform Admin standing mandate 18 Nov 2026 19:28, S1-AER step 2): the level is printed once over the table, not in each row'),
 ('pipeline', 'aer.matrix_level_inherit_codes', 'Entry requirements: levels a table heading may give its rows',
  'Study level codes a heading or file title may give to rows with no level read. Diploma and certificate are left out: in a heading they usually name the overseas qualification.',
  'list', '["bachelor", "masters", "doctorate", "foundation"]'::jsonb, null, null, 'study level codes', 1497, 'Entry requirements', 'security.aer_matrix_machine_exclusions_v1',
  'CF-247 S671 (Platform Admin standing mandate 18 Nov 2026 19:28, S1-AER step 2)'),
 ('pipeline', 'aer.matrix_completion_only_on', 'Entry requirements: completion requirements with no score are complete rows',
  '1: a country-table row whose quote states only a completion requirement ("Successful completion of ...") and carries no score is a published requirement with no minimum, not a missing minimum. 0: such rows are held (the rule of 12 Nov 2026).',
  'number', '1'::jsonb, 0, 1, 'on/off', 1498, 'Entry requirements', 'security.aer_matrix_machine_exclusions_v1, security.aer_matrix_machine_check_v1',
  'CF-247 S671 (Platform Admin standing mandate 18 Nov 2026 19:28, S1-AER step 2): "no minimum" is the correct reading of a completion requirement')
on conflict (toolset_key, key) do nothing;

-- 2 exclusions: replaced whole (same name, same signature, same result keys plus the S671 sets) ---------------------------------------------------
create or replace function security.aer_matrix_machine_exclusions_v1(p_run uuid) returns jsonb
language sql stable security definer set search_path to '' as $function$
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
$function$;
comment on function security.aer_matrix_machine_exclusions_v1(uuid) is 'CF-247 F-AER.04 machine Approve except (12 Nov 2026) and S671 (18 Nov 2026): the proposed rows of one entry-matrix read that fail a row rule, by rule; rows with no level read take the one level named in the stored heading or file title (aer.matrix_level_inherit_on, aer.matrix_level_inherit_codes); "Year N equivalent" labels are not a level; completion requirements with no score are not missing minimums (aer.matrix_completion_only_on). Read only.';
revoke all on function security.aer_matrix_machine_exclusions_v1(uuid) from public, anon, authenticated;

-- 3 check and admission: md5-guarded text edits ---------------------------------------------------------------------------------------------------
do $edit$
declare e record; v_def text; v_new text; v_c int;
begin
  for e in select * from (values
    (1, 'security.aer_matrix_machine_check_v1(uuid)',
        $o$v_exids uuid[] := '{}'::uuid[];$o$,
        $n$v_exids uuid[] := '{}'::uuid[]; v_inf jsonb; v_inh uuid[] := '{}'::uuid[]; v_cmp uuid[] := '{}'::uuid[]; -- S671$n$),
    (2, 'security.aer_matrix_machine_check_v1(uuid)',
        $o$  g := security.entry_matrix_gate_v1(r.id, v_exids);$o$,
        $n$  -- S671 (18 Nov 2026): rows that take the level printed over the table, and completion-only rows, are not row failures
  v_inf := security.aer_matrix_machine_exclusions_v1(r.id);
  v_inh := coalesce(array(select jsonb_array_elements_text(v_inf->'level_inherit_ids')::uuid), '{}'::uuid[]);
  v_cmp := coalesce(array(select jsonb_array_elements_text(v_inf->'completion_only_ids')::uuid), '{}'::uuid[]);
  g := security.entry_matrix_gate_v1(r.id, v_exids);$n$),
    (3, 'security.aer_matrix_machine_check_v1(uuid)',
        $o$                when m.study_level_id is null then 'level_unmapped'$o$,
        $n$                when m.study_level_id is null and not (m.id = any(v_inh)) then 'level_unmapped'$n$),
    (4, 'security.aer_matrix_machine_check_v1(uuid)',
        $o$                when not ((m.min_value is not null and coalesce(m.grade_scale, 'none') <> 'none') or nullif(btrim(coalesce(m.min_grade, '')), '') is not null) then 'no_minimum'
                when not security.aer_quote_has_value_v1(m.quote, m.min_grade, m.min_value) then 'minimum_not_in_quote' end why$o$,
        $n$                when not (m.id = any(v_cmp)) and not ((m.min_value is not null and coalesce(m.grade_scale, 'none') <> 'none') or nullif(btrim(coalesce(m.min_grade, '')), '') is not null) then 'no_minimum'
                when not (m.id = any(v_cmp)) and not security.aer_quote_has_value_v1(m.quote, m.min_grade, m.min_value) then 'minimum_not_in_quote' end why$n$),
    (5, 'security.aer_matrix_machine_check_v1(uuid)',
        $o$                when length(btrim(coalesce(q.quote, ''))) < v_qmin then 'short_quote' when q.study_level_id is null then 'level_unmapped'
                when not ((q.min_value is not null and coalesce(q.grade_scale, 'none') <> 'none') or nullif(btrim(coalesce(q.min_grade, '')), '') is not null) then 'no_minimum'
                when not security.aer_quote_has_value_v1(q.quote, q.min_grade, q.min_value) then 'minimum_not_in_quote' end$o$,
        $n$                when length(btrim(coalesce(q.quote, ''))) < v_qmin then 'short_quote' when q.study_level_id is null and not (q.id = any(v_inh)) then 'level_unmapped'
                when not (q.id = any(v_cmp)) and not ((q.min_value is not null and coalesce(q.grade_scale, 'none') <> 'none') or nullif(btrim(coalesce(q.min_grade, '')), '') is not null) then 'no_minimum'
                when not (q.id = any(v_cmp)) and not security.aer_quote_has_value_v1(q.quote, q.min_grade, q.min_value) then 'minimum_not_in_quote' end$n$),
    (6, 'security.aer_matrix_machine_check_v1(uuid)',
        $o$  v_checks := v_checks || jsonb_build_object('rows', v_nm, 'qualification_rows', v_nq, 'host', v_sh, 'min_confidence', v_conf)$o$,
        $n$  v_checks := v_checks || jsonb_build_object('rows', v_nm, 'qualification_rows', v_nq, 'host', v_sh, 'min_confidence', v_conf,
                                          'level_inherited', cardinality(v_inh), 'completion_only', cardinality(v_cmp), 'level_from', v_inf->'inherit')$n$),
    (7, 'security.aer_matrix_machine_admit_v1(uuid,text)',
        $o$        v_sys uuid := security.system_actor_id(); v_run uuid; v_after int;$o$,
        $n$        v_sys uuid := security.system_actor_id(); v_run uuid; v_after int; v_inf jsonb; v_ex uuid[]; -- S671$n$),
    (8, 'security.aer_matrix_machine_admit_v1(uuid,text)',
        $o$  v_res := security.entry_matrix_review_apply_v1(p_item, 'approve', jsonb_build_object('reviewer', 'aer-matrix-machine-v1',$o$,
        $n$  -- S671 (18 Nov 2026): the level printed over the table is written to the rows that take it, with its basis, before the unchanged apply (which runs D-R3, D4 and
  -- the completeness guard again on the rows as written); completion-only rows are marked in provenance; nothing is written into a minimum
  v_inf := security.aer_matrix_machine_exclusions_v1(v_run);
  v_ex := coalesce(array(select jsonb_array_elements_text(coalesce(v->'checks'->'exclude_row_ids', '[]'::jsonb))::uuid), '{}'::uuid[]);
  if v_inf->'inherit' is not null and jsonb_array_length(coalesce(v_inf->'level_inherit_ids', '[]'::jsonb)) > 0 then
    update catalogue.provider_entry_matrix m set study_level_id = (v_inf->'inherit'->>'study_level_id')::uuid,
           provenance = coalesce(m.provenance, '{}'::jsonb) || jsonb_build_object('level_from', v_inf->'inherit')
                        || case when m.level_label is not null then jsonb_build_object('equivalent_to', m.level_label) else '{}'::jsonb end,
           updated_at = now()
     where m.run_id = v_run and m.status = 'proposed' and m.study_level_id is null and not (m.id = any(v_ex))
       and m.id in (select jsonb_array_elements_text(v_inf->'level_inherit_ids')::uuid);
    update catalogue.provider_qualification_requirements q set study_level_id = (v_inf->'inherit'->>'study_level_id')::uuid,
           provenance = coalesce(q.provenance, '{}'::jsonb) || jsonb_build_object('level_from', v_inf->'inherit')
                        || case when q.level_label is not null then jsonb_build_object('equivalent_to', q.level_label) else '{}'::jsonb end,
           updated_at = now()
     where q.run_id = v_run and q.status = 'proposed' and q.study_level_id is null and not (q.id = any(v_ex))
       and q.id in (select jsonb_array_elements_text(v_inf->'level_inherit_ids')::uuid);
  end if;
  update catalogue.provider_entry_matrix m set provenance = coalesce(m.provenance, '{}'::jsonb) || jsonb_build_object('completion_only', true, 'completion_rule', 'S671'), updated_at = now()
   where m.run_id = v_run and m.status = 'proposed' and not (m.id = any(v_ex)) and m.id in (select jsonb_array_elements_text(coalesce(v_inf->'completion_only_ids', '[]'::jsonb))::uuid);
  update catalogue.provider_qualification_requirements q set provenance = coalesce(q.provenance, '{}'::jsonb) || jsonb_build_object('completion_only', true, 'completion_rule', 'S671'), updated_at = now()
   where q.run_id = v_run and q.status = 'proposed' and not (q.id = any(v_ex)) and q.id in (select jsonb_array_elements_text(coalesce(v_inf->'completion_only_ids', '[]'::jsonb))::uuid);
  v_res := security.entry_matrix_review_apply_v1(p_item, 'approve', jsonb_build_object('reviewer', 'aer-matrix-machine-v1',$n$)
  ) v(n, sig, old, new) order by n loop
    v_def := pg_catalog.pg_get_functiondef(to_regprocedure(e.sig));
    if v_def like '%' || e.new || '%' then raise notice 'S671 edit %: already applied', e.n; continue; end if;
    v_c := (length(v_def) - length(replace(v_def, e.old, ''))) / length(e.old);
    if v_c <> 1 then raise exception 'S671 edit % on %: the text to replace occurs % times; the edit must apply exactly once', e.n, e.sig, v_c; end if;
    v_new := replace(v_def, e.old, e.new);
    execute v_new;
  end loop;
end $edit$;
comment on function security.aer_matrix_machine_check_v1(uuid) is 'CF-247 F-AER.04 (decision D1; Approve except 12 Nov 2026; S671 18 Nov 2026): rule aer-matrix-machine-v1 for one entry-matrix Layer 4 item: ok only for a never-decided first read of the provider''s own official source whose rows are source-proved with a published minimum (or a completion requirement with no score), a mapped level (or the one level printed over the table) and explicit applicability; otherwise the reason it stays with a person. Read only.';

-- 4 matrix validation refreshed (aer.matrix_machine_mode is not changed) -----------------------------------------------------------------------------
do $val$
declare v jsonb; vid bigint; t timestamptz := clock_timestamp();
begin
  v := security.aer_matrix_machine_validate_v1();
  select max(id) into vid from pipeline.aer_matrix_machine_validations;
  insert into pipeline.admin_control_events(area, action, target, detail)
  values ('aer', 'matrix_machine_validate', 'aer.matrix_machine_mode', (v - 'history') || jsonb_build_object('validation_id', vid,
          'history', (v->'history') - 'disagreements', 'secs', round(extract(epoch from clock_timestamp() - t)::numeric, 1),
          'authority', 'Platform Admin standing mandate 18 Nov 2026 19:28 AEDT (S1-AER step 2)', 'by', 'Integration Controller (migration 20261118238000)'));
  raise notice 'S671: matrix validation % passed=%', vid, v->>'passed';
end $val$;

-- 5 post-checks --------------------------------------------------------------------------------------------------------------------------------------
do $p$
begin
  if pg_catalog.pg_get_functiondef('security.aer_matrix_machine_check_v1(uuid)'::regprocedure) not like '%v_inh := coalesce(array(select jsonb_array_elements_text(v_inf->''level_inherit_ids'')%'
     or pg_catalog.pg_get_functiondef('security.aer_matrix_machine_admit_v1(uuid,text)'::regprocedure) not like '%S671 (18 Nov 2026): the level printed over the table%' then
    raise exception 'post-check: S671 edits missing';
  end if;
  if security.pipeline_num_v1('aer.matrix_machine_min_confidence', -1) <> 0.9 or security.pipeline_num_v1('aer.machine_min_quote_chars', -1) <> 8
     or security.pipeline_num_v1('aer.machine_min_confidence', -1) <> 0.8 then
    raise exception 'post-check: AER v1 thresholds must stay unchanged (Decision 276)';
  end if;
  if (select count(*) from security.consumer_api_functions_v1()) <> 75 or (select count(*) from security.consumer_api_relations_v1()) <> 48 then
    raise exception 'post-check: G3 must stay 75 functions and 48 relations';
  end if;
  -- with both switches off the rules of 12 Nov hold exactly: no row is inherited or completion-only
  if exists (select 1 from pipeline.entry_matrix_runs r join pipeline.layer4_review_items i on i.id = r.review_item_id and i.status = 'pending'
              where security.pipeline_num_v1('aer.matrix_level_inherit_on', 0) < 1 and jsonb_array_length(security.aer_matrix_machine_exclusions_v1(r.id)->'level_inherit_ids') > 0) then
    raise exception 'post-check: inheritance must be off when aer.matrix_level_inherit_on is 0';
  end if;
end $p$;
