-- CF-247 StudySearch Layer 4 settlement recovery (Platform Admin mandate 1 Nov 2026 11:28; incident
-- admin docs/platform/nz-enrichment-brief/2026-11-01-layer4-all-kinds-settlement-timeout-stop.md; record §35).
-- Why (verified live 1 Nov 2026, database log 31 Oct 23:51 to 23:52 UTC and reproduced as a Platform Admin at the 8 s limit for signed-in users):
--   1. Adapter builder › Waiting for approval (central pages, Niagara College) timed out in public.admin_provider_fee_schedules_read:
--      for each of 51 parsed documents it ran security.provider_fee_proposal_rows five times (one pass 1.7 s; the list 8.2 s), and each pass
--      matched fee rows to courses by upper(btrim(course_code)) with no index for it.
--   2. Evidence › search by source address (refs VK2DWH, ZKEMAX) timed out in security.admin_evidence_page: a text search tests ten
--      fields with ilike '%...%' over all 181,399 stored copies, metadata text included (11.5 s; the call 8.8 s before cancellation).
-- What (no decision, admission, evidence or consumer change):
--   * index evidence_artifacts_source_url_pattern_idx (lower(source_url) text_pattern_ops);
--   * admin_evidence_page: a search that is a page address finds stored copies whose address starts with it (case-insensitive,
--     trailing slash and #fragment ignored; newest 5,000); every other search and filter is unchanged;
--   * index courses_provider_code_trim_active_idx (provider_id, upper(btrim(course_code))) for active courses: one pass 1,661 -> 89 ms;
--   * admin_provider_fee_schedules_read: the five counts per document come from one pass (same output, md5 4a3dbd90 before and after).
-- Dry runs (rolled back, as a Platform Admin): Niagara address search 126 ms (1 copy; 19 ms upper-case with slash); default Evidence view
--   unchanged (181,402); fee schedules list 8.2 s -> 2.6 to 3.7 s warm before the course index.
-- Rollback: re-apply the previous definitions (md5 fc04124f, 8f21ca12); the indexes can stay (paste file to drop).
-- Replaces: security.admin_evidence_page, public.admin_provider_fee_schedules_read (same names; md5-guarded edits)
-- Retires: nothing
-- Nothing dropped or deleted. Consumer API untouched (G3).

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

-- 1. index for address searches (built once; writers wait a few seconds)
create index if not exists evidence_artifacts_source_url_pattern_idx on pipeline.evidence_artifacts (lower(source_url) text_pattern_ops);
comment on index pipeline.evidence_artifacts_source_url_pattern_idx is 'Layer 4 recovery (1 Nov 2026): Evidence search by page address (prefix, case-insensitive).';
-- fee schedule rows are matched to courses by trimmed course code (security.provider_fee_proposal_rows): one pass 1,661 ms -> 89 ms
create index if not exists courses_provider_code_trim_active_idx on catalogue.courses (provider_id, upper(btrim(course_code))) where lifecycle_status = 'active';
comment on index catalogue.courses_provider_code_trim_active_idx is 'Layer 4 recovery (1 Nov 2026): fee schedule rows matched to active courses by provider and trimmed course code.';

-- 2. Evidence search by page address
select pg_temp.edit_once('security.admin_evidence_page(jsonb)', 'fc04124f37acf248e0afdfe63bd043e8', '7ab917871c6161dc3449d6625ebb2350', array[
 array[$o$  v_fast boolean;
begin$o$,
       $n$  v_fast boolean;
  v_url text;         -- Layer 4 recovery (1 Nov 2026): a search for a page address
  v_url_ids uuid[];
begin$n$],
 array[$o$and v_sort='captured' and v_direction='desc';
$o$,
       $n$and v_sort='captured' and v_direction='desc';

  -- Layer 4 recovery (1 Nov 2026): a search for a page address (https://...) finds the stored copies whose address starts with it through
  -- index evidence_artifacts_source_url_pattern_idx, instead of a contains-search of every field of every row (11.5 s against the 8 s limit).
  -- The newest matches are kept; other searches are unchanged.
  if v_query ~* '^https?://[^[:space:]]+$' then
    v_url := lower(regexp_replace(regexp_replace(v_query, '#.*$', ''), '/+$', ''));
    v_url_ids := coalesce((select array_agg(z.id) from (select e.id from pipeline.evidence_artifacts e
                             where lower(e.source_url) ~>=~ v_url and lower(e.source_url) ~<~ (v_url || chr(1114111))
                             order by e.captured_at desc nulls last, e.id limit 5000) z), '{}');  -- fixed: bound on the stored copies one address search returns
  end if;
$n$],
 array[$o$(v_query is null or e.id::text ilike '%'||v_query||'%' or$o$,
       $n$(v_query is null or e.id = any(v_url_ids) or (v_url_ids is null and (e.id::text ilike '%'||v_query||'%' or$n$],
 array[$o$coalesce(e.storage_path,'') ilike '%'||v_query||'%')$o$,
       $n$coalesce(e.storage_path,'') ilike '%'||v_query||'%')))$n$]],
 array[1, 1, 1, 1]);

-- 3. fee schedules list: proposal rows worked out once per document
select pg_temp.edit_once('public.admin_provider_fee_schedules_read(uuid,integer)', '8f21ca127c6773f4abeb2690c96b90f2', '9ca85971fea06c9dae930c44bd88475d', array[
 array[$o$'rows', (select count(*) from security.provider_fee_proposal_rows(f.id)),
               'new', (select count(*) from security.provider_fee_proposal_rows(f.id) x where x.outcome = 'new'),
               'same', (select count(*) from security.provider_fee_proposal_rows(f.id) x where x.outcome = 'same'),
               'differs', (select count(*) from security.provider_fee_proposal_rows(f.id) x where x.outcome = 'differs'),
               'no_course', (select count(*) from security.provider_fee_proposal_rows(f.id) x where x.outcome = 'no_course')) d
          from pipeline.provider_fact_sources f join catalogue.providers p on p.id = f.provider_id
$o$,
       $n$'rows', k.n, 'new', k.n_new, 'same', k.n_same, 'differs', k.n_differs, 'no_course', k.n_no_course) d
          from pipeline.provider_fact_sources f join catalogue.providers p on p.id = f.provider_id
          -- Layer 4 recovery (1 Nov 2026): each document's proposal rows are worked out once, not five times (8.2 s timed out at the 8 s limit)
          cross join lateral (select count(*) n, count(*) filter (where x.outcome = 'new') n_new, count(*) filter (where x.outcome = 'same') n_same,
                                     count(*) filter (where x.outcome = 'differs') n_differs, count(*) filter (where x.outcome = 'no_course') n_no_course
                                from security.provider_fee_proposal_rows(f.id) x) k
$n$]],
 array[1]);

-- post-check
do $$
begin
  if md5(pg_get_functiondef('security.admin_evidence_page(jsonb)'::regprocedure)) <> '7ab917871c6161dc3449d6625ebb2350'
     or md5(pg_get_functiondef('public.admin_provider_fee_schedules_read(uuid,integer)'::regprocedure)) <> '9ca85971fea06c9dae930c44bd88475d' then
    raise exception 'Layer 4 recovery post-check: definitions'; end if;
  if to_regclass('pipeline.evidence_artifacts_source_url_pattern_idx') is null or to_regclass('catalogue.courses_provider_code_trim_active_idx') is null then
    raise exception 'Layer 4 recovery post-check: indexes'; end if;
end $$;
