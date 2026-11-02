-- CF-247 integration issue IQ-00055 (P2): the provider description picker within its time-out (v2.15.410 regression).
-- Why (live, read-only, 3 Nov 2026 AEDT): since v2.15.410 (the page rule, 20261102130000) public.svc_provider_description_next hits the
--   statement time-out, so the provider-description-read job claims nothing (the three re-queued pilot reads, CDU, Monash and ACU, stay queued)
--   while the scheduler says "succeeded". security.provider_description_stored_v1 ran the page rule (security.provider_description_page_v1) for
--   every stored evidence copy of the provider, twice (in the filter and again in the order): measured 0.85-1.2 s for CDU (621 copies),
--   1.2-1.7 s ACU (660), 2.8-3.8 s Monash (2,089), 2.7-5.2 s Wollongong (1,367) and 6.6-10.7 s Queensland (3,856); the picker then looked the
--   stored copy up again for each claimed row and ran the page rule twice for each central page finder suggestion. The worker's statement
--   time-out is 8 s (authenticator), so three claimed rows (CDU, Monash, ACU) cannot fit.
-- What (the page chosen is unchanged; only the work to choose it):
--   * stored_v1: a cheap prefilter from the page rule's own lists (pdesc.about_patterns, pdesc.about_prefixes; no new value): a copy is checked
--     only when its address contains "/<About page name>" or "/<About prefix>" somewhere. The page rule passes only an address whose first path
--     part is such a name or starts with such a prefix, so every address it passes also passes the prefilter (the prefilter only skips addresses
--     the rule refuses). The prefilter runs first (LIKE with the words escaped) and the other checks only on what it keeps; then one of the
--     first two path parts (read as the page rule reads the path) must be such a name or start with such a prefix, as the rule's About part is
--     the first part or the second after a language part, and the path has at most pdesc.about_max_segments parts plus a language part
--     (live 3 Nov 2026: Waikato has 735 stored copies under /about/calendar/..., all refused by the rule for their length). The oldest capture
--     kept (pdesc.source_max_age_days) is read once, not once per copy. The page rule then runs once per remaining copy (a lateral, offset 0 so
--     it is not repeated), and the same order picks it. New logic measured on live (read-only, 3 Nov 2026 10:16 AEDT, run before the old one):
--     CDU 31 ms, ACU 19 ms, Monash 72 ms, Wollongong 188 ms, Queensland 429 ms (cold; 226-250 ms on other runs).
--   * svc_provider_description_next: stored_v1 is computed once per claimed row (a lateral) for the stored copy; the pick filter calls it only
--     when pdesc.acquire_direct is below 1 (a CASE, so it is never evaluated while direct acquisition is on); the page rule runs once per
--     central page finder suggestion (a lateral) for both the filter and the order.
-- Proof of equivalence: the old live stored_v1 and the new logic, compared read-only on live (3 Nov 2026 09:26-10:18 AEDT): the five pilot
--   providers (same choice; CDU 7e303cdd-985b-4260-9cf4-d55aa3aea025, the other four none), 50 other providers with stored copies (same choice
--   for 50 of 50; 3 with a copy) and 10 other Australian universities (10 of 10). The fixture run (tests/fixtures/pdesc-picker-perf/run.sh)
--   records the old definitions' choices for 63 providers under seven settings variants and the picker's answers, and compares them after the
--   migration (no difference), and checks that both prefilters keep every copy the page rule passes.
-- md5 (before = live v2.15.415, read 3 Nov 2026 09:15 AEDT; after = local replay on PostgreSQL 16, tests/fixtures/pdesc-picker-perf/run.sh):
--   security.provider_description_stored_v1(uuid)                                6ddc25869e9865c9aeebf11c819feee2 -> b4bef5671c9b2125b530df3abc9c502a
--   public.svc_provider_description_next(integer)                                33d735da514a7d37e2815bbb0073af03 -> 5342ae3f9279f6c2ec0849ec4fe0fffd
--   security.provider_description_page_v1(uuid,text) is read, not edited         f68e0130757c71ec8d8de24eb730da96
-- Replaces: security.provider_description_stored_v1, public.svc_provider_description_next (same names; md5-guarded edits)
-- Retires: nothing (the per-copy double page rule call and the per-row repeated stored copy lookup are removed by these edits)
-- Nothing is dropped, deleted, renamed or switched on. No setting is added or changed (G2: the prefilter reads the existing page rule lists).
-- Consumer API untouched (G3).

