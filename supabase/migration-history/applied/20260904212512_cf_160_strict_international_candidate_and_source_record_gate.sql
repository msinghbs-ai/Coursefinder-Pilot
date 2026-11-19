-- Re-gate ALL current detail-ready candidates in the scale-wave providers, including pre-CF156 rows.
with target as (
  select c.id,c.observed_title,coalesce(nullif(c.detail_target_url,''),nullif(c.scholarship_url,'')) url,
         lower(coalesce(c.observed_title,'') || ' ' || coalesce(c.scholarship_url,'')) as observation_text
  from pipeline.layer2_scholarship_discovery_candidates c
  join pipeline.sources s on s.id=c.source_id
  where c.classification='detail_ready'
    and s.provider_id in (
      '982fb12f-41ed-4358-9d1b-d7422b3089dd'::uuid,
      'f34fae5e-b5b9-4c82-a6ca-44bf0803020e'::uuid,
      'fac03540-a412-4c76-a5ab-cd338d7760db'::uuid,
      '6f5cb7f7-7c70-4c06-970f-f368c3a786e2'::uuid,
      'c5c5d225-3d4c-4e41-8275-78eddd261073'::uuid
    )
), classified as (
  select id,url,
    observation_text ~ '(international|overseas|global merit|global scholarship|asean|south[ -]?east asia|southeast asia|india|indonesia|vietnam|malaysia|singapore|thailand|thai|china|chinese|pakistan|bangladesh|sri lanka|nepal|africa|latin america|middle east)' as explicit_international,
    coalesce(url,'') ~* '/search\?|[?&](query|collection|form|num_ranks|f\.)=|residency[^#]*international' as filter_page,
    coalesce(url,'') ~ '#.+' as fragment_url
  from target
)
update pipeline.layer2_scholarship_discovery_candidates c
set classification=case
      when x.filter_page then 'catalogue_or_filter'
      when x.fragment_url and not x.explicit_international then 'catalogue_or_filter'
      when x.explicit_international then 'detail_ready'
      else 'needs_review'
    end,
    classification_reason=case
      when x.filter_page then 'strict international gate: search/filter page retained as catalogue Evidence'
      when x.fragment_url and not x.explicit_international then 'strict international gate: fragment/section link retained as catalogue Evidence, not individual detail'
      when x.explicit_international then 'strict international gate: explicit international cue in catalogue observation; detail verification allowed'
      else 'strict international gate: no explicit international cue in catalogue observation; review required before detail/canonical use'
    end,
    classified_at=now()
from classified x where c.id=x.id;

-- Preserve already-extracted rows but park records sourced from candidates that no longer qualify for automatic international use.
with generated as (
  select distinct j.payload->>'target_url' url,c.classification
  from pipeline.jobs j
  join pipeline.layer2_scholarship_discovery_candidates c on c.id=(j.payload->>'candidate_id')::uuid
  where j.domain='scholarship' and j.payload->>'change_control_ref' in ('CF-157','CF-159')
    and c.classification <> 'detail_ready'
)
update pipeline.scholarship_source_records sr
set status='unmapped',
    payload=coalesce(sr.payload,'{}'::jsonb)||jsonb_build_object(
      'international_gate_status','review_required',
      'international_gate_reason','catalogue observation did not prove international eligibility; page-template keyword is insufficient',
      'canonical_mutation_authorised',false
    )
from generated g
where sr.source_record_url=g.url and sr.status='captured';

-- Mark clearly catalogue-like extracted rows as review-only even where the page is international-focused.
update pipeline.scholarship_source_records
set status='unmapped',
    payload=coalesce(payload,'{}'::jsonb)||jsonb_build_object(
      'international_gate_status','catalogue_or_filter',
      'canonical_mutation_authorised',false
    )
where created_at>now()-interval '1 day'
  and (
    source_record_url ~* '/search\?'
    or source_record_url ~* '[?&](query|collection|form|num_ranks|f\.)='
    or coalesce(payload->>'name','') ~* '^(find a scholarship|all scholarship opportunities|internal scholarship opportunities|external scholarship opportunities|government-funded scholarships|skip to main content|international scholarship detail)$'
  );
