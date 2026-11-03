-- The defects on the live definitions (3 Nov 2026), before the migration
do $$
declare v jsonb; q bigint; r jsonb;
begin
  -- B1: a read of Bond 1230 through the scholarship AI queue is handed the candidate's stored copy of 29 Sep 2026, never the page
  insert into pipeline.scholarship_ai_queue(model_code, prompt_version, run_kind, candidate_id, provider_id, url)
  values ('qwen3-30b', 2, 'admit', 6712, '739948f6-6338-4ee9-8d0c-a8c8e953c29d', 'https://bond.edu.au/scholarship/abedian-foundation-master-of-architecture-scholarship') returning id into q;
  v := public.svc_scholarship_ai_next(8);
  if v->0->>'storage_path' is distinct from 'layer2/AU/scholarships/739948f6-6338-4ee9-8d0c-a8c8e953c29d/candidates/6712/9d25e2f7.html.gz' then raise exception 'B1 not reproduced: %', v; end if;
  raise notice 'B1 reproduced: the Bond read is given the old stored copy (%)', v->0->>'storage_path';
  -- B2: with AI admission on, a settled, confirmed answer is applied (it may admit), bypassing the held item in Layer 4
  update pipeline.scholarship_ai_queue set step = 2, model_code = 'gpt-4.1-mini' where id = q;
  r := public.svc_scholarship_ai_record(q, '{"name": "The Abedian Foundation Master of Architecture Scholarship", "audience": "both", "offered": "yes", "is_scholarship": true}'::jsonb,
         '{"name": true, "audience": true}'::jsonb, 'scholarship', 0.001, 100, 50, 1, null, null, null, null, null, false);
  if not exists (select 1 from pipeline.fx_calls where fn = 'apply') then raise exception 'B2 not reproduced: %', r; end if;
  raise notice 'B2 reproduced: the answer went to scholarship_ai_apply_v1 (admission), not to the held item';
end $$;
