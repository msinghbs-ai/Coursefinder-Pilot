-- CF-247 F-SCH.01 proof v2 shadow review (12 Nov 2026 19:58 AEDT; 15 proven reads since worker v0.78.0): 6 of 15 are still wrong.
--   Five international proofs come from a linked general admissions page, not from the scholarship: Alberta University of the Arts x4
--   ("International Applicants (non-Canadian citizens) Apply via AUArtsApply", how-to-apply-for-a-bachelors-degree) and UTS ("Start your
--   application as an international student", for-students/admissions-entry/how-to-apply).
--   One domestic proof names international candidates (RMIT: "an Australian citizen, permanent resident or an onshore international candidate").
-- The rule now refuses a linked-page sentence unless the linked page is about the scholarship, its terms, eligibility or funding (and not a general
-- application or admissions page), and does not record domestic-only for a sentence that also names international or overseas candidates.
-- The reader stays in shadow (sch_elig.apply_on 0; post-check). The proofs recorded in shadow are evaluated again under the corrected rule.
-- Replaces: nothing (the proof rule is extended). Retires: nothing.

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

select pg_temp.edit_n('security.scholarship_eligibility_apply_v1(integer)', '8a72bff9ffae9c512007402f90b73c06', array[
  array[$o$      when r.outcome = 'proven' and coalesce((r.result->>'audience_proven')::boolean, false) and r.result->>'audience' = 'domestic' then 'domestic'$o$,
        $n$      -- 20261113065000: a sentence that also names international or overseas candidates is not a domestic-only proof
      when r.outcome = 'proven' and coalesce((r.result->>'audience_proven')::boolean, false) and r.result->>'audience' = 'domestic'
           and coalesce(r.result->>'audience_quote', '') ~* '\m(international|overseas|non[- ]?residents?)\M' then 'mixed_audience'
      when r.outcome = 'proven' and coalesce((r.result->>'audience_proven')::boolean, false) and r.result->>'audience' = 'domestic' then 'domestic'$n$],
  array[$o$        case when not coalesce(security.url_on_provider_sites(v_url, r.provider_id), false) or security.third_party_host_v1(coalesce(v_url, ''))
                  or security.scholarship_government_host_v1(v_url) then 'sentence_off_provider_site'$o$,
        $n$        case when not coalesce(security.url_on_provider_sites(v_url, r.provider_id), false) or security.third_party_host_v1(coalesce(v_url, ''))
                  or security.scholarship_government_host_v1(v_url) then 'sentence_off_provider_site'
             -- 20261113065000: a linked page proves only when it is about the scholarship, its terms, eligibility or funding
             when coalesce(r.result->>'source', 'page') = 'linked'
                  and (coalesce(v_url, '') !~* '(scholar|award|bursar|grant|prize|stipend|terms|condition|eligib|rules|funding|fee[-_]?waiver)'
                       or coalesce(v_url, '') ~* '(how[-_]to[-_]apply|/admissions?([-/_]|$)|apply[-_]now|/apply(/|$))') then 'linked_page_not_scholarship'$n$]
], array[1, 1]);

do $r$
declare v_n int;
begin
  update pipeline.scholarship_eligibility_reads set applied = null, updated_at = now()
   where outcome = 'proven' and applied->>'mode' = 'shadow';
  get diagnostics v_n = row_count;
  raise notice 'shadow proofs to evaluate again: %', v_n;
  if security.pipeline_num_v1('sch_elig.apply_on', -1) <> 0 then raise exception 'post-check: the reader stays in shadow'; end if;
end $r$;
