-- CF-156 — International-only bulk Scholarship candidate gate
-- Scope: first-party catalogue candidates for Curtin, Charles Sturt, ECU, CDU and Deakin.
-- Ambiguous catalogue rows are parked before scraper firing; explicit international cues remain detail-ready.
with target as (
  select c.id,
         lower(coalesce(c.observed_title,'') || ' ' || coalesce(c.detail_target_url,'') || ' ' || coalesce(c.scholarship_url,'')) as txt
  from pipeline.layer2_scholarship_discovery_candidates c
  join pipeline.sources s on s.id=c.source_id
  where s.provider_id in (
    '982fb12f-41ed-4358-9d1b-d7422b3089dd'::uuid,
    'f34fae5e-b5b9-4c82-a6ca-44bf0803020e'::uuid,
    'fac03540-a412-4c76-a5ab-cd338d7760db'::uuid,
    '6f5cb7f7-7c70-4c06-970f-f368c3a786e2'::uuid,
    'c5c5d225-3d4c-4e41-8275-78eddd261073'::uuid
  )
  and c.classification is null
), intl as (
  select id from target where txt ~ '(international|overseas|global merit|global scholarship|asean|south[ -]?east asia|southeast asia|india|indonesia|vietnam|malaysia|singapore|thailand|thai|china|chinese|pakistan|bangladesh|sri lanka|nepal|africa|latin america|middle east)'
)
update pipeline.layer2_scholarship_discovery_candidates c
set classification=case when i.id is not null then 'detail_ready' else 'needs_review' end,
    classification_reason=case when i.id is not null
      then 'international_only_gate: explicit international/overseas catalogue cue; first-party detail verification required'
      else 'international_only_gate: no explicit international eligibility cue in catalogue observation; parked before scraper firing' end,
    classified_at=now()
from target t left join intl i on i.id=t.id
where c.id=t.id;
