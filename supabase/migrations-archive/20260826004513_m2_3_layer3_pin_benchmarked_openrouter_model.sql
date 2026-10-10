update pipeline.layer3_model_profiles
set model_identifier='nvidia/nemotron-3-nano-omni-30b-a3b-reasoning:free',
    updated_at=now()
where code='openrouter-free-router-v1'
  and model_identifier is distinct from 'nvidia/nemotron-3-nano-omni-30b-a3b-reasoning:free';
