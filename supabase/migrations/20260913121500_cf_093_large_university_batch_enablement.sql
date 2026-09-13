begin;

-- CF-CHG-20260910-093
-- Bounded multi-university expansion of the accepted course-facts execution model.
-- Active acquisition route for this cohort is Firecrawl -> ZenRows only.
-- Existing authority, Evidence, Preview binding, retry, Layer 3 and Layer 4 rules remain unchanged.

with cohort(profile_key) as (
  values
    ('au-rmit-course-detail'),
    ('qualification-au-982fb12f41ed4358'), -- Curtin University
    ('qualification-au-0a42da168df14439'), -- Flinders University
    ('qualification-au-36086f5e9fe04878'), -- Griffith University
    ('qualification-au-4f86e09a557c4544'), -- La Trobe University
    ('qualification-au-2c4f515cc1464e90')  -- Queensland University of Technology
), profiles as (
  select p.id,p.profile_key
  from pipeline.layer2_source_profiles p
  join cohort c using(profile_key)
), providers as (
  select id,provider_key
  from pipeline.layer2_acquisition_providers
  where provider_key in ('direct-http','firecrawl','scrape-do','scraperapi','zenrows')
)
update pipeline.layer2_profile_provider_routes r
set priority=r.priority+1000,
    updated_at=now()
from profiles p,providers ap
where r.profile_id=p.id and r.acquisition_provider_id=ap.id;

with cohort(profile_key) as (
  values
    ('au-rmit-course-detail'),
    ('qualification-au-982fb12f41ed4358'),
    ('qualification-au-0a42da168df14439'),
    ('qualification-au-36086f5e9fe04878'),
    ('qualification-au-4f86e09a557c4544'),
    ('qualification-au-2c4f515cc1464e90')
), profiles as (
  select p.id,p.profile_key from pipeline.layer2_source_profiles p join cohort c using(profile_key)
), providers as (
  select id,provider_key from pipeline.layer2_acquisition_providers
  where provider_key in ('direct-http','firecrawl','scrape-do','scraperapi','zenrows')
)
update pipeline.layer2_profile_provider_routes r
set enabled=ap.provider_key in ('firecrawl','zenrows'),
    priority=case ap.provider_key
      when 'firecrawl' then 10
      when 'zenrows' then 20
      when 'direct-http' then 110
      when 'scrape-do' then 120
      when 'scraperapi' then 130
      else r.priority
    end,
    updated_at=now()
from profiles p,providers ap
where r.profile_id=p.id and r.acquisition_provider_id=ap.id;

-- Extend the already-accepted bounded deterministic execution-policy shape used by
-- RMIT/UQ to the new university cohort. This enables execution; it does not grant
-- canonical/Search/Publication authority or bypass Preview binding.
insert into pipeline.layer2_execution_policies(
  profile_id,schedule_mode,batch_size,routing_strategy,max_paid_attempts_per_entity,
  auto_handoff_layer3,stop_on_identity_mismatch,enabled,max_concurrency,stale_after_minutes
)
select p.id,'manual',10,'direct_then_best_value',2,true,true,true,1,30
from pipeline.layer2_source_profiles p
where p.profile_key in (
  'qualification-au-982fb12f41ed4358',
  'qualification-au-0a42da168df14439',
  'qualification-au-36086f5e9fe04878',
  'qualification-au-4f86e09a557c4544',
  'qualification-au-2c4f515cc1464e90'
)
on conflict(profile_id) do update set
  schedule_mode='manual',
  batch_size=excluded.batch_size,
  routing_strategy=excluded.routing_strategy,
  max_paid_attempts_per_entity=excluded.max_paid_attempts_per_entity,
  auto_handoff_layer3=true,
  stop_on_identity_mismatch=true,
  enabled=true,
  max_concurrency=excluded.max_concurrency,
  stale_after_minutes=excluded.stale_after_minutes,
  updated_at=now();

commit;
