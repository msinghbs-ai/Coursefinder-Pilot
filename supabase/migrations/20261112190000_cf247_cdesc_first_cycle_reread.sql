-- CF-247 F-CDESC first-cycle check of Pilot #1047 (cdesc-source-grounded-v1), 12 Nov 2026 02:20 AEDT. Direction: Platform Admin 11 Nov 2026 (Admin PR #430): process every eligible course; accurate, original, source-backed.
--
-- First cycle (1,882 readings with the new prompt, US$2.86, US$0.00152 a reading): 87 filled, 220 to Layer 4, 22 insufficient_verified_course_facts, 1,553 held. Causes found:
--   * 733 (481 unsupported_sentence, 252 quote_not_on_page) were the worker's recording, not the answers: a claim reached only one sentence and the catalogue title and provider counted as unsupported words. Worker v0.72.1
--     fixes that (course-text.ts cdescValue); 215 of the 481 pass support with the catalogue record alone. These 733 readings are marked reread: and read again once (US$1.1 at the measured rate; temperature 0, so the same answer is
--     recorded the right way). The answers' text cannot be re-recorded from storage: the stored value keeps each sentence's joined quote, not each cited span (v0.72.1 now keeps cited_spans).
--   * 302 of the 341 unsupported_claim checks were the word "students" used as the neutral subject of a sentence its spans support ("Students study ..."). "students" is removed from enrich.course_description_claim_words; rankings,
--     outcomes, accreditation, facilities, staff and awards stay. The policy stamp changes, so the held recheck re-checks those stored readings at no AI cost (no re-read).
--   * 305 copied_sentence, 155 sentence_count, 44 unsupported_marketing, 28 length and 3 course_id_mismatch are the answers themselves: held as designed, never cut or edited.
--
-- Live definition this change edits (pg_proc.prosrc md5, read 12 Nov 2026): security.enrich_course_text_gaps_v1(text[])  ddba9b553a63a9e38c49782a0b0d29c9 -> d117edb4198b81a692e93af9a937110e
-- Replaces: the re-read condition of security.enrich_course_text_gaps_v1 (a reading superseded in Layer 4, or marked reread:, is read again whatever prompt made it)
-- Retires: nothing
-- Nothing is dropped or deleted. One setting value changes (recorded in admin_control_events). 733 readings get a reason prefix (no value, state or description changes). No table, job or consumer-API object is added or changed (G3).
-- Forward recovery: supabase/held/cdesc_reread_forward_recovery.sql (restores the body and the claim words; the reread: prefix is removed from readings not yet read again).

create or replace function pg_temp.edit_all(p_sig text, p_before text, p_after text, p_olds text[], p_news text[]) returns text language plpgsql as $f$
declare v_def text := pg_get_functiondef(p_sig::regprocedure); v_src text := (select p.prosrc from pg_proc p where p.oid = p_sig::regprocedure); v_c int; i int;
begin
  -- fixed: the guard is the md5 of the function body (pg_proc.prosrc), the same text on PostgreSQL 16 and 17
  if md5(v_src) = p_after then return p_sig || ': already applied'; end if;
  if md5(v_src) <> p_before then raise exception 'live % differs from the definition this change replaces (body md5 %)', p_sig, md5(v_src); end if;
  -- fixed: line endings are normalised, so the edit applies the same however the text arrives
  v_def := replace(v_def, chr(13), '');
  for i in 1 .. array_length(p_olds, 1) loop
    v_c := (length(v_def) - length(replace(v_def, p_olds[i], ''))) / length(p_olds[i]);
    if v_c <> 1 then raise exception '%: edit % must apply exactly once (found %)', p_sig, i, v_c; end if;
    v_def := replace(v_def, p_olds[i], p_news[i]);
  end loop;
  execute v_def;
  v_src := (select p.prosrc from pg_proc p where p.oid = p_sig::regprocedure);
  if md5(v_src) <> p_after then raise exception '% after the edit has body md5 %, expected %', p_sig, md5(v_src), p_after; end if;
  return p_sig || ': applied';
end $f$;

