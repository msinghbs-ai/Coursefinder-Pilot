-- CF-247 English requirements and scholarships: a refusal is not a failed page (agent: English and scholarships owner, 7 Nov 2026).
-- Why (live, read-only, 7 Nov 2026 07:00-08:00 UTC, project fxcwkweaxjtknorudmwp):
--   * pipeline.provider_fact_sources: 195 English pages (117 providers) are 'failed' with error "budget" and 64 with "target_list_refused": the worker's Firecrawl check
--     refused them, svc_provider_facts_read_next had already counted a try when it leased them, and svc_provider_facts_read_record closes a source at 3 tries. Three refusals
--     (22-27 Oct, while the budget was held) made them permanent: no further attempt, no new page attached (central_pages_attach_v1 counts every source toward central.attach_per_kind).
--     Providers that only have such pages: 52 providers / 762 courses without English (stage page_not_stored), 27 / 207 (target list), 18 / 438 more behind an approved rule.
--     The same functions serve intake_calendar (191 + 39 + 6) and fee_schedule (117 + 287) sources.
--   * pipeline.scholarship_ai_queue: 202 items closed "no scraper credit after 3 tries" (13-26 Oct) and 32 more at 2 tries (waiting 30 minutes each time; 8 calls on 7 Nov 07:16 all
--     "every item waited: waiting_scraper", refusal reason university_cap) are on the same path in svc_scholarship_ai_record. A budget or university-cap hold turns into a permanent failure.
--   (AER fetches got this fix on 29 Oct, migration 20261029001000: "a budget refusal is not the page failing".)
-- What:
--   1 security.provider_fact_refusal_v1(text): the names the worker records for a refusal.
--   2 svc_provider_facts_read_record: a refused read gives its try back and the source stays 'found' (parse_summary keeps the reason). Any other failure behaves as before (3 tries).
--   3 svc_provider_facts_read_next: a source refused within retry.provider_facts_refusal_hours is not offered again at once (so refused pages do not take the read slots of the others).
--   4 svc_scholarship_ai_record: a read put back (p_retry: credits, university cap, run time) gives its try back and waits retry.sch_ai_wait_minutes; it is closed only after
--     sch_ai.wait_max_days (an approved single read ends its request then). Real failures (page unreadable, AI error) still use their 3 tries.
--   Settings (G2): retry.provider_facts_refusal_hours (6), retry.sch_ai_wait_minutes (30, was written in code), sch_ai.wait_max_days (14).
-- Not done here: the sources and items already closed stay closed. Putting them back spends Firecrawl credits, so it is a Platform Admin decision with a paste file
--   (docs/paste/PASTE-20261107-english-refused-sources-requeue.sql, and its rollback). Nothing is switched on by this migration beyond the corrected accounting.
-- Consumer API: unchanged (G3). No table or column is added, changed or read by the website.
-- Replaces: public.svc_provider_facts_read_next(integer), public.svc_provider_facts_read_record(uuid,text,integer,text,text,text,jsonb,jsonb), public.svc_scholarship_ai_record(bigint,jsonb,jsonb,text,numeric,integer,integer,numeric,text,text,text,text,jsonb,boolean) (each md5-guarded on its live definition, replaced in place)
-- Retires: nothing.
-- Nothing is dropped or deleted by this migration.

-- 0 guards ---------------------------------------------------------------------------------------------------------------------------------------------
do $guard$
declare r record; v_md5 text;
begin
  for r in select * from (values
  ('public.svc_provider_facts_read_next(integer)', '5125d17949c155b56bd2b3a3903e6479'),
  ('public.svc_provider_facts_read_record(uuid,text,integer,text,text,text,jsonb,jsonb)', '1d365d6a6357e6a7db701a1814744604'),
  ('public.svc_scholarship_ai_record(bigint,jsonb,jsonb,text,numeric,integer,integer,numeric,text,text,text,text,jsonb,boolean)', 'b2fafccb2532afc3e0d1337588b5c43d')
  ) g(sig, md5) loop
    select md5(pg_get_functiondef(to_regprocedure(r.sig))) into v_md5;
    if v_md5 is distinct from r.md5 then raise exception 'live % (md5 %) differs from the definition this change was written against (%)', r.sig, v_md5, r.md5; end if;
  end loop;
