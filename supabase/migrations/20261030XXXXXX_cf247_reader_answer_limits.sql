-- CF-247 decision W32 (29 Oct 2026, AER programme Workstream 5, lane I: reader hardening): every AI read's answer limit is a setting.
-- Numbered 20261030XXXXXX: the integrator gives the number. It ships with worker coverage-sweep-worker-v0.54.0.
-- Why: W29 (20261029130000, worker v0.53.0) fixed the course entry-requirements read, whose answer was a fixed 2,000 tokens. The other reads
-- in the worker still had their answer limits written into the code: the Enrich fields reads (course page fields, titles, campus regions,
-- campus lists, provider addresses) 2,000 tokens, scholarship pages 3,000, scholarship re-checks 800, central pages 1,500, course page
-- matching 300, adapter proposals 4,000 then 8,000, and fee pages none at all. Live (read-only, 15 to 29 Oct 2026): seven Enrich fields
-- items on four course pages failed three times each with "Unterminated string in JSON at position 3,948 to 9,149" (fields english, intakes,
-- delivery, international), with cost_usd 0; two scholarship page reads failed "the answer was cut off at its length limit", cost_usd 0.
-- What: worker v0.54.0 reads each limit below through svc_worker_settings_v1 (prefix reading., so that function does not change). An answer
-- that reaches its limit (finish_reason length, or not JSON at the limit) fails the whole read as "held_partial: output_truncated" on the
-- existing failure path (no new status) and nothing of it is parsed or proposed; the cost of every call is recorded also when a read fails.
-- The values are those fixed in the code before, so nothing changes until a person changes a setting; the fee reader, which sent no limit
-- (gpt-4.1-mini's own 32,768 applied), gets 32,000.
-- Replaces: the answer limits fixed in worker coverage-sweep (enrich_ai ask, scholarship_ai, scholarship_recheck, central_ai, fee_ai, ai_match, adapter_propose), replaced in place by v0.54.0
-- Retires: nothing (no table, function, job or edge function is left unused)
-- Nothing dropped, deleted or renamed. The consumer API is not touched (Decision 266). No new job, table, function or status. No AI read is started.

insert into pipeline.platform_toolset_settings(toolset_key, key, label, help, kind, value, min_value, max_value, unit, sort, section, used_by, reason) values
 ('pipeline', 'reading.answer_tokens.course_fields', 'AI answer length: course page fields',
  'The longest answer the Enrich fields reader may give for one course page (campus, duration, delivery, level, international, English, intakes). An answer that reaches it is held_partial: output_truncated and no field of it is applied.', 'number',
  to_jsonb(2000), 500, 16000, 'tokens', 930, 'AI answer limits', 'worker coverage-sweep enrich_ai (course page fields)',
  'CF-247 decision W32 (29 Oct 2026): was fixed at 2,000 in the worker; seven items on four course pages were cut mid-answer (Unterminated string in JSON) 21 to 27 Oct 2026'),
 ('pipeline', 'reading.answer_tokens.course_titles', 'AI answer length: field of study and level from titles',
  'The longest answer the Enrich fields reader may give for one batch of course titles (enrich.title_batch titles a call). A cut answer fails the whole batch, named.', 'number',
  to_jsonb(2000), 500, 16000, 'tokens', 931, 'AI answer limits', 'worker coverage-sweep enrich_ai (field_of_study, level)',
  'CF-247 decision W32 (29 Oct 2026): was fixed at 2,000 in the worker'),
 ('pipeline', 'reading.answer_tokens.campus_regions', 'AI answer length: campus regions',
  'The longest answer the Enrich fields reader may give when it places one university''s campus cities in their regions. A cut answer fails the read, named.', 'number',
  to_jsonb(2000), 500, 16000, 'tokens', 932, 'AI answer limits', 'worker coverage-sweep enrich_ai (campus_region)',
  'CF-247 decision W32 (29 Oct 2026): was fixed at 2,000 in the worker'),
 ('pipeline', 'reading.answer_tokens.campus_lists', 'AI answer length: campus lists',
  'The longest answer the Enrich fields reader may give when it makes one university''s campus list. A cut answer fails the read, named.', 'number',
  to_jsonb(2000), 500, 16000, 'tokens', 933, 'AI answer limits', 'worker coverage-sweep enrich_ai (campus_list)',
  'CF-247 decision W32 (29 Oct 2026): was fixed at 2,000 in the worker'),
 ('pipeline', 'reading.answer_tokens.provider_address', 'AI answer length: provider address',
  'The longest answer the Enrich fields reader may give when it reads a provider''s street address. A cut answer fails the read, named.', 'number',
  to_jsonb(2000), 500, 16000, 'tokens', 934, 'AI answer limits', 'worker coverage-sweep enrich_ai (provider_address)',
  'CF-247 decision W32 (29 Oct 2026): was fixed at 2,000 in the worker'),
 ('pipeline', 'reading.answer_tokens.scholarship_page', 'AI answer length: scholarship page',
  'The longest answer the scholarship reader may give for one scholarship page. A cut answer is recorded as failed with its cost; nothing of it is checked or applied.', 'number',
  to_jsonb(3000), 1000, 16000, 'tokens', 935, 'AI answer limits', 'worker coverage-sweep scholarship_ai',
  'CF-247 decision W32 (29 Oct 2026): was fixed at 3,000 in the worker; two reads cut in the last 14 days were recorded with cost 0'),
 ('pipeline', 'reading.answer_tokens.scholarship_recheck', 'AI answer length: scholarship re-check',
  'The longest answer the narrow re-check of a held scholarship page may give. A cut or empty answer fails the re-check, named.', 'number',
  to_jsonb(800), 200, 4000, 'tokens', 936, 'AI answer limits', 'worker coverage-sweep scholarship_recheck',
  'CF-247 decision W32 (29 Oct 2026): was fixed at 800 in the worker'),
 ('pipeline', 'reading.answer_tokens.central_page', 'AI answer length: central pages',
  'The longest answer the central-page reader may give for one English policy or academic calendar page. A cut answer fails the read with its cost; nothing of it is proposed.', 'number',
  to_jsonb(1500), 500, 16000, 'tokens', 937, 'AI answer limits', 'worker coverage-sweep central_ai',
  'CF-247 decision W32 (29 Oct 2026): was fixed at 1,500 in the worker'),
 ('pipeline', 'reading.answer_tokens.fee_page', 'AI answer length: fee pages',
  'The longest answer the AI fee reader may give for one fee page or course page. A cut answer fails the read with its cost; no fee row of it is proposed.', 'number',
  to_jsonb(32000), 4000, 32000, 'tokens', 938, 'AI answer limits', 'worker coverage-sweep fee_ai',
  'CF-247 decision W32 (29 Oct 2026): the worker sent no limit (the model''s own applied); 32,000 keeps the pinned model''s room (gpt-4.1-mini, 32,768) and names a cut answer'),
 ('pipeline', 'reading.answer_tokens.course_page_match', 'AI answer length: course page match',
  'The longest answer the AI page match may give (a short reason and the chosen candidate). A cut or empty answer fails the match, named.', 'number',
  to_jsonb(300), 100, 2000, 'tokens', 939, 'AI answer limits', 'worker coverage-sweep ai_match',
  'CF-247 decision W32 (29 Oct 2026): was fixed at 300 in the worker'),
 ('pipeline', 'reading.answer_tokens.adapter_proposal', 'AI answer length: adapter proposal',
  'The longest answer the adapter builder''s proposal may give at its first ask. A cut answer is asked again once at the larger limit below; every attempt''s tokens and cost are recorded.', 'number',
  to_jsonb(4000), 1000, 16000, 'tokens', 940, 'AI answer limits', 'worker coverage-sweep adapter_propose',
  'CF-247 decision W32 (29 Oct 2026): was fixed at 4,000 in the worker (v0.17.14)'),
 ('pipeline', 'reading.answer_tokens.adapter_proposal_retry', 'AI answer length: adapter proposal asked again',
  'The answer limit when an adapter proposal is asked again after its first answer was cut. Not used when it is not larger than the first limit.', 'number',
  to_jsonb(8000), 1000, 32000, 'tokens', 941, 'AI answer limits', 'worker coverage-sweep adapter_propose',
  'CF-247 decision W32 (29 Oct 2026): was fixed at 8,000 in the worker (v0.19.0)')
on conflict (toolset_key, key) do nothing;

-- post-check: twelve answer-limit settings, each with its label, range, unit and used_by, and the worker can read them
do $$ declare v_n int; v_ws jsonb; begin
  select count(*) into v_n from pipeline.platform_toolset_settings
   where toolset_key = 'pipeline' and key like 'reading.answer_tokens.%'
     and label is not null and unit = 'tokens' and used_by is not null and min_value is not null and max_value is not null
     and (value #>> '{}')::numeric between min_value and max_value;
  if v_n <> 12 then raise exception 'W32 post-check: expected 12 answer-limit settings within their ranges, found %', v_n; end if;
  select public.svc_worker_settings_v1() into v_ws;
  if not (v_ws ? 'reading.answer_tokens.course_fields' and v_ws ? 'reading.answer_tokens.fee_page') then
    raise exception 'W32 post-check: svc_worker_settings_v1 does not return the reading.answer_tokens settings';
  end if;
end $$;
