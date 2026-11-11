-- CF-247 F-CDESC first-cycle check of Pilot #1047 (cdesc-source-grounded-v1), 12 Nov 2026 02:20 AEDT. Direction: Platform Admin 11 Nov 2026 (Admin PR #430): process every eligible course; accurate, original, source-backed.
--
-- First cycle (1,882 readings with the new prompt, US$2.86, US$0.00152 a reading): 87 filled, 220 to Layer 4, 22 insufficient_verified_course_facts, 1,553 held. Causes found:
--   * 733 (481 unsupported_sentence, 252 quote_not_on_page) were the worker's recording, not the answers: a claim reached only one sentence, and the course's own title and provider counted as unsupported words. Worker v0.72.1
--     lets a page claim back every sentence sharing enough of its meaningful words (new settings enrich.course_description_claim_reach_share 0.5 and enrich.course_description_claim_reach_min_words 2); quotes stay page text only.
--     security.cdesc_known_strip_v1 (new) takes the course's title and provider out of a sentence before its tests (security.course_description_check_with_v1, md5-guarded): they are verified catalogue facts, never claims, and
--     never quote material (QA of #1049 rejected adding them to the quote: a sentence could pass on title words alone). These 733 readings are marked reread: and read again once (US$1.1 at the measured rate; temperature 0, so the
--     same answer is recorded the right way). The answers cannot be re-recorded from storage: the stored value keeps each sentence's joined quote, not each cited span (v0.72.1 now keeps cited_spans).
--   * 302 of the 341 unsupported_claim checks were the word "students" used as the neutral subject of a sentence its spans support ("Students study ..."). "students" is removed from enrich.course_description_claim_words; rankings,
--     outcomes, accreditation, facilities, staff and awards stay. The policy stamp changes, so the held recheck re-checks those stored readings at no AI cost (no re-read).
--   * 305 copied_sentence, 155 sentence_count, 44 unsupported_marketing, 28 length and 3 course_id_mismatch are the answers themselves: held as designed, never cut or edited.
--
-- Live definitions this change edits (pg_proc.prosrc md5, read 12 Nov 2026):
--   security.enrich_course_text_gaps_v1(text[])  ddba9b553a63a9e38c49782a0b0d29c9 -> d117edb4198b81a692e93af9a937110e
--   security.course_description_check_with_v1(uuid,jsonb,jsonb,jsonb)  d310fa64f61f2243df1416d3e48f6bab -> b4d4dabd655afb9352003b87b2b4387d
-- Replaces: the re-read condition of security.enrich_course_text_gaps_v1 (a reading superseded in Layer 4, or marked reread:, is read again whatever prompt made it); the sentence text security.course_description_check_with_v1 tests
-- Retires: nothing
-- Nothing is dropped or deleted. One setting value changes and two settings are added (each recorded in admin_control_events); one function is added. 733 readings get a reason prefix (no value, state or description changes). No table, job or consumer-API object is added or changed (G3).
-- Forward recovery: supabase/held/cdesc_reread_forward_recovery.sql (restores both bodies and the claim words; the reread: prefix is removed from readings not yet read again; the new function and settings stay, unused).

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

-- the course's own title and provider are left out of a sentence's tests
create or replace function security.cdesc_known_strip_v1(p_text text, p_title text, p_provider text) returns text language plpgsql immutable set search_path = '' as $f$
declare t text := coalesce(p_text, ''); x text;
begin
  -- the course's own title and provider (and the provider without Pty Ltd, Limited, Ltd or Inc) are taken out of a sentence, as whole phrases, before its tests;
  -- fixed: a name shorter than 4 characters is left in (an acronym such as MBA is also a common word in a sentence)
  foreach x in array array[p_title, p_provider, regexp_replace(coalesce(p_provider, ''), '\s+(pty\.?\s+ltd\.?|limited|ltd\.?|inc\.?)$', '', 'i')] loop
    continue when length(btrim(coalesce(x, ''))) < 4;
    t := regexp_replace(t, '(^|[^[:alnum:]])' || regexp_replace(btrim(x), '([.+*?^$(){}|/\\\[\]-])', '\\\1', 'g') || '(?![[:alnum:]])', '\1', 'gi');
  end loop;
  return t;
end $f$;;
comment on function security.cdesc_known_strip_v1(text, text, text) is 'CF-247 F-CDESC (20261112190000): the course''s title and provider taken out of a description sentence before its tests (verified catalogue facts, never claims)';
revoke all on function security.cdesc_known_strip_v1(text, text, text) from public;

