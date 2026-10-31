-- Consumer API change approved: Platform Admin, 31 Oct 2026 13:30 (StudySearch decision D6: "Proceed with optimisation of the two identified consumer search functions … preserving the existing response contract and search semantics … Do not deploy any change that fails contract-equivalence testing"; admin 2026-10-31-studysearch-d1-d6-approval.md and 2026-10-31-studysearch-transformation.md §26) — output-identical internal change only: no key, type, value, order, identifier or route changes
-- CF-247 StudySearch D6 / SS-012: Website (and Zoho, through the same item) course items are built about twice as fast, with identical output.
-- Why (record §21, §26): website search pages of 50 items take a median 3.1 s; building each item cost about 11 ms, of which the course
-- display code (computed three times per item) and the published check (a scan of the hidden-provider view per item) took about 5 ms.
-- What (api.website_v2_course_item, md5-guarded single-line edits):
--   * the display code is computed once per item and its three keys read from it;
--   * the published check asks whether this provider is hidden (exists, keyed on the provider id) instead of building the whole hidden list
--     for every item. Same result for every value, null included: a null provider is "published" in both forms.
-- Not changed: public.website_v2_course_search. A rewrite of its sort and count was tried and measured no faster under live load, so it
-- is not shipped. No response key, type, value, order, filter, identifier or route changes.
-- Proof (live, rolled back, 31 Oct 2026): 34 representative searches (every sort, filters, pagination past the end, empty results,
-- page sizes 1/20/50, unknown filter keys) return byte-identical JSON before and after; 400 random courses' items identical. Benchmark,
-- 8 interleaved runs of 50 items: median 536 ms before, 280 ms after (-48%).
-- Replaces: api.website_v2_course_item (same name; md5-guarded edit)
-- Retires: nothing
-- Nothing dropped, deleted or renamed. No new table, job, setting or status. The consumer API baseline is re-taken for this function only.

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

select pg_temp.edit_once('api.website_v2_course_item(uuid,text[],text[])', '151293140767d73fdcc1243d9d9e9ad0', '8f2a0ac921c4507673c1232cf2ecc8aa', array[
 array[$o$declare d search.course_documents; v jsonb;$o$, $n$declare d search.course_documents; v jsonb; dc jsonb;$n$],
 array[$o$then return null; end if;  -- v2.15.236$o$, $n$then return null; end if; dc := security.course_display_code_v1(d.course_id);  -- v2.15.236; StudySearch D6 (31 Oct 2026): the display code is read once$n$],
 array[$o$security.course_display_code_v1(d.course_id)->>'$o$, $n$dc->>'$n$],
 array[$o$case when d.provider_id in (select h.provider_id from security.provider_hidden_v1 h where h.provider_id is not null) then 'unpublished' else 'published' end$o$, $n$case when exists (select 1 from security.provider_hidden_v1 h where h.provider_id = d.provider_id) then 'unpublished' else 'published' end$n$]],
 array[1, 1, 3, 1]);

select security.consumer_api_rebaseline_v1('D6 (31 Oct 2026): api.website_v2_course_item output-identical speed-up (display code once, keyed published check); approved Platform Admin 31 Oct 2026 13:30, record §26');
