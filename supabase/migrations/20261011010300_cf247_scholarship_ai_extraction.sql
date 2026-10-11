-- CF-247 (11 Oct 2026, Platform Admin bugs 11/10-6, 22:10): "Just like courses adapter I need scholarship to be read by code using
-- Firecrawl but then use AI to extract attributes. Simple code extraction fields are making too many mistakes and rejecting the
-- values." Platform Admin decisions: AI reads every page; qualify two models and keep the better; AI-admitted scholarships pass the
-- same publish checks hourly; the watch list (27 universities) first, then the rest in nightly batches.
--   Feature 1: scholarship pages read through the scraper are extracted by one pinned AI model with versioned instructions; every
--     fact carries an exact quote from the page.
--   Feature 2: the worker checks every quote against the page; an unproven fact is "not stated", never a guess.
--   Feature 3: a model is qualified on a hand-checked sample before it can be made active; AI admission is a separate switch
--     (off until a Platform Admin switches it on, with a reason). New instructions switch it off until qualified again.
--   Feature 4: while AI admission is on, new and re-read pages are decided by the AI answer (rule-read facts kept under "rules");
--     the hourly audience reader leaves AI-read scholarships alone; Find scholarships now also queues refused pages for AI.
--   Fix 5: a listing name matched to a record by its link must also share the record's name (VU Medibank School Leavers Merit
--     was matched to the VU Block Model record).
--   Task types scholarship_ai_qualify and scholarship_ai_backfill; scheduled jobs scholarship-ai-extract (each minute, when pages
--     are queued) and scholarship-ai-backfill (nightly): standing rule G1.
-- Nothing is dropped or deleted. Each replaced function is checked against its live definition first.
do $guard$
declare v_expected jsonb := '{"security.admin_job_slice_v1(uuid,integer)": "6ced8179e6c4279008fd53d1b73beaec", "security.admin_job_watch_v1(uuid)": "f0c7f496ec21728587b46d689d2c628b", "public.svc_scholarship_read_record(uuid,text,integer,text,text,text,text,jsonb)": "8bd3588ac05703567b7d7050a7224f6d", "public.svc_scholarship_candidate_record(bigint,text,integer,text,text,text,text,jsonb)": "ae89fd44d52b075254b214de2e03edda", "security.scholarship_audience_read_v1()": "6896910608e5953cdb0e8b16c0a73f87", "security.scholarship_task_prepare_v1(text,jsonb)": "747d4df851a35ef6c80184036ee6fee0", "security.scholarship_listing_match_v1(uuid)": "bded0b0fdcf6709821ab37c106a45aad", "public.admin_jobs(text,jsonb)": "e5aa7642d610954253f18ceeaf0390de"}'::jsonb;
  v_sig text;
begin
  for v_sig in select jsonb_object_keys(v_expected) loop
    if md5(replace(pg_get_functiondef(v_sig::regprocedure), E'\r', '')) <> v_expected->>v_sig then
      raise exception 'live % differs from the definition this change replaces', v_sig;
    end if;
  end loop;
end $guard$;

-- ===== Tables =====
create table if not exists pipeline.scholarship_ai_models (
  code text primary key, label text not null, model_identifier text not null, price_note text,
  status text not null default 'candidate' check (status in ('candidate', 'active', 'retired')),
  activated_at timestamptz, activated_by uuid, reason text, sort int not null default 100);
alter table pipeline.scholarship_ai_models enable row level security;
insert into pipeline.scholarship_ai_models(code, label, model_identifier, price_note, sort) values
  ('qwen3-30b', 'Qwen3 30B A3B Instruct (2507)', 'qwen/qwen3-30b-a3b-instruct-2507', 'about US$0.0003 a page; pinned for course-page matching since 2 Oct', 10),
  ('gpt-4.1-mini', 'GPT-4.1 mini', 'openai/gpt-4.1-mini', 'about US$0.002 a page', 20)
on conflict (code) do nothing;

create table if not exists pipeline.scholarship_ai_prompts (
  version serial primary key, text text not null, active boolean not null default false, reason text not null,
  created_by uuid, created_at timestamptz not null default now());
alter table pipeline.scholarship_ai_prompts enable row level security;
insert into pipeline.scholarship_ai_prompts(text, active, reason)
select 'You read one web page from a university''s own website and extract facts about a scholarship for international students. Use only the page text you are given. Never guess and never use outside knowledge.

Decide first:
- is_scholarship: true only if the page offers money, a fee reduction or a benefit (for example free accommodation) that students apply for or are awarded to study. Prizes for completed work, staff awards, teaching awards, research grants to staff, news, events, course pages and general information pages are not scholarships.
- single_scholarship: true if the page is about one scholarship (it may have tiers or levels). False if it lists several different scholarships.

Then, for a scholarship, extract each fact with a short exact quote copied from the page text (word for word, 5 to 40 words) that proves it. If the page does not state a fact, use "not_stated" and an empty quote.
- name: the scholarship''s own name as written on the page.
- audience: "international" (only international students), "both" (international and domestic), "domestic" (only domestic students, citizens or residents), or "not_stated".
- offered: "yes" if it is currently offered or open to applications in the current or a coming intake; "no" only if the page says it has ended, closed permanently or is no longer offered. A condition such as "until all places are filled" or "places are limited" means "yes".
- value: kind "percentage" (a percent off tuition), "fixed_amount" (an amount of money), "tiers" (several amounts or percentages, for example by level or result), "full_tuition", "non_monetary" (a benefit such as accommodation with no stated money value) or "not_stated". Give numbers without currency symbols or commas. An amount the student must pay (a deposit, bond, fee or charge) is never the value. If a benefit is "valued at" an amount, use that amount.
- levels: any of "undergraduate", "postgraduate_coursework", "postgraduate_research", "vet", "english", "pathway"; empty if not stated.
- courses: the exact names of courses the page says the scholarship is for (empty if it is for all courses or none are named).
- open_date and close_date: YYYY-MM-DD if a day, month and year are stated, otherwise null.
- not_scholarship_reason: if is_scholarship is false or single_scholarship is false, one short sentence why; otherwise null.

Answer only with the JSON object in the required format.', true, 'v1 (11 Oct 2026, Platform Admin bugs 11/10-6): AI reads every scholarship page; quotes prove each fact'
 where not exists (select 1 from pipeline.scholarship_ai_prompts);

create table if not exists pipeline.scholarship_ai_settings (
  id int primary key default 1 check (id = 1), ai_admission boolean not null default false, backfill_providers_per_night int not null default 25,
  pages_per_call int not null default 8, calls_at_once int not null default 3, changed_by uuid, changed_at timestamptz, reason text);
alter table pipeline.scholarship_ai_settings enable row level security;
insert into pipeline.scholarship_ai_settings(id) values (1) on conflict (id) do nothing;

create table if not exists pipeline.scholarship_ai_sample (
  id serial primary key, url text not null, candidate_id bigint, scholarship_id uuid, provider_id uuid, expected jsonb not null,
  label_source text not null, note text, active boolean not null default true, added_by uuid, added_at timestamptz not null default now());
alter table pipeline.scholarship_ai_sample enable row level security;
create unique index if not exists scholarship_ai_sample_url_key on pipeline.scholarship_ai_sample (url);

create table if not exists pipeline.scholarship_ai_queue (
  id bigserial primary key, model_code text not null references pipeline.scholarship_ai_models(code), prompt_version int not null,
  run_kind text not null check (run_kind in ('qualify', 'admit', 'reread', 'test')), job_id uuid, sample_id int, candidate_id bigint, scholarship_id uuid,
  provider_id uuid, url text not null, state text not null default 'queued' check (state in ('queued', 'leased', 'done', 'failed')),
  attempts int not null default 0, leased_until timestamptz, next_try_at timestamptz not null default now(), created_at timestamptz not null default now(), done_at timestamptz, extraction_id bigint);
create index if not exists scholarship_ai_queue_due_idx on pipeline.scholarship_ai_queue (state, next_try_at) where state in ('queued', 'leased');
create index if not exists scholarship_ai_queue_job_idx on pipeline.scholarship_ai_queue (job_id);
alter table pipeline.scholarship_ai_queue enable row level security;

create table if not exists pipeline.scholarship_ai_extractions (
  id bigserial primary key, queue_id bigint, model_code text, model_identifier text, prompt_version int, run_kind text, job_id uuid,
  sample_id int, candidate_id bigint, scholarship_id uuid, provider_id uuid, url text, storage_path text, content_hash text, evidence_id uuid,
  answer jsonb, checks jsonb, verdict text, applied jsonb, cost_usd numeric, tokens_in int, tokens_out int, seconds numeric, error text, at timestamptz not null default now());
create index if not exists scholarship_ai_extractions_cand_idx on pipeline.scholarship_ai_extractions (candidate_id, at desc);
create index if not exists scholarship_ai_extractions_sch_idx on pipeline.scholarship_ai_extractions (scholarship_id, at desc);
create index if not exists scholarship_ai_extractions_job_idx on pipeline.scholarship_ai_extractions (job_id);
alter table pipeline.scholarship_ai_extractions enable row level security;

-- Standing rule G1: the two new task types and the two scheduled jobs appear in Task manager and Automations
insert into pipeline.admin_job_kinds(kind, label, what, can_pause, added_in) values
  ('scholarship_ai_qualify', 'Qualify the scholarship AI', 'Runs the hand-checked sample through one AI model and scores it; admits nothing.', false, 'v2.15.249'),
  ('scholarship_ai_backfill', 'Re-check scholarship pages with AI', 'Reads chosen universities'' refused and known scholarship pages with the active AI model; admits under the publish checks when AI admission is on.', false, 'v2.15.249')
on conflict (kind) do nothing;

-- ===== The current active model and instructions =====
create or replace function security.scholarship_ai_active_v1()
returns table(model_code text, model_identifier text, prompt_version int, ai_admission boolean)
language sql stable security definer set search_path to '' as $f$
  select m.code, m.model_identifier, (select p.version from pipeline.scholarship_ai_prompts p where p.active order by p.version desc limit 1), s.ai_admission
    from pipeline.scholarship_ai_settings s left join pipeline.scholarship_ai_models m on m.status = 'active' where s.id = 1
$f$;

-- Queue AI reading for providers: refused or unread candidate pages, and known scholarship pages
create or replace function security.scholarship_ai_enqueue_v1(p_run_kind text, p_provider_ids uuid[], p_job uuid default null, p_known boolean default true)
returns integer language plpgsql security definer set search_path to '' as $f$
declare a record; v_n int := 0; v_k int;
begin
  select * into a from security.scholarship_ai_active_v1();
  if a.model_code is null then return 0; end if;
  insert into pipeline.scholarship_ai_queue(model_code, prompt_version, run_kind, job_id, candidate_id, provider_id, url)
  select a.model_code, a.prompt_version, p_run_kind, p_job, c.id, c.provider_id, coalesce(c.final_url, c.url)
    from pipeline.scholarship_page_candidates c
   where c.provider_id = any (p_provider_ids) and c.source <> 'register' and c.admitted_scholarship_id is null and c.matched_scholarship_id is null
     and coalesce(c.admit_status, '') not in ('skipped', 'duplicate', 'admitted', 'matched_held')
     and not exists (select 1 from pipeline.scholarship_ai_extractions e where e.candidate_id = c.id and e.model_code = a.model_code and e.prompt_version = a.prompt_version and e.error is null)
     and not exists (select 1 from pipeline.scholarship_ai_queue q where q.candidate_id = c.id and q.state in ('queued', 'leased'));
  get diagnostics v_k = row_count; v_n := v_n + v_k;
  if p_known then
    insert into pipeline.scholarship_ai_queue(model_code, prompt_version, run_kind, job_id, scholarship_id, provider_id, url)
    select a.model_code, a.prompt_version, 'reread', p_job, s.id, s.provider_id, coalesce(sp.final_url, sp.url)
      from scholarship.scholarships s join pipeline.scholarship_pages sp on sp.scholarship_id = s.id
     where s.provider_id = any (p_provider_ids) and s.lifecycle_status = 'active'
       and not exists (select 1 from pipeline.scholarship_ai_extractions e where e.scholarship_id = s.id and e.model_code = a.model_code and e.prompt_version = a.prompt_version and e.error is null)
       and not exists (select 1 from pipeline.scholarship_ai_queue q where q.scholarship_id = s.id and q.state in ('queued', 'leased'));
    get diagnostics v_k = row_count; v_n := v_n + v_k;
  end if;
  perform security.scholarship_ai_fire_v1();
  return v_n;
end $f$;

-- Send the AI reader when there is work and fewer calls than allowed are on their way (each minute, and when work is queued)
create or replace function security.scholarship_ai_fire_v1()
returns integer language plpgsql security definer set search_path to '' as $f$
declare v_open int; v_max int; v_due int; v_sent int := 0;
begin
  select calls_at_once into v_max from pipeline.scholarship_ai_settings where id = 1;
  select count(*) into v_due from pipeline.scholarship_ai_queue q where (q.state = 'queued' and q.next_try_at <= now()) or (q.state = 'leased' and q.leased_until < now());
  if v_due = 0 then return 0; end if;
  select count(*) into v_open from pipeline.edge_request_log l where l.function_name = 'coverage-sweep' and l.mode = 'scholarship_ai' and l.created_at > now() - interval '3 minutes'
     and not exists (select 1 from net._http_response r where r.id = l.request_id);
  while v_open + v_sent < coalesce(v_max, 3) and v_sent * 8 < v_due loop
    perform pipeline.svc_pilot_submit_nonce('coverage-sweep', jsonb_build_object('mode', 'scholarship_ai'));
    v_sent := v_sent + 1;
  end loop;
  return v_sent;
end $f$;

-- The worker takes the next pages: model, instructions, stored copy (or the address to read through the scraper)
create or replace function public.svc_scholarship_ai_next(p_limit integer)
returns jsonb language plpgsql security definer set search_path to 'pg_catalog', 'pipeline', 'security' as $f$
declare v jsonb;
begin
  if current_user <> 'postgres' and coalesce(auth.role(), '') <> 'service_role' then raise exception 'service_role required'; end if;
  with pick as (
    select q.id from pipeline.scholarship_ai_queue q
     where ((q.state = 'queued' and q.next_try_at <= now()) or (q.state = 'leased' and q.leased_until < now())) and q.attempts < 3
     order by (q.run_kind = 'test') desc, (q.run_kind = 'qualify') desc, q.id
     limit greatest(1, least(coalesce(p_limit, 8), 20)) for update skip locked),
  upd as (update pipeline.scholarship_ai_queue q set state = 'leased', leased_until = now() + interval '4 minutes', attempts = q.attempts + 1 from pick where q.id = pick.id returning q.*)
  select coalesce(jsonb_agg(jsonb_build_object('queue_id', u.id, 'model_code', u.model_code, 'model', m.model_identifier, 'prompt_version', u.prompt_version,
           'prompt', (select p.text from pipeline.scholarship_ai_prompts p where p.version = u.prompt_version), 'run_kind', u.run_kind, 'url', u.url,
           'candidate_id', u.candidate_id, 'scholarship_id', u.scholarship_id, 'provider_id', u.provider_id,
           'provider', (select coalesce(pr.display_name, pr.canonical_name) from catalogue.providers pr where pr.id = u.provider_id),
           'currency', case when u.provider_id is not null then scholarship.provider_currency(u.provider_id) else 'AUD' end,
           'storage_path', coalesce((select c.storage_path from pipeline.scholarship_page_candidates c where c.id = u.candidate_id),
                                    (select e.storage_path from pipeline.scholarship_pages sp join pipeline.evidence_artifacts e on e.id = sp.evidence_id where sp.scholarship_id = u.scholarship_id),
                                    (select e.storage_path from scholarship.scholarships s join pipeline.evidence_artifacts e on e.id = s.evidence_id where s.id = u.scholarship_id)))), '[]'::jsonb)
    into v from upd u join pipeline.scholarship_ai_models m on m.code = u.model_code;
  return v;
