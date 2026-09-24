-- Provider fee profiles (programme owner decision, 25 Sep 2026): approved, versioned,
-- provider-specific fee conventions applied deterministically at Layer 2, so Layer 3 only
-- confirms amount and year. First entry: UQ program pages show the indicative annual
-- international tuition fee, per UQ's official guidance ("Check the program page for an
-- indicative annual tuition fee"; "each program page shows an indicative annual fee").
create table if not exists pipeline.provider_fee_profiles(
  id uuid primary key default extensions.gen_random_uuid(),
  rule_code text not null unique,
  provider_id uuid not null references catalogue.providers(id),
  page_url_pattern text not null,
  audience text not null default 'international',
  resolved_basis text not null check (resolved_basis in ('annual','indicative_annual')),
  exclusion_pattern text not null,
  guidance_url text not null,
  guidance_text text not null,
  approval_ref text not null,
  approved_at timestamptz not null default now(),
  review_by date not null,
  active boolean not null default true,
  created_at timestamptz not null default now()
);
alter table pipeline.provider_fee_profiles enable row level security;
revoke all on pipeline.provider_fee_profiles from public, anon, authenticated;

insert into pipeline.provider_fee_profiles(rule_code,provider_id,page_url_pattern,audience,resolved_basis,exclusion_pattern,guidance_url,guidance_text,approval_ref,review_by)
select 'uq-program-page-indicative-annual-v1', p.id, '^https://study\.uq\.edu\.au/study-options/programs/', 'international', 'indicative_annual',
  '(total|semester|trimester|per unit|per credit|subsid|commonwealth|csp|domestic|hecs)',
  'https://study.uq.edu.au/admissions/undergraduate/review-fees-and-financial-support',
  'International tuition fees are program-based; check the program page for an indicative annual tuition fee. Each program page shows an indicative annual fee, based on average first-year enrolment data.',
  'CF-CHG-20260915-247; programme owner decision 25 Sep 2026: UQ program-page fee = indicative annual international tuition',
  date '2027-03-31'
from catalogue.providers p where p.canonical_name='The University of Queensland'
on conflict (rule_code) do nothing;

-- Apply approved profiles to waiting and Layer 4 tuition work items whose Layer 2 target
-- basis still needs validation. Conservative: the item's previous AI quote (if any) must
-- not contain the rule's exclusion words. Items not yet interpreted take the normal path.
create or replace function security.apply_provider_fee_profiles_v1()
returns jsonb language plpgsql security definer
set search_path to 'pg_catalog','security','pipeline','catalogue'
as $function$
declare n int;
begin
  with m as (
    select w.id, pf.rule_code, pf.resolved_basis
    from pipeline.layer3_work_items w
    join catalogue.courses c on c.id=w.entity_id
    join pipeline.provider_fee_profiles pf on pf.provider_id=c.provider_id and pf.active and pf.review_by>=current_date
    join pipeline.evidence_artifacts e on e.id=w.evidence_id
    join pipeline.layer3_interpretations i on i.id=w.interpretation_id
    where w.task_class='provider_current_tuition_validation'
      and w.status in ('pending','layer4_required')
      and w.candidate_context->'provider_current_tuition'->>'basis'='annual_or_indicative_requires_validation'
      and coalesce(w.candidate_context->'provider_current_tuition'->>'audience','')=pf.audience
      and e.source_url ~* pf.page_url_pattern
      and coalesce(i.evidence_quotes::text,'') !~* pf.exclusion_pattern
      and not (w.candidate_context ? 'provider_fee_rule'))
  update pipeline.layer3_work_items w
  set candidate_context = jsonb_set(w.candidate_context,'{provider_current_tuition,basis}',to_jsonb(m.resolved_basis))
                          || jsonb_build_object('provider_fee_rule',m.rule_code,'provider_fee_rule_applied_at',now()),
      updated_at=now()
  from m where w.id=m.id;
  get diagnostics n = row_count;
  return jsonb_build_object('applied',n);
end $function$;
revoke all on function security.apply_provider_fee_profiles_v1() from public, anon, authenticated;
grant execute on function security.apply_provider_fee_profiles_v1() to service_role;

select cron.unschedule(jobid) from cron.job where jobname='provider-fee-profiles-apply';
select cron.schedule('provider-fee-profiles-apply','*/5 * * * *',$c$select security.apply_provider_fee_profiles_v1();$c$);

-- Layer 4: suggest "Send back" where an approved provider rule now settles the frequency.
do $mig$
declare d text;
  a text := $q$      when coalesce(b.l3_validator->'errors','[]'::jsonb) ? 'evidence quote not present in governed Evidence'$q$;
  b text := $q$      when b.field_code='provider_current_tuition_validation' and exists(select 1 from pipeline.layer3_work_items w2 where w2.interpretation_id=b.layer3_interpretation_id and w2.candidate_context ? 'provider_fee_rule')
        then jsonb_build_object('action','return_layer3','text','The provider publishes this figure as its indicative annual fee (approved provider rule). Send it back to record it.')
      when coalesce(b.l3_validator->'errors','[]'::jsonb) ? 'evidence quote not present in governed Evidence'$q$;
begin
  d := pg_get_functiondef('security.layer4_review_desk_v1_impl(text,integer)'::regprocedure);
  if strpos(d,'approved provider rule')>0 then return; end if;
  if (length(d)-length(replace(d,a,'')))/length(a) <> 1 then raise exception 'suggestion anchor not found exactly once'; end if;
  execute replace(d,a,b);
end $mig$;
