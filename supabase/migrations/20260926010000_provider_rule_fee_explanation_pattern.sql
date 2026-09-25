-- Decision 131 (programme owner, 26 Sep 2026): the UQ provider rule also matches UQ's fee explanation
-- ("Approximate yearly cost of full-time tuition" + exact amount), recording the year only when printed
-- immediately after the amount (Decision 96). Same audit, superseded status and search refresh.
create or replace function security.provider_rule_admit_v1(p_apply boolean default false, p_limit integer default 500)
returns jsonb language plpgsql security definer
set search_path to 'pg_catalog','security','pipeline','catalogue','search'
as $function$
declare v_summary jsonb; v_samples jsonb; v_admitted int:=0; v_courses uuid[]:='{}'; r record; v_fee uuid; v_key text; v_code text; v_source uuid; v_review uuid;
begin
  create temp table if not exists _pra(wid uuid, course_id uuid, evidence_id uuid, interpretation_id uuid, rule_code text, amount numeric,
    basis text, excl text, fc jsonb, matched text, outcome text, fee_year int) on commit drop;
  truncate _pra;
  insert into _pra
  select w.id, w.entity_id, w.evidence_id, w.interpretation_id, pf.rule_code,
         (w.candidate_context->'provider_current_tuition'->>'amount')::numeric, pf.resolved_basis, pf.exclusion_pattern,
         (select f from jsonb_array_elements(coalesce(w.candidate_context->'fee_candidates','[]'::jsonb)) f
           where jsonb_typeof(f)='object' and (f->>'amount')::numeric=(w.candidate_context->'provider_current_tuition'->>'amount')::numeric
             and coalesce((f->>'domestic')::boolean,false)=false
           order by (f->>'score')::numeric desc nulls last limit 1),
         null, null, null
  from pipeline.layer3_work_items w
  join pipeline.provider_fee_profiles pf on pf.rule_code=w.candidate_context->>'provider_fee_rule' and pf.active and pf.review_by>=current_date
  where w.task_class='provider_current_tuition_validation'
    and w.candidate_context ? 'provider_fee_rule'
    and w.status in ('pending','layer4_required','failed','no_candidate','rejected')
    and coalesce(w.candidate_context->'provider_current_tuition'->>'audience','')='international'
  limit greatest(1,least(coalesce(p_limit,500),2000));

  update _pra set matched = security.layer4_clean_quote(fc->>'context') where fc is not null;
  update _pra set outcome = case
      when fc is null then 'no Layer 2 candidate with the exact amount (or it is domestic)'
      -- Pattern 1: the fee panel ("Fees A$X"), no exclusion words before "Duration".
      when lower(regexp_replace(coalesce(matched,''),'[\s,\[\]]','','g')) ~ ('fees(a|aud)?\$'||trunc(amount)::bigint::text)
       and coalesce(split_part(lower(coalesce(substring(matched from '(?i)fees\s*(?:a|aud)?\s*\$\s*[\d,\.]+(.{0,80})'),'')),'duration',1),'') !~* excl
        then 'admit'
      -- Pattern 2 (programme owner decision, 26 Sep 2026): UQ's fee explanation,
      -- "Approximate yearly cost of full-time tuition", followed by the exact amount,
      -- no exclusion words in the 40 characters after the amount (up to "Learn more").
      when lower(regexp_replace(coalesce(matched,''),'[\s,\[\]]','','g')) ~ 'approximateyearlycostoffull.?timetuition'
       and matched ~* ('(a|aud)\s*\$\s*'||replace(to_char(trunc(amount)::bigint,'FM999,999,999'),',',',?')||'([^0-9,]|$)')
       and coalesce(split_part(lower(coalesce(substring(matched from '(?i)(?:a|aud)\s*\$\s*'||replace(to_char(trunc(amount)::bigint,'FM999,999,999'),',',',?')||'(.{0,40})'),'')),'learn more',1),'') !~* excl
        then 'admit (fee explanation)'
      when lower(regexp_replace(coalesce(matched,''),'[\s,\[\]]','','g')) !~ ('fees(a|aud)?\$'||trunc(amount)::bigint::text) then 'amount not labelled "Fees" in the fee panel'
      else 'exclusion word next to the amount' end
  where true;
  -- Year only when printed immediately after the amount (Decision 96).
  -- Year only when printed immediately after the amount AND no other year appears in the
  -- snippet (e.g. "displayed is for 2026" beside "AUD $X 2027" is conflicting -> blank).
  update _pra set fee_year = substring(matched from '(?i)(?:a|aud)\s*\$\s*'||replace(to_char(trunc(amount)::bigint,'FM999,999,999'),',',',?')||'\s+(20[2-3][0-9])\y')::int
  where outcome='admit (fee explanation)';
  update _pra p set fee_year = null
  where outcome='admit (fee explanation)' and fee_year is not null
    and exists (select 1 from regexp_matches(p.matched,'\y(20[2-3][0-9])\y','g') m where m[1]::int <> p.fee_year);

  select jsonb_object_agg(outcome,n) into v_summary from (select outcome, count(*) n from _pra group by 1) x;
  select jsonb_agg(s) into v_samples from (select jsonb_build_object('outcome',outcome,'amount',amount,'year',fee_year,'text',left(matched,140)) s from _pra order by outcome, amount limit 6) y;

  if p_apply then
    for r in select * from _pra where outcome in ('admit','admit (fee explanation)') loop
      select course_code into v_code from catalogue.courses where id=r.course_id;
      select source_id into v_source from pipeline.evidence_artifacts where id=r.evidence_id;
      if v_code is null or v_source is null then continue; end if;
      v_key := lower(upper(btrim(v_code))||':international:'||coalesce(r.fee_year::text,'current')||':'||r.basis);
      insert into catalogue.course_fees(course_id,fee_year,audience,fee_type,amount,currency_code,basis,notes,source_id,evidence_id,confidence,campus_id,source_fee_key,status,last_verified_at,source_snapshot_at,updated_at)
      values (r.course_id,r.fee_year,'international','provider_current_tuition',r.amount,'AUD',r.basis,
              format('CF-247 provider rule admission (deterministic, Decision 106; %s); rule %s; work item %s',r.outcome,r.rule_code,r.wid),
              v_source,r.evidence_id,1,null,v_key,'active',now(),now(),now())
      on conflict(course_id,source_id,source_fee_key) where source_id is not null and source_fee_key is not null do nothing
      returning id into v_fee;
      update pipeline.layer3_work_items set status='admitted', completed_at=now(), last_error=null, updated_at=now() where id=r.wid;
      v_review := null;
      update pipeline.layer4_review_items set status='superseded', decided_at=now()
        where layer3_interpretation_id=r.interpretation_id and status='pending' returning id into v_review;
      insert into pipeline.provider_rule_admissions(work_item_id,review_item_id,course_id,course_fee_id,rule_code,amount,basis,matched_text)
      values (r.wid,v_review,r.course_id,v_fee,r.rule_code,r.amount,r.basis,left(r.matched,500));
      v_courses := v_courses || r.course_id; v_admitted := v_admitted+1;
    end loop;
    if cardinality(v_courses)>0 then perform search.refresh_course_enrichment_scoped_v1(v_courses, true); end if;
  end if;
  return jsonb_build_object('mode',case when p_apply then 'apply' else 'proof' end,'outcomes',coalesce(v_summary,'{}'::jsonb),'admitted',v_admitted,'samples',coalesce(v_samples,'[]'::jsonb));
end $function$;
revoke all on function security.provider_rule_admit_v1(boolean,integer) from public, anon, authenticated;
grant execute on function security.provider_rule_admit_v1(boolean,integer) to service_role;