create or replace function pg_temp.edit_once(p_sig text, p_before text, p_after text, p_edits text[][], p_times int[]) returns text language plpgsql as $f$
declare v_def text := pg_get_functiondef(p_sig::regprocedure); i int; v_c int; v_old text; v_new text;
begin
  if md5(v_def) = p_after then return p_sig || ': already applied'; end if;
  if md5(v_def) <> p_before then raise exception 'live % differs from the definition this change edits (md5 %)', p_sig, md5(v_def); end if;
  for i in 1 .. array_length(p_edits, 1) loop
    -- fixed: line endings are normalised, so the edit applies the same however the text arrives
    v_old := replace(p_edits[i][1], chr(13), ''); v_new := replace(p_edits[i][2], chr(13), '');
    v_c := (length(v_def) - length(replace(v_def, v_old, ''))) / length(v_old);
    if v_c <> p_times[i] then raise exception '%: edit % must apply exactly % times (found %)', p_sig, i, p_times[i], v_c; end if;
    v_def := replace(v_def, v_old, v_new);
  end loop;
  execute v_def;
  if md5(pg_get_functiondef(p_sig::regprocedure)) <> p_after then
    raise exception '% after the edit has md5 %, expected %', p_sig, md5(pg_get_functiondef(p_sig::regprocedure)), p_after;
  end if;
  return p_sig || ': applied';
end $f$;

-- 0. the page rule this change relies on is the one it was written against (not changed here)
do $g$
begin
  if md5(pg_get_functiondef('security.provider_description_page_v1(uuid,text)'::regprocedure)) <> 'f68e0130757c71ec8d8de24eb730da96' then
    raise exception 'live security.provider_description_page_v1 differs from the page rule this change was written against';
  end if;
end $g$;