-- the worker's claim reach (worker coverage-sweep v0.72.1 reads them through svc_worker_settings_v1)
insert into pipeline.platform_toolset_settings(toolset_key, key, label, help, kind, value, min_value, max_value, unit, sort, section, used_by, reason)
values ('pipeline', 'enrich.course_description_claim_reach_share', 'Course description: share of a claim''s words that ties it to a sentence',
        'A claim with page evidence backs every sentence of the description that shares at least this share of its meaningful words (and always the sentence it matches best). Lower ties evidence to more sentences.',
        'number', to_jsonb(0.5), '0.1', '1', 'share', 1123, 'Course description and deadline', 'worker coverage-sweep enrich_ai (course-text.ts cdescValue)',
        'F-CDESC first-cycle check of Pilot #1047: 252 sentences had no quote because a claim reached only one sentence'),
       ('pipeline', 'enrich.course_description_claim_reach_min_words', 'Course description: fewest shared words that tie a claim to a sentence',
        'A claim backs a sentence only when they share at least this many meaningful words; a sentence no claim reaches takes the closest page claim with at least this many.',
        'number', to_jsonb(2), '1', '10', 'words', 1124, 'Course description and deadline', 'worker coverage-sweep enrich_ai (course-text.ts cdescValue)',
        'F-CDESC first-cycle check of Pilot #1047 (QA of #1049: at least two meaningful words, stop words left out)')
on conflict (toolset_key, key) do nothing;
insert into pipeline.admin_control_events(area, action, target, detail, actor)
select 'toolsets', 'setting', 'pipeline.' || k, jsonb_build_object('before', null, 'after', v, 'reason', 'Added by migration 20261112190000 (F-CDESC first-cycle check of Pilot #1047): the worker''s claim reach'),
       '63ba56cb-48d4-4169-98c2-7c4d1f72925b'
  from (values ('enrich.course_description_claim_reach_share', to_jsonb(0.5)), ('enrich.course_description_claim_reach_min_words', to_jsonb(2))) x(k, v)
 where not exists (select 1 from pipeline.admin_control_events e where e.area = 'toolsets' and e.target = 'pipeline.' || x.k);

select pg_temp.edit_all('security.enrich_course_text_gaps_v1(text[])', 'ddba9b553a63a9e38c49782a0b0d29c9', 'd117edb4198b81a692e93af9a937110e',
  array[$o0$               (f = 'description' and e.state = 'skipped' and ((e.reason like 'held%' and e.reason not like 'held\_first\_admission:%') or e.reason like 'superseded:%')
                and coalesce(e.value->>'prompt_version', e.value->'reader'->>'prompt', '') <> security.cdesc_prompt_version_v1()) old_prompt$o0$],
  array[$n0$               -- 12 Nov 2026 (first-cycle check of #1047): a reading superseded in Layer 4, or marked reread: (a reading the worker mis-recorded, read again on a recorded decision), is read again whatever prompt made it
               (f = 'description' and e.state = 'skipped' and ((e.reason like 'held%' and e.reason not like 'held\_first\_admission:%'
                and coalesce(e.value->>'prompt_version', e.value->'reader'->>'prompt', '') <> security.cdesc_prompt_version_v1()) or e.reason like 'superseded:%' or e.reason like 'reread:%')) old_prompt$n0$]);

select pg_temp.edit_all('security.course_description_check_with_v1(uuid,jsonb,jsonb,jsonb)', 'd310fa64f61f2243df1416d3e48f6bab', 'b4d4dabd655afb9352003b87b2b4387d',
  array[$o0$        v_checks jsonb; v_words text[];$o0$,
        $o1$  select c.provider_id into v_pid from catalogue.courses c where c.id = p_course;$o1$,
        $o2$    v_f := security.cdesc_sentence_fault_v1(s->>'text', s->>'quote',$o2$],
  array[$n0$        v_checks jsonb; v_words text[]; v_title text; v_prov text;$n0$,
        $n1$  select c.provider_id, c.canonical_title, coalesce(p.display_name, p.canonical_name) into v_pid, v_title, v_prov
    from catalogue.courses c left join catalogue.providers p on p.id = c.provider_id where c.id = p_course;$n1$,
        $n2$    -- 12 Nov 2026 (QA of #1049): the course's own title and provider are verified facts, not claims: they are left out of the sentence's tests (never added to the quote)
    v_f := security.cdesc_sentence_fault_v1(security.cdesc_known_strip_v1(s->>'text', v_title, v_prov), s->>'quote',$n2$]);

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

-- the readings worker v0.72.0 mis-recorded are read again once (field-gap-queue, within the daily cap); 733 when measured
do $rl$
declare v_n int;
begin
  update pipeline.field_enrich_items e set reason = left('reread: v0.72.0 mapping: ' || e.reason, 300), updated_at = now()
   where e.field = 'description' and e.state = 'skipped' and e.value->>'prompt_version' = 'cdesc-source-grounded-v1' and e.value->'reader'->>'worker' = 'coverage-sweep-worker-v0.72.0'
     and (e.reason like 'held: unsupported\_sentence:%' or e.reason like 'held: quote\_not\_on\_page:%');
  get diagnostics v_n = row_count;
  -- fixed: the bound is the measured 733 with room for the hour between measuring and applying (the worker stopped writing v0.72.0 readings when v0.72.1 deployed)
  if v_n > 2000 then raise exception 'relabel would mark % readings, far more than the 733 measured: stopped, nothing applied', v_n; end if;
  raise notice 'reread: % readings marked to be read again', v_n;
end $rl$;

do $chk$
begin
  if exists (select 1 from pipeline.platform_toolset_settings s where s.toolset_key = 'pipeline' and s.key = 'enrich.course_description_claim_words' and s.value ? 'students') then
    raise notice 'enrich.course_description_claim_words was changed by a person since it was measured: left as it is';
  end if;
end $chk$;
