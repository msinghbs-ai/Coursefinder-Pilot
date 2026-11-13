-- CF-247 AER: the entry-source attach step checks each provider once, and only for pages not attached yet (Platform Admin 13 Nov 2026 09:30: "If an actual
-- technical bottleneck prevents higher throughput, fix the shared cause through the normal engineering release process").
-- Evidence (13 Nov 2026 11:25 AEDT): job entry-matrix-read (every 5 minutes) took 37 to 86 seconds a run. security.entry_matrix_attach_v1 called
--   security.entry_matrix_attach_allowed_v1 (which builds the whole AER-eligible set, about 140 ms) for every found page, 148 rows a run, although 128 of
--   them were attached already and are skipped by "on conflict do nothing". The same step timed out a Claude-session on-demand cycle (statement timeout).
-- Rolled-back live check: the old step attached 0 pages in 51,335 ms; the new step the same 0 pages in 134 ms.
-- What: security.entry_matrix_attach_v1 (md5-guarded rewrite of the same statement): pages are ranked exactly as before (all found pages of a provider, by
--   score then URL length), then only ranks within entry.attach_per_provider that are not attached yet and whose provider has room are kept, and the
--   allowed check runs once per remaining provider. The pages attached are the same; only the work to find them is smaller.
-- Guards: G2 (no new value), G3 (no consumer API object), Decision 260; nothing deleted.
-- Live definition this change edits (md5 of pg_get_functiondef, read 13 Nov 2026 11:30 AEDT): security.entry_matrix_attach_v1 b2a3fbdc77633618cee0b1914fbdc336.
-- Replaces: the per-row allowed check in security.entry_matrix_attach_v1 (same function). Retires: nothing.

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

select pg_temp.edit_n('security.entry_matrix_attach_v1()', 'b2a3fbdc77633618cee0b1914fbdc336', array[
  array[$o$  select x.provider_id, x.url, x.title, x.rn, 'search'
    from (select s.provider_id, e->>'url' url, left(e->>'title', 200) title,
                 row_number() over (partition by s.provider_id order by (e->>'score')::numeric desc, length(e->>'url')) rn
            from pipeline.provider_central_search s, jsonb_array_elements(coalesce(s.found, '[]'::jsonb)) e
           where e->>'kind' = 'entry_requirements' and e->>'url' ~ '^https?://'
             and coalesce((e->>'score')::numeric, 0) >= security.pipeline_num_v1('central.min_suggest_score', 4)
             and security.entry_matrix_attach_allowed_v1(s.provider_id)) x
   where x.rn <= v_max
     and (select count(*) from pipeline.entry_matrix_sources m where m.provider_id = x.provider_id) < v_max$o$,
        $n$  -- 13 Nov 2026: ranked as before, then only new pages within the rank limit for a provider with room; the allowed check once per provider
  with x as materialized (
         select s.provider_id, e->>'url' url, left(e->>'title', 200) title,
                row_number() over (partition by s.provider_id order by (e->>'score')::numeric desc, length(e->>'url')) rn
           from pipeline.provider_central_search s, jsonb_array_elements(coalesce(s.found, '[]'::jsonb)) e
          where e->>'kind' = 'entry_requirements' and e->>'url' ~ '^https?://'
            and coalesce((e->>'score')::numeric, 0) >= security.pipeline_num_v1('central.min_suggest_score', 4)),
       n as materialized (
         select x.* from x
          where x.rn <= v_max
            and not exists (select 1 from pipeline.entry_matrix_sources m where m.provider_id = x.provider_id and m.url = x.url)
            and (select count(*) from pipeline.entry_matrix_sources m where m.provider_id = x.provider_id) < v_max),
       ok as materialized (select p.provider_id from (select distinct n.provider_id from n) p where security.entry_matrix_attach_allowed_v1(p.provider_id))
  select n.provider_id, n.url, n.title, n.rn, 'search' from n join ok on ok.provider_id = n.provider_id$n$]
], array[1]);