end $f$;
revoke all on function public.svc_scholarship_ai_next(integer) from public, anon, authenticated;

-- Facts in the shape the scholarship records use, from the AI answer (proven fields only) laid over the rule-read facts
create or replace function security.scholarship_ai_facts_v1(p_answer jsonb, p_checks jsonb, p_rule jsonb, p_label text)
returns jsonb language plpgsql immutable set search_path to '' as $f$
declare a jsonb := coalesce(p_answer, '{}'::jsonb); k jsonb := coalesce(p_checks, '{}'::jsonb); f jsonb := coalesce(p_rule, '{}'::jsonb) - 'criteria';
        v jsonb := a->'value'; v_val jsonb; v_aud text := a->>'audience'; v_intl boolean; v_admit boolean; v_reasons text[] := '{}';
begin
  v_intl := v_aud in ('international', 'both') and coalesce((k->>'audience')::boolean, false);
  if not coalesce((a->>'is_scholarship')::boolean, false) then v_reasons := v_reasons || 'not_a_scholarship'; end if;
  if not coalesce((a->>'single_scholarship')::boolean, false) then v_reasons := v_reasons || 'listing_page'; end if;
  if not coalesce((k->>'name')::boolean, false) then v_reasons := v_reasons || 'no_named_title'; end if;
  if v_aud = 'domestic' and coalesce((k->>'audience')::boolean, false) then v_reasons := v_reasons || 'domestic_only';
  elsif not v_intl then v_reasons := v_reasons || 'international_not_stated'; end if;
  if a->>'offered' = 'no' and coalesce((k->>'offered')::boolean, false) then v_reasons := v_reasons || 'not_offered'; end if;
  v_admit := cardinality(v_reasons) = 0;
  if coalesce((k->>'value')::boolean, false) then
    v_val := case v->>'kind'
      when 'percentage' then jsonb_build_object('type', 'percentage', 'percentage', (v->>'percentage')::numeric, 'applies_to', 'tuition_fee', 'context', v->>'quote')
      when 'full_tuition' then jsonb_build_object('type', 'percentage', 'percentage', 100, 'applies_to', 'tuition_fee', 'context', v->>'quote')
      when 'fixed_amount' then jsonb_build_object('type', 'fixed_amount', 'amount', (v->>'amount')::numeric, 'currency', coalesce(nullif(v->>'currency', ''), 'AUD'), 'context', v->>'quote')
      when 'tiers' then jsonb_build_object('type', 'ambiguous', 'amounts', coalesce((select jsonb_agg((t->>'amount')::numeric) from jsonb_array_elements(coalesce(v->'tiers', '[]'::jsonb)) t where t->>'amount' is not null), '[]'::jsonb),
                                           'percentages', coalesce((select jsonb_agg((t->>'percentage')::numeric) from jsonb_array_elements(coalesce(v->'tiers', '[]'::jsonb)) t where t->>'percentage' is not null), '[]'::jsonb), 'context', v->>'quote')
      else null end;
  end if;
  f := f || jsonb_build_object(
    'extracted_by', 'ai', 'extractor', p_label, 'ai', jsonb_build_object('answer', a, 'checks', k),
    'admission', jsonb_build_object('name', a->>'name', 'admit', v_admit, 'reasons', to_jsonb(v_reasons), 'detail_page', coalesce((a->>'single_scholarship')::boolean, false),
                                    'international_explicit', v_intl, 'offered', coalesce(a->>'offered', 'not_stated') <> 'no', 'by', 'ai'),
    'international', v_intl, 'value', v_val,
    'eligibility_excerpt', nullif(a->>'audience_quote', ''),
    'levels', coalesce(a->'levels', '[]'::jsonb), 'levels_text', nullif(a->>'levels_quote', ''), 'levels_from', 'ai',
    'named_courses', jsonb_build_object('codes', '[]'::jsonb, 'titles', coalesce((select jsonb_agg(jsonb_build_object('title', x, 'text', 'Named on the page (AI, quote checked)')) from jsonb_array_elements_text(coalesce(k->'courses_found', '[]'::jsonb)) x), '[]'::jsonb), 'excluded', '[]'::jsonb),
    'dates', jsonb_build_object('open', case when a->>'open_date' ~ '^\d{4}-\d{2}-\d{2}$' and coalesce((k->>'dates')::boolean, false) then jsonb_build_object('date', a->>'open_date', 'text', a->>'dates_quote', 'precision', 'day') end,
                                'close', case when a->>'close_date' ~ '^\d{4}-\d{2}-\d{2}$' and coalesce((k->>'dates')::boolean, false) then jsonb_build_object('date', a->>'close_date', 'text', a->>'dates_quote', 'precision', 'day') end),
    'criteria', coalesce((select jsonb_agg(c) from jsonb_array_elements(coalesce(p_rule->'criteria', '[]'::jsonb)) c where c->>'type' <> 'student_type'), '[]'::jsonb)
                || case when v_intl then jsonb_build_array(jsonb_build_object('type', 'student_type', 'operator', 'in', 'value_codes', case when v_aud = 'both' then jsonb_build_array('international', 'domestic') else jsonb_build_array('international') end, 'text', a->>'audience_quote', 'by', 'ai'))
                        when v_aud = 'domestic' then jsonb_build_array(jsonb_build_object('type', 'student_type', 'operator', 'in', 'value_codes', jsonb_build_array('domestic'), 'text', a->>'audience_quote', 'by', 'ai'))
                        else '[]'::jsonb end);
  return f;
end $f$;

-- Apply one AI extraction (only while AI admission is on): a new page is admitted or refused; a known page is updated or withdrawn
create or replace function security.scholarship_ai_apply_v1(p_extraction bigint)
returns jsonb language plpgsql security definer set search_path to '' as $f$
declare e pipeline.scholarship_ai_extractions%rowtype; v_facts jsonb; v_rule jsonb; r jsonb; v_sid uuid; v_aud text;
begin
  select * into e from pipeline.scholarship_ai_extractions where id = p_extraction;
  if e.id is null or e.error is not null or e.answer is null then return jsonb_build_object('applied', false, 'reason', 'no answer'); end if;
  v_aud := case e.answer->>'audience' when 'international' then 'international' when 'both' then 'international_and_domestic' when 'domestic' then 'domestic' else null end;
  if e.candidate_id is not null then
    select c.facts into v_rule from pipeline.scholarship_page_candidates c where c.id = e.candidate_id;
    v_facts := security.scholarship_ai_facts_v1(e.answer, e.checks, coalesce(v_rule->'rules', v_rule), e.model_code || ' / instructions v' || e.prompt_version) || jsonb_build_object('rules', coalesce(v_rule->'rules', v_rule));
    update pipeline.scholarship_page_candidates set facts = v_facts, admit_status = null, admit_reasons = null, read_status = 'read' where id = e.candidate_id and admitted_scholarship_id is null;
    if coalesce((v_facts->'admission'->>'admit')::boolean, false) then
      r := security.scholarship_admit_from_provider_page_v1(e.candidate_id);
      v_sid := (r->>'scholarship_id')::uuid;
      if coalesce((r->>'admitted')::boolean, false) and v_aud is not null then update scholarship.scholarships set audience = v_aud, updated_at = now() where id = v_sid; end if;
    else
      update pipeline.scholarship_page_candidates set admit_status = 'rejected', admit_reasons = array(select jsonb_array_elements_text(v_facts->'admission'->'reasons')) where id = e.candidate_id;
      insert into pipeline.scholarship_admission_log(candidate_id, provider_id, action, detail) values (e.candidate_id, e.provider_id, 'rejected', jsonb_build_object('by', 'ai', 'extraction', e.id, 'reasons', v_facts->'admission'->'reasons'));
      r := jsonb_build_object('admitted', false, 'reasons', v_facts->'admission'->'reasons');
    end if;
  elsif e.scholarship_id is not null then
    select sp.facts into v_rule from pipeline.scholarship_pages sp where sp.scholarship_id = e.scholarship_id;
    v_facts := security.scholarship_ai_facts_v1(e.answer, e.checks, coalesce(v_rule->'rules', v_rule), e.model_code || ' / instructions v' || e.prompt_version) || jsonb_build_object('rules', coalesce(v_rule->'rules', v_rule));
    update pipeline.scholarship_pages set facts = v_facts, read_status = 'read', evidence_id = coalesce(e.evidence_id, evidence_id) where scholarship_id = e.scholarship_id;
    if not coalesce((v_facts->'admission'->>'admit')::boolean, false) and exists (select 1 from pipeline.scholarship_pages where scholarship_id = e.scholarship_id and url_source = 'admitted') then
      r := security.scholarship_admission_withdraw_v1(e.scholarship_id, jsonb_build_object('reasons', v_facts->'admission'->'reasons', 'extractor', v_facts->>'extractor', 'by', 'ai'));
    else
      r := security.scholarship_sweep_apply_v1(e.scholarship_id);
      if v_aud is not null then update scholarship.scholarships set audience = v_aud, updated_at = now() where id = e.scholarship_id and audience is distinct from v_aud; end if;
    end if;
  end if;
  update pipeline.scholarship_ai_extractions set applied = coalesce(r, '{}'::jsonb) || jsonb_build_object('at', now()) where id = e.id;
  return r;
end $f$;
revoke all on function security.scholarship_ai_apply_v1(bigint) from public, anon, authenticated;

-- The worker records one page's AI answer; a page read live is kept as evidence; it is applied when AI admission is on
create or replace function public.svc_scholarship_ai_record(p_queue_id bigint, p_answer jsonb, p_checks jsonb, p_verdict text, p_cost numeric, p_tokens_in integer, p_tokens_out integer,
                                                           p_seconds numeric, p_error text, p_storage_path text, p_sha256 text, p_final_url text, p_rule_facts jsonb, p_retry boolean default false)
returns jsonb language plpgsql security definer set search_path to 'pg_catalog', 'pipeline', 'security' as $f$
declare q pipeline.scholarship_ai_queue%rowtype; v_id bigint; v_ev uuid; v_on boolean; r jsonb;
begin
  if current_user <> 'postgres' and coalesce(auth.role(), '') <> 'service_role' then raise exception 'service_role required'; end if;
  select * into q from pipeline.scholarship_ai_queue where id = p_queue_id for update;
  if q.id is null then return jsonb_build_object('ok', false, 'reason', 'no queue item'); end if;
  if p_retry then
    update pipeline.scholarship_ai_queue set state = 'queued', leased_until = null, attempts = greatest(attempts - 1, 0), next_try_at = now() + interval '30 minutes' where id = q.id;
    return jsonb_build_object('ok', true, 'retry', true);
  end if;
  -- a candidate page read live for the first time: its copy and read are recorded on the candidate, as the scheduled reader does
  if q.candidate_id is not null and p_storage_path is not null then
    update pipeline.scholarship_page_candidates set storage_path = p_storage_path, content_hash = p_sha256, final_url = coalesce(p_final_url, final_url), read_at = now(),
           read_status = coalesce(nullif(p_rule_facts->>'read_status', ''), 'read'), next_read_at = now() + interval '90 days', leased_until = null,
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
  update pipeline.scholarship_ai_queue set state = case when p_error is null or attempts >= 3 then 'done' else 'queued' end, done_at = case when p_error is null or attempts >= 3 then now() end,
         leased_until = null, next_try_at = now() + interval '10 minutes', extraction_id = v_id where id = q.id;
  select ai_admission into v_on from pipeline.scholarship_ai_settings where id = 1;
  if p_error is null and v_on and q.run_kind in ('admit', 'reread') then r := security.scholarship_ai_apply_v1(v_id); end if;
  return jsonb_build_object('ok', true, 'extraction', v_id, 'applied', r);
end $f$;
revoke all on function public.svc_scholarship_ai_record(bigint, jsonb, jsonb, text, numeric, integer, integer, numeric, text, text, text, text, jsonb, boolean) from public, anon, authenticated;

-- Qualification scores: each model's answers on the hand-checked sample, for the current instructions
create or replace function security.scholarship_ai_scores_v1(p_prompt int)
returns jsonb language sql stable security definer set search_path to '' as $f$
  with last as (
    select distinct on (e.model_code, e.sample_id) e.* from pipeline.scholarship_ai_extractions e
     where e.sample_id is not null and e.prompt_version = p_prompt order by e.model_code, e.sample_id, e.at desc),
  j as (
    select l.model_code, s.id, s.expected x, l.answer a, l.checks k, l.error, l.cost_usd, l.seconds,
           (coalesce((l.answer->>'is_scholarship')::boolean, false) and coalesce((l.answer->>'single_scholarship')::boolean, false)) a_sch,
           (coalesce((s.expected->>'is_scholarship')::boolean, false) and coalesce((s.expected->>'single')::boolean, true)) x_sch
      from last l join pipeline.scholarship_ai_sample s on s.id = l.sample_id and s.active)
  select coalesce(jsonb_object_agg(z.model_code, z.v), '{}'::jsonb) from (
    select j.model_code, jsonb_build_object(
      'pages', count(*), 'errors', count(*) filter (where j.error is not null),
      'scholarship_right', count(*) filter (where j.error is null and j.a_sch = j.x_sch),
      'international_checked', count(*) filter (where j.x ? 'international' and j.x_sch and j.error is null),
      'international_right', count(*) filter (where j.x ? 'international' and j.x_sch and j.error is null and ((j.a->>'audience') in ('international', 'both')) = (j.x->>'international')::boolean),
      'offered_checked', count(*) filter (where j.x ? 'offered' and j.x_sch and j.error is null),
      'offered_right', count(*) filter (where j.x ? 'offered' and j.x_sch and j.error is null and ((j.a->>'offered') <> 'no') = (j.x->>'offered')::boolean),
      'proven', count(*) filter (where j.error is null and j.a_sch and coalesce((j.k->>'name')::boolean, false)),
      'proofs_failed', count(*) filter (where j.error is null and j.a_sch and (not coalesce((j.k->>'name')::boolean, true) or not coalesce((j.k->>'audience')::boolean, true) or not coalesce((j.k->>'value')::boolean, true))),
      'cost_usd', round(coalesce(sum(j.cost_usd), 0), 4), 'cost_per_page', round(coalesce(avg(j.cost_usd), 0), 5), 'seconds_per_page', round(coalesce(avg(j.seconds), 0), 1)) v
      from j group by j.model_code) z
