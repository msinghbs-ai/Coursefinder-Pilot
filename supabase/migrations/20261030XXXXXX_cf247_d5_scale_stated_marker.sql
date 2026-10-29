-- CF-247 D5: additive Website API v2 marker `scale_stated` on entry rows (decision A4, register O9).
-- Consumer API change approved: Platform Admin, 30 Oct 2026 08:45 (decision D5, admin decision §11.2, commit aef0490f): "Implement an additive Website API v2 marker such as scale_stated: false, following the existing G3 process" — no change to existing consumer field meanings or frozen shapes; printed grade and evidence preserved; printed-grade-without-scale distinct from case by case and no published requirement; no inferred scale, percentage, ATAR conversion or band; applied by the Platform Admin as a paste before the PR merges (precedent 20261028005000), never auto-merged
-- Record: admin docs/platform/AER-OPERATIONS-WORKSPACE-DECISION-2026-10-29.md §9 (A4) and §11.2; docs/integrations/WEBSITE-DEVELOPER-REQUIREMENTS.md O9; design note ui-audit/2026-10-30-D5-design-note.md.
--
-- 1. security.entry_matrix_payload_v1 (provider `entry_matrix[]` items) gains one key, `scale_stated`:
--      true  = a printed grade with a stated scale (grade_scale percentage, points, aggregate, gpa, letter or rank);
--      false = a printed grade with no stated scale (min_grade printed, grade_scale null; `scale` is then null, "not held");
--      null  = case by case (min_grade null, or scale 'none'). The key is always present.
-- 2. security.entry_resolve_v1 (course `entry.resolution.rows[]` items): steps 2-4 gain the same `scale_stated`; step 1 (course-page rows,
--    which hold no scale) gains `scale_stated` null; `case_by_case` is made null-safe (grade_scale is not distinct from 'none') so a row with
--    no stated scale is `false`, never JSON null, and the outcome stays minimum_published. For every row stored today the value is identical.
-- 3. The public.website_v2_* functions and every edge function are NOT edited (they already call these two payload parts); wix-course-api
--    passes the provider payload through and gains the key with no code change; Zoho is untouched. The consumer baseline is re-taken.
-- Computed only from the admitted row's min_grade and grade_scale: no text is parsed and nothing is inferred.
-- Self-contained and re-runnable: each edit is md5-guarded (before → after); a second run finds the after-md5 and changes nothing.
-- Replaces: security.entry_matrix_payload_v1, security.entry_resolve_v1 (same names, md5-guarded edits)
-- Retires: nothing
-- Nothing dropped, deleted, renamed or retyped. No new table, column, job, setting or status.

create or replace function pg_temp.edit_once(p_sig text, p_before text, p_after text, p_edits text[][], p_times int[]) returns text language plpgsql as $f$
declare v_def text := pg_get_functiondef(p_sig::regprocedure); i int; v_c int;
begin
  if md5(v_def) = p_after then return p_sig || ': already applied'; end if;
  if md5(v_def) <> p_before then raise exception 'live % differs from the definition this change edits (md5 %)', p_sig, md5(v_def); end if;
  for i in 1 .. array_length(p_edits, 1) loop
    v_c := (length(v_def) - length(replace(v_def, p_edits[i][1], ''))) / length(p_edits[i][1]);
    if v_c <> p_times[i] then raise exception '%: edit % must apply exactly % times (found %)', p_sig, i, p_times[i], v_c; end if;
    v_def := replace(v_def, p_edits[i][1], p_edits[i][2]);
  end loop;
  execute v_def;
  if md5(pg_get_functiondef(p_sig::regprocedure)) <> p_after then
    raise exception '% after the edit has md5 %, expected %', p_sig, md5(pg_get_functiondef(p_sig::regprocedure)), p_after;
  end if;
  return p_sig || ': applied';
end $f$;

