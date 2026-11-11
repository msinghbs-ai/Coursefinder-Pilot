-- CF-247 F-AER.08 production verification fixes (Platform Admin mandate 12 Nov 2026 09:23: "If production verification fails, create or update the integration issue,
-- correct the root cause and continue autonomously"; decision 1: "Every extracted minimum must map to exactly one course and one qualification").
-- Guards: G1 (no job), G2 (the heading list is a setting), G3 (no consumer API object), Decision 260, Layer 4 authority unchanged.
-- Evidence (production, 12 Nov 2026 10:25-10:45 AEDT; the grid reads of #1052, worker v0.73.0): Sydney 1,869 rows and 178 qualification rows, UQ 1,268 and 162,
--   nothing dropped, every Sydney row linked by CRICOS and 1,150 of 1,268 UQ rows by exact title. The D-R3 gate holds both reads:
--   1. same identity (Sydney 168 groups, 630 rows; UQ 47, 117): a university prints several streams of one catalogue course ("B Science", "B Science (Advanced)",
--      "B Science (Health)", one CRICOS code, different minimums). The row identity holds the course, not the printed course, so the streams collide.
--   2. "qualification named by a column label" (Sydney 89, UQ 49): the ATAR column was read as Australia's row with qualification "ATAR". The ATAR is the course's
--      own rank (the course record holds it; the platform's rule refuses a rank as a qualification's minimum), not a qualification of a country of education.
-- What:
--   1. security.entry_matrix_identity_tg (md5-guarded): a row printed for a course keeps its printed course in its identity (key "course: <label>"), as the level
--      label already is; nothing else changes. Rows without a course label keep their identity.
--   2. reading.entry_grid_headings: "ATAR" and "Tertiary Admission Rank" are course facts (were "=AU").
--   3. The three grid reads are read again from their stored copies (no model, no Firecrawl), skipping any item a person has taken.
-- Live definition this change edits (md5 of pg_get_functiondef, read 12 Nov 2026 08:57 AEDT): security.entry_matrix_identity_tg() 915df18ea188103fbf0f9978bdd25536
-- Replaces: security.entry_matrix_identity_tg (same name; md5-guarded text edit). Retires: nothing.
-- Reversal: reading.entry_grid_headings back to "ATAR=AU"; the identity edit only adds a key for rows that print a course.

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

select pg_temp.edit_n('security.entry_matrix_identity_tg()', '915df18ea188103fbf0f9978bdd25536', array[
  array[$o$jsonb_build_array(jsonb_build_object('key', 'level: ' || btrim(new.level_label))) else '[]'::jsonb end);$o$,
        $n$jsonb_build_array(jsonb_build_object('key', 'level: ' || btrim(new.level_label))) else '[]'::jsonb end
    -- F-AER.08 (12 Nov 2026): the printed course (a stream of one catalogue course has its own minimum)
    || case when nullif(btrim(new.course_label), '') is not null then jsonb_build_array(jsonb_build_object('key', 'course: ' || btrim(new.course_label))) else '[]'::jsonb end);$n$]
], array[1]);

update pipeline.platform_toolset_settings
   set value = (select jsonb_agg(case x when 'ATAR=AU' then 'ATAR=fact' when 'Tertiary Admission Rank=AU' then 'Tertiary Admission Rank=fact' else x end order by n)
                  from jsonb_array_elements_text(value) with ordinality t(x, n)),
       reason = 'F-AER.08 production verification 12 Nov 2026: the ATAR column is the course''s own rank (a course fact), not Australia''s qualification row', updated_at = now()
 where toolset_key = 'pipeline' and key = 'reading.entry_grid_headings' and value ? 'ATAR=AU';

do $r$
declare v jsonb; ids uuid[] := array['b1222e5d-04c2-4964-a574-3630258da766', '1f22a28d-0543-4e59-8d17-f696801a396e', '291cd06c-0232-40ae-9950-15fc1c5d19e4']::uuid[];
begin
  if not (security.toolset_setting('pipeline', 'reading.entry_grid_headings') ? 'ATAR=fact') then raise exception 'post-check: heading list'; end if;
  ids := array(select u from unnest(ids) u where not exists (
           select 1 from pipeline.entry_matrix_runs r join pipeline.layer4_review_items li on li.id = r.review_item_id
            where r.source_id = u and li.status = 'pending' and (li.claimed_at is not null or li.assigned_to is not null)));
  if cardinality(ids) = 0 then raise notice 'every item is taken by a person: nothing read again'; return; end if;
  v := public.admin_entry_matrix_reread(ids, 'F-AER.08 production verification: printed course in the row identity; ATAR read as a course fact (read again from the stored copy)');
  raise notice 'reread: %', v;
  if coalesce((v->>'runs')::int, 0) = 0 then raise exception 'post-check: nothing queued (%)', v; end if;
end $r$;
