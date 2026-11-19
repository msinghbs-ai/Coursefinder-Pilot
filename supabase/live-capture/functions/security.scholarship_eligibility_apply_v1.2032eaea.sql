CREATE OR REPLACE FUNCTION security.scholarship_eligibility_apply_v1(p_limit integer DEFAULT NULL::integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
-- F-SCH.01: the rule for finished reads. In shadow (sch_elig.apply_on 0) only what would be done is recorded on the read. Live:
--   domestic proven                         -> the case is recorded domestic_only (coverage state domestic_only, resolved);
--   international or both proven, the page's only refusal was international_not_stated, the sentence's page on the provider's own site
--                                           -> the page facts record the sentence and the candidate goes back through
--                                              security.scholarship_admit_from_provider_page_v1, which checks every other rule again;
--   silent, with sch_elig.silent_resolves   -> recorded as not proven for international students (resolved); otherwise it stays unresolved and
--                                              security.har_sch_generate_v1 may raise it for a person.
-- No agent and no person is replaced: the decision is the existing admission rule's, on a sentence the page states.
declare v_lim int := greatest(0, coalesce(p_limit, security.pipeline_num_v1('batch.sch_eligibility_apply', 200)::int));
        v_live boolean := security.pipeline_num_v1('sch_elig.apply_on', 0) >= 1;
        v_silent boolean := security.pipeline_num_v1('sch_elig.silent_resolves', 0) >= 1;
        v_readmit boolean := security.pipeline_num_v1('sch_elig.readmit_on', 0) >= 1;  -- 20261113260000: re-admission path
        r record; v_act text; v_url text; v_only boolean; v_res jsonb; v_ev jsonb; v_by jsonb := '{}'::jsonb;
begin
  for r in select e.candidate_id, e.outcome, e.result, c.provider_id, c.admit_status, c.admit_reasons, c.facts, c.admitted_scholarship_id, c.matched_scholarship_id,
                  coalesce(c.final_url, c.url) page_url
             from pipeline.scholarship_eligibility_reads e join pipeline.scholarship_page_candidates c on c.id = e.candidate_id
            where e.state in ('done', 'failed') and e.applied is null
            order by e.read_at nulls last, e.candidate_id limit v_lim loop
    v_url := coalesce(nullif(r.result->>'source_url', ''), r.page_url);
    v_only := coalesce(r.admit_reasons, '{}'::text[]) <@ array['international_not_stated']
              and not exists (select 1 from jsonb_array_elements_text(case when jsonb_typeof(r.facts->'admission'->'reasons') = 'array' then r.facts->'admission'->'reasons' else '[]'::jsonb end) x
                               where x <> 'international_not_stated');
    v_act := case
      -- 20261113260000: a record withdrawn for a proof that was not specific, whose proof passes the current rule on the award's own page
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
             when security.scholarship_readmit_blocker_v1(r.admitted_scholarship_id) is not null then 'readmit_' || security.scholarship_readmit_blocker_v1(r.admitted_scholarship_id)
             else 'readmit' end
      when r.admit_status is distinct from 'rejected' or r.admitted_scholarship_id is not null or r.matched_scholarship_id is not null then 'changed_since'
      -- 20261113065000: a sentence that also names international or overseas candidates is not a domestic-only proof
      when r.outcome = 'proven' and coalesce((r.result->>'audience_proven')::boolean, false) and r.result->>'audience' = 'domestic'
           and coalesce(r.result->>'audience_quote', '') ~* '\m(international|overseas|non[- ]?residents?)\M' then 'mixed_audience'
      when r.outcome = 'proven' and coalesce((r.result->>'audience_proven')::boolean, false) and r.result->>'audience' = 'domestic' then 'domestic'
      when r.outcome = 'proven' and coalesce((r.result->>'audience_proven')::boolean, false) and r.result->>'audience' in ('international', 'both') then
        case when not coalesce(security.url_on_provider_sites(v_url, r.provider_id), false) or security.third_party_host_v1(coalesce(v_url, ''))
                  or security.scholarship_government_host_v1(v_url) then 'sentence_off_provider_site'
             -- 20261113065000: a linked page proves only when it is about the scholarship, its terms, eligibility or funding
             when coalesce(r.result->>'source', 'page') = 'linked'
                  and (coalesce(v_url, '') !~* '(scholar|award|bursar|grant|prize|stipend|terms|condition|eligib|rules|funding|fee[-_]?waiver)'
                       or coalesce(v_url, '') ~* '(how[-_]to[-_]apply|/admissions?([-/_]|$)|apply[-_]now|/apply(/|$))') then 'linked_page_not_scholarship'
             when not v_only then 'proven_other_refusals'
             else 'admit' end
      when r.outcome = 'silent' then 'silent'
      else 'unsettled' end;
    v_ev := jsonb_build_object('audience', r.result->>'audience', 'quote', r.result->>'audience_quote', 'source', r.result->>'source', 'source_url', v_url,
                               'model', r.result->>'model', 'read_at', now(), 'by', 'security.scholarship_eligibility_apply_v1');
    if not v_live then
      update pipeline.scholarship_eligibility_reads set applied = jsonb_build_object('mode', 'shadow', 'action', v_act, 'at', now()), updated_at = now() where candidate_id = r.candidate_id;
    elsif v_act = 'domestic' then
      update pipeline.scholarship_page_candidates set admit_reasons = array_append(array_remove(coalesce(admit_reasons, '{}'::text[]), 'international_not_stated'), 'domestic_only'),
             facts = coalesce(facts, '{}'::jsonb) || jsonb_build_object('eligibility_read', v_ev) where id = r.candidate_id;
      insert into pipeline.scholarship_admission_log(candidate_id, provider_id, action, detail) values (r.candidate_id, r.provider_id, 'eligibility_domestic', v_ev);
      update pipeline.scholarship_eligibility_reads set applied = jsonb_build_object('mode', 'live', 'action', v_act, 'at', now()), updated_at = now() where candidate_id = r.candidate_id;
    elsif v_act = 'admit' then
      update pipeline.scholarship_page_candidates
         set facts = jsonb_set(jsonb_set(jsonb_set(coalesce(facts, '{}'::jsonb) || jsonb_build_object('international', true, 'eligibility_read', v_ev, 'eligibility_excerpt', left(coalesce(r.result->>'audience_quote', ''), 600)),
                                                   '{admission,international_explicit}', 'true'::jsonb, true), '{admission,admit}', 'true'::jsonb, true), '{admission,reasons}', '[]'::jsonb, true),
             admit_status = null, admit_reasons = null
       where id = r.candidate_id;
      v_res := security.scholarship_admit_from_provider_page_v1(r.candidate_id);
      update pipeline.scholarship_eligibility_reads set applied = jsonb_build_object('mode', 'live', 'action', v_act, 'admission', v_res, 'at', now()), updated_at = now() where candidate_id = r.candidate_id;
      v_act := case when coalesce((v_res->>'admitted')::boolean, false) then 'admitted' else 'admission_refused' end;
    elsif v_act = 'readmit' and not v_readmit then
      update pipeline.scholarship_eligibility_reads set applied = jsonb_build_object('mode', 'live', 'action', 'readmit_held', 'at', now()), updated_at = now() where candidate_id = r.candidate_id;
      v_act := 'readmit_held';
    elsif v_act = 'readmit' then
      v_res := security.scholarship_readmit_v1(r.candidate_id, v_ev);
      update pipeline.scholarship_eligibility_reads set applied = jsonb_build_object('mode', 'live', 'action', v_act, 'readmission', v_res, 'at', now()), updated_at = now() where candidate_id = r.candidate_id;
      v_act := case when coalesce((v_res->>'readmitted')::boolean, false) then 'readmitted' else 'readmission_refused' end;
    elsif v_act = 'silent' and v_silent then
      update pipeline.scholarship_page_candidates set admit_reasons = array_append(array_remove(coalesce(admit_reasons, '{}'::text[]), 'international_not_stated'), 'international_not_proven_after_eligibility_read'),
             facts = coalesce(facts, '{}'::jsonb) || jsonb_build_object('eligibility_read', v_ev) where id = r.candidate_id;
      insert into pipeline.scholarship_admission_log(candidate_id, provider_id, action, detail) values (r.candidate_id, r.provider_id, 'eligibility_not_proven', v_ev);
      update pipeline.scholarship_eligibility_reads set applied = jsonb_build_object('mode', 'live', 'action', 'silent_resolved', 'at', now()), updated_at = now() where candidate_id = r.candidate_id;
      v_act := 'silent_resolved';
    else
      update pipeline.scholarship_eligibility_reads set applied = jsonb_build_object('mode', 'live', 'action', v_act, 'at', now()), updated_at = now() where candidate_id = r.candidate_id;
    end if;
    v_by := v_by || jsonb_build_object(v_act, coalesce((v_by->>v_act)::int, 0) + 1);
  end loop;
  return jsonb_build_object('live', v_live, 'by_action', v_by);
end $function$
