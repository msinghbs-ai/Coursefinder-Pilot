
insert into pipeline.provider_contact_dispositions(
  provider_id,profile_id,disposition,international_students_url,contact_team_url,general_email,
  named_contact_count,territory_contact_count,source_urls,evidence_ids,
  interpretation_source,observed_at,last_verified_at,supersedes_disposition_id
)
select
  p.provider_id,p.id,'not_found_in_qualified_evidence',
  case when p.base_url ~* '(international|study)' then p.base_url else null end,
  case when p.base_url ~* '(contact|international)' then p.base_url else null end,
  null,0,0,array[p.base_url]::text[],'{}'::uuid[],
  'a15_reconciliation',p.last_run_at,p.last_success_at,d.id
from pipeline.provider_contact_profiles p
join lateral (
  select d0.id,d0.disposition
  from pipeline.provider_contact_dispositions d0
  where d0.provider_id=p.provider_id
  order by d0.created_at desc,d0.id desc
  limit 1
) d on true
where d.disposition='pending_acquisition'
  and p.last_success_at is not null
  and p.last_error is null
  and nullif(trim(p.base_url),'') is not null;

comment on table pipeline.provider_contact_dispositions is
'A16 explicit AU/NZ Provider international-contact coverage/disposition history. Older successful profile runs without attempt-row telemetry are retained as not_found_in_qualified_evidence using their official profile URL; no contact is manufactured.';