end $guard$;

-- 1 settings (G2) --------------------------------------------------------------------------------------------------------------------------------------
insert into pipeline.platform_toolset_settings(toolset_key, key, label, help, kind, value, min_value, max_value, unit, sort, section, used_by, reason) values
 ('pipeline', 'retry.provider_facts_refusal_hours', 'Provider pages refused for credits: wait before offering again',
  'A provider page (English requirements, key dates, fees) that Firecrawl refused for credits or the target list is not a failed page: it keeps its tries and waits this long before the reader is offered it again.',
  'number', to_jsonb(6), 1, 168, 'hours', 1020, 'English policies', 'public.svc_provider_facts_read_next; public.svc_provider_facts_read_record',
  'Agent finding 7 Nov 2026: 259 English pages were closed after three refusals'),
 ('pipeline', 'retry.sch_ai_wait_minutes', 'Scholarship AI reads waiting for credits: wait between tries',
  'A scholarship page the reader could not fetch for credits or the university cap is put back and offered again after this long. It keeps its tries.',
  'number', to_jsonb(30), 5, 1440, 'minutes', 1021, 'Scholarships', 'public.svc_scholarship_ai_record',
  'G2: the 30 minutes were written in code'),
 ('pipeline', 'sch_ai.wait_max_days', 'Scholarship AI reads waiting for credits: close after',
  'A scholarship page that has waited this long for credits (created longer ago than this) is closed with the reason "no scraper credit within the waiting time"; an approved single read ends its request.',
  'number', to_jsonb(14), 1, 90, 'days', 1022, 'Scholarships', 'public.svc_scholarship_ai_record',
  'Agent finding 7 Nov 2026: replaces closing after three refused tries')
on conflict (toolset_key, key) do nothing;

-- 2 helper -----------------------------------------------------------------------------------------------------------------------------------------
create or replace function security.provider_fact_refusal_v1(p_error text) returns boolean
language sql immutable set search_path to 'pg_catalog' as $function$
  -- the names the worker (coverage-sweep useFcWhy / time budget) writes when it refuses a paid read before making it
  select coalesce(p_error in ('budget', 'credits_refused', 'credits_reserve', 'target_list_refused', 'no_firecrawl_key', 'time budget'), false)  -- fixed: the worker's own refusal names
$function$;
comment on function security.provider_fact_refusal_v1(text) is 'CF-247 7 Nov 2026: whether a provider-page read error is a refusal made before the read (credits, target list, run time) and not the page failing.';

