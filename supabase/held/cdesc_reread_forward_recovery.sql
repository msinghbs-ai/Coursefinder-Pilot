-- HELD forward recovery for migration 20261112190000_cf247_cdesc_first_cycle_reread.sql (CF-247 F-CDESC). NOT a migration: run by hand only on the Platform Admin's decision.
-- Restores the gap function and check bodies and the claim words (with "students"); takes the reread: prefix off readings not yet read again (a reason that was
-- longer than 275 characters keeps its first 275: reasons are held to 300).
create or replace function pg_temp.edit_all(p_sig text, p_before text, p_after text, p_olds text[], p_news text[]) returns text language plpgsql as $f$
declare v_def text := pg_get_functiondef(p_sig::regprocedure); v_src text := (select p.prosrc from pg_proc p where p.oid = p_sig::regprocedure); v_c int; i int;
begin
  -- fixed: the guard is the md5 of the function body (pg_proc.prosrc), the same text on PostgreSQL 16 and 17
  if md5(v_src) = p_after then return p_sig || ': already applied'; end if;
  if md5(v_src) <> p_before then raise exception 'live % differs from the definition this recovery restores from (body md5 %)', p_sig, md5(v_src); end if;
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

select pg_temp.edit_all('security.enrich_course_text_gaps_v1(text[])', 'd117edb4198b81a692e93af9a937110e', 'ddba9b553a63a9e38c49782a0b0d29c9',
  array[$o0$               -- 12 Nov 2026 (first-cycle check of #1047): a reading superseded in Layer 4, or marked reread: (a reading the worker mis-recorded, read again on a recorded decision), is read again whatever prompt made it
               (f = 'description' and e.state = 'skipped' and ((e.reason like 'held%' and e.reason not like 'held\_first\_admission:%'
                and coalesce(e.value->>'prompt_version', e.value->'reader'->>'prompt', '') <> security.cdesc_prompt_version_v1()) or e.reason like 'superseded:%' or e.reason like 'reread:%')) old_prompt$o0$],
  array[$n0$               (f = 'description' and e.state = 'skipped' and ((e.reason like 'held%' and e.reason not like 'held\_first\_admission:%') or e.reason like 'superseded:%')
                and coalesce(e.value->>'prompt_version', e.value->'reader'->>'prompt', '') <> security.cdesc_prompt_version_v1()) old_prompt$n0$]);

select pg_temp.edit_all('security.course_description_check_with_v1(uuid,jsonb,jsonb,jsonb)', 'b4d4dabd655afb9352003b87b2b4387d', 'd310fa64f61f2243df1416d3e48f6bab',
  array[$o0$        v_checks jsonb; v_words text[]; v_title text; v_prov text;$o0$,
        $o1$  select c.provider_id, c.canonical_title, coalesce(p.display_name, p.canonical_name) into v_pid, v_title, v_prov
    from catalogue.courses c left join catalogue.providers p on p.id = c.provider_id where c.id = p_course;$o1$,
        $o2$    -- 12 Nov 2026 (QA of #1049): the course's own title and provider are verified facts, not claims: they are left out of the sentence's tests (never added to the quote)
    v_f := security.cdesc_sentence_fault_v1(security.cdesc_known_strip_v1(s->>'text', v_title, v_prov), s->>'quote',$o2$],
  array[$n0$        v_checks jsonb; v_words text[];$n0$,
        $n1$  select c.provider_id into v_pid from catalogue.courses c where c.id = p_course;$n1$,
        $n2$    v_f := security.cdesc_sentence_fault_v1(s->>'text', s->>'quote',$n2$]);

with u as (
  update pipeline.platform_toolset_settings set value = '["ranked", "ranking", "rankings", "rated", "rating", "qs", "times higher", "top 1%", "employment", "employability", "employed", "employers", "graduate outcomes", "salary", "salaries", "accredited", "accreditation", "facilities", "state-of-the-art", "five-star", "5-star", "students", "staff", "alumni", "award", "awards"]'::jsonb, reason = 'Forward recovery of migration 20261112190000', updated_at = now()
   where toolset_key = 'pipeline' and key = 'enrich.course_description_claim_words' and value = '["ranked", "ranking", "rankings", "rated", "rating", "qs", "times higher", "top 1%", "employment", "employability", "employed", "employers", "graduate outcomes", "salary", "salaries", "accredited", "accreditation", "facilities", "state-of-the-art", "five-star", "5-star", "staff", "alumni", "award", "awards"]'::jsonb returning key)
insert into pipeline.admin_control_events(area, action, target, detail, actor)
select 'toolsets', 'setting', 'pipeline.enrich.course_description_claim_words', jsonb_build_object('before', '["ranked", "ranking", "rankings", "rated", "rating", "qs", "times higher", "top 1%", "employment", "employability", "employed", "employers", "graduate outcomes", "salary", "salaries", "accredited", "accreditation", "facilities", "state-of-the-art", "five-star", "5-star", "staff", "alumni", "award", "awards"]'::jsonb, 'after', '["ranked", "ranking", "rankings", "rated", "rating", "qs", "times higher", "top 1%", "employment", "employability", "employed", "employers", "graduate outcomes", "salary", "salaries", "accredited", "accreditation", "facilities", "state-of-the-art", "five-star", "5-star", "students", "staff", "alumni", "award", "awards"]'::jsonb, 'reason', 'Forward recovery of migration 20261112190000'),
       '63ba56cb-48d4-4169-98c2-7c4d1f72925b' from u;
update pipeline.field_enrich_items e set reason = substr(e.reason, length('reread: v0.72.0 mapping: ') + 1), updated_at = now()
 where e.field = 'description' and e.state = 'skipped' and e.reason like 'reread: v0.72.0 mapping: %';