$f$;

-- Scholarships › Extraction (Curator and above read; Platform Admin changes, always with a reason)
create or replace function public.admin_scholarship_ai(p_action text default 'read', p_args jsonb default '{}'::jsonb)
returns jsonb language plpgsql security definer set search_path to '' as $f$
declare v_rank int := security.current_role_rank(); v_reason text := btrim(coalesce(p_args->>'reason', '')); a record; v_pv int; v_job uuid; v_n int; v_ids uuid[];
begin
  if auth.uid() is null or v_rank < 3 then raise exception 'Curator role or above required' using errcode = '42501'; end if;
  select * into a from security.scholarship_ai_active_v1();
  if p_action <> 'read' then
    if v_rank < 6 then raise exception 'Platform Admin required' using errcode = '42501'; end if;
    if p_action not in ('label', 'test') and length(v_reason) < 4 then raise exception 'give a reason (kept in the log)'; end if;
    if p_action = 'set_prompt' then
      if length(btrim(coalesce(p_args->>'text', ''))) < 200 then raise exception 'the instructions are too short'; end if;
      update pipeline.scholarship_ai_prompts set active = false where active;
      insert into pipeline.scholarship_ai_prompts(text, active, reason, created_by) values (p_args->>'text', true, v_reason, auth.uid());
      -- new instructions: the active model must be qualified again before it admits anything
      if a.ai_admission then update pipeline.scholarship_ai_settings set ai_admission = false, changed_by = auth.uid(), changed_at = now(), reason = 'instructions changed: qualify again before switching on' where id = 1; end if;
    elsif p_action = 'label' then
      if v_rank < 6 then raise exception 'Platform Admin required'; end if;
      if p_args ? 'sample_id' then
        update pipeline.scholarship_ai_sample set expected = coalesce(p_args->'expected', expected), active = coalesce((p_args->>'active')::boolean, active), note = coalesce(p_args->>'note', note), label_source = 'Platform Admin ' || to_char(now() at time zone 'Australia/Melbourne', 'DD Mon YYYY HH24:MI') where id = (p_args->>'sample_id')::int;
      else
        insert into pipeline.scholarship_ai_sample(url, provider_id, expected, label_source, note, added_by)
        values (btrim(p_args->>'url'), nullif(p_args->>'provider_id', '')::uuid, coalesce(p_args->'expected', '{}'::jsonb), 'Platform Admin ' || to_char(now() at time zone 'Australia/Melbourne', 'DD Mon YYYY HH24:MI'), p_args->>'note', auth.uid())
        on conflict (url) do update set expected = excluded.expected, active = true, note = excluded.note, label_source = excluded.label_source;
      end if;
    elsif p_action = 'qualify' then
      if not exists (select 1 from pipeline.scholarship_ai_models m where m.code = p_args->>'model_code' and m.status <> 'retired') then raise exception 'choose a model'; end if;
      v_pv := coalesce(a.prompt_version, 1);
      insert into pipeline.admin_jobs(kind, lane, title, args, progress, requested_by, reason, scope)
      values ('scholarship_ai_qualify', 'scholarship_ai:qualify:' || (p_args->>'model_code'), 'Qualify the scholarship AI: ' || (select m.label from pipeline.scholarship_ai_models m where m.code = p_args->>'model_code') || ' (instructions v' || v_pv || ')',
              jsonb_build_object('model_code', p_args->>'model_code', 'prompt_version', v_pv), jsonb_build_object('done', 0, 'total', (select count(*) from pipeline.scholarship_ai_sample where active)), auth.uid(), v_reason, p_args->>'model_code')
      returning id into v_job;
      insert into pipeline.scholarship_ai_queue(model_code, prompt_version, run_kind, job_id, sample_id, candidate_id, scholarship_id, provider_id, url)
      select p_args->>'model_code', v_pv, 'qualify', v_job, s.id, s.candidate_id, s.scholarship_id, s.provider_id, s.url from pipeline.scholarship_ai_sample s where s.active;
      insert into pipeline.admin_job_events(job_id, note, detail) values (v_job, 'queued by ' || coalesce((select u.email from auth.users u where u.id = auth.uid()), ''), jsonb_build_object('reason', v_reason));
      perform security.scholarship_ai_fire_v1();
    elsif p_action = 'activate' then
      if not exists (select 1 from pipeline.admin_jobs j where j.kind = 'scholarship_ai_qualify' and j.state = 'done' and j.args->>'model_code' = p_args->>'model_code' and (j.args->>'prompt_version')::int = a.prompt_version) then
        raise exception 'qualify this model with the current instructions first';
      end if;
      update pipeline.scholarship_ai_models set status = 'candidate' where status = 'active';
      update pipeline.scholarship_ai_models set status = 'active', activated_at = now(), activated_by = auth.uid(), reason = v_reason where code = p_args->>'model_code';
    elsif p_action = 'set_admission' then
      if coalesce((p_args->>'on')::boolean, false) and a.model_code is null then raise exception 'make a qualified model active first'; end if;
      update pipeline.scholarship_ai_settings set ai_admission = coalesce((p_args->>'on')::boolean, false), changed_by = auth.uid(), changed_at = now(), reason = v_reason where id = 1;
    elsif p_action = 'backfill' then
      if a.model_code is null then raise exception 'make a qualified model active first'; end if;
      v_ids := case when p_args->>'scope' = 'watch' then array(select w.provider_id from pipeline.scholarship_watch w where w.active)
                    else array(select x::uuid from jsonb_array_elements_text(coalesce(p_args->'provider_ids', '[]'::jsonb)) x) end;
      if coalesce(cardinality(v_ids), 0) = 0 then raise exception 'choose universities'; end if;
      insert into pipeline.admin_jobs(kind, lane, title, args, progress, requested_by, reason, scope)
      values ('scholarship_ai_backfill', 'scholarship_ai:backfill', 'Re-check scholarship pages with AI: ' || case when p_args->>'scope' = 'watch' then 'watch list (' || cardinality(v_ids) || ')' else cardinality(v_ids) || ' universities' end,
              jsonb_build_object('providers', to_jsonb(v_ids), 'model_code', a.model_code, 'prompt_version', a.prompt_version), jsonb_build_object('done', 0, 'total', 0), auth.uid(), v_reason, 'backfill:' || md5(array_to_string(v_ids, ',')))
      returning id into v_job;
      v_n := security.scholarship_ai_enqueue_v1('admit', v_ids, v_job, true);
      update pipeline.admin_jobs set progress = jsonb_build_object('done', 0, 'total', v_n) where id = v_job;
      insert into pipeline.admin_job_events(job_id, note, detail) values (v_job, 'queued by ' || coalesce((select u.email from auth.users u where u.id = auth.uid()), '') || ': ' || v_n || ' page(s)', jsonb_build_object('reason', v_reason));
    elsif p_action = 'test' then
      if a.model_code is null and coalesce(p_args->>'model_code', '') = '' then raise exception 'choose a model'; end if;
      insert into pipeline.scholarship_ai_queue(model_code, prompt_version, run_kind, url, provider_id)
      values (coalesce(nullif(p_args->>'model_code', ''), a.model_code), coalesce(a.prompt_version, 1), 'test', btrim(p_args->>'url'), nullif(p_args->>'provider_id', '')::uuid);
      perform security.scholarship_ai_fire_v1();
    else raise exception 'unknown action';
    end if;
    insert into pipeline.admin_control_events(area, action, target, detail, actor) values ('scholarship_ai', p_action, coalesce(p_args->>'model_code', p_args->>'sample_id', p_args->>'url', ''), p_args - 'text', auth.uid());
    select * into a from security.scholarship_ai_active_v1();
  end if;
  return jsonb_build_object(
    'can_manage', v_rank >= 6, 'ai_admission', a.ai_admission, 'active_model', a.model_code, 'prompt_version', a.prompt_version,
    'settings', (select to_jsonb(s) - 'id' from pipeline.scholarship_ai_settings s where s.id = 1),
    'models', (select jsonb_agg(to_jsonb(m) - 'activated_by' order by m.sort) from pipeline.scholarship_ai_models m),
    'prompts', (select jsonb_agg(jsonb_build_object('version', p.version, 'active', p.active, 'reason', p.reason, 'at', p.created_at, 'text', case when p.active then p.text end) order by p.version desc) from pipeline.scholarship_ai_prompts p),
    'scores', security.scholarship_ai_scores_v1(a.prompt_version),
    'qualify_runs', (select coalesce(jsonb_agg(jsonb_build_object('id', j.id, 'model_code', j.args->>'model_code', 'prompt_version', j.args->>'prompt_version', 'state', j.state, 'progress', j.progress, 'at', j.created_at, 'finished_at', j.finished_at) order by j.created_at desc), '[]'::jsonb)
                      from (select * from pipeline.admin_jobs j where j.kind = 'scholarship_ai_qualify' order by j.created_at desc limit 10) j),
    'sample', (select coalesce(jsonb_agg(jsonb_build_object('id', s.id, 'url', s.url, 'expected', s.expected, 'label_source', s.label_source, 'note', s.note, 'active', s.active,
                 'provider', (select coalesce(pr.display_name, pr.canonical_name) from catalogue.providers pr where pr.id = s.provider_id),
                 'answers', (select coalesce(jsonb_object_agg(e.model_code, jsonb_build_object('answer', e.answer, 'checks', e.checks, 'verdict', e.verdict, 'error', e.error, 'evidence_id', e.evidence_id, 'cost', e.cost_usd)), '{}'::jsonb)
                               from (select distinct on (e.model_code) e.* from pipeline.scholarship_ai_extractions e where e.sample_id = s.id and e.prompt_version = a.prompt_version order by e.model_code, e.at desc) e))
                 order by s.id), '[]'::jsonb) from pipeline.scholarship_ai_sample s),
    'queue', (select jsonb_build_object('waiting', count(*) filter (where q.state in ('queued', 'leased')), 'done_today', count(*) filter (where q.state = 'done' and q.done_at > date_trunc('day', now()))) from pipeline.scholarship_ai_queue q),
    'cost_today', (select round(coalesce(sum(e.cost_usd), 0), 4) from pipeline.scholarship_ai_extractions e where e.at > date_trunc('day', now())),
    'recent', (select coalesce(jsonb_agg(jsonb_build_object('id', e.id, 'at', e.at, 'url', e.url, 'model_code', e.model_code, 'run_kind', e.run_kind, 'verdict', e.verdict, 'error', e.error, 'answer', e.answer, 'checks', e.checks,
                 'applied', e.applied, 'evidence_id', e.evidence_id, 'cost', e.cost_usd, 'provider', (select coalesce(pr.display_name, pr.canonical_name) from catalogue.providers pr where pr.id = e.provider_id)) order by e.at desc), '[]'::jsonb)
               from (select * from pipeline.scholarship_ai_extractions e where e.sample_id is null order by e.at desc limit 40) e));
end $f$;
revoke all on function public.admin_scholarship_ai(text, jsonb) from public, anon;
grant execute on function public.admin_scholarship_ai(text, jsonb) to authenticated;

-- Each night (02:13 Melbourne) while AI admission is on: the next universities not yet read with the active model and instructions
create or replace function security.scholarship_ai_backfill_tick_v1()
returns jsonb language plpgsql security definer set search_path to '' as $f$
declare a record; v_ids uuid[]; v_n int; v_per int;
begin
  select * into a from security.scholarship_ai_active_v1();
  if not coalesce(a.ai_admission, false) or a.model_code is null then return jsonb_build_object('skipped', 'AI admission is off'); end if;
  select backfill_providers_per_night into v_per from pipeline.scholarship_ai_settings where id = 1;
  v_ids := array(select c.provider_id from pipeline.scholarship_page_candidates c
                  where c.admit_status = 'rejected' and c.source <> 'register'
                    and not exists (select 1 from pipeline.scholarship_ai_extractions e where e.candidate_id = c.id and e.model_code = a.model_code and e.prompt_version = a.prompt_version)
                  group by c.provider_id order by count(*) desc limit v_per);
  if cardinality(v_ids) = 0 then return jsonb_build_object('done', 'every university read'); end if;
  v_n := security.scholarship_ai_enqueue_v1('admit', v_ids, null, true);
  return jsonb_build_object('providers', cardinality(v_ids), 'pages', v_n);
end $f$;

select cron.schedule('scholarship-ai-extract', '* * * * *', 'select security.scholarship_ai_fire_v1()') where not exists (select 1 from cron.job where jobname = 'scholarship-ai-extract');
select cron.schedule('scholarship-ai-backfill', '13 15 * * *', 'select security.scholarship_ai_backfill_tick_v1()') where not exists (select 1 from cron.job where jobname = 'scholarship-ai-backfill');
insert into pipeline.automation_catalogue(jobname, area, sort, label, description, control_rank) values
  ('scholarship-ai-extract', 'Scholarships', 45, 'Read scholarship pages with AI', 'Sends queued scholarship pages to the active AI model (and the qualification sample to the model being qualified); each answer is checked against the page.', 6),
  ('scholarship-ai-backfill', 'Scholarships', 46, 'AI re-check of refused pages (nightly)', 'While AI admission is on, queues the next universities whose refused pages have not been read with the active model and instructions.', 6)
on conflict (jobname) do nothing;

CREATE OR REPLACE FUNCTION security.admin_job_slice_v1(p_id uuid, p_items integer)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_j pipeline.admin_jobs%rowtype; v_next int; v_total int; v_ids uuid[]; v_pid uuid; v_r jsonb; v_min_read numeric; v_min_agree numeric;
        v_done int := 0; v_errs int; v_pass int; v_fields text[]; v_have text[]; v_want text[]; v_claims text; v_res jsonb; v_added text[];
