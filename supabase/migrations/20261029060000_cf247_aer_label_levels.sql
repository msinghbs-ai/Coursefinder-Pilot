-- CF-247 AER (Platform Admin mandate 29 Oct 2026 12:23, A3; admin docs/platform/AER-OPERATIONS-WORKSPACE-DECISION-2026-10-29.md W19).
-- A published matrix level label can name several levels ("Diploma/Associate degrees"). security.entry_level_map_v1 keeps the first it
-- recognises (Associate degree), so a Diploma course (RMIT DP020) found no row at its level and the resolver said "none for this course's
-- level". security.entry_label_levels_v1 maps each level the label names (split on "/", ",", "&", "and", "or") with the existing mapping;
-- the resolver's rules 3 and 4 and its step-5 explanation, and the workspace's Resolution inspection, match a row whose study_level_id is
-- the course's level OR whose published label names it. Nothing is inferred (the provider printed the level); active rows only; the five
-- rules, the setting entry.level_equivalents and the consumer API shape are unchanged (G3: values change only where a printed label now
-- matches; no function of the consumer API is edited).
-- Replaces: security.entry_resolve_v1, public.admin_aer (same names, md5-guarded edits)
-- Retires: nothing
-- Nothing dropped, deleted or renamed. No new job, table, setting or status.

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

create or replace function security.entry_label_levels_v1(p_label text) returns uuid[]
language sql stable security definer set search_path to '' as $$
  -- every level a published label names, each part mapped with the existing mapping (security.entry_level_map_v1)
  select coalesce(array_agg(distinct z.l) filter (where z.l is not null), '{}'::uuid[])
    from (select security.entry_level_map_v1(btrim(part)) l
            from regexp_split_to_table(coalesce(p_label, ''), '\s*(/|,|&|\mand\M|\mor\M)\s*', 'i') part
          union all select security.entry_level_map_v1(p_label)) z
$$;
revoke all on function security.entry_label_levels_v1(text) from public, anon;
grant execute on function security.entry_label_levels_v1(text) to authenticated;
comment on function security.entry_label_levels_v1(text) is 'CF-247 AER W19 (29 Oct 2026): every study level a published matrix level label names ("Diploma/Associate degrees" gives diploma and associate degree), mapped part by part with security.entry_level_map_v1. Used by the resolver and Resolution inspection.';

select pg_temp.edit_n('security.entry_resolve_v1(uuid,text)', '8281a03fc85dcc1c5be19d86ad3ee3a0', array[
  array[$o$m.study_level_id = any (v_levels)$o$,
        $n$(m.study_level_id = any (v_levels) or security.entry_label_levels_v1(m.level_label) && v_levels)$n$]], array[3]);

select pg_temp.edit_n('public.admin_aer(text,jsonb)', '744cb0173b8ea0f8092d5bcc9a6268b1', array[
  array[$o$m0.study_level_id = any (v_levels)$o$,
        $n$(m0.study_level_id = any (v_levels) or security.entry_label_levels_v1(m0.level_label) && v_levels)$n$]], array[3]);

insert into pipeline.component_register(kind, name, layer, purpose, status, replaces, introduced_in) values
 ('function', 'security.entry_label_levels_v1', 'Pipeline', 'AER W19: every level a published matrix level label names', 'active', '{}', '20261029060000')
on conflict do nothing;
