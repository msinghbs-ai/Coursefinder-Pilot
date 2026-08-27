-- M2.4.2 A11 — record source-pattern benchmark model candidate and blocked acceptance state.
-- No Layer 3 A11 requests are executable until a dedicated source-pattern profile passes benchmark.
-- Canonical/Search/Publication mutation remains false.

begin;

update pipeline.layer3_model_profiles
set model_identifier='openai/gpt-oss-20b:free',
    structured_output_schema='{
      "type":"object",
      "additionalProperties":false,
      "required":["candidate_value","confidence","rationale","evidence_quotes"],
      "properties":{
        "candidate_value":{"type":["string","null"]},
        "confidence":{"type":"number","minimum":0,"maximum":1},
        "rationale":{"type":"string"},
        "evidence_quotes":{"type":"array","items":{"type":"string"}}
      }
    }'::jsonb,
    deterministic_validators=deterministic_validators||'{"candidate_shape":"https_url_string_or_null"}'::jsonb,
    paused=true,
    last_validation_result=coalesce(last_validation_result,'{}'::jsonb)||jsonb_build_object(
      'state','source_pattern_benchmark_blocked',
      'validated',false,
      'benchmark_passed',false,
      'nemotron_best_run_id','579a52d5-f4c2-4995-ab42-0adc4754cef2',
      'nemotron_best_result','3/4 live + 3/3 controls; one persistent empty completion',
      'alternate_model_run_id','ba0ca2de-1034-4bdf-a9ea-82e7a6a7918d',
      'alternate_model_result','openai/gpt-oss-20b:free returned aggregator 404 for all cases',
      'next_action','qualify a reliable specific structured-output model before executing blocked A11 Layer 3 requests',
      'canonical_mutation_authorised',false,
      'search_mutation_authorised',false,
      'publication_mutation_authorised',false
    ),
    updated_at=now()
where code='openrouter-source-pattern-v1';

commit;
