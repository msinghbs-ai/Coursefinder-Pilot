-- CF-247 Decision 162 (Platform Admin approval, 28 Sep 2026): deterministic RMIT fee-basis rule.
-- RMIT course pages print the basis next to the fee: "Full-fee places: AU $31,680 (2027 total)" or
-- "... (2027 annual)". The rule admits the Layer 2 candidate only when the fee panel shows exactly that pattern
-- for the candidate's amount: "(YYYY annual)" -> basis annual, fee year YYYY; "(YYYY total)" -> basis
-- total_indicative, fee year YYYY. Anything else (for example a scholarship amount picked up as a fee) is left to
-- Layer 3 / Layer 4. Kept separate from pipeline.provider_fee_profiles, whose stamping step applies one basis
-- to every item (UQ). Runs every 10 minutes, just before the Layer 3 dispatcher.
create table if not exists pipeline.provider_fee_basis_rules(
  rule_code text primary key,
  provider_id uuid not null references catalogue.providers(id),
  page_url_pattern text not null,
  fee_pattern text not null,
  basis_map jsonb not null,
  approval_ref text not null,
  approved_at timestamptz not null default now(),
  review_by date not null,
  active boolean not null default true);
alter table pipeline.provider_fee_basis_rules enable row level security;
revoke all on pipeline.provider_fee_basis_rules from public, anon, authenticated;

insert into pipeline.provider_fee_basis_rules(rule_code,provider_id,page_url_pattern,fee_pattern,basis_map,approval_ref,review_by)
select 'rmit-program-page-year-basis-v1', pr.provider_id, '^https://www\.rmit\.edu\.au/study-with-us/',
       'full-fee places:\s*(?:a|au|aud)\s*\$\s*{AMOUNT}\s*\((20[2-3][0-9])\s+(annual|total)\)',
       '{"annual":"annual","total":"total_indicative"}'::jsonb,
       'CF-CHG-20260915-247; Decision 162; Platform Admin approval 28 Sep 2026 (RMIT pages print "(YYYY annual)" or "(YYYY total)" beside the fee)',
       date '2027-03-31'
  from catalogue.provider_registrations pr where upper(pr.registration_code)='00122A' and lower(pr.registration_scheme)='cricos'
on conflict (rule_code) do nothing;

create or replace function security.provider_basis_rule_admit_v1(p_apply boolean default false, p_limit integer default 200)
returns jsonb language plpgsql security definer set search_path to 'pg_catalog','security','pipeline','catalogue','search' as $f$
declare r record; v_text text; v_m text[]; v_basis text; v_year int; v_code text; v_source uuid; v_key text; v_fee uuid; v_review uuid;
        v_admitted int:=0; v_nomatch int:=0; v_courses uuid[]:='{}'; v_samples jsonb:='[]'::jsonb; v_amt_re text;
begin
  if current_user<>'postgres' and coalesce(auth.role(),'')<>'service_role' then raise exception 'service_role required'; end if;
  for r in
    select w.id wid, w.entity_id course_id, w.evidence_id, w.interpretation_id, br.rule_code, br.fee_pattern, br.basis_map,
           (w.candidate_context->'provider_current_tuition'->>'amount')::numeric amount,
           (select f->>'context' from jsonb_array_elements(coalesce(w.candidate_context->'fee_candidates','[]'::jsonb)) f
             where jsonb_typeof(f)='object' and (f->>'amount')::numeric=(w.candidate_context->'provider_current_tuition'->>'amount')::numeric
               and coalesce((f->>'domestic')::boolean,false)=false order by (f->>'score')::numeric desc nulls last limit 1) ctx
      from pipeline.layer3_work_items w
      join catalogue.courses c on c.id=w.entity_id
      join pipeline.provider_fee_basis_rules br on br.provider_id=c.provider_id and br.active and br.review_by>=current_date
      join pipeline.evidence_artifacts e on e.id=w.evidence_id and e.source_url ~* br.page_url_pattern
     where w.task_class='provider_current_tuition_validation'
       and w.status in ('pending','layer4_required','failed','no_candidate','rejected')
       and coalesce(w.candidate_context->'provider_current_tuition'->>'audience','')='international'
       and not exists (select 1 from catalogue.course_fees f where f.course_id=w.entity_id and f.fee_type='provider_current_tuition' and f.status='active')
     limit greatest(1,least(coalesce(p_limit,200),2000))
  loop
    v_text:=security.layer4_clean_quote(r.ctx);
    v_amt_re:=replace(to_char(trunc(r.amount)::bigint,'FM999,999,999'),',',',?');
    v_m:=regexp_match(coalesce(v_text,''), replace(r.fee_pattern,'{AMOUNT}',v_amt_re)||'([^0-9,]|$)', 'i');
    if v_m is null then v_nomatch:=v_nomatch+1; continue; end if;
    v_year:=v_m[1]::int; v_basis:=r.basis_map->>lower(v_m[2]);
    if v_basis is null then v_nomatch:=v_nomatch+1; continue; end if;
    if jsonb_array_length(v_samples)<6 then v_samples:=v_samples||jsonb_build_object('amount',r.amount,'year',v_year,'basis',v_basis,'text',left(substring(v_text from '(?i)full-fee places.{0,60}'),90)); end if;
    if not p_apply then v_admitted:=v_admitted+1; continue; end if;
    select course_code into v_code from catalogue.courses where id=r.course_id;
    select source_id into v_source from pipeline.evidence_artifacts where id=r.evidence_id;
    if v_code is null or v_source is null then v_nomatch:=v_nomatch+1; continue; end if;
    v_key:=lower(upper(btrim(v_code))||':international:'||v_year||':'||v_basis);
    v_fee:=null;
    insert into catalogue.course_fees(course_id,fee_year,audience,fee_type,amount,currency_code,basis,notes,source_id,evidence_id,confidence,campus_id,source_fee_key,status,last_verified_at,source_snapshot_at,updated_at)
    values (r.course_id,v_year,'international','provider_current_tuition',r.amount,'AUD',v_basis,
            format('CF-247 provider basis rule admission (deterministic, Decision 162); rule %s; work item %s',r.rule_code,r.wid),
            v_source,r.evidence_id,1,null,v_key,'active',now(),now(),now())
    on conflict(course_id,source_id,source_fee_key) where source_id is not null and source_fee_key is not null do nothing
    returning id into v_fee;
    update pipeline.layer3_work_items set status='admitted', completed_at=now(), last_error=null, updated_at=now() where id=r.wid;
    v_review:=null;
    if r.interpretation_id is not null then
      update pipeline.layer4_review_items set status='superseded', decided_at=now() where layer3_interpretation_id=r.interpretation_id and status='pending' returning id into v_review;
    end if;
    insert into pipeline.provider_rule_admissions(work_item_id,review_item_id,course_id,course_fee_id,rule_code,amount,basis,matched_text)
    values (r.wid,v_review,r.course_id,v_fee,r.rule_code,r.amount,v_basis,left(v_text,500));
    v_courses:=v_courses||r.course_id; v_admitted:=v_admitted+1;
  end loop;
  if p_apply and cardinality(v_courses)>0 then perform search.refresh_course_enrichment_scoped_v1(v_courses,true); end if;
  return jsonb_build_object('mode',case when p_apply then 'apply' else 'proof' end,'admitted',v_admitted,'not_matched',v_nomatch,'samples',v_samples);
end $f$;
revoke all on function security.provider_basis_rule_admit_v1(boolean,integer) from public, anon, authenticated;

