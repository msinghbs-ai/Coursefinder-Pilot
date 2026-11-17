-- CF-247 AER decision W29 (29 Oct 2026, AER programme Workstream 2, lane D): course-level reading of long pages in bounded slices.
-- Numbered 20261029130000 by the integrator; it ships with worker coverage-sweep-worker-v0.53.0 (release v2.15.369).
-- Why: three Monash course reads (field_enrich_items 228658, 228627, 228642; courses e58e7771, 512b56fe, 9cf18451) failed three times with
-- "Unterminated string in JSON at position 8,061 to 8,598". The course entry read (worker enrich_ai, field entry_requirements) asked for
-- the whole page in one call with its answer fixed at 2,000 tokens; pages that publish a long per-country minimum list answered past it,
-- the cut answer was parsed as JSON, retried at the same size, and the calls' cost was not recorded (cost_usd 0 on all three). The provider
-- entry-matrix reader met the same fault in Wave H and was given an answer-length setting and slices (20261029001000, 20261029020000).
-- What: worker v0.53.0 reads a course page in contiguous slices of the stored text, every answer limited by a setting, and holds the whole
-- read (held_partial) when any slice is cut, empty or unreadable or the page is longer than entry.course_page_chars. The settings below are
-- read by the worker through svc_worker_settings_v1 (prefix enrich.), so no worker-settings function changes. The record keeps the read's
-- coverage (slices, character ranges, rows read twice) beside its rows on the item.
-- Replaces: security.enrich_entry_record_v1 (same name, md5-guarded edit: the item keeps the read's coverage); the single-call course entry read inside worker mode enrich_ai (replaced in place by v0.53.0)
-- Retires: nothing (no table, function, job or edge function is left unused)
-- Nothing dropped, deleted or renamed. The consumer API is not touched (Decision 266). No new job, table or status. No AI read is started.

insert into pipeline.platform_toolset_settings(toolset_key, key, label, help, kind, value, min_value, max_value, unit, sort, section, used_by, reason) values
 ('pipeline', 'enrich.course_entry_slice_chars', 'Course entry requirements: characters a slice',
  'A course page is read for entry requirements in slices of at most this many characters of its stored text; every slice is one AI call, and together the slices cover the whole page.', 'number',
  to_jsonb(12000), 4000, 40000, 'characters', 918, 'Entry requirements', 'worker coverage-sweep enrich_ai (entry_requirements)',
  'CF-247 AER decision W29 (29 Oct 2026): three Monash course pages with long per-country minimum lists were cut off mid-answer when read in one call'),
 ('pipeline', 'enrich.course_entry_slice_overlap_chars', 'Course entry requirements: overlap between slices',
  'Each later slice of a course page begins with the last lines of the slice before it, up to this many characters, so a requirement printed across the boundary is read whole once. A row read in both slices is kept once.', 'number',
  to_jsonb(600), 0, 4000, 'characters', 919, 'Entry requirements', 'worker coverage-sweep enrich_ai (entry_requirements)',
  'CF-247 AER decision W29 (29 Oct 2026): slices of a long course page'),
 ('pipeline', 'enrich.course_entry_max_slices', 'Course entry requirements: slices a page',
  'The most slices (AI calls) one course page is read in. A page needing more is held before any AI call (held_partial), never read in part.', 'number',
  to_jsonb(10), 1, 20, 'slices', 920, 'Entry requirements', 'worker coverage-sweep enrich_ai (entry_requirements)',
  'CF-247 AER decision W29 (29 Oct 2026): bounds the calls of one course read; 100,000 characters at 12,000 a slice with overlap fit in 10'),
 ('pipeline', 'enrich.course_entry_max_tokens', 'Course entry requirements: answer length',
  'The longest answer the course entry reader may give for one slice. A slice whose answer reaches it is output_truncated and the whole read is held (held_partial); no row of a cut read is proposed.', 'number',
  to_jsonb(8000), 2000, 32000, 'tokens', 921, 'Entry requirements', 'worker coverage-sweep enrich_ai (entry_requirements)',
  'CF-247 AER decision W29 (29 Oct 2026): the course read''s answer was fixed at 2,000 tokens in the worker and cut three Monash answers at about 8,000 characters'),
 ('pipeline', 'enrich.course_entry_slice_concurrency', 'Course entry requirements: slices read at once',
  'This many slices of one course page are read at the same time and joined in page order. 1 reads them one after another. A failed slice stops the slices not yet started.', 'number',
  to_jsonb(4), 1, 12, 'slices', 922, 'Entry requirements', 'worker coverage-sweep enrich_ai (entry_requirements)',
  'CF-247 AER decision W29 (29 Oct 2026): as Entry matrices: slices read at once, for course pages')
on conflict (toolset_key, key) do nothing;

-- the page-size setting now holds a longer page instead of cutting it (the value is unchanged)
update pipeline.platform_toolset_settings
   set help = 'How much of the stored course page text the model reads for entry requirements. A page whose text is longer is held (held_partial) before any AI call, never cut.',
       used_by = 'public.svc_enrich_ai_next, worker coverage-sweep enrich_ai (entry_requirements)',
       reason = 'CF-247 AER decision W29 (29 Oct 2026): a cut page is never read as complete', updated_at = now()
 where toolset_key = 'pipeline' and key = 'entry.course_page_chars';

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

-- the item keeps the read's coverage (basis, page characters, slices, character ranges, rows read twice) on every outcome; nothing else changes
-- live md5 0f4d8f90b006f84f4523b110dfa5eaa2 read on 29 Oct 2026 (lane D, read-only)
select pg_temp.edit_n('security.enrich_entry_record_v1(bigint,jsonb)', '0f4d8f90b006f84f4523b110dfa5eaa2', array[
  array[$o$value = jsonb_build_object('dropped', v_drop), updated_at$o$,
        $n$value = jsonb_build_object('dropped', v_drop, 'coverage', p_r->'value'->'coverage'), updated_at$n$],
  array[$o$value = jsonb_build_object('dropped', v_drop, 'notes', v_notes), updated_at$o$,
        $n$value = jsonb_build_object('dropped', v_drop, 'notes', v_notes, 'coverage', p_r->'value'->'coverage'), updated_at$n$],
  array[$o$value = jsonb_build_object('rows', v_in, 'review_item_id', v_review, 'dropped', v_drop, 'notes', v_notes), updated_at$o$,
        $n$value = jsonb_build_object('rows', v_in, 'review_item_id', v_review, 'dropped', v_drop, 'notes', v_notes, 'coverage', p_r->'value'->'coverage'), updated_at$n$]],
  array[1, 1, 1]);

-- post-check: five settings present with their ranges, and the record function keeps coverage
do $$ declare v_n int; begin
  select count(*) into v_n from pipeline.platform_toolset_settings
   where toolset_key = 'pipeline' and key in ('enrich.course_entry_slice_chars', 'enrich.course_entry_slice_overlap_chars', 'enrich.course_entry_max_slices',
                                              'enrich.course_entry_max_tokens', 'enrich.course_entry_slice_concurrency')
     and label is not null and unit is not null and used_by is not null and min_value is not null and max_value is not null;
  if v_n <> 5 then raise exception 'W29 post-check: expected 5 course entry slice settings, found %', v_n; end if;
  if pg_get_functiondef('security.enrich_entry_record_v1(bigint,jsonb)'::regprocedure) not like '%''coverage'', p_r->''value''->''coverage''%' then
    raise exception 'W29 post-check: security.enrich_entry_record_v1 does not keep coverage';
  end if;
end $$;