-- 3 the three readers --------------------------------------------------------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.svc_provider_facts_read_next(p_limit integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v jsonb;
begin
  if current_user <> 'postgres' and coalesce(auth.role(), '') <> 'service_role' then raise exception 'service_role required'; end if;
  with pick as (
    select f.id from pipeline.provider_fact_sources f
     where ((f.kind = 'fee_schedule' and security.tuition_chase_enabled(f.provider_id))
            or f.kind in ('english_policy', 'intake_calendar'))
       and (f.status = 'found' or (f.status = 'reading' and f.updated_at < now() - interval '20 minutes')) and f.attempts < security.pipeline_num_v1('retry.provider_facts_attempts', 3)
       and not (f.status = 'found' and security.provider_fact_refusal_v1(f.parse_summary->>'error')
                and f.updated_at > now() - make_interval(hours => security.pipeline_num_v1('retry.provider_facts_refusal_hours', 6)::int))  -- CF-247 7 Nov 2026: a refused page waits, it is not read at once again
       and not exists (select 1 from security.provider_hidden_v1 h where h.provider_id = f.provider_id)  -- v2.15.237: paused while the provider is unpublished or archived
     order by (f.linked_from is null), f.rank,
              (select count(*) from catalogue.courses c where c.provider_id = f.provider_id and c.lifecycle_status = 'active') desc, f.created_at limit greatest(1, least(coalesce(p_limit, 10), 30))
     for update skip locked),
  upd as (update pipeline.provider_fact_sources f set status = 'reading', attempts = f.attempts + 1, updated_at = now() from pick where f.id = pick.id
          returning f.id, f.provider_id, f.kind, f.url)
  select coalesce(jsonb_agg(jsonb_build_object('id', u.id, 'provider_id', u.provider_id, 'kind', u.kind, 'url', u.url,
           'country', (select k.iso_alpha2 from catalogue.providers p join ref.countries k on k.id = p.country_id where p.id = u.provider_id),
           'currency', (select a.currency_code from catalogue.providers p join pipeline.coverage_admission_countries a on a.country_id = p.country_id where p.id = u.provider_id))), '[]'::jsonb)
    into v from upd u;
  return v;
end $function$
;

CREATE OR REPLACE FUNCTION public.svc_provider_facts_read_record(p_id uuid, p_status text, p_http integer, p_storage_path text, p_sha256 text, p_mime text, p_rows jsonb, p_summary jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare f pipeline.provider_fact_sources%rowtype; v_src uuid; v_ev uuid; v_cur text; v_n int := 0;
begin
  if current_user <> 'postgres' and coalesce(auth.role(), '') <> 'service_role' then raise exception 'service_role required'; end if;
  select * into f from pipeline.provider_fact_sources where id = p_id for update;
  if f.id is null then raise exception 'source not found'; end if;
  if p_status not in ('read','failed') then raise exception 'status must be read or failed'; end if;
  if p_status = 'failed' then
    -- CF-247 7 Nov 2026: a refusal (credits, the target list, the run's time) is not the page failing: the try it used is given back and the page stays found
    if security.provider_fact_refusal_v1(p_summary->>'error') then
      update pipeline.provider_fact_sources set status = 'found', attempts = greatest(attempts - 1, 0), http_status = p_http,
             parse_summary = p_summary, updated_at = now() where id = p_id;
      return jsonb_build_object('status', 'refused');
    end if;
    update pipeline.provider_fact_sources set status = case when attempts >= 3 then 'failed' else 'found' end, http_status = p_http,
           parse_summary = p_summary, updated_at = now() where id = p_id;
    return jsonb_build_object('status', 'failed');
  end if;
  if p_storage_path is not null and p_sha256 ~ '^[0-9a-f]{64}$' then
    v_src := security.coverage_sweep_source(f.provider_id);
    select id into v_ev from pipeline.evidence_artifacts where source_id = v_src and content_hash = p_sha256 and source_url = f.url limit 1;
    if v_ev is null then
      v_ev := public.svc_coursefacts_register_evidence(v_src, f.url, p_storage_path, p_sha256, coalesce(p_mime, 'text/markdown'),
                jsonb_build_object('layer', 2, 'kind', 'provider_' || f.kind, 'worker', 'coverage-sweep', 'provider_fact_source_id', f.id));
    end if;
  end if;
  select a.currency_code into v_cur from catalogue.providers p join pipeline.coverage_admission_countries a on a.country_id = p.country_id where p.id = f.provider_id;
  -- a re-read replaces the rows parsed before (kept, marked not current, for the record)
  update pipeline.provider_fee_rows set current = false where source_id = p_id and current;
  if f.kind = 'fee_schedule' and v_cur is not null then
    insert into pipeline.provider_fee_rows(source_id, provider_id, course_code, amount, currency_code, basis, fee_year, column_label, row_text)
    select p_id, f.provider_id, upper(btrim(r->>'course_code')), (r->>'amount')::numeric, v_cur, nullif(r->>'basis', ''), nullif(r->>'fee_year', '')::int,
           left(r->>'column_label', 120), left(r->>'row_text', 500)
      from jsonb_array_elements(coalesce(p_rows, '[]'::jsonb)) r
     where coalesce(r->>'course_code', '') ~ '^[0-9A-Za-z]{4,12}$' and coalesce(r->>'amount', '') ~ '^[0-9]+(\.[0-9]+)?$'
       and (r->>'amount')::numeric between 1000 and 200000
       and coalesce(nullif(r->>'basis', ''), 'annual') in ('annual','per_semester','per_trimester','total_indicative')
    on conflict on constraint provider_fee_rows_key do update set current = true, fee_year = excluded.fee_year, column_label = excluded.column_label, row_text = excluded.row_text;
    get diagnostics v_n = row_count;
  end if;
  update pipeline.provider_fact_sources set status = case when f.kind <> 'fee_schedule' then 'read' when v_n > 0 then 'parsed' else 'no_values' end,
         http_status = p_http, evidence_id = coalesce(v_ev, evidence_id), content_hash = coalesce(p_sha256, content_hash), read_at = now(),
         parse_summary = coalesce(p_summary, '{}'::jsonb) || jsonb_build_object('fee_rows', v_n), updated_at = now()
   where id = p_id;
  return jsonb_build_object('status', 'read', 'fee_rows', v_n, 'evidence_id', v_ev);
end $function$
;

CREATE OR REPLACE FUNCTION public.svc_scholarship_ai_record(p_queue_id bigint, p_answer jsonb, p_checks jsonb, p_verdict text, p_cost numeric, p_tokens_in integer, p_tokens_out integer, p_seconds numeric, p_error text, p_storage_path text, p_sha256 text, p_final_url text, p_rule_facts jsonb, p_retry boolean DEFAULT false)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'pipeline', 'security'
AS $function$
declare q pipeline.scholarship_ai_queue%rowtype; v_id bigint; v_ev uuid; v_on boolean; r jsonb; v_why text; v_next text; v_prev record;
begin
  if current_user <> 'postgres' and coalesce(auth.role(), '') <> 'service_role' then raise exception 'service_role required'; end if;
  select * into q from pipeline.scholarship_ai_queue where id = p_queue_id for update;
  if q.id is null then return jsonb_build_object('ok', false, 'reason', 'no queue item'); end if;
  if p_retry then
    -- CF-247 7 Nov 2026: a read refused for credits, the university cap or the run's time is not the page failing. It gives its try back and waits
    -- (retry.sch_ai_wait_minutes); it is closed only when it has waited longer than sch_ai.wait_max_days. Before this it was closed "after 3 tries" (202 items).
    update pipeline.scholarship_ai_queue set attempts = greatest(attempts - 1, 0), leased_until = null,
           state = case when q.created_at < now() - make_interval(days => security.pipeline_num_v1('sch_ai.wait_max_days', 14)::int) then 'failed' else 'queued' end,
           done_at = case when q.created_at < now() - make_interval(days => security.pipeline_num_v1('sch_ai.wait_max_days', 14)::int) then now() end,
           skip_reason = case when q.created_at < now() - make_interval(days => security.pipeline_num_v1('sch_ai.wait_max_days', 14)::int) then 'no scraper credit within the waiting time' end,
           next_try_at = now() + make_interval(mins => security.pipeline_num_v1('retry.sch_ai_wait_minutes', 30)::int) where id = q.id;
    -- an approved single read that has waited longer than the waiting time ends its request
    if q.read_request_id is not null and q.created_at < now() - make_interval(days => security.pipeline_num_v1('sch_ai.wait_max_days', 14)::int) then
      update pipeline.scholarship_read_requests set state = 'refused', finished_at = now(), outcome = jsonb_build_object('why', 'no scraper credit within the waiting time')
       where id = q.read_request_id and state = 'queued';
    end if;
    return jsonb_build_object('ok', true, 'retry', true);
  end if;
  -- v2.15.256: a value an earlier model in this chain proved stands when this model's value is not proven (its own proven value wins)
  if p_error is null and p_verdict = 'scholarship' and not coalesce((p_checks->>'value')::boolean, false)
     and coalesce(p_answer->'value'->>'kind', 'not_stated') not in ('not_stated', 'non_monetary') then
    select e.answer->'value' val, e.model_code into v_prev from pipeline.scholarship_ai_extractions e join pipeline.scholarship_ai_queue x on x.id = e.queue_id
     where coalesce(x.root_id, x.id) = coalesce(q.root_id, q.id) and x.id <> q.id and e.verdict = 'scholarship' and e.error is null
       and coalesce((e.checks->>'value')::boolean, false) order by e.id desc limit 1;
    if v_prev.val is not null then
      p_answer := jsonb_set(p_answer, '{value}', v_prev.val) || jsonb_build_object('value_from', v_prev.model_code);
      p_checks := p_checks || jsonb_build_object('value', true);
    end if;
  end if;
  -- a candidate page read live for the first time: its copy and read are recorded on the candidate, as the scheduled reader does
  if q.candidate_id is not null and p_storage_path is not null then
    update pipeline.scholarship_page_candidates set storage_path = p_storage_path, content_hash = p_sha256, final_url = coalesce(p_final_url, final_url), read_at = now(),
           read_status = coalesce(nullif(p_rule_facts->>'read_status', ''), 'read'), next_read_at = now() + make_interval(days => security.pipeline_num_v1('reread.scholarship_ai_days', 90)::int), leased_until = null,
           facts = case when p_rule_facts ? 'facts' then p_rule_facts->'facts' else facts end
     where id = q.candidate_id;
  end if;
  if p_storage_path is not null then
    insert into pipeline.evidence_artifacts(source_id, evidence_type, source_url, storage_path, content_hash, mime_type, metadata, capture_version, evidence_group_key)
    values (security.coverage_sweep_source(q.provider_id), 'scholarship_ai_page', coalesce(p_final_url, q.url), p_storage_path, p_sha256, 'application/gzip',
            jsonb_build_object('queue_id', q.id, 'candidate_id', q.candidate_id, 'scholarship_id', q.scholarship_id, 'model', q.model_code, 'worker', 'coverage-sweep scholarship_ai'), 1, 'scholarship_ai:' || q.id)
    returning id into v_ev;
    if q.candidate_id is not null then update pipeline.scholarship_page_candidates set evidence_id = coalesce(evidence_id, v_ev) where id = q.candidate_id; end if;
  end if;
  insert into pipeline.scholarship_ai_extractions(queue_id, model_code, model_identifier, prompt_version, run_kind, job_id, sample_id, candidate_id, scholarship_id, provider_id, url,
         storage_path, content_hash, evidence_id, answer, checks, verdict, cost_usd, tokens_in, tokens_out, seconds, error)
  values (q.id, q.model_code, (select m.model_identifier from pipeline.scholarship_ai_models m where m.code = q.model_code), q.prompt_version, q.run_kind, q.job_id, q.sample_id, q.candidate_id, q.scholarship_id, q.provider_id,
          coalesce(p_final_url, q.url), coalesce(p_storage_path, (select c.storage_path from pipeline.scholarship_page_candidates c where c.id = q.candidate_id)), p_sha256,
          coalesce(v_ev, (select c.evidence_id from pipeline.scholarship_page_candidates c where c.id = q.candidate_id), (select sp.evidence_id from pipeline.scholarship_pages sp where sp.scholarship_id = q.scholarship_id)),
          p_answer, p_checks, p_verdict, p_cost, p_tokens_in, p_tokens_out, p_seconds, p_error)
  returning id into v_id;
  -- v2.15.250 (bugs 11/10-6 follow-up): an unsettled answer (failed reply, name not proven, or a stated fact not proven by its quote)
  -- goes to the next model in the chain, on the same stored copy; after the last model it goes to Layer 4 while AI admission is on
  -- CF-247 4 Nov 2026: an approved single read whose page could not be read ends here (one read; no retry, no other model)
  if q.read_request_id is not null and p_error is not null and p_storage_path is null then
    update pipeline.scholarship_ai_queue set state = 'done', done_at = now(), leased_until = null, extraction_id = v_id where id = q.id;
    r := security.scholarship_read_request_close_v1(q.read_request_id, v_id, 'read_failed', 'Approved read: the page could not be read (' || left(p_error, 200) || ')');
    return jsonb_build_object('ok', true, 'extraction', v_id, 'request', r);
  end if;
  v_why := case when q.run_kind in ('admit', 'reread') then security.scholarship_ai_unsettled_v1(p_answer, p_checks, p_verdict, p_error) end;
  -- v2.15.250 (23:50): an answer that would admit is confirmed by the next model while confirm_admissions is on
  if v_why is null and q.run_kind in ('admit', 'reread') and p_error is null and p_verdict = 'scholarship' and p_answer->>'audience' in ('international', 'both')
     and coalesce((p_checks->>'audience')::boolean, false) and coalesce(p_answer->>'offered', '') <> 'no'
     and coalesce((select s.confirm_admissions from pipeline.scholarship_ai_extract_settings s where s.id = 1), true)
     and security.scholarship_ai_next_model_v1(q.model_code) is not null then
    v_why := 'a second model confirms each admission';
  end if;
  v_next := case when v_why is not null then security.scholarship_ai_next_model_v1(q.model_code) end;
  if v_next is not null then
    update pipeline.scholarship_ai_queue set state = 'done', done_at = now(), leased_until = null, extraction_id = v_id where id = q.id;
    insert into pipeline.scholarship_ai_queue(model_code, prompt_version, run_kind, job_id, sample_id, candidate_id, scholarship_id, provider_id, url, step, storage_path, root_id, fresh_read, read_request_id)
    values (v_next, q.prompt_version, q.run_kind, q.job_id, q.sample_id, q.candidate_id, q.scholarship_id, q.provider_id, coalesce(p_final_url, q.url), q.step + 1,
            coalesce(p_storage_path, q.storage_path), coalesce(q.root_id, q.id), q.fresh_read and coalesce(p_storage_path, q.storage_path) is null, q.read_request_id);
    return jsonb_build_object('ok', true, 'extraction', v_id, 'escalated_to', v_next, 'why', v_why);
  end if;
  update pipeline.scholarship_ai_queue set state = case when p_error is null or attempts >= 3 then 'done' else 'queued' end, done_at = case when p_error is null or attempts >= 3 then now() end,
         leased_until = null, next_try_at = now() + interval '10 minutes', extraction_id = v_id where id = q.id;
  -- CF-247 4 Nov 2026: an approved single read never admits or publishes; its answer goes to the held item in Layer 4, where the decision stays
  if q.read_request_id is not null then
    if p_error is null or q.attempts >= 3 then
      r := security.scholarship_read_request_close_v1(q.read_request_id, v_id, case when p_error is null then 'read' else 'read_failed' end,
             coalesce(v_why, 'Approved read: answer recorded; the decision stays in Layer 4'));
    end if;
    return jsonb_build_object('ok', true, 'extraction', v_id, 'request', r);
  end if;
  select ai_admission into v_on from pipeline.scholarship_ai_extract_settings where id = 1;
  if v_on and v_why is not null and (p_error is null or q.attempts >= 3) then r := security.scholarship_ai_review_open_v1(v_id, v_why);
  elsif p_error is null and v_on and q.run_kind in ('admit', 'reread') then r := security.scholarship_ai_apply_v1(v_id); end if;
  return jsonb_build_object('ok', true, 'extraction', v_id, 'applied', r);
end $function$
;