-- ---------------------------------------------------------------- count guard (before)
do $$
begin
  -- before the marker exists, no matrix row may hold a null scale: `false` must only ever come from a person's recording (R1)
  if position('scale_stated' in pg_get_functiondef('security.entry_matrix_payload_v1(uuid,text)'::regprocedure)) = 0
     and (select count(*) from catalogue.provider_entry_matrix where grade_scale is null) <> 0 then
    raise exception 'count guard: % matrix rows hold a null scale before the marker exists', (select count(*) from catalogue.provider_entry_matrix where grade_scale is null);
  end if;
end $$;

-- ---------------------------------------------------------------- 1: provider entry_matrix items
select pg_temp.edit_once('security.entry_matrix_payload_v1(uuid,text)', 'be5478d0402620cbc4c701a1e590856e', 'c1f83b82ce5c0b4b934f620a9864710f', array[
  array[$o$'band', m.benchmark_band, 'conditions', m.conditions, 'as_at', m.as_at)$o$,
        $n$'band', m.benchmark_band, 'conditions', m.conditions, 'as_at', m.as_at,
           -- CF-247 D5 (decision A4): additive; true stated scale, false printed grade with no stated scale, null case by case
           'scale_stated', case when m.min_grade is null or m.grade_scale = 'none' then null else m.grade_scale is not null end)$n$]], array[1]);

-- ---------------------------------------------------------------- 2: course entry.resolution rows
select pg_temp.edit_once('security.entry_resolve_v1(uuid,text)', '492ece033520ad81cd0046c5a851bedb', '74d48db0de885e69cd98db374547b22e', array[
  array[$o$'quote', r.quote, 'as_at', r.as_at, 'case_by_case', r.min_grade is null and r.min_entry_score is null)$o$,
        $n$'quote', r.quote, 'as_at', r.as_at, 'case_by_case', r.min_grade is null and r.min_entry_score is null,
                                      -- CF-247 D5: course-page rows hold no scale
                                      'scale_stated', null::boolean)$n$],
  array[$o$'case_by_case', m.min_grade is null or m.grade_scale = 'none')$o$,
        $n$'case_by_case', m.min_grade is null or m.grade_scale is not distinct from 'none',
                                        -- CF-247 D5 (decision A4): additive; true stated scale, false printed grade with no stated scale, null case by case
                                        'scale_stated', case when m.min_grade is null or m.grade_scale = 'none' then null else m.grade_scale is not null end)$n$]], array[1, 1]);

comment on function security.entry_matrix_payload_v1(uuid, text) is 'CF-247 Track C Step B (B2): the provider payload''s entry_matrix from active matrix rows, optionally one country. D5 (30 Oct 2026): each item carries scale_stated (true stated scale, false printed grade with no stated scale, null case by case).';
comment on function security.entry_resolve_v1(uuid, text) is 'CF-247 Track C Step B: the five-rule entry resolution (course override → per-course country row → band ladder → provider minimum → contact the provider) over active rows; case by case kept; pure lookup. D5 (30 Oct 2026): each row carries scale_stated (null for course-page rows and case by case).';

-- ---------------------------------------------------------------- count guard (after): every active matrix row reaches the payload with the key
do $$
declare v_rows int; v_items int; v_keyed int;
begin
  select count(*) into v_rows from catalogue.provider_entry_matrix where status = 'active';
  select coalesce(sum(jsonb_array_length(p.j)), 0), coalesce(sum((select count(*) from jsonb_array_elements(p.j) e where e ? 'scale_stated')), 0)
    into v_items, v_keyed
    from (select security.entry_matrix_payload_v1(z.provider_id, null) j from (select distinct provider_id from catalogue.provider_entry_matrix where status = 'active') z) p;
  if v_items <> v_rows or v_keyed <> v_rows then
    raise exception 'count guard: % active matrix rows, % payload items, % with scale_stated', v_rows, v_items, v_keyed;
  end if;
  raise notice 'D5: % active matrix rows carry scale_stated', v_rows;
end $$;

-- ---------------------------------------------------------------- 3: the consumer baseline re-taken (approved change)
select security.consumer_api_rebaseline_v1('D5 (30 Oct 2026): additive scale_stated on entry_matrix items and entry.resolution rows (security.entry_matrix_payload_v1, security.entry_resolve_v1); approved Platform Admin 30 Oct 2026 08:45, admin decision §11.2');
