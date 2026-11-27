-- CF-247 s995 (S2-RM-Design; Platform Admin 23 Nov 2026 18:22 AEDT, Step 2: "Pull & Execute Step 2 Items #2 & #3 (CDU, UWA, Victoria University,
-- Macquarie - 472 waiting rows) ... process the waiting proposed tables ... on AER v2 against stored artifacts ($0 Firecrawl, $0 unapproved AI,
-- preserving Decision 276's AER v1 freeze and keeping 0.8 confidence + 5% audit sample)").
-- Measured live 23 Nov 2026 18:40 to 19:30 AEDT (rolled-back read-backs; head 20261123190000). The 472 rows are university-wide entry-matrix rows of
-- six Layer 4 entry_matrix_first_run reads (12 Nov 2026). What stops each read (security.aer_matrix_machine_check_v1 and its exclusions):
--   UWA (194 rows, all_rows_held): every row is excluded only as level_unmapped. Every row has a minimum, its minimum in its quote, confidence of at
--     least 0.9 and a quote of at least 8 characters. The page ("International and overseas qualifications") is an ATAR-equivalence table: 178 rows
--     are band_ladder rows and 154 quotes name the ATAR ("Indian School Certificate Average: 90 | ATAR Equivalent: 95"). Neither its heading nor its
--     address names a level, so the S671 rule (level printed over the table) cannot give one.
--   CDU (45 rows, gate_incomplete): 44 rows would pass every rule but level; the page states no level (heading "Entry requirements", no ATAR, no
--     undergraduate wording) and 4 published rows were dropped (band_not_in_quote). Stays with a person.
--   Macquarie (3 reads; 107 rows): the undergraduate and pathways PDFs were read with their minimum column missing (1 of 46 and 16 of 61 rows carry a
--     minimum; Gao Kao and IB rows dropped as quote_not_on_page): a reader problem, not a level rule. Stays with a person.
--   Victoria University (126 rows, host_shared): two provider records share vu.edu.au. Stays with a person (identity).
-- What changes (in place, md5-guarded; one new setting; no new table, job or function; no consumer object):
--   security.aer_matrix_machine_exclusions_v1 gains a second source for the inherited level. When neither the heading nor the address names a
--   level (the S671 rule finds no level word), the read's rows take the bachelor level when the table itself states its benchmark is the ATAR: at
--   least aer.matrix_atar_table_share (0.5) of its proposed rows are band_ladder rows whose quote names the ATAR, the ATAR being the undergraduate
--   entry rank. As with S671, no row may carry a printed level other than "Year 12 equivalent", the level must be in aer.matrix_level_inherit_codes,
--   and aer.matrix_level_inherit_on switches both off. The inherit answer names its rule ('S995 ATAR is the table''s benchmark ...').
--   Every other row rule is unchanged (aer.matrix_machine_min_confidence 0.9, quote length, minimum in the quote, completeness gate D-R3, host
--   checks, manual locks), so the unchanged machine admission (aer_matrix_machine_admit_v1 and the partial pass of aer_partial_admit_v1) decides.
-- Live on deploy. AER v1 readers untouched (Decision 276): no reader, word list or recovery path; an admission rule over an existing read.
-- G1: no job. G2: aer.matrix_atar_table_share is a setting (label, range, unit, used_by). G3: 75/48 before and after. Manual locks untouched.
-- aer.machine_min_confidence (0.8) and aer.machine_audit_pct (5) untouched. $0. Nothing dropped.
-- Replaces: the inherited-level CTE (lvl) of security.aer_matrix_machine_exclusions_v1 and the rule name in its inherit answer.
-- Retires: nothing.
set local lock_timeout = '5s';  -- fixed: lock wait for the function edit

do $g$
declare v jsonb := security.consumer_api_check_v1();
begin
  if jsonb_array_length(coalesce(v->'drift', '[]'::jsonb)) <> 0 or (v->>'functions')::int <> 75 or (v->>'relations')::int <> 48 then
    raise exception 'guard: the consumer API is not at its baseline before this change: %', v;
  end if;
end $g$;
create temp table s995_base on commit drop as
  select (select count(*) from pipeline.manual_locks) locks, (select count(*) from cron.job where active) jobs,
         (select value from pipeline.platform_toolset_settings where key = 'aer.machine_min_confidence') conf,
         (select value from pipeline.platform_toolset_settings where key = 'aer.machine_audit_pct') audit,
         (select count(*) from catalogue.provider_entry_matrix where status = 'active') active_matrix;

insert into pipeline.platform_toolset_settings (toolset_key, key, label, help, kind, value, min_value, max_value, unit, sort, section, used_by, reason) values
 ('pipeline', 'aer.matrix_atar_table_share', 'Entry requirements: share of ATAR rows that makes a table undergraduate',
  'When an entry-matrix read names no level in its heading or address, its rows take the bachelor level if at least this share of them are band rows whose quote names the ATAR (the undergraduate entry rank). 0.5 means half.',
  'number', '0.5'::jsonb, 0.5, 1, 'share', 1498, 'Entry requirements', 'security.aer_matrix_machine_exclusions_v1 (S995 inherited level)',
  'CF-247 s995 (Platform Admin 23 Nov 2026 18:22): AER v2 level from the table''s own ATAR benchmark')
on conflict (toolset_key, key) do nothing;

do $e$
declare r record; v_def text; v_src text; v_n int;
begin
  for r in select * from (values
    (1, 'security.aer_matrix_machine_exclusions_v1(uuid)', '51ad50c58c2f0db1712310a761e8d99b', $o1$  lvl as materialized (select case when cfg.inh_on and (select count(*) from words) = 1 and cfg.inh_codes ? (select min(w.code) from words w)
                                    and not exists (select 1 from m0 where m0.level_label is not null and not m0.eqv)
                                    and not exists (select 1 from q0 where q0.level_label is not null and not q0.eqv)
                               then (select (array_agg(w.id))[1] from words w) end id,
                              (select min(w.code) from words w) code, (select run.heading from run) heading, (select run.slug from run) slug
                         from cfg),$o1$, $n1$  -- s995 (AER v2, Decision 276 section 9; Platform Admin 23 Nov 2026 18:22): a table whose own benchmark is the ATAR (the undergraduate entry rank)
  atar as materialized (select (select count(*) from m0) > 0
                               and (select count(*) from m0 where m0.matrix_kind = 'band_ladder' and m0.quote ~* '\mATAR\M')
                                   >= security.pipeline_num_v1('aer.matrix_atar_table_share', 0.5) * (select count(*) from m0) yes),
  lvl as materialized (select case when cfg.inh_on and (select count(*) from words) = 1 and cfg.inh_codes ? (select min(w.code) from words w)
                                    and not exists (select 1 from m0 where m0.level_label is not null and not m0.eqv)
                                    and not exists (select 1 from q0 where q0.level_label is not null and not q0.eqv)
                               then (select (array_agg(w.id))[1] from words w)
                               when cfg.inh_on and (select count(*) from words) = 0 and cfg.inh_codes ? 'bachelor' and atar.yes
                                    and not exists (select 1 from m0 where m0.level_label is not null and not m0.eqv)
                                    and not exists (select 1 from q0 where q0.level_label is not null and not q0.eqv)
                               then (select l.id from ref.study_levels l where l.code = 'bachelor') end id,
                              coalesce((select min(w.code) from words w), case when atar.yes then 'bachelor' end) code, (select run.heading from run) heading, (select run.slug from run) slug,
                              case when (select count(*) from words) = 1 then 'S671 level printed over the table' else 'S995 ATAR is the table''s benchmark (undergraduate entry rank)' end rule
                         from cfg, atar),$n1$),
    (2, 'security.aer_matrix_machine_exclusions_v1(uuid)', null, $o2$'rule', 'S671 level printed over the table',$o2$, $n2$'rule', lvl.rule,$n2$)
  ) v(n, sig, md5, old, new) order by n
  loop
    v_def := pg_get_functiondef(r.sig::regprocedure); v_src := (select prosrc from pg_proc where oid = r.sig::regprocedure);
    if position(r.new in v_def) > 0 then raise notice 's995 edit %: already applied', r.n; continue; end if;
    if r.md5 is not null and md5(v_src) <> r.md5 then raise exception 'guard: % differs from the definition this change edits (live md5 %)', r.sig, md5(v_src); end if;
    v_n := (length(v_def) - length(replace(v_def, r.old, ''))) / length(r.old);
    if v_n <> 1 then raise exception 'guard: the fragment of % (edit %) is found % times', r.sig, r.n, v_n; end if;
    execute replace(v_def, r.old, r.new);
  end loop;
end $e$;

do $p$
declare v jsonb := security.consumer_api_check_v1(); b record;
begin
  select * into b from pg_temp.s995_base;
  if jsonb_array_length(coalesce(v->'drift', '[]'::jsonb)) <> 0 or (v->>'functions')::int <> 75 or (v->>'relations')::int <> 48 then
    raise exception 'post-check: the consumer API moved: %', v;
  end if;
  if (select count(*) from pipeline.manual_locks) <> b.locks then raise exception 'post-check: manual locks changed'; end if;
  if (select count(*) from cron.job where active) <> b.jobs then raise exception 'post-check: active job count changed'; end if;
  if (select value from pipeline.platform_toolset_settings where key = 'aer.machine_min_confidence') is distinct from b.conf
     or (select value from pipeline.platform_toolset_settings where key = 'aer.machine_audit_pct') is distinct from b.audit then
    raise exception 'post-check: a confidence or audit setting changed';
  end if;
  if (select count(*) from catalogue.provider_entry_matrix where status = 'active') <> b.active_matrix then raise exception 'post-check: active matrix rows changed during the migration'; end if;
  if position('S995 ATAR is the table' in pg_get_functiondef('security.aer_matrix_machine_exclusions_v1(uuid)'::regprocedure)) = 0
     or position('''rule'', lvl.rule,' in pg_get_functiondef('security.aer_matrix_machine_exclusions_v1(uuid)'::regprocedure)) = 0 then
    raise exception 'post-check: an edit is missing';
  end if;
  insert into pipeline.admin_control_events (area, action, target, detail, actor)
  values ('aer', 'aer_matrix_atar_level', 'security.aer_matrix_machine_exclusions_v1', jsonb_build_object('change', 's995',
          'decision', 'Platform Admin 23 Nov 2026 18:22 AEDT, Step 2'), null);
end $p$;
