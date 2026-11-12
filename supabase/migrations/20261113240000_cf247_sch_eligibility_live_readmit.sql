-- CF-247 F-SCH.01 follow-up (scheduled review 12 Nov 2026 23:15 AEDT; Platform Admin directive 12 Nov 16:12 "Do not introduce another indefinite
-- manual activation checkpoint"). Two parts.
--
-- 1. The eligibility reader goes live again (sch_elig.apply_on 0 -> 1). Review of every shadow decision under the current rule (20261113065000,
--    re-evaluated 12 Nov 20:14 AEDT; no new proof read since): 17 proven reads, every action right —
--      domestic 9 (each quote names citizens or permanent residents only: CQU NCP grant, Auckland BProp, Yukon Sysco, EIT, Ara, ECNZ, Swinburne x2,
--        Adelaide Biggins): recorded domestic_only, nothing published;
--      linked_page_not_scholarship 4 (AUArts how-to-apply page); mixed_audience 1 (RMIT "onshore international candidate"): refused, right;
--      changed_since 3 (withdrawn earlier: Sydney Charles Perkins, Sydney Bowel Cancer, UTS Gullotta): held; part 2 decides them.
--    No international admission follows from the reset. The 17 shadow proofs are reset (applied = null) so the live rule acts on them.
-- 2. A re-admission path for candidates withdrawn with reason eligibility_proof_not_specific (20261113062000) whose proof is valid under the
--    current rule. New action readmit: proven international or both; the sentence on the provider's own site (not third-party, not government);
--    a linked page only when about the scholarship; the page's original refusal only international_not_stated; and the page is this award's own
--    page: its last path segment names the award (security.scholarship_page_names_award_v1, at least two of the name's distinctive words, or all
--    when fewer). Live re-admission (security.scholarship_readmit_v1) reverses the withdrawal: the same record active again (unpublished; the
--    publish rules decide as for any admission), the candidate admitted, the course links rebuilt by security.scholarship_sweep_apply_v1.
--    It is gated by its own new setting sch_elig.readmit_on, shipped 0 (shadow): until it is 1 the reader records readmit_held. Expected from
--    today's reads: Sydney Bowel Cancer Translational Research Scholarship readmit; Charles Perkins (an awards list page) and UTS (how-to-apply
--    page) stay withdrawn.
-- Replaces: security.scholarship_eligibility_apply_v1(integer) (same name and signature; md5-guarded edits). Retires: nothing.

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

insert into pipeline.platform_toolset_settings (toolset_key, key, label, help, kind, value, min_value, max_value, unit, sort, reason, section, used_by)
values ('pipeline', 'sch_elig.readmit_on', 'Scholarship eligibility reader: re-admit withdrawn records whose proof is now valid',
        '1: a scholarship withdrawn for a proof that was not specific is admitted again (unpublished, the publish rules then decide) when its proof passes the current rule and the page is the award''s own page. 0: the reader records readmit_held only.',
        'number', '0'::jsonb, 0, 1, 'on (1) or off (0)', 1423, 'F-SCH.01 12 Nov 2026 23:15: re-admission path ships in shadow', 'Scholarship eligibility reader', 'security.scholarship_eligibility_apply_v1')
on conflict (toolset_key, key) do nothing;

-- the page is this award's own page: its last path segment names the award
create or replace function security.scholarship_page_names_award_v1(p_url text, p_name text)
returns boolean language sql immutable set search_path = '' as $$
  with seg as (select lower(regexp_replace(regexp_replace(regexp_replace(coalesce(p_url, ''), '[?#].*$', ''), '/+$', ''), '^.*/', '')) s),
  w as (select distinct t from regexp_split_to_table(lower(coalesce(p_name, '')), '[^a-z0-9]+') t
         where length(t) >= 4 and t not in ('scholarship', 'scholarships', 'award', 'awards', 'bursary', 'bursaries', 'grant', 'grants', 'prize', 'prizes',
                                            'with', 'from', 'that', 'this', 'their', 'university', 'program', 'programme'))
  select case when (select count(*) from w) = 0 then false
              else (select count(*) from w, seg where seg.s ~ ('(^|[^a-z0-9])' || w.t || '([^a-z0-9]|$)')) >= least(2, (select count(*) from w)) end