select pg_temp.edit_all('security.enrich_course_text_gaps_v1(text[])', 'ddba9b553a63a9e38c49782a0b0d29c9', 'd117edb4198b81a692e93af9a937110e',
  array[$o0$               (f = 'description' and e.state = 'skipped' and ((e.reason like 'held%' and e.reason not like 'held\_first\_admission:%') or e.reason like 'superseded:%')
                and coalesce(e.value->>'prompt_version', e.value->'reader'->>'prompt', '') <> security.cdesc_prompt_version_v1()) old_prompt$o0$],
  array[$n0$               -- 12 Nov 2026 (first-cycle check of #1047): a reading superseded in Layer 4, or marked reread: (a reading the worker mis-recorded, read again on a recorded decision), is read again whatever prompt made it
               (f = 'description' and e.state = 'skipped' and ((e.reason like 'held%' and e.reason not like 'held\_first\_admission:%'
                and coalesce(e.value->>'prompt_version', e.value->'reader'->>'prompt', '') <> security.cdesc_prompt_version_v1()) or e.reason like 'superseded:%' or e.reason like 'reread:%')) old_prompt$n0$]);

-- "students" leaves the course description claim words (only when the list is still the one measured)
with u as (
  update pipeline.platform_toolset_settings set value = '["ranked", "ranking", "rankings", "rated", "rating", "qs", "times higher", "top 1%", "employment", "employability", "employed", "employers", "graduate outcomes", "salary", "salaries", "accredited", "accreditation", "facilities", "state-of-the-art", "five-star", "5-star", "staff", "alumni", "award", "awards"]'::jsonb,
         reason = 'F-CDESC first-cycle check of #1047: 302 of 341 unsupported_claim holds were "students" as the neutral subject of a supported sentence (migration 20261112190000)', updated_at = now()
   where toolset_key = 'pipeline' and key = 'enrich.course_description_claim_words' and value = '["ranked", "ranking", "rankings", "rated", "rating", "qs", "times higher", "top 1%", "employment", "employability", "employed", "employers", "graduate outcomes", "salary", "salaries", "accredited", "accreditation", "facilities", "state-of-the-art", "five-star", "5-star", "students", "staff", "alumni", "award", "awards"]'::jsonb
  returning key)
insert into pipeline.admin_control_events(area, action, target, detail, actor)
select 'toolsets', 'setting', 'pipeline.enrich.course_description_claim_words',
       jsonb_build_object('before', '["ranked", "ranking", "rankings", "rated", "rating", "qs", "times higher", "top 1%", "employment", "employability", "employed", "employers", "graduate outcomes", "salary", "salaries", "accredited", "accreditation", "facilities", "state-of-the-art", "five-star", "5-star", "students", "staff", "alumni", "award", "awards"]'::jsonb, 'after', '["ranked", "ranking", "rankings", "rated", "rating", "qs", "times higher", "top 1%", "employment", "employability", "employed", "employers", "graduate outcomes", "salary", "salaries", "accredited", "accreditation", "facilities", "state-of-the-art", "five-star", "5-star", "staff", "alumni", "award", "awards"]'::jsonb,
                          'reason', 'Migration 20261112190000 (F-CDESC first-cycle check of Pilot #1047): "students" removed; 302 of 341 unsupported_claim holds under cdesc-source-grounded-v1 were the neutral subject of a supported sentence'),
       '63ba56cb-48d4-4169-98c2-7c4d1f72925b'
  from u;

-- the readings worker v0.72.0 mis-recorded are read again once (field-gap-queue, within the daily cap)
update pipeline.field_enrich_items e set reason = left('reread: v0.72.0 mapping: ' || e.reason, 300), updated_at = now()
 where e.field = 'description' and e.state = 'skipped' and e.value->>'prompt_version' = 'cdesc-source-grounded-v1' and e.value->'reader'->>'worker' = 'coverage-sweep-worker-v0.72.0'
   and (e.reason like 'held: unsupported\_sentence:%' or e.reason like 'held: quote\_not\_on\_page:%');

do $chk$
begin
  if exists (select 1 from pipeline.platform_toolset_settings s where s.toolset_key = 'pipeline' and s.key = 'enrich.course_description_claim_words' and s.value ? 'students') then
    raise notice 'enrich.course_description_claim_words was changed by a person since it was measured: left as it is';
  end if;
end $chk$;
