-- Decision 106: deterministic admission for pages covered by an approved provider fee rule.
-- No AI. Uses the fee-panel text Layer 2 already recorded for each fee candidate.
-- An item is admitted only when a Layer 2 candidate has the exact target amount, is not
-- domestic, is labelled "Fees", and the text right after the amount (up to "Duration",
-- at most 80 characters) contains none of the rule's exclusion words. Year is left blank
-- (none is printed beside the amount on rule-covered UQ pages). Everything else stays on
-- its current path. Default is proof mode (no writes).
create table if not exists pipeline.provider_rule_admissions(
  id uuid primary key default extensions.gen_random_uuid(),
  work_item_id uuid not null,
  review_item_id uuid,
  course_id uuid not null,
  course_fee_id uuid,
  rule_code text not null,
  amount numeric not null,
  basis text not null,
  matched_text text not null,
  admitted_at timestamptz not null default now()
);
alter table pipeline.provider_rule_admissions enable row level security;
revoke all on pipeline.provider_rule_admissions from public, anon, authenticated;

create or replace function security.provider_rule_admit_v1(p_apply boolean default false, p_limit integer default 500)
returns jsonb language plpgsql security definer
set search_path to 'pg_catalog','security','pipeline','catalogue','search'
as $function$
declare v_summary jsonb; v_samples jsonb; v_admitted int:=0; v_courses uuid[]:='{}'; r record; v_fee uuid; v_key text; v_code text; v_source uuid; v_review uuid;
begin
  create temp table if not exists _pra(wid uuid, course_id uuid, evidence_id uuid, interpretation_id uuid, rule_code text, amount numeric,
    basis text, excl text, fc jsonb, matched text, outcome text) on commit drop;
  truncate _pra;
  insert into _pra
  select w.id, w.entity_id, w.evidence_id, w.interpretation_id, pf.rule_code,
         (w.candidate_context->'provider_current_tuition'->>'amount')::numeric, pf.resolved_basis, pf.exclusion_pattern,
         (select f from jsonb_array_elements(coalesce(w.candidate_context->'fee_candidates','[]'::jsonb)) f
           where jsonb_typeof(f)='object' and (f->>'amount')::numeric=(w.candidate_context->'provider_current_tuition'->>'amount')::numeric
             and coalesce((f->>'domestic')::boolean,false)=false
           order by (f->>'score')::numeric desc nulls last limit 1),
         null, null
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
      when lower(regexp_replace(coalesce(matched,''),'[\s,\[\]]','','g')) !~ ('fees(a|aud)?\$'||trunc(amount)::bigint::text) then 'amount not labelled "Fees" in the fee panel'
      when coalesce(split_part(lower(coalesce(substring(matched from '(?i)fees\s*(?:a|aud)?\s*\$\s*[\d,\.]+(.{0,80})'),'')),'duration',1),'') ~* excl then 'exclusion word next to the amount'
      else 'admit' end
  where true;

  select jsonb_object_agg(outcome,n) into v_summary from (select outcome, count(*) n from _pra group by 1) x;
  select jsonb_agg(s) into v_samples from (select jsonb_build_object('outcome',outcome,'amount',amount,'text',left(matched,140)) s from _pra order by outcome, amount limit 6) y;

  if p_apply then
    for r in select * from _pra where outcome='admit' loop
      select course_code into v_code from catalogue.courses where id=r.course_id;
      select source_id into v_source from pipeline.evidence_artifacts where id=r.evidence_id;
      if v_code is null or v_source is null then continue; end if;
      v_key := lower(upper(btrim(v_code))||':international:current:'||r.basis);
      insert into catalogue.course_fees(course_id,fee_year,audience,fee_type,amount,currency_code,basis,notes,source_id,evidence_id,confidence,campus_id,source_fee_key,status,last_verified_at,source_snapshot_at,updated_at)
      values (r.course_id,null,'international','provider_current_tuition',r.amount,'AUD',r.basis,
              format('CF-247 provider rule admission (deterministic, Decision 106); rule %s; work item %s',r.rule_code,r.wid),
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
