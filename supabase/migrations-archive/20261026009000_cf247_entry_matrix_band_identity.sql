-- CF-247 AER v1.1, RMIT benchmark-band fix (Platform Admin 26 Oct 2026 22:50: "Build and release the narrow RMIT benchmark-band fix").
-- Record: admin docs/platform/aer-v1.1-build-log.md. The re-read of 26 Oct 22:4x gave all 59 RMIT rows (quote parity held) but no benchmark
-- band on any of them, so rows of one level and qualification shared an identity (Bangladesh 11 rows, 3 identities). Worker v0.48.2 now
-- keeps the band each quoted table line prints and drops a row that shows a band it did not give (band_missing). Two database edits:
-- 1 Row identity (security.entry_matrix_identity_tg, md5-guarded): the row's own level label counts as one of its condition keys, as its
--   qualification name already does (#706). RMIT's "Foundation Studies" and "University Pathways Fast Track" both map to the foundation
--   study level and carry no band, so with the band alone Bangladesh would still give 10 identities for 11 published rows. The hash
--   function, its inputs and the status values are unchanged; the key is "level: <label>" so it cannot meet a qualification name.
-- 2 Approval guard (security.entry_matrix_review_apply_v1, md5-guarded): a run whose proposed rows share an identity is not admitted (the
--   approval raises; nothing changes), so rows that lost their band or level can never be made active.
-- Replaces: nothing (two functions edited in place, md5-guarded)
-- Retires: nothing
-- Nothing dropped, deleted or renamed. The consumer API is not touched (no consumer function reads these tables).

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

select pg_temp.edit_n('security.entry_matrix_identity_tg()', '86ddafc3140eab8bea505295bb2b5bea', array[
  array[$o$  new.row_hash := security.entry_matrix_row_hash_v1(new.provider_id, new.course_id, new.country_code, new.study_level_id, new.benchmark_band, new.qualification_name, new.conditions);$o$,
        $n$  -- RMIT band fix (26 Oct 2026): the level label is one of the row's condition keys (two levels can map to one study level)
  new.row_hash := security.entry_matrix_row_hash_v1(new.provider_id, new.course_id, new.country_code, new.study_level_id, new.benchmark_band, new.qualification_name,
    (case when jsonb_typeof(new.conditions) = 'array' then new.conditions else '[]'::jsonb end)
    || case when nullif(btrim(new.level_label), '') is not null then jsonb_build_array(jsonb_build_object('key', 'level: ' || btrim(new.level_label))) else '[]'::jsonb end);$n$]], array[1]);

select pg_temp.edit_n('security.entry_matrix_review_apply_v1(uuid,text,jsonb,text,uuid)', 'e3f02aaa014afe4dd64946af0b3e44cf', array[
  array[$o$    v_ex := coalesce(array(select jsonb_array_elements_text(coalesce(p_final->'exclude_row_ids', '[]'::jsonb))::uuid), '{}');$o$,
        $n$    v_ex := coalesce(array(select jsonb_array_elements_text(coalesce(p_final->'exclude_row_ids', '[]'::jsonb))::uuid), '{}');
    -- RMIT band fix (26 Oct 2026): rows of one run that share an identity (a lost band or level) are never admitted
    if exists (select 1 from catalogue.provider_entry_matrix m where m.run_id = r.id and m.status = 'proposed' and not (m.id = any(v_ex))
                group by m.row_hash having count(*) > 1) then
      raise exception 'entry matrix run %: proposed rows share an identity; nothing admitted', r.id using errcode = '23505';
    end if;$n$]], array[1]);