begin
  select * into v_j from pipeline.admin_jobs j where j.id = p_id for update;
  if v_j.kind in ('reread_pages', 'firecrawl_run', 'adapter_apply', 'central_page_read', 'scholarship_provider_scan', 'scholarship_course_check', 'scholarship_reread', 'provider_fill', 'course_page_find', 'scholarship_ai_qualify', 'scholarship_ai_backfill') then return security.admin_job_watch_v1(p_id); end if;
  v_ids := array(select (x)::uuid from jsonb_array_elements_text(v_j.args->'providers') x);
  v_total := coalesce(array_length(v_ids, 1), 0);
  v_next := coalesce((v_j.cursor->>'next')::int, 1);
  v_errs := coalesce((v_j.result->>'errors')::int, 0);
  v_pass := coalesce((v_j.result->>'passing')::int, 0);
  v_min_read := coalesce((security.firecrawl_setting('eval_field_share') #>> '{}')::numeric, 0.5);
  v_min_agree := coalesce((security.firecrawl_setting('qualify_agree_share') #>> '{}')::numeric, 0.9);
  while v_next <= v_total and v_done < p_items loop
    v_pid := v_ids[v_next];
    begin
      if v_j.kind = 'qualify_adapters' then
        v_r := security.adapter_qualify_one_v1(v_pid, v_min_read, v_min_agree);
        insert into pipeline.adapter_qualifications(job_id, provider_id, pages_read, fields, passing)
          values (p_id, v_pid, (v_r->>'pages_read')::int, v_r->'fields', array(select x from jsonb_array_elements_text(v_r->'passing') x))
          on conflict (job_id, provider_id) do update set measured_at = now(), pages_read = excluded.pages_read, fields = excluded.fields, passing = excluded.passing where pipeline.adapter_qualifications.job_id = excluded.job_id and pipeline.adapter_qualifications.provider_id = excluded.provider_id;
        if jsonb_array_length(v_r->'passing') > 0 then v_pass := v_pass + 1; end if;
      elsif v_j.kind = 'admit_qualified' then
        v_want := array(select x from jsonb_array_elements_text(v_j.args->'fields') x);
        select q.passing into v_fields from pipeline.adapter_qualifications q where q.job_id = coalesce((v_j.args->'qual_jobs'->>v_pid::text)::uuid, (v_j.args->>'qualification_job_id')::uuid) and q.provider_id = v_pid;
        select coalesce(u.admit_fields, '{}') into v_have from pipeline.uni_adapters u where u.provider_id = v_pid;
        v_added := array(select f from unnest(v_fields) f where f = any (v_want) and f <> all (v_have));
        if coalesce(array_length(v_added, 1), 0) > 0 then
          -- as the person who started the job, through the ordinary admission control (its checks and its log entry)
          v_claims := jsonb_build_object('sub', v_j.requested_by::text, 'role', 'authenticated')::text;
          perform set_config('request.jwt.claims', v_claims, true);
          v_res := public.admin_uni_adapter_control('admit', jsonb_build_object('provider_id', v_pid, 'admit', true,
                     'fields', to_jsonb(array(select distinct f from unnest(v_have || v_added) f order by f)),
                     'reason', left('Admitted by job ' || p_id::text || ' (' || v_j.title || '): ' || v_j.reason, 400)));
          perform set_config('request.jwt.claims', '', true);
          v_pass := v_pass + 1;
          insert into pipeline.admin_job_events(job_id, note, detail) values (p_id, 'admitted ' || array_to_string(v_added, ', ') || ' for ' || (select coalesce(p.display_name, p.canonical_name) from catalogue.providers p where p.id = v_pid), jsonb_build_object('provider_id', v_pid, 'fields', v_res->'fields'));
        end if;
      end if;
    exception when others then
      perform set_config('request.jwt.claims', '', true);
      v_errs := v_errs + 1;
      insert into pipeline.admin_job_events(job_id, note, detail) values (p_id, 'error for ' || coalesce((select coalesce(p.display_name, p.canonical_name) from catalogue.providers p where p.id = v_pid), v_pid::text) || ': ' || left(sqlerrm, 300), jsonb_build_object('provider_id', v_pid));
    end;
    v_next := v_next + 1; v_done := v_done + 1;
  end loop;
  update pipeline.admin_jobs set cursor = jsonb_build_object('next', v_next), progress = jsonb_build_object('done', v_next - 1, 'total', v_total), result = jsonb_build_object('passing', v_pass, 'errors', v_errs), updated_at = now() where id = p_id;
  return v_next > v_total;
end $function$;

CREATE OR REPLACE FUNCTION security.admin_job_watch_v1(p_id uuid)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_j pipeline.admin_jobs%rowtype; v_done int := 0; v_total int := 0; v_fin boolean := false; v_note text := null; v_phase text := null;
        v_n_map int := 0; v_n_cand int := 0; v_extra jsonb; v_sch uuid[]; v_before uuid[]; v_since timestamptz;
        v_last_done int; v_last_at timestamptz; v_stall interval; v_ids uuid[]; r record;
        v_pid uuid; v_site text; v_cok boolean; v_c int := 0; v_c2 int := 0;
begin
  select * into v_j from pipeline.admin_jobs j where j.id = p_id for update;
  v_last_done := coalesce((v_j.cursor->>'last_done')::int, -1);
  v_last_at := coalesce((v_j.cursor->>'last_change_at')::timestamptz, v_j.started_at, v_j.created_at);
  if v_j.kind = 'reread_pages' then
    v_stall := interval '30 minutes';
    select * into r from pipeline.university_reread_requests q where q.id = (v_j.args->>'request_id')::uuid;
    if r.id is null then v_fin := true; v_note := 'the re-read request is gone';
    elsif r.status = 'cancelled' then v_fin := true; v_note := 'cancelled before every university was sent (' || cardinality(r.done_ids) || ' of ' || cardinality(r.provider_ids) || ' sent)';
    elsif r.status = 'failed' then v_fin := true; v_note := 'the request failed: ' || coalesce(r.last_error, 'no detail');
    elsif r.status in ('waiting', 'sending') then
      v_phase := 'sending'; v_done := cardinality(r.done_ids); v_total := cardinality(r.provider_ids);
    else
      v_phase := 'reading'; v_total := coalesce(r.pages, 0);
      v_ids := r.provider_ids;
      select count(*) into v_done from pipeline.coverage_course_pages pg where pg.provider_id = any (v_ids) and pg.read_at >= coalesce(v_j.started_at, v_j.created_at);
      if v_done >= v_total then v_fin := true; v_note := v_total || ' page(s) sent back and read again'; end if;
    end if;
  elsif v_j.kind = 'firecrawl_run' then
    select * into r from pipeline.firecrawl_runs x where x.id = (v_j.args->>'run_id')::uuid;
    if r.id is null then v_fin := true; v_note := 'the run is gone';
    else
      v_done := coalesce(r.done, 0); v_total := coalesce(r.items, 0);
      if r.status <> 'running' then v_fin := true; v_note := 'run ' || r.status || ': ' || v_done || ' of ' || v_total || ' done, ' || coalesce(r.credits_used, 0) || ' credits'; end if;
    end if;
  elsif v_j.kind = 'adapter_apply' then
    v_stall := interval '20 minutes';
    v_total := coalesce((v_j.args->>'pages')::int, 0);
    select count(*) into v_done from pipeline.coverage_course_pages pg where pg.provider_id = (v_j.args->>'provider_id')::uuid and pg.read_at >= coalesce(v_j.started_at, v_j.created_at);
    if v_done >= v_total then v_fin := true; v_note := v_total || ' page(s) read again with the adapter'; end if;
  elsif v_j.kind = 'central_page_read' then
    v_stall := interval '30 minutes'; v_total := 1;
    select * into r from pipeline.provider_fact_sources s where s.id = (v_j.args->>'source_id')::uuid;
    if r.id is null then v_fin := true; v_note := 'the central page record is gone';
    elsif r.status in ('read', 'parsed', 'no_values', 'failed') and r.updated_at >= coalesce(v_j.started_at, v_j.created_at) - interval '1 minute' then
      v_done := 1; v_fin := true; v_note := 'page ' || r.status || coalesce(': ' || (r.parse_summary->>'error'), '');
    end if;
  -- 11 Oct 2026 (CF-247, Platform Admin): on-demand scholarship tasks. The pages in scope were queued first in line when the task
  -- started; each minute this checks progress, sends the scraper worker the next step (map the site, screen candidate pages, read
  -- scholarship pages) when none is already on its way, and finishes when nothing in scope is left to do.
  elsif v_j.kind in ('scholarship_provider_scan', 'scholarship_course_check', 'scholarship_reread') then
    v_stall := interval '30 minutes'; v_since := v_j.created_at;
    v_ids := array(select x::uuid from jsonb_array_elements_text(coalesce(v_j.args->'providers', '[]'::jsonb)) x);
    v_sch := array(select x::uuid from jsonb_array_elements_text(coalesce(v_j.args->'scholarship_ids', '[]'::jsonb)) x);
    select count(*) filter (where p.requested_at is null and p.read_at >= v_since), count(*) into v_done, v_total
      from pipeline.scholarship_pages p join scholarship.scholarships s on s.id = p.scholarship_id
     where s.lifecycle_status = 'active'
       and (case when v_j.kind = 'scholarship_reread' then s.id = any (v_sch) else s.provider_id = any (v_ids) end)
       and (p.requested_at is not null or p.read_at >= v_since or s.created_at >= v_since);
    if v_j.kind = 'scholarship_provider_scan' then
      select count(*) into v_n_map from pipeline.scholarship_discovery_providers d where d.provider_id = any (v_ids) and d.status = 'pending' and d.attempts < 3;
      select count(*) into v_n_cand from pipeline.scholarship_page_candidates c
       where c.provider_id = any (v_ids) and c.admit_status is null and c.matched_scholarship_id is null and c.source <> 'register' and c.next_read_at <= now() and c.attempts < 3;
    end if;
    v_phase := case when v_n_map > 0 then 'mapping the site' when v_n_cand > 0 then 'screening candidate pages' when v_done < v_total then 'reading scholarship pages' else 'finishing' end;
    v_extra := jsonb_build_object('phase_detail', v_phase, 'providers_mapping', v_n_map, 'candidates_waiting', v_n_cand,
      'new_scholarships', (select count(*) from scholarship.scholarships s where s.provider_id = any (v_ids) and s.created_at >= v_since),
      'links_changed', (select count(*) from pipeline.scholarship_sweep_changes c join scholarship.scholarships s on s.id = c.scholarship_id
                         where s.provider_id = any (v_ids) and c.field = 'course_links' and c.changed_at >= v_since),
      'credits', (select coalesce(sum(u.units), 0) from pipeline.coverage_vendor_usage u where u.provider_id = any (v_ids) and u.purpose like 'sch\_%' and u.at >= v_since));
    if v_j.kind = 'scholarship_course_check' then
      v_before := array(select x::uuid from jsonb_array_elements_text(coalesce(v_j.args->'before', '[]'::jsonb)) x);
      v_extra := v_extra || jsonb_build_object('course_id', v_j.args->>'course_id',
        'linked_now', (select count(*) from scholarship.course_mappings m where m.course_id = (v_j.args->>'course_id')::uuid and m.mapping_state = 'mapped'),
        'added', (select coalesce(jsonb_agg(jsonb_build_object('id', s.id, 'name', s.name) order by s.name), '[]'::jsonb) from scholarship.course_mappings m join scholarship.scholarships s on s.id = m.scholarship_id
                   where m.course_id = (v_j.args->>'course_id')::uuid and m.mapping_state = 'mapped' and not (m.scholarship_id = any (v_before))),
        'removed', (select coalesce(jsonb_agg(jsonb_build_object('id', s.id, 'name', s.name) order by s.name), '[]'::jsonb) from scholarship.scholarships s
                     where s.id = any (v_before) and not exists (select 1 from scholarship.course_mappings m where m.course_id = (v_j.args->>'course_id')::uuid and m.scholarship_id = s.id and m.mapping_state = 'mapped')));
    end if;
    if v_n_map = 0 and v_n_cand = 0 and v_done >= v_total then
      v_fin := true;
      v_note := v_done || ' known scholarship page(s) read again through the scraper' || coalesce(', ' || nullif((v_extra->>'new_scholarships')::int, 0) || ' new scholarship(s) found', '')
             || ', course links changed on ' || (v_extra->>'links_changed') || ', ' || (v_extra->>'credits') || ' scholarship scraper credit(s) used for ' || case when cardinality(v_ids) = 1 then 'this provider' else 'these providers' end || ' while the task ran'
             || case when v_j.kind = 'scholarship_course_check' then '; this course now has ' || (v_extra->>'linked_now') || ' scholarship(s) (' || jsonb_array_length(v_extra->'added') || ' added, ' || jsonb_array_length(v_extra->'removed') || ' removed)' else '' end;
    else
      perform security.scholarship_task_fire_v1(case when v_n_map > 0 then array['discover'] when v_n_cand > 0 then array['candidates'] else array['read'] end);
    end if;
    -- v2.15.248 (Platform Admin bugs 11/10-5, Feature 2): record what the task found and read, item by item, and count the new
    -- pages it checked in its progress and result
    perform security.scholarship_job_items_sync_v1(v_j.id);
    select v_extra || jsonb_build_object('candidates_found', count(*) filter (where i.kind = 'candidate'), 'became', count(*) filter (where i.outcome = 'became_scholarship'),
             'refused', count(*) filter (where i.outcome = 'refused'), 'too_thin', count(*) filter (where i.outcome = 'too_thin'), 'skipped', count(*) filter (where i.outcome = 'skipped'),
             'known_pages', count(*) filter (where i.kind = 'page')),
           v_done + count(*) filter (where i.kind = 'candidate' and i.outcome <> 'waiting'), v_total + count(*) filter (where i.kind = 'candidate')
      into v_extra, v_done, v_total from pipeline.admin_job_items i where i.job_id = v_j.id;
    if v_fin then
      v_done := v_total;
      v_note := coalesce(nullif((v_extra->>'candidates_found')::int, 0) || ' new page(s) checked (' || (v_extra->>'became') || ' became scholarships, ' || (v_extra->>'refused') || ' refused, '
                || (v_extra->>'too_thin') || ' too thin, ' || (v_extra->>'skipped') || ' skipped); ', 'no new pages found; ') || v_note;
    end if;
  -- 11 Oct 2026 (CF-247, Platform Admin bugs 11/10-2): Fill in a provider from its website (website, then contacts, then central
  -- pages; each step sent to the worker when none is on its way) and Find course pages with Firecrawl (the chosen courses first in
  -- the course page search, finished when each has been searched).
  elsif v_j.kind = 'provider_fill' then
    v_stall := interval '30 minutes'; v_since := v_j.created_at; v_pid := (v_j.args->>'provider_id')::uuid; v_total := 3;
    select nullif(btrim(p.website), ''), (p.phone is not null and p.email is not null) into v_site, v_cok from catalogue.providers p where p.id = v_pid;
    select * into r from pipeline.coverage_provider_discovery d where d.provider_id = v_pid;
    if v_site is null and r.provider_id is not null and r.status = 'no_website' and (r.site_searched_at is null or r.site_searched_at < v_since) then
      v_phase := 'finding the website'; v_done := 0;
      perform security.provider_task_fire_v1('find_site');
    elsif v_site is null then
      v_fin := true; v_done := 3;
      v_note := 'no website could be verified by search' || coalesce(' (' || (r.site_evidence->>'note') || ')', '') || '; enter it by hand in the Adapter builder, step 1.1';
    else
      v_done := 1;
      if not coalesce(v_cok, false) and exists (select 1 from catalogue.courses c where c.provider_id = v_pid and c.lifecycle_status = 'active')
         and not exists (select 1 from pipeline.provider_contact_checks k where k.provider_id = v_pid and k.kind = 'public_general' and k.checked_at >= v_since and k.outcome not in ('leased', 'requested')) then
        v_phase := 'reading contacts';
        perform security.provider_task_fire_v1('contact_page');
      else
        v_done := 2;
        if exists (select 1 from pipeline.provider_central_search s where s.provider_id = v_pid and s.state in ('queued', 'leased')) then
          v_phase := 'finding central pages';
          perform security.provider_task_fire_v1('central_find');
        else
          v_done := 3; v_fin := true;
        end if;
      end if;
    end if;
    v_extra := jsonb_build_object('phase_detail', coalesce(v_phase, 'finishing'), 'website', v_site, 'website_basis', r.site_evidence->>'basis',
      'phone', (select p.phone from catalogue.providers p where p.id = v_pid), 'email', (select p.email from catalogue.providers p where p.id = v_pid),
      'central_found', (select coalesce(jsonb_array_length(s.found), 0) from pipeline.provider_central_search s where s.provider_id = v_pid),
      'credits', (select coalesce(sum(u.units), 0) from pipeline.coverage_vendor_usage u where u.provider_id = v_pid and u.at >= v_since));
    if v_fin and v_note is null then
      v_note := 'website ' || coalesce(v_site, 'not found') || '; phone ' || coalesce(v_extra->>'phone', 'not found') || ', email ' || coalesce(v_extra->>'email', 'not found')
             || '; ' || coalesce(v_extra->>'central_found', '0') || ' central page suggestion(s) to attach in the Adapter builder, step 1.3; ' || (v_extra->>'credits') || ' Firecrawl credit(s)';
    end if;
  -- v2.15.249 (bugs 11/10-6): qualifying the scholarship AI on the sample, or re-checking universities' pages with it
  elsif v_j.kind in ('scholarship_ai_qualify', 'scholarship_ai_backfill') then
    v_stall := interval '30 minutes';
    select count(*) filter (where q.state in ('done', 'failed')), count(*) into v_done, v_total from pipeline.scholarship_ai_queue q where q.job_id = v_j.id;
    v_phase := 'reading pages with AI';
    select jsonb_build_object('phase_detail', v_phase, 'scholarships', count(*) filter (where e.verdict = 'scholarship'), 'not_scholarships', count(*) filter (where e.verdict in ('not_scholarship', 'listing')),
             'unproven', count(*) filter (where e.verdict = 'unproven'), 'ai_errors', count(*) filter (where e.error is not null), 'admitted', count(*) filter (where coalesce((e.applied->>'admitted')::boolean, false)),
             'cost_usd', round(coalesce(sum(e.cost_usd), 0), 4))
      into v_extra from pipeline.scholarship_ai_extractions e where e.job_id = v_j.id;
    if v_done >= v_total then
      v_fin := true;
      v_note := v_done || ' page(s) read with AI: ' || (v_extra->>'scholarships') || ' scholarship(s), ' || (v_extra->>'not_scholarships') || ' not a scholarship, ' || (v_extra->>'unproven') || ' unproven, '
                || (v_extra->>'ai_errors') || ' error(s)' || case when v_j.kind = 'scholarship_ai_backfill' then ', ' || (v_extra->>'admitted') || ' admitted' else '' end || '; US$' || (v_extra->>'cost_usd');
    else
      perform security.scholarship_ai_fire_v1();
    end if;
  elsif v_j.kind = 'course_page_find' then
    v_stall := interval '45 minutes'; v_since := v_j.created_at; v_pid := (v_j.args->>'provider_id')::uuid;
    v_ids := array(select x::uuid from jsonb_array_elements_text(coalesce(v_j.args->'course_ids', '[]'::jsonb)) x);
    v_total := coalesce(cardinality(v_ids), 0);
    select count(*) filter (where s.state not in ('queued', 'sent') and s.queued_at >= v_since),
           count(*) filter (where s.state in ('verified', 'found') and s.queued_at >= v_since),
           count(*) filter (where s.state = 'none' and s.queued_at >= v_since)
      into v_done, v_c, v_c2 from pipeline.course_link_search s where s.course_id = any (v_ids);
    v_phase := 'searching course pages';
    v_extra := jsonb_build_object('phase_detail', v_phase, 'found', v_c, 'not_found', v_c2,
      'credits', (select coalesce(sum(u.units), 0) from pipeline.coverage_vendor_usage u where u.provider_id = v_pid and u.purpose = 'course_link_search' and u.at >= v_since));
    if v_done >= v_total then
      v_fin := true;
      v_note := v_c || ' of ' || v_total || ' course page(s) found on the provider''s site; ' || v_c2 || ' not found (enter those by hand in the Adapter builder, step 2.1)';
    end if;
  end if;
  if v_done <> v_last_done then v_last_done := v_done; v_last_at := now(); end if;
  if not v_fin and v_stall is not null and now() - v_last_at > v_stall then
    v_fin := true; v_note := coalesce(v_note, v_done || ' of ' || v_total || ' done, nothing more for ' || extract(epoch from v_stall)::int / 60 || ' minutes: the rest wait their turn in the reader');
  end if;
  update pipeline.admin_jobs set cursor = jsonb_build_object('last_done', v_last_done, 'last_change_at', v_last_at), progress = jsonb_build_object('done', v_done, 'total', v_total) || coalesce(jsonb_build_object('phase', v_phase), '{}'::jsonb), result = jsonb_build_object('done', v_done, 'total', v_total, 'errors', case when v_note like 'the request failed%' then 1 else 0 end) || coalesce(jsonb_build_object('note', v_note), '{}'::jsonb) || coalesce(v_extra, '{}'::jsonb), updated_at = now() where id = p_id;
  if v_fin and v_note is not null then insert into pipeline.admin_job_events(job_id, note) values (p_id, v_note); end if;
  return v_fin;
end $function$;

CREATE OR REPLACE FUNCTION public.svc_scholarship_read_record(p_scholarship_id uuid, p_read_status text, p_http_status integer, p_fetched_via text, p_final_url text, p_storage_path text, p_sha256 text, p_facts jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'scholarship', 'pipeline', 'security'
AS $function$
declare v_ev uuid; v_src uuid; v_pid uuid; v_url text; r jsonb; v_ai boolean := coalesce((select s.ai_admission from pipeline.scholarship_ai_settings s where s.id=1),false) and exists (select 1 from pipeline.scholarship_ai_models m where m.status='active');
begin
  if current_user<>'postgres' and coalesce(auth.role(),'')<>'service_role' then raise exception 'service_role required'; end if;
  select s.provider_id, p.url into v_pid, v_url from scholarship.scholarships s join pipeline.scholarship_pages p on p.scholarship_id=s.id where s.id=p_scholarship_id;
  if p_storage_path is not null and p_read_status='read' then
    v_src:=security.coverage_sweep_source(v_pid);
    -- unchanged page: reuse its evidence; changed page: next capture version, superseding the previous one
    select e.id into v_ev from pipeline.evidence_artifacts e where e.evidence_group_key='scholarship:'||p_scholarship_id and e.content_hash=p_sha256 order by e.capture_version desc limit 1;
    if v_ev is null then
      insert into pipeline.evidence_artifacts(entity_id,source_id,evidence_type,source_url,storage_path,content_hash,mime_type,metadata,capture_version,evidence_group_key,supersedes_evidence_id)
      select p_scholarship_id, v_src, 'scholarship_page', coalesce(p_final_url,v_url), p_storage_path, p_sha256, 'application/gzip',
             jsonb_build_object('worker','coverage-sweep scholarship_read','decision','Decision 139 sweep'),
             coalesce((select max(e.capture_version) from pipeline.evidence_artifacts e where e.evidence_group_key='scholarship:'||p_scholarship_id),0)+1,
             'scholarship:'||p_scholarship_id,
             (select e.id from pipeline.evidence_artifacts e where e.evidence_group_key='scholarship:'||p_scholarship_id order by e.capture_version desc limit 1)
      returning id into v_ev;
    end if;
  end if;
  update pipeline.scholarship_pages set requested_at=case when p_read_status='waiting_scraper' then requested_at end, read_status=p_read_status, http_status=p_http_status, fetched_via=p_fetched_via, final_url=p_final_url,
         read_at=now(), leased_until=null, evidence_id=case when p_read_status='read' then coalesce(v_ev,evidence_id) else evidence_id end,
         -- v2.15.249: with AI admission on, an AI-read page keeps its AI facts; the rule-read facts are kept under 'rules'
         facts=case when p_read_status='read' then case when v_ai and facts->>'extracted_by'='ai' then facts || jsonb_build_object('rules', p_facts) else coalesce(p_facts,facts) end else facts end,
         name_check=case when p_facts ? 'name_check' then p_facts->'name_check' else name_check end,
         -- 11 Oct 2026: pages are read through the scraper only; one waiting for the scraper (no credit or service) is tried again
         -- within the hour and does not use up its attempts; a blocked page is tried again in 2 days
         next_read_at=case when p_read_status='read' then now()+interval '90 days' when p_read_status='name_mismatch' then now()+interval '30 days'
                           when p_read_status='blocked' then now()+interval '2 days' when p_read_status='waiting_scraper' then now()+interval '1 hour' else now()+interval '6 hours' end,
         attempts=case when p_read_status='read' then 0 when p_read_status='waiting_scraper' then greatest(attempts-1,0) else attempts end
   where scholarship_id=p_scholarship_id;
  -- v2.15.249 (bugs 11/10-6): with AI admission on, the AI reads the page again and decides; the rules no longer withdraw or apply
  if p_read_status='read' and v_ai then
    insert into pipeline.scholarship_ai_queue(model_code,prompt_version,run_kind,scholarship_id,provider_id,url)
    select a.model_code,a.prompt_version,'reread',p_scholarship_id,v_pid,coalesce(p_final_url,v_url) from security.scholarship_ai_active_v1() a
     where not exists (select 1 from pipeline.scholarship_ai_queue q where q.scholarship_id=p_scholarship_id and q.state in ('queued','leased'));
    r:=jsonb_build_object('applied',false,'ai','queued');
  -- an admitted page that no longer meets the admission rules is withdrawn, not applied
  elsif p_read_status='read' and p_facts ? 'admission' and coalesce((p_facts->'admission'->>'admit')::boolean,true) is false
     and exists (select 1 from pipeline.scholarship_pages where scholarship_id=p_scholarship_id and url_source='admitted') then
    r:=security.scholarship_admission_withdraw_v1(p_scholarship_id, jsonb_build_object('reasons',p_facts->'admission'->'reasons','extractor',p_facts->>'extractor'));
  elsif p_read_status='read' then r:=security.scholarship_sweep_apply_v1(p_scholarship_id); end if;
  -- a discovered page that does not name the scholarship: the match is released (logged) so another page can be tried
  if p_read_status='name_mismatch' then
    update pipeline.scholarship_page_candidates c set match_basis='rejected_name_mismatch', matched_scholarship_id=null
      from pipeline.scholarship_pages sp where sp.scholarship_id=p_scholarship_id and sp.url_source='discovered' and c.id=sp.candidate_id;
    insert into pipeline.scholarship_sweep_changes(scholarship_id,field,before_value,after_value)
    select p_scholarship_id,'provider_page_rejected',jsonb_build_object('url',sp.url,'url_source',sp.url_source),p_facts->'name_check' from pipeline.scholarship_pages sp where sp.scholarship_id=p_scholarship_id;
  end if;
  return coalesce(r,jsonb_build_object('applied',false));
end $function$;

CREATE OR REPLACE FUNCTION public.svc_scholarship_candidate_record(p_candidate_id bigint, p_read_status text, p_http_status integer, p_fetched_via text, p_final_url text, p_storage_path text, p_sha256 text, p_facts jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'pipeline', 'security'
AS $function$
declare r jsonb; c pipeline.scholarship_page_candidates%rowtype; v_ev uuid; v_ai boolean := coalesce((select s.ai_admission from pipeline.scholarship_ai_settings s where s.id=1),false) and exists (select 1 from pipeline.scholarship_ai_models m where m.status='active');
begin
  if current_user<>'postgres' and coalesce(auth.role(),'')<>'service_role' then raise exception 'service_role required'; end if;
  if p_read_status='deferred' then -- out of time in this run: back to the queue unchanged
    update pipeline.scholarship_page_candidates set leased_until=null, attempts=greatest(0,attempts-1) where id=p_candidate_id;
    return jsonb_build_object('admitted',false,'deferred',true);
  end if;
  update pipeline.scholarship_page_candidates set read_status=p_read_status, http_status=p_http_status, fetched_via=p_fetched_via, final_url=p_final_url,
         read_at=now(), leased_until=null, storage_path=coalesce(p_storage_path,storage_path), content_hash=coalesce(p_sha256,content_hash), facts=coalesce(p_facts,facts),
         next_read_at=case when p_read_status in ('read','robots_disallowed','gone') then now()+interval '90 days' else now()+interval '6 hours' end,
         admit_status=case when not v_ai and p_read_status='read' and coalesce((p_facts->'admission'->>'admit')::boolean,false) is not true then 'rejected' else admit_status end,
         admit_reasons=case when not v_ai and p_read_status='read' and coalesce((p_facts->'admission'->>'admit')::boolean,false) is not true
                            then array(select jsonb_array_elements_text(coalesce(p_facts->'admission'->'reasons','[]'))) else admit_reasons end
   where id=p_candidate_id;
  if not v_ai and p_read_status='read' and coalesce((p_facts->'admission'->>'admit')::boolean,false) then r:=security.scholarship_admit_from_provider_page_v1(p_candidate_id); end if;
  -- v2.15.249 (bugs 11/10-6): with AI admission on, the AI decides every page read (its copy is kept), not the rules
  if v_ai and p_read_status in ('read','too_thin') and p_storage_path is not null then
    insert into pipeline.scholarship_ai_queue(model_code,prompt_version,run_kind,candidate_id,provider_id,url)
    select a.model_code,a.prompt_version,'admit',p_candidate_id,(select x.provider_id from pipeline.scholarship_page_candidates x where x.id=p_candidate_id),coalesce(p_final_url,(select x.url from pipeline.scholarship_page_candidates x where x.id=p_candidate_id))
      from security.scholarship_ai_active_v1() a where not exists (select 1 from pipeline.scholarship_ai_queue q where q.candidate_id=p_candidate_id and q.state in ('queued','leased'));
    r:=jsonb_build_object('admitted',false,'ai','queued');
  end if;
  select * into c from pipeline.scholarship_page_candidates where id=p_candidate_id;
  -- v2.15.248 (Platform Admin bugs 11/10-5, Fix 2): a stored page that did not become a scholarship is kept as evidence of the decision
  if c.storage_path is not null and c.evidence_id is null and coalesce(c.admit_status,'')<>'admitted' then
    insert into pipeline.evidence_artifacts(source_id,evidence_type,source_url,storage_path,content_hash,mime_type,metadata,capture_version,evidence_group_key)
    values (security.coverage_sweep_source(c.provider_id),'scholarship_candidate_page',coalesce(c.final_url,c.url),c.storage_path,c.content_hash,'application/gzip',
            jsonb_build_object('candidate_id',c.id,'provider_id',c.provider_id,'read_status',c.read_status,'decision',coalesce(c.admit_status,c.read_status),'reasons',to_jsonb(coalesce(c.admit_reasons,'{}'::text[])),'worker','coverage-sweep scholarship candidates'),1,'scholarship_candidate:'||c.id)
    returning id into v_ev;
    update pipeline.scholarship_page_candidates set evidence_id=v_ev where id=c.id;
  end if;
  -- (Fix 4) a page that lists scholarships is suggested as the provider's listing page, for a person to confirm
  if coalesce(c.admit_status,'')<>'admitted' and c.read_status in ('read','too_thin')
     and (coalesce(c.facts->>'h1','')||' '||coalesce(c.title,'')||' '||coalesce(c.facts->>'page_title','') ~* '(scholarships? (finder|search|list|directory)|grants and scholarships|find (a|your) scholarship|^\s*scholarships\s*$)'
          or coalesce(c.admit_reasons,'{}') && array['listing_page'] or c.url ~* '(scholarship-finder|/scholarships?/?$|/grants-scholarships/?$)') then
    insert into pipeline.scholarship_listing_pages(provider_id,url,url_norm,source,active,status)
    values (c.provider_id,coalesce(c.final_url,c.url),security.scholarship_url_norm(coalesce(c.final_url,c.url)),'suggested',false,'suggested')
    on conflict (provider_id,url_norm) do nothing;
  end if;
  return coalesce(r, jsonb_build_object('admitted',false));
end $function$;

CREATE OR REPLACE FUNCTION security.scholarship_audience_read_v1()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'scholarship', 'pipeline', 'security'
AS $function$
declare v_changed int := 0; v_read int := 0; v_counts jsonb;
  c_intl constant text := '\m(international students?|overseas students?|student visa|subclass 500|onshore|offshore|citizens? of (india|china|sri lanka|bangladesh|indonesia|malaysia|vietnam|nepal|pakistan|philippines|thailand|cambodia|kenya|nigeria|colombia|brazil|mexico|chile|peru|hong kong|singapore|japan|korea|taiwan|turkey|saudi|uae|iran|iraq|egypt|ghana|south africa|canada|usa|united states|uk|united kingdom|germany|france|italy|spain)|from (india|china|sri lanka|bangladesh|indonesia|malaysia|vietnam|nepal|pakistan|philippines|thailand|latin america|africa|asia|europe|the americas)|full[- ]fee[- ]paying international|global excellence|international (merit|excellence|academic))\M';
  c_dom constant text := '\m(domestic students?|australian citizens?|australian permanent residents?|permanent residen(t|cy) of australia|commonwealth supported|csp|hecs|fee[- ]help|home students?|new zealand citizens?|humanitarian visa|aboriginal|torres strait|indigenous|first nations)\M';
  c_dom_nz constant text := '\m(domestic students?|new zealand citizens?|new zealand permanent residents?|permanent residen(t|cy) of new zealand|australian citizens?|home students?|fees[- ]free|studylink|student allowance|maori|māori|pasifika)\M';
  c_dom_ca constant text := '\m(domestic students?|canadian citizens?|canadian permanent residents?|permanent residents? of canada|protected persons?|indigenous|first nations|métis|metis|inuit|osap|canada student (loans?|grants?)|residents? of (british columbia|alberta|ontario|quebec|québec|manitoba|saskatchewan|nova scotia|new brunswick))\M';
  c_both constant text := '\m(all students|domestic and international|international and domestic|regardless of (citizenship|residency|nationality)|open to all)\M';
begin
  with t as (
    select s.id, lower(coalesce(s.name,'') || ' ' || coalesce(s.description,'') || ' ' || coalesce((select string_agg(c.human_text, ' ') from scholarship.criteria c where c.scholarship_id = s.id), '')) txt,
           (select k.iso_alpha2 from catalogue.providers pp join ref.countries k on k.id = pp.country_id where pp.id = s.provider_id) cc
      from scholarship.scholarships s where s.lifecycle_status = 'active'),
  r as (
    select t.id, substring(t.txt from c_intl) p_intl, substring(t.txt from case t.cc when 'NZ' then c_dom_nz when 'CA' then c_dom_ca when 'AU' then c_dom else coalesce((select '\m(' || o.domestic_terms || ')\M' from scholarship.country_onboarding o where o.country_code = t.cc and coalesce(o.domestic_terms, '') <> ''), c_dom) end) p_dom, substring(t.txt from c_both) p_both from t),
  v as (
    select r.id, case when r.p_both is not null or (r.p_intl is not null and r.p_dom is not null) then 'international_and_domestic'
                      when r.p_intl is not null then 'international' when r.p_dom is not null then 'domestic' else 'not_stated' end audience,
           r.p_intl, r.p_dom, r.p_both from r),
  up as (
    insert into scholarship.audience_readings(scholarship_id, audience, phrase_international, phrase_domestic, phrase_both, reader_version, read_at)
    select v.id, v.audience, v.p_intl, v.p_dom, v.p_both, 'scholarship-audience-v1', now() from v
    on conflict (scholarship_id) do update set audience = excluded.audience, phrase_international = excluded.phrase_international, phrase_domestic = excluded.phrase_domestic, phrase_both = excluded.phrase_both, reader_version = excluded.reader_version, read_at = now()
    returning scholarship_id)
  select count(*) into v_read from up;
  update scholarship.scholarships s set audience = a.audience, updated_at = now() from scholarship.audience_readings a where a.scholarship_id = s.id and s.lifecycle_status = 'active' and s.audience is distinct from a.audience  and not exists (select 1 from pipeline.manual_locks k where k.entity = 'scholarship' and k.entity_id = s.id and k.field = 'audience')
    -- v2.15.249: a scholarship whose page the AI read keeps the audience the AI proved
    and not exists (select 1 from pipeline.scholarship_pages sp where sp.scholarship_id = s.id and sp.facts->>'extracted_by' = 'ai');
  get diagnostics v_changed = row_count;
  select jsonb_object_agg(x.audience, x.n) into v_counts from (select a.audience, count(*) n from scholarship.audience_readings a group by 1) x;
  if v_changed > 0 then
    insert into pipeline.admin_control_events(area, action, target, detail, actor)
    values ('scholarships', 'audience_read', 'Audience read from each scholarship''s wording', jsonb_build_object('read', v_read, 'changed', v_changed, 'counts', v_counts, 'decision', 'Decision 244'), '63ba56cb-48d4-4169-98c2-7c4d1f72925b');
  end if;
  return jsonb_build_object('read', v_read, 'changed', v_changed, 'counts', v_counts);
end $function$;

CREATE OR REPLACE FUNCTION security.scholarship_task_prepare_v1(p_kind text, p_args jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_prov uuid[]; v_sch uuid[]; v_course uuid; v_before uuid[] := '{}'; v_pages int := 0; v_cands int := 0; v_title text; v_scope text; v_missing text;
begin
  if p_kind = 'scholarship_provider_scan' then
    v_prov := array(select distinct x::uuid from jsonb_array_elements_text(coalesce(p_args->'provider_ids', '[]'::jsonb)) x);
    if coalesce(cardinality(v_prov), 0) = 0 then raise exception 'choose at least one provider'; end if;
    if cardinality(v_prov) > 50 then raise exception 'at most 50 providers in one task'; end if;
    select string_agg(coalesce(p.display_name, p.canonical_name), ', ') into v_missing from catalogue.providers p
     where p.id = any (v_prov) and coalesce(nullif(btrim(p.website), ''), (select nullif(btrim(d.website), '') from pipeline.coverage_provider_discovery d where d.provider_id = p.id and d.status = 'mapped')) is null;
    if v_missing is not null then raise exception 'no website is known for %; add it on the provider first', v_missing; end if;
  elsif p_kind = 'scholarship_course_check' then
    v_course := (p_args->>'course_id')::uuid;
    select array[c.provider_id] into v_prov from catalogue.courses c where c.id = v_course;
    if v_prov is null then raise exception 'unknown course'; end if;
    v_before := array(select m.scholarship_id from scholarship.course_mappings m where m.course_id = v_course and m.mapping_state = 'mapped');
  elsif p_kind = 'scholarship_reread' then
    v_sch := array(select distinct x::uuid from jsonb_array_elements_text(coalesce(p_args->'scholarship_ids', '[]'::jsonb)) x);
    if coalesce(cardinality(v_sch), 0) = 0 then raise exception 'choose a scholarship'; end if;
    v_prov := array(select distinct s.provider_id from scholarship.scholarships s where s.id = any (v_sch));
    if not exists (select 1 from pipeline.scholarship_pages p where p.scholarship_id = any (v_sch)) then raise exception 'this scholarship has no provider page to read'; end if;
  else
    raise exception 'unknown scholarship task';
  end if;
  if exists (select 1 from security.provider_hidden_v1 h where h.provider_id = any (v_prov)) then
    raise exception 'a chosen provider is unpublished or archived; publish or restore it first';
  end if;
  if p_kind = 'scholarship_provider_scan' then
    insert into pipeline.scholarship_discovery_providers(provider_id, website, priority, reason, status, attempts, updated_at)
    select p.id, coalesce(nullif(btrim(p.website), ''), (select nullif(btrim(d.website), '') from pipeline.coverage_provider_discovery d where d.provider_id = p.id and d.status = 'mapped')), 0, 'on_demand', 'pending', 0, now()
      from catalogue.providers p where p.id = any (v_prov)
    on conflict (provider_id) do update set status = 'pending', priority = 0, attempts = 0, leased_until = null, reason = 'on_demand', updated_at = now();
    update pipeline.scholarship_page_candidates c set next_read_at = now(), attempts = 0, leased_until = null, requested_at = now()
     where c.provider_id = any (v_prov) and c.admit_status is null and c.matched_scholarship_id is null and c.source <> 'register'
       and (c.read_status is null or c.read_status in ('blocked', 'fetch_failed', 'too_thin', 'not_html', 'robots_disallowed', 'scrape_failed', 'waiting_scraper', 'deferred'));
    get diagnostics v_cands = row_count;
    -- v2.15.249 (bugs 11/10-6): with AI admission on, refused pages of the chosen providers are read again by the AI
    if exists (select 1 from pipeline.scholarship_ai_settings s where s.id = 1 and s.ai_admission) then v_cands := v_cands + security.scholarship_ai_enqueue_v1('admit', v_prov, null, false); end if;
  end if;
  update pipeline.scholarship_pages p set requested_at = now(), next_read_at = now(), attempts = 0, leased_until = null
    from scholarship.scholarships s
   where s.id = p.scholarship_id and s.lifecycle_status = 'active'
     and (case when v_sch is not null then s.id = any (v_sch) else s.provider_id = any (v_prov) end);
  get diagnostics v_pages = row_count;
  if v_pages = 0 and p_kind = 'scholarship_reread' then raise exception 'this scholarship is not active, so there is no page to read; restore it first'; end if;
  if v_pages = 0 and p_kind = 'scholarship_course_check' then raise exception 'this course''s provider has no active scholarship pages yet; use Find scholarships now on the provider'; end if;
  if v_sch is null then update pipeline.scholarship_listing_pages set next_read_at = now() where active and provider_id = any (v_prov); end if;
  v_title := case p_kind
    when 'scholarship_provider_scan' then 'Find scholarships now: ' || case when cardinality(v_prov) = 1 then (select coalesce(p.display_name, p.canonical_name) from catalogue.providers p where p.id = v_prov[1]) else cardinality(v_prov) || ' providers' end
    when 'scholarship_course_check' then 'Check scholarships for ' || (select coalesce(c.display_title, c.canonical_title) || coalesce(' (' || c.course_code || ')', '') from catalogue.courses c where c.id = v_course)
    else 'Read again now: ' || case when cardinality(v_sch) = 1 then (select s.name from scholarship.scholarships s where s.id = v_sch[1]) else cardinality(v_sch) || ' scholarships' end end;
  v_scope := case p_kind
    when 'scholarship_provider_scan' then case when cardinality(v_prov) = 1 then v_prov[1]::text else 'providers:' || md5(array_to_string(array(select x::text from unnest(v_prov) x order by 1), ',')) end
    when 'scholarship_course_check' then v_course::text
    else case when cardinality(v_sch) = 1 then v_sch[1]::text else 'scholarships:' || md5(array_to_string(array(select x::text from unnest(v_sch) x order by 1), ',')) end end;
  return jsonb_build_object('providers', to_jsonb(v_prov), 'scholarship_ids', to_jsonb(coalesce(v_sch, '{}'::uuid[])), 'course_id', v_course, 'before', to_jsonb(v_before),
                            'pages', v_pages, 'candidates', v_cands, 'title', v_title, 'scope', v_scope);
end $function$;

CREATE OR REPLACE FUNCTION security.scholarship_listing_match_v1(p_provider_id uuid)
 RETURNS TABLE(listing_id bigint, item_name text, item_url text, scholarship_id uuid, matched_by text)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  with items as (
    select distinct on (lower(btrim(e->>'name'))) l.id listing_id, btrim(e->>'name') item_name, nullif(btrim(e->>'url'), '') item_url
      from pipeline.scholarship_listing_pages l, jsonb_array_elements(l.items) e
     where l.provider_id = p_provider_id and l.active and l.source <> 'suggested' and coalesce(btrim(e->>'name'), '') <> ''
     order by lower(btrim(e->>'name')), (nullif(btrim(e->>'url'), '') is null), l.id),
  recs as (
    select s.id, s.name, s.publication_status, security.scholarship_series_key_v1(s.name) k,
           array_remove(array[security.scholarship_url_norm(s.source_url)]
             || array(select security.scholarship_url_norm(i.identifier_value) from scholarship.identifiers i where i.scholarship_id = s.id and i.scheme = 'first_party_detail_url')
             || array(select security.scholarship_url_norm(coalesce(sp.final_url, sp.url)) from pipeline.scholarship_pages sp where sp.scholarship_id = s.id)
             || array(select security.scholarship_url_norm(sp.url) from pipeline.scholarship_pages sp where sp.scholarship_id = s.id), null) urls
      from scholarship.scholarships s where s.provider_id = p_provider_id and s.lifecycle_status = 'active')
  select it.listing_id, it.item_name, it.item_url, m.id, m.how
    from items it
    cross join lateral (select security.scholarship_series_key_v1(it.item_name) ik, security.scholarship_url_norm(it.item_url) iu) x
    left join lateral (
      select r.id, case when x.iu is not null and x.iu = any(r.urls) then 'page' when r.k = x.ik then 'name' else 'similar name' end how
        from recs r
       -- v2.15.249 (Fix 5): a link match also needs the names to agree (VU's Medibank item linked to the Block Model page)
       where (x.iu is not null and x.iu = any(r.urls) and (r.k = x.ik or strpos(r.k, x.ik) > 0 or strpos(x.ik, r.k) > 0
              or (select count(*) from unnest(regexp_split_to_array(x.ik, '[^a-z0-9]+')) w where length(w) > 3 and w not in ('scholarship', 'scholarships', 'university', 'international') and w = any(regexp_split_to_array(r.k, '[^a-z0-9]+'))) >= 2))
          or r.k = x.ik
          or (length(x.ik) >= 15 and length(r.k) >= 15 and (strpos(r.k, x.ik) > 0 or strpos(x.ik, r.k) > 0))
       order by (x.iu is not null and x.iu = any(r.urls)) desc, (r.k = x.ik) desc, (r.publication_status = 'published') desc, r.id
       limit 1) m on true
$function$;

CREATE OR REPLACE FUNCTION public.admin_jobs(p_action text, p_args jsonb DEFAULT '{}'::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_rank int := security.current_role_rank(); v_reason text := btrim(coalesce(p_args->>'reason', '')); v_id uuid; v_kind text; v_ids uuid[]; v_j pipeline.admin_jobs%rowtype;
        v_q pipeline.admin_jobs%rowtype; v_fields text[]; v_title text; v_n int; v_res jsonb;
begin
  if auth.uid() is null or coalesce(v_rank, 0) < 4 then raise exception 'Operator or above required' using errcode = '42501'; end if;
  if p_action = 'read' then
    return jsonb_build_object(
      'jobs', coalesce((select jsonb_agg(to_jsonb(j) - 'args' || jsonb_build_object('args', j.args - 'providers', 'providers', coalesce(jsonb_array_length(j.args->'providers'), 0), 'requested_by_name', (select coalesce(u.email, j.requested_by::text) from auth.users u where u.id = j.requested_by)) order by j.created_at desc)
                         from (select * from pipeline.admin_jobs where state in ('queued', 'running', 'paused') or (p_args->>'all')::boolean order by created_at desc limit greatest(1, least(coalesce((p_args->>'limit')::int, 50), 200))) j), '[]'::jsonb),
      'match', case when p_args ? 'kind' then (select to_jsonb(j) - 'args' || jsonb_build_object('providers', coalesce(jsonb_array_length(j.args->'providers'), 0)) from pipeline.admin_jobs j
                      where j.kind = p_args->>'kind' and j.scope is not distinct from nullif(p_args->>'scope', '') and j.state in ('queued', 'running', 'paused') order by j.created_at desc limit 1) end,
      'job', case when p_args ? 'id' then (select to_jsonb(j) - 'args' || jsonb_build_object('args', j.args - 'providers', 'providers', coalesce(jsonb_array_length(j.args->'providers'), 0),
                    'requested_by_name', (select coalesce(u.email, j.requested_by::text) from auth.users u where u.id = j.requested_by),
                    'events', coalesce((select jsonb_agg(jsonb_build_object('at', e.at, 'note', e.note, 'detail', e.detail) order by e.id desc) from (select * from pipeline.admin_job_events e where e.job_id = j.id order by e.id desc limit 200) e), '[]'::jsonb),
                    'qualifications', coalesce((select jsonb_agg(jsonb_build_object('provider_id', q.provider_id, 'name', coalesce(p.display_name, p.canonical_name), 'country', security.coverage_country(p.id), 'pages_read', q.pages_read, 'fields', q.fields, 'passing', q.passing, 'adapter', (select case when not u.enabled then 'off' when u.admit then 'admitting' else 'testing' end from pipeline.uni_adapters u where u.provider_id = q.provider_id), 'admitted', (select to_jsonb(u.admit_fields) from pipeline.uni_adapters u where u.provider_id = q.provider_id and u.admit)) order by coalesce(p.display_name, p.canonical_name))
                                       from pipeline.adapter_qualifications q join catalogue.providers p on p.id = q.provider_id where (q.job_id = coalesce(j.args->>'qualification_job_id', j.id::text)::uuid or q.job_id::text = j.args->'qual_jobs'->>q.provider_id::text)), '[]'::jsonb))
                  from pipeline.admin_jobs j where j.id = (p_args->>'id')::uuid) end,
      'settings', jsonb_build_object('min_read_share', coalesce(security.firecrawl_setting('eval_field_share'), '0.5'::jsonb), 'min_agree_share', coalesce(security.firecrawl_setting('qualify_agree_share'), '0.9'::jsonb)),
      'countries', coalesce((select jsonb_agg(jsonb_build_object('code', k.iso_alpha2, 'name', k.name, 'adapters', n.n) order by k.name) from ref.countries k join (select p.country_id, count(*) n from pipeline.uni_adapters u join catalogue.providers p on p.id = u.provider_id group by p.country_id) n on n.country_id = k.id), '[]'::jsonb),
      'states', coalesce((select jsonb_agg(jsonb_build_object('code', s.code, 'name', s.name, 'country', k.iso_alpha2, 'adapters', n.n) order by s.code) from ref.subdivisions s join ref.countries k on k.id = s.country_id join (select p.subdivision_id, count(*) n from pipeline.uni_adapters u join catalogue.providers p on p.id = u.provider_id group by p.subdivision_id) n on n.subdivision_id = s.id), '[]'::jsonb),
      'can_admit', v_rank >= 6,
      -- 11 Oct 2026: job kinds from the registry, and (Task manager) everything using resources right now
      'kinds', (select coalesce(jsonb_object_agg(k.kind, jsonb_build_object('label', k.label, 'can_pause', k.can_pause)), '{}'::jsonb) from pipeline.admin_job_kinds k),
      'running_now', case when coalesce((p_args->>'running')::boolean, false) then security.admin_running_now_v1() end);
  end if;
  -- v2.15.247 (bugs 11/10-4): starting a task needs no reason; it is logged as started from the screen named in p_args.from.
  -- Admit the passing fields (writes data in bulk), pause, resume and cancel still need one.
  if length(v_reason) < 4 then
    if p_action = 'start' and coalesce(p_args->>'kind', '') <> 'admit_qualified' then
      v_reason := 'Started from ' || coalesce(nullif(btrim(p_args->>'from'), ''), 'the app');
    else
      raise exception 'give a reason (kept in the log)';
    end if;
  end if;
  if p_action = 'start' then
    v_kind := p_args->>'kind';
    if v_kind = 'qualify_adapters' then
      if v_rank < 5 then raise exception 'Operator (adapters) or above required' using errcode = '42501'; end if;
      v_ids := security.admin_jobs_resolve_adapters_v1(coalesce(p_args->'args', '{}'::jsonb));
      if coalesce(array_length(v_ids, 1), 0) = 0 then raise exception 'no adapters match that choice'; end if;
      v_title := 'Qualify ' || array_length(v_ids, 1) || ' adapter(s)' || coalesce(' in ' || nullif(btrim(coalesce(p_args->'args'->>'state', p_args->'args'->>'country', '')), ''), '');
      insert into pipeline.admin_jobs(kind, lane, title, args, progress, requested_by, reason, scope)
        values (v_kind, 'adapters', v_title, coalesce(p_args->'args', '{}'::jsonb) || jsonb_build_object('providers', to_jsonb(v_ids)), jsonb_build_object('done', 0, 'total', array_length(v_ids, 1)), auth.uid(), v_reason,
                coalesce(nullif(p_args->'args'->>'scope', ''), nullif(p_args->'args'->>'state', ''), nullif(p_args->'args'->>'country', '')))
        returning * into v_j;
    elsif v_kind = 'admit_qualified' and not (coalesce(p_args->'args', '{}'::jsonb) ? 'qualification_job_id') then
      -- 6 Oct (Layer 2 › Adapters): admit the ticked adapters, each from its own latest finished Qualify
      if v_rank < 6 then raise exception 'Platform Admin required' using errcode = '42501'; end if;
      v_fields := case when p_args->'args' ? 'fields' then array(select x from jsonb_array_elements_text(p_args->'args'->'fields') x where x in ('intakes', 'english', 'fee', 'delivery')) else array['intakes', 'english', 'fee', 'delivery'] end;
      select coalesce(jsonb_object_agg(z.provider_id, z.job_id), '{}'::jsonb), coalesce(array_agg(z.provider_id order by z.provider_id), '{}') into v_res, v_ids
        from (select distinct on (x.provider_id) x.provider_id, x.job_id, x.passing from pipeline.adapter_qualifications x join pipeline.admin_jobs qj on qj.id = x.job_id and qj.kind = 'qualify_adapters' and qj.state = 'done'
               where x.provider_id = any (array(select (y)::uuid from jsonb_array_elements_text(coalesce(p_args->'args'->'provider_ids', '[]'::jsonb)) y))
               order by x.provider_id, x.measured_at desc) z
       where z.passing && v_fields and exists (select 1 from pipeline.uni_adapters u where u.provider_id = z.provider_id and u.enabled);
      if coalesce(array_length(v_ids, 1), 0) = 0 then raise exception 'no ticked adapter passed for those fields in its latest Qualify (or it is switched off)'; end if;
      v_title := 'Admit the passing fields of ' || case when array_length(v_ids, 1) = 1 then coalesce((select coalesce(p.display_name, p.canonical_name) from catalogue.providers p where p.id = v_ids[1]), '1 adapter') else array_length(v_ids, 1) || ' adapters' end || ' (latest Qualify of each)';
      insert into pipeline.admin_jobs(kind, lane, title, args, progress, requested_by, reason, scope)
        values (v_kind, 'adapters', v_title, jsonb_build_object('qual_jobs', v_res, 'fields', to_jsonb(v_fields), 'providers', to_jsonb(v_ids)), jsonb_build_object('done', 0, 'total', array_length(v_ids, 1)), auth.uid(), v_reason,
                coalesce(nullif(p_args->'args'->>'scope', ''), case when array_length(v_ids, 1) = 1 then v_ids[1]::text else 'adapters' end))
        returning * into v_j;
      v_res := null;
    elsif v_kind = 'admit_qualified' then
      if v_rank < 6 then raise exception 'Platform Admin required' using errcode = '42501'; end if;
      select * into v_q from pipeline.admin_jobs q where q.id = (p_args->'args'->>'qualification_job_id')::uuid;
      if v_q.id is null or v_q.kind <> 'qualify_adapters' or v_q.state <> 'done' then raise exception 'choose a finished Qualify job'; end if;
      v_fields := case when p_args->'args' ? 'fields' then array(select x from jsonb_array_elements_text(p_args->'args'->'fields') x where x in ('intakes', 'english', 'fee', 'delivery')) else array['intakes', 'english', 'fee', 'delivery'] end;
      v_ids := array(select q.provider_id from pipeline.adapter_qualifications q where q.job_id = v_q.id and q.passing && v_fields
                      and exists (select 1 from pipeline.uni_adapters u where u.provider_id = q.provider_id and u.enabled)
                      order by q.provider_id);
      if coalesce(array_length(v_ids, 1), 0) = 0 then raise exception 'no adapter passed for those fields'; end if;
      v_title := 'Admit the passing fields of ' || array_length(v_ids, 1) || ' adapter(s) (from ' || v_q.title || ')';
      insert into pipeline.admin_jobs(kind, lane, title, args, progress, requested_by, reason, scope)
        values (v_kind, 'adapters', v_title, jsonb_build_object('qualification_job_id', v_q.id, 'fields', to_jsonb(v_fields), 'providers', to_jsonb(v_ids)), jsonb_build_object('done', 0, 'total', array_length(v_ids, 1)), auth.uid(), v_reason, v_q.id::text)
        returning * into v_j;
    elsif v_kind = 'reread_pages' then
      v_res := public.admin_university_reread('queue', coalesce(p_args->'args', '{}'::jsonb) || jsonb_build_object('reason', v_reason));
      v_ids := array(select distinct (x)::uuid from jsonb_array_elements_text(coalesce(p_args->'args'->'provider_ids', '[]'::jsonb)) x);
      v_title := 'Read pages again: ' || case when cardinality(v_ids) = 1 then coalesce((select coalesce(p.display_name, p.canonical_name) from catalogue.providers p where p.id = v_ids[1]), '1 university') else cardinality(v_ids) || ' universities' end
                 || case when coalesce(p_args->'args'->>'which', 'all') = 'not_confirmed' then ' (pages not confirmed)' else '' end || case when coalesce((p_args->'args'->>'central')::boolean, false) then ' with central pages' else '' end;
      insert into pipeline.admin_jobs(kind, lane, title, args, progress, requested_by, reason, scope)
        values (v_kind, 'reads', v_title, jsonb_build_object('request_id', v_res->>'request_id', 'provider_ids', to_jsonb(v_ids), 'which', coalesce(p_args->'args'->>'which', 'all'), 'central', coalesce((p_args->'args'->>'central')::boolean, false)),
                jsonb_build_object('done', 0, 'total', cardinality(v_ids), 'phase', 'sending'), auth.uid(), v_reason, case when cardinality(v_ids) = 1 then v_ids[1]::text else coalesce(nullif(p_args->'args'->>'scope', ''), 'universities') end)
        returning * into v_j;
    elsif v_kind = 'firecrawl_run' then
      v_res := public.admin_firecrawl_write('start', jsonb_build_object('use_case', p_args->'args'->>'use_case', 'reason', v_reason));
      v_title := 'Firecrawl run: ' || replace(coalesce(p_args->'args'->>'use_case', ''), '_', ' ') || ' (' || coalesce(v_res->>'items', '0') || ' pages, cap ' || coalesce(v_res->>'credits_cap', '-') || ' credits)';
      insert into pipeline.admin_jobs(kind, lane, title, args, progress, requested_by, reason, scope)
        values (v_kind, 'firecrawl', v_title, jsonb_build_object('run_id', v_res->>'run_id', 'use_case', p_args->'args'->>'use_case', 'items', (v_res->>'items')::int), jsonb_build_object('done', 0, 'total', coalesce((v_res->>'items')::int, 0)), auth.uid(), v_reason, p_args->'args'->>'use_case')
        returning * into v_j;
      v_ids := '{}';
    elsif v_kind = 'adapter_apply' then
      v_res := public.admin_uni_adapter_write('apply', jsonb_build_object('provider_id', p_args->'args'->>'provider_id', 'reason', v_reason));
      v_title := 'Apply the adapter: ' || coalesce((select coalesce(p.display_name, p.canonical_name) from catalogue.providers p where p.id = (p_args->'args'->>'provider_id')::uuid), '') || ' (' || coalesce(v_res->>'pages_read_again', '0') || ' pages)';
      insert into pipeline.admin_jobs(kind, lane, title, args, progress, requested_by, reason, scope)
        values (v_kind, 'reads', v_title, jsonb_build_object('provider_id', p_args->'args'->>'provider_id', 'pages', coalesce((v_res->>'pages_read_again')::int, 0), 'providers', jsonb_build_array(p_args->'args'->>'provider_id')), jsonb_build_object('done', 0, 'total', coalesce((v_res->>'pages_read_again')::int, 0)), auth.uid(), v_reason, p_args->'args'->>'provider_id')
        returning * into v_j;
      v_ids := array[(p_args->'args'->>'provider_id')::uuid];
    elsif v_kind = 'central_page_read' then
      v_res := public.admin_provider_central_page(coalesce(nullif(p_args->'args'->>'action', ''), 'add'), jsonb_build_object('provider_id', p_args->'args'->>'provider_id', 'kind', p_args->'args'->>'kind', 'url', p_args->'args'->>'url', 'title', p_args->'args'->>'title', 'reason', v_reason));
      v_title := 'Read a central page: ' || replace(coalesce(p_args->'args'->>'kind', ''), '_', ' ') || ' for ' || coalesce((select coalesce(p.display_name, p.canonical_name) from catalogue.providers p where p.id = (p_args->'args'->>'provider_id')::uuid), '');
      insert into pipeline.admin_jobs(kind, lane, title, args, progress, requested_by, reason, scope)
        values (v_kind, 'reads', v_title, jsonb_build_object('source_id', v_res->>'source_id', 'provider_id', p_args->'args'->>'provider_id', 'kind', p_args->'args'->>'kind', 'url', p_args->'args'->>'url', 'providers', jsonb_build_array(p_args->'args'->>'provider_id')), jsonb_build_object('done', 0, 'total', 1), auth.uid(), v_reason, p_args->'args'->>'provider_id')
        returning * into v_j;
      v_ids := array[(p_args->'args'->>'provider_id')::uuid];
    -- 11 Oct 2026 (CF-247, Platform Admin): on-demand scholarship tasks (provider, several providers, course, scholarship)
    elsif v_kind in ('scholarship_provider_scan', 'scholarship_course_check', 'scholarship_reread') then
      v_res := security.scholarship_task_prepare_v1(v_kind, coalesce(p_args->'args', '{}'::jsonb));
      if exists (select 1 from pipeline.admin_jobs j where j.kind = v_kind and j.scope is not distinct from (v_res->>'scope') and j.state in ('queued', 'running', 'paused')) then
        raise exception 'this check is already running; see Scheduled jobs › Task manager';
      end if;
      insert into pipeline.admin_jobs(kind, lane, title, args, progress, requested_by, reason, scope)
        values (v_kind, 'scholarships:' || v_kind || ':' || coalesce(v_res->>'scope', ''), v_res->>'title', v_res - 'title' - 'scope', jsonb_build_object('done', 0, 'total', coalesce((v_res->>'pages')::int, 0)), auth.uid(), v_reason, v_res->>'scope')
        returning * into v_j;
      v_ids := array(select x::uuid from jsonb_array_elements_text(v_res->'providers') x);
      perform security.scholarship_task_fire_v1(case when v_kind = 'scholarship_provider_scan' then array['discover', 'read'] else array['read'] end);
    -- 11 Oct 2026 (CF-247, Platform Admin bugs 11/10-2): Fill in a provider from its website; Find course pages with Firecrawl
    elsif v_kind in ('provider_fill', 'course_page_find') then
      v_res := security.provider_task_prepare_v1(v_kind, coalesce(p_args->'args', '{}'::jsonb));
      if exists (select 1 from pipeline.admin_jobs j where j.kind = v_kind and j.scope is not distinct from (v_res->>'scope') and j.state in ('queued', 'running', 'paused')) then
        raise exception 'this task is already running; see Scheduled jobs › Task manager';
      end if;
      insert into pipeline.admin_jobs(kind, lane, title, args, progress, requested_by, reason, scope)
        values (v_kind, 'providers:' || v_kind || ':' || coalesce(v_res->>'scope', ''), v_res->>'title', v_res - 'title' - 'scope',
                jsonb_build_object('done', 0, 'total', case when v_kind = 'provider_fill' then 3 else jsonb_array_length(v_res->'course_ids') end), auth.uid(), v_reason, v_res->>'scope')
        returning * into v_j;
      v_ids := array[(v_res->>'provider_id')::uuid];
      if v_kind = 'provider_fill' then
        perform security.provider_task_fire_v1(case when coalesce((v_res->>'had_website')::boolean, false) then 'contact_page' else 'find_site' end);
      end if;
    elsif v_kind in ('scholarship_ai_qualify', 'scholarship_ai_backfill') then
      raise exception 'start this from Scholarships › Extraction';
    else
      raise exception 'unknown job kind';
    end if;
    insert into pipeline.admin_job_events(job_id, note, detail) values (v_j.id, 'queued by ' || coalesce((select u.email from auth.users u where u.id = auth.uid()), auth.uid()::text), jsonb_build_object('reason', v_reason));
    insert into pipeline.admin_control_events(area, action, target, detail, actor) values ('jobs', 'job_start', v_j.id::text, jsonb_build_object('kind', v_kind, 'title', v_j.title, 'providers', array_length(v_ids, 1), 'reason', v_reason), auth.uid());
    return jsonb_build_object('ok', true, 'id', v_j.id, 'title', v_j.title, 'providers', array_length(v_ids, 1));
  end if;
  v_id := (p_args->>'id')::uuid;
  select * into v_j from pipeline.admin_jobs j where j.id = v_id;
  if v_j.id is null then raise exception 'unknown job'; end if;
  if v_rank < 5 and v_j.requested_by <> auth.uid() then raise exception 'only the person who started it, or an Operator, may change this job' using errcode = '42501'; end if;
  if p_action = 'cancel' then
    if v_j.state in ('done', 'failed', 'cancelled') then raise exception 'the job has already finished'; end if;
    if v_j.kind = 'reread_pages' then
      update pipeline.university_reread_requests set status = 'cancelled', finished_at = now() where id = (v_j.args->>'request_id')::uuid and status in ('waiting', 'sending');
    elsif v_j.kind = 'firecrawl_run' then
      perform public.admin_firecrawl_write('stop', jsonb_build_object('run_id', v_j.args->>'run_id', 'reason', v_reason));
    elsif v_j.kind in ('scholarship_provider_scan', 'scholarship_course_check', 'scholarship_reread') then
      -- the pages lose their place at the front of the queue; they are read again in their normal turn
      update pipeline.scholarship_pages p set requested_at = null from scholarship.scholarships s
       where s.id = p.scholarship_id and p.requested_at is not null
         and (s.provider_id = any (array(select x::uuid from jsonb_array_elements_text(coalesce(v_j.args->'providers', '[]'::jsonb)) x))
              or s.id = any (array(select x::uuid from jsonb_array_elements_text(coalesce(v_j.args->'scholarship_ids', '[]'::jsonb)) x)));
      update pipeline.scholarship_page_candidates c set requested_at = null
       where c.requested_at is not null and c.provider_id = any (array(select x::uuid from jsonb_array_elements_text(coalesce(v_j.args->'providers', '[]'::jsonb)) x));
    elsif v_j.kind = 'course_page_find' then
      -- the courses lose their place at the front of the course page search; they are searched in their normal turn
      update pipeline.course_link_search set requested_at = null
       where requested_at is not null and course_id = any (array(select x::uuid from jsonb_array_elements_text(coalesce(v_j.args->'course_ids', '[]'::jsonb)) x));
    elsif v_j.kind = 'provider_fill' then
      update pipeline.coverage_provider_discovery set requested_at = null where provider_id = (v_j.args->>'provider_id')::uuid and requested_at is not null;
      update pipeline.provider_central_search set requested_at = null where provider_id = (v_j.args->>'provider_id')::uuid and requested_at is not null;
    end if;
    if v_j.state in ('queued', 'paused') then
      update pipeline.admin_jobs set state = 'cancelled', finished_at = now(), updated_at = now(), cancel_requested = true where id = v_id;
      perform security.admin_job_close_v1(v_id);
    else
      update pipeline.admin_jobs set cancel_requested = true, updated_at = now() where id = v_id;
    end if;
  elsif p_action = 'pause' then
    if v_j.state not in ('queued', 'running') then raise exception 'only a queued or running job can be paused'; end if;
    if not coalesce((select k.can_pause from pipeline.admin_job_kinds k where k.kind = v_j.kind), false) then raise exception 'this task cannot be paused, only cancelled'; end if;
    if v_j.kind = 'firecrawl_run' then perform public.admin_firecrawl_write('stop', jsonb_build_object('run_id', v_j.args->>'run_id', 'reason', v_reason)); end if;
    if v_j.state = 'queued' then
      update pipeline.admin_jobs set state = 'paused', updated_at = now() where id = v_id;
    else
      update pipeline.admin_jobs set pause_requested = true, updated_at = now() where id = v_id;
    end if;
  elsif p_action = 'resume' then
    if v_j.state <> 'paused' then raise exception 'only a paused job can be resumed'; end if;
    if v_j.kind = 'firecrawl_run' then perform public.admin_firecrawl_write('continue', jsonb_build_object('run_id', v_j.args->>'run_id', 'reason', v_reason)); end if;
    update pipeline.admin_jobs set state = 'queued', pause_requested = false, updated_at = now() where id = v_id;
  else
    raise exception 'unknown action';
  end if;
  insert into pipeline.admin_job_events(job_id, note, detail) values (v_id, p_action || ' requested by ' || coalesce((select u.email from auth.users u where u.id = auth.uid()), auth.uid()::text), jsonb_build_object('reason', v_reason));
  insert into pipeline.admin_control_events(area, action, target, detail, actor) values ('jobs', 'job_' || p_action, v_id::text, jsonb_build_object('title', v_j.title, 'reason', v_reason), auth.uid());
  return jsonb_build_object('ok', true, 'id', v_id);
end $function$;

-- The hand-checked sample the models are qualified on (a Platform Admin can add, correct or switch off any page on Scholarships › Extraction)
insert into pipeline.scholarship_ai_sample(url, scholarship_id, provider_id, expected, label_source)
select x.url, x.id, x.provider_id, jsonb_build_object('is_scholarship', true, 'single', true, 'international', true, 'offered', true), 'Published after a person''s hand-check (Decision 139)'
  from (select distinct on (s.provider_id) s.id, s.provider_id, coalesce(sp.final_url, sp.url) url
          from scholarship.scholarships s join pipeline.scholarship_pages sp on sp.scholarship_id = s.id
         where s.lifecycle_status = 'active' and s.publication_status = 'published' and sp.evidence_id is not null
           and exists (select 1 from pipeline.scholarship_publication_batches b where s.id = any (b.scholarship_ids) and b.kind = 'publish' and b.approval_ref not like 'auto-publish%')
           and not exists (select 1 from pipeline.scholarship_publication_holds h where h.scholarship_id = s.id and h.released_at is null)
         order by s.provider_id, s.updated_at desc) x
 order by md5(x.id::text) limit 30
on conflict (url) do nothing;
insert into pipeline.scholarship_ai_sample(url, candidate_id, provider_id, expected, label_source, note)
select coalesce(c.final_url, c.url), c.id, c.provider_id, jsonb_build_object('is_scholarship', true, 'single', true, 'international', true, 'offered', true),
       'Platform Admin 11 Oct 2026 22:00', 'VU STEM Accommodation: open while places last; free accommodation valued at $15,548 (UG) and $8,502 (PG)'
  from pipeline.scholarship_page_candidates c where c.id = 7997
on conflict (url) do nothing;
insert into pipeline.scholarship_ai_sample(url, scholarship_id, provider_id, expected, label_source, note)
select coalesce(sp.final_url, sp.url, s.source_url), s.id, s.provider_id, jsonb_build_object('is_scholarship', false), 'Platform Admin 11 Oct 2026 22:00', 'James Cook prize or award, not a scholarship'
  from scholarship.scholarships s join pipeline.scholarship_publication_holds h on h.scholarship_id = s.id and h.released_at is null and h.reason like 'Prize or award%'
  left join pipeline.scholarship_pages sp on sp.scholarship_id = s.id
on conflict (url) do nothing;
insert into pipeline.scholarship_ai_sample(url, scholarship_id, provider_id, expected, label_source, note)
select coalesce(sp.final_url, sp.url, s.source_url), s.id, s.provider_id, jsonb_build_object('is_scholarship', true, 'single', false), 'Review of the 27-university run, 11 Oct 2026', 'Macquarie list page admitted as one scholarship named "Scholarships"'
  from scholarship.scholarships s left join pipeline.scholarship_pages sp on sp.scholarship_id = s.id
 where s.provider_id = '188103a5-1aba-4f99-bd3e-0416659086d3' and s.name = 'Scholarships' and s.lifecycle_status = 'active'
on conflict (url) do nothing;
insert into pipeline.scholarship_ai_sample(url, candidate_id, provider_id, expected, label_source, note)
select coalesce(c.final_url, c.url), c.id, c.provider_id, jsonb_build_object('is_scholarship', false), 'Review of the 4-university run, 11 Oct 2026', 'Charles Darwin short-course page'
  from pipeline.scholarship_page_candidates c where c.url like 'https://www.cdu.edu.au/study/course/zscv%' order by c.id limit 4
on conflict (url) do nothing;

do $post$
declare v_expected jsonb := '{"security.admin_job_slice_v1(uuid,integer)": "07273bfdec334c015ac67c27ffaf72ac", "security.admin_job_watch_v1(uuid)": "33f0a68bffa354b09fc6d3576b088846", "public.svc_scholarship_read_record(uuid,text,integer,text,text,text,text,jsonb)": "11538dcba17d0c66943194ba9b490589", "public.svc_scholarship_candidate_record(bigint,text,integer,text,text,text,text,jsonb)": "f26d5fd830b74d21dd172a65715fe139", "security.scholarship_audience_read_v1()": "0251fe1ac6594affc3166631516010e9", "security.scholarship_task_prepare_v1(text,jsonb)": "afef1848cfb8fde120b2b07a5d44cc97", "security.scholarship_listing_match_v1(uuid)": "2725ab7c6bde402d50083dbe9fbec90a", "public.admin_jobs(text,jsonb)": "e5c8f8447e33aacc176abc3a72a38e8a"}'::jsonb;
  v_sig text;
begin
  for v_sig in select jsonb_object_keys(v_expected) loop
    if md5(replace(pg_get_functiondef(v_sig::regprocedure), E'\r', '')) <> v_expected->>v_sig then
      raise exception '20261011010300 post-check: % not as intended', v_sig;
    end if;
  end loop;
end $post$;