$$;
comment on function security.scholarship_page_names_award_v1(text, text) is
  'F-SCH.01 re-admission: true when the last path segment of the page names the award (at least two of its distinctive words, or all when fewer).';

-- re-admission: the reverse of security.scholarship_admission_withdraw_v1 for one candidate
create or replace function security.scholarship_readmit_v1(p_candidate bigint, p_evidence jsonb)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare c record; s record; v_apply jsonb;
begin
  select * into c from pipeline.scholarship_page_candidates where id = p_candidate for update;
  if c.id is null or c.admit_status is distinct from 'withdrawn' or c.admitted_scholarship_id is null then
    return jsonb_build_object('readmitted', false, 'reason', 'not a withdrawn admission');
  end if;
  select * into s from scholarship.scholarships where id = c.admitted_scholarship_id for update;
  if s.id is null or s.lifecycle_status <> 'inactive' or s.publication_status = 'published' then
    return jsonb_build_object('readmitted', false, 'reason', 'record not withdrawn');
  end if;
  update scholarship.scholarships set lifecycle_status = 'active', updated_at = now() where id = s.id;
  update pipeline.scholarship_page_candidates set admit_status = 'admitted', admit_reasons = null,
         facts = coalesce(facts, '{}'::jsonb) || jsonb_build_object('eligibility_read', p_evidence, 'international', true) where id = c.id;
  insert into pipeline.scholarship_sweep_changes(scholarship_id, field, before_value, after_value)
  values (s.id, 'admission_readmitted', jsonb_build_object('lifecycle_status', 'inactive'), p_evidence);
  v_apply := security.scholarship_sweep_apply_v1(s.id);
  insert into pipeline.scholarship_admission_log(candidate_id, scholarship_id, provider_id, action, detail)
  values (c.id, s.id, c.provider_id, 'readmitted', p_evidence || jsonb_build_object('apply', v_apply));
  return jsonb_build_object('readmitted', true, 'scholarship_id', s.id, 'apply', v_apply);
end $$;
comment on function security.scholarship_readmit_v1(bigint, jsonb) is
  'F-SCH.01: re-admits a scholarship withdrawn for a proof that was not specific, once its proof is valid (the same record active again, unpublished; course links rebuilt).';
revoke all on function security.scholarship_readmit_v1(bigint, jsonb) from public, anon, authenticated;
revoke all on function security.scholarship_page_names_award_v1(text, text) from public, anon, authenticated;