-- 1. the stored copy: prefilter from the page rule's lists, then the page rule once per copy ---------------------------------------------
select pg_temp.edit_once('security.provider_description_stored_v1(uuid)', '6ddc25869e9865c9aeebf11c819feee2', 'b4bef5671c9b2125b530df3abc9c502a', array[
  array[$o$  select a.id
    from pipeline.sources s join pipeline.evidence_artifacts a on a.source_id = s.id
   where s.provider_id = p_provider and a.storage_path is not null and a.source_url ~* '^https?://'
     and coalesce(a.mime_type, 'text/html') ~* 'html|markdown|text'
     and coalesce(a.captured_at, a.created_at) > now() - make_interval(days => security.pipeline_num_v1('pdesc.source_max_age_days', 365)::int)
     -- pilot 2 Nov 2026 16:16: the page rule (a held news article was used because "about" was one of its path parts)
     and (security.provider_description_page_v1(p_provider, a.source_url)->>'ok')::boolean
   order by (security.provider_description_page_v1(p_provider, a.source_url)->>'main_host')::boolean desc, coalesce(a.captured_at, a.created_at) desc, a.id
   limit 1$o$,
        $n$  -- IQ-00055 (v2.15.410 regression): the page rule passes only an address whose first path part is an About page name or starts with an
  -- About prefix, so an address without "/<name>" or "/<prefix>" anywhere cannot pass; those copies are skipped first (a LIKE with the
  -- list's own words, escaped), then the other checks run on what is left, then the page rule once per copy
  with w as (select array(select '%/' || replace(replace(replace(lower(t), '\', '\\'), '%', '\%'), '_', '\_') || '%'
                            from jsonb_array_elements_text(coalesce(security.toolset_setting('pipeline', 'pdesc.about_patterns'), '[]'::jsonb)) t
                          union all
                          select '%/' || replace(replace(replace(lower(t), '\', '\\'), '%', '\%'), '_', '\_') || '%'
                            from jsonb_array_elements_text(coalesce(security.toolset_setting('pipeline', 'pdesc.about_prefixes'), '[]'::jsonb)) t where t <> '') ws,
                    array(select lower(t) from jsonb_array_elements_text(coalesce(security.toolset_setting('pipeline', 'pdesc.about_patterns'), '[]'::jsonb)) t) names,
                    array(select lower(t) from jsonb_array_elements_text(coalesce(security.toolset_setting('pipeline', 'pdesc.about_prefixes'), '[]'::jsonb)) t where t <> '') prefixes,
                    -- the oldest capture kept, read once (it was read once per copy)
                    security.pipeline_num_v1('pdesc.about_max_segments', 2) + 1 max_parts,
                    now() - make_interval(days => security.pipeline_num_v1('pdesc.source_max_age_days', 365)::int) since),
  f as (select a.id, a.source_url, a.storage_path, a.mime_type, coalesce(a.captured_at, a.created_at) at
          from w, pipeline.sources s join pipeline.evidence_artifacts a on a.source_id = s.id
         where s.provider_id = p_provider and lower(a.source_url) like any (w.ws)
        offset 0),
  -- the page rule's About part is the first path part, or the second after a language part: one of the first two parts must be an About
  -- page name or start with an About prefix (the path is read as the page rule reads it)
  c as (select f.id, f.at, f.source_url
          from w, f cross join lateral (select z.p, regexp_match(z.p, '^/*([^/]+)(?:/+([^/]+))?') m
                                          from (select lower(coalesce(substring(f.source_url from '^https?://[^/?#]+(/[^?#]*)'), '')) p) z) g
         where f.storage_path is not null and f.source_url ~* '^https?://'
           and coalesce(f.mime_type, 'text/html') ~* 'html|markdown|text'
           and f.at > w.since
           -- at most pdesc.about_max_segments parts, and one more for a language part
           and regexp_count(g.p, '[^/]+') <= w.max_parts
           and (g.m[1] = any (w.names) or g.m[2] = any (w.names)
                or exists (select 1 from unnest(w.prefixes) x where (left(g.m[1], length(x)) = x and length(g.m[1]) > length(x))
                                                                 or (left(g.m[2], length(x)) = x and length(g.m[2]) > length(x))))
        offset 0)
  -- pilot 2 Nov 2026 16:16: the page rule (a held news article was used because "about" was one of its path parts), once per copy
  select c.id
    from c cross join lateral (select security.provider_description_page_v1(p_provider, c.source_url) pg offset 0) r
   where (r.pg->>'ok')::boolean
   order by (r.pg->>'main_host')::boolean desc, c.at desc, c.id
   limit 1$n$]], array[1]);

-- 2. the picker: the stored copy once per claimed row, never in the filter while direct acquisition is on; the page rule once per suggestion
select pg_temp.edit_once('public.svc_provider_description_next(integer)', '33d735da514a7d37e2815bbb0073af03', '5342ae3f9279f6c2ec0849ec4fe0fffd', array[
  array[$o$                   and (security.pipeline_num_v1('pdesc.acquire_direct', 0) >= 1 or security.provider_description_stored_v1(r.provider_id) is not null)$o$,
        $n$                   -- IQ-00055: a CASE, so the stored copy is not looked up per queued row while direct acquisition is on
                   and case when security.pipeline_num_v1('pdesc.acquire_direct', 0) >= 1 then true else security.provider_description_stored_v1(r.provider_id) is not null end$n$],
  array[$o$                        from pipeline.evidence_artifacts a where a.id = security.provider_description_stored_v1(u.provider_id)),$o$,
        $n$                        from pipeline.evidence_artifacts a where a.id = st.stored_id),$n$],
  array[$o$           'candidates', (select coalesce(jsonb_agg(z.url order by (security.provider_description_page_v1(u.provider_id, z.url)->>'main_host')::boolean desc, z.score desc, length(z.url)), '[]'::jsonb) from (
                            select distinct e->>'url' url, coalesce((e->>'score')::numeric, 0) score
                              from pipeline.provider_central_search cs, jsonb_array_elements(coalesce(cs.found, '[]'::jsonb)) e
                             where cs.provider_id = u.provider_id and e->>'kind' = 'about_page' and e->>'url' ~* '^https?://'
                               and coalesce((e->>'score')::numeric, 0) >= security.pipeline_num_v1('central.min_suggest_score', 4)
                               and (security.provider_description_page_v1(u.provider_id, e->>'url')->>'ok')::boolean) z))), '[]'::jsonb)$o$,
        $n$           -- IQ-00055: the page rule once per suggestion (a lateral), for the filter and the order
           'candidates', (select coalesce(jsonb_agg(z.url order by (z.pg->>'main_host')::boolean desc, z.score desc, length(z.url)), '[]'::jsonb) from (
                            select y.url, y.score, g.pg from (
                              select distinct e->>'url' url, coalesce((e->>'score')::numeric, 0) score
                                from pipeline.provider_central_search cs, jsonb_array_elements(coalesce(cs.found, '[]'::jsonb)) e
                               where cs.provider_id = u.provider_id and e->>'kind' = 'about_page' and e->>'url' ~* '^https?://'
                                 and coalesce((e->>'score')::numeric, 0) >= security.pipeline_num_v1('central.min_suggest_score', 4)) y
                              cross join lateral (select security.provider_description_page_v1(u.provider_id, y.url) pg offset 0) g
                             where (g.pg->>'ok')::boolean) z))), '[]'::jsonb)$n$],
  array[$o$    from upd u join catalogue.providers p on p.id = u.provider_id join ref.countries k on k.id = p.country_id;$o$,
        $n$    -- IQ-00055: the stored copy once per claimed row
    from upd u cross join lateral (select security.provider_description_stored_v1(u.provider_id) stored_id offset 0) st
         join catalogue.providers p on p.id = u.provider_id join ref.countries k on k.id = p.country_id;$n$]], array[1, 1, 1, 1]);

comment on function security.provider_description_stored_v1(uuid) is 'CF-247 P1 provider descriptions: the newest stored copy of the provider''s About page that passes the page rule (security.provider_description_page_v1), main site first; a prefilter from pdesc.about_patterns and pdesc.about_prefixes skips addresses the rule cannot pass, and the rule runs once per copy (IQ-00055).';