select pg_temp.edit_n('security.scholarship_eligibility_apply_v1(integer)', '45e52f66312824e4e7265814cb712728', array[
  array[$o$v_silent boolean := security.pipeline_num_v1('sch_elig.silent_resolves', 0) >= 1;$o$,
        $n$v_silent boolean := security.pipeline_num_v1('sch_elig.silent_resolves', 0) >= 1;
        v_readmit boolean := security.pipeline_num_v1('sch_elig.readmit_on', 0) >= 1;  -- 20261113240000: re-admission path$n$],
  array[$o$    v_act := case
      when r.admit_status is distinct from 'rejected'$o$,
        $n$    v_act := case
      -- 20261113240000: a record withdrawn for a proof that was not specific, whose proof passes the current rule on the award's own page
      when r.admit_status = 'withdrawn' and coalesce(r.admit_reasons, '{}'::text[]) = array['eligibility_proof_not_specific'] and r.admitted_scholarship_id is not null
           and r.outcome = 'proven' and coalesce((r.result->>'audience_proven')::boolean, false) and r.result->>'audience' in ('international', 'both') then
        case when not coalesce(security.url_on_provider_sites(v_url, r.provider_id), false) or security.third_party_host_v1(coalesce(v_url, ''))
                  or security.scholarship_government_host_v1(v_url) then 'sentence_off_provider_site'
             when coalesce(r.result->>'source', 'page') = 'linked'
                  and (coalesce(v_url, '') !~* '(scholar|award|bursar|grant|prize|stipend|terms|condition|eligib|rules|funding|fee[-_]?waiver)'
                       or coalesce(v_url, '') ~* '(how[-_]to[-_]apply|/admissions?([-/_]|$)|apply[-_]now|/apply(/|$))') then 'linked_page_not_scholarship'
             when exists (select 1 from jsonb_array_elements_text(case when jsonb_typeof(r.facts->'admission'->'reasons') = 'array' then r.facts->'admission'->'reasons' else '[]'::jsonb end) x
                           where x <> 'international_not_stated') then 'proven_other_refusals'
             when not security.scholarship_page_names_award_v1(r.page_url, (select s.name from scholarship.scholarships s where s.id = r.admitted_scholarship_id)) then 'readmit_page_not_specific'
             else 'readmit' end
      when r.admit_status is distinct from 'rejected'$n$],
  array[$o$    elsif v_act = 'silent' and v_silent then$o$,
        $n$    elsif v_act = 'readmit' and not v_readmit then
      update pipeline.scholarship_eligibility_reads set applied = jsonb_build_object('mode', 'live', 'action', 'readmit_held', 'at', now()), updated_at = now() where candidate_id = r.candidate_id;
      v_act := 'readmit_held';
    elsif v_act = 'readmit' then
      v_res := security.scholarship_readmit_v1(r.candidate_id, v_ev);
      update pipeline.scholarship_eligibility_reads set applied = jsonb_build_object('mode', 'live', 'action', v_act, 'readmission', v_res, 'at', now()), updated_at = now() where candidate_id = r.candidate_id;
      v_act := case when coalesce((v_res->>'readmitted')::boolean, false) then 'readmitted' else 'readmission_refused' end;
    elsif v_act = 'silent' and v_silent then$n$]
], array[1, 1, 1]);

-- 1. live again: the reviewed shadow proofs are acted on by the live rule
update pipeline.platform_toolset_settings set value = to_jsonb(1), updated_at = now(), updated_by = '63ba56cb-48d4-4169-98c2-7c4d1f72925b',
       reason = 'F-SCH.01 12 Nov 2026 23:15: every shadow decision under rule 20261113065000 reviewed and right (9 domestic, 5 refused, 3 held); live again'
 where toolset_key = 'pipeline' and key = 'sch_elig.apply_on' and value is distinct from to_jsonb(1);
insert into pipeline.admin_control_events(area, action, target, detail, actor)
values ('scholarships', 'setting_changed', 'sch_elig.apply_on 0 -> 1 (eligibility reader live again after the shadow review)',
        jsonb_build_object('key', 'sch_elig.apply_on', 'from', 0, 'to', 1, 'reviewed', 17, 'domestic', 9, 'linked_page_not_scholarship', 4, 'mixed_audience', 1, 'changed_since', 3,
                           'readmit_on', 0, 'migration', '20261113240000'),
        '63ba56cb-48d4-4169-98c2-7c4d1f72925b');
update pipeline.scholarship_eligibility_reads set applied = null, updated_at = now()
 where outcome = 'proven' and applied->>'mode' = 'shadow';

do $post$ begin
  if not security.scholarship_page_names_award_v1('https://www.sydney.edu.au/scholarships/c/bowel-cancer-translational-research-scholarship.html', 'Bowel Cancer Translational Research Scholarship') then raise exception 'post-check: own page not recognised'; end if;
  if security.scholarship_page_names_award_v1('https://www.sydney.edu.au/charles-perkins-centre/our-research/prizes-and-awards.html', 'Charles Perkins Centre Summer Scholarships') then raise exception 'post-check: a list page must not count'; end if;
  if security.scholarship_page_names_award_v1('https://www.unbc.ca/financial-aid/graduate-awards-overview', 'Graduate Entrance Research Scholarship (GERS)') then raise exception 'post-check: an overview page must not count'; end if;
end $post$;
