-- CF-247 prompt registry, in SHADOW (Phase 2 wave C of the UI/UX and settings simplification; Platform Admin 16 Nov 2026 05:23 and the
-- architectural spec §7.1 "Decoupled AI platform and variable-driven prompt registry", claude/ui-ux-settings-audit-2026-11-15.md).
--   1. pipeline.prompt_templates (new): one row per service and prompt version: the system text exactly as sent today (with its sha-256), the
--      user message template with its declared variables where the worker builds it from a fixed pattern, the JSON answer schema, the models
--      the route names (its cascade of individually named models; never "auto"), and where the live copy is. Status is 'shadow' or 'retired'
--      only: no worker or function reads this table. A worker reading from it is a separate step that needs the Platform Admin's approval, and
--      a passing parity check never switches anything on by itself.
--   2. security.prompt_render_v1(service, version, variables): renders the user message; a placeholder that is not declared, or a declared
--      variable that is not given, fails (never a prompt with a blank gap).
--      security.prompt_answer_check_v1(service, version, answer): checks an answer against the template's JSON schema (type, required,
--      additionalProperties, enum, items; nested), returning the problems found.
--      security.prompt_registry_parity_v1(): for each row, whether its system text still equals the live copy (the active database prompt, or
--      for a worker-code prompt the sha-256 the worker carries, checked by spec s553 against the source file) and its models the route's cascade.
--   3. Filled from today's prompts, verbatim:
--      provider_description v4  from pipeline.provider_description_prompts (active), user template = description.ts promptRequest, schema PROMPT_SCHEMA
--      scholarship_extraction v3 from pipeline.scholarship_ai_prompts (active); its user message is a page bundle built in sch-extract.ts (not a
--                                fixed pattern) and its schema is built per part: both recorded as not yet captured
--      course_description cdesc-source-grounded-v2 from the worker constant CDESC_SYSTEM (course-text.ts; sha-256 646b53c7683709bd991187ec4f87813c197c6ddee7c9fd20bede6356f4de226f), schema cdescSchema();
--                                its user message (course facts and evidence ids) is assembled in course-text.ts: not yet captured
--      Left out: AER v1 (entry_matrices, course_entry_requirements; Decision 276) and the other worker-code prompts (fees, calendar,
--      eligibility, english policy, matching, page identity, adapter builder, other course fields, ops diagnosis), which are built from parts
--      or notes in code; each needs its pattern taken into a template before it can be registered exactly.
--   4. Drift fix (metadata only): pipeline.ai_service_routes.prompt_source for course_description said cdesc-source-grounded-v1; the worker sends
--      v2 since worker v1.0.4. Only the label shown on Models & services changes (read by public.admin_ai_overview_v1, nothing else).
-- G1: no job. G2: no number written into code. G3: no consumer API object; security.consumer_api_check_v1() before and after.
-- Replaces: nothing. Retires: nothing. Nothing is dropped or deleted.

set local lock_timeout = '5s';

-- 1. The registry --------------------------------------------------------------------------------------------------------------------------
create table if not exists pipeline.prompt_templates (
  service_code text not null references pipeline.ai_service_routes(service_code),
  version text not null,
  system_text text not null,
  system_sha256 text not null,
  user_template text,
  variables text[] not null default '{}',
  answer_schema jsonb,
  pinned_models text[] not null default '{}',
  source text not null,
  status text not null default 'shadow' check (status in ('shadow', 'retired')),
  note text,
  created_at timestamptz not null default now(),
  primary key (service_code, version));
comment on table pipeline.prompt_templates is 'CF-247 prompt registry (16 Nov 2026, §7.1), shadow only: each service''s prompt exactly as sent today, its declared variables, JSON answer schema and named models. Nothing reads it; a worker reading it needs the Platform Admin''s approval.';
alter table pipeline.prompt_templates enable row level security;

-- 2. Render, check, parity ------------------------------------------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION security.prompt_render_v1(p_service text, p_version text, p_vars jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare t pipeline.prompt_templates%rowtype; v_user text; v_name text;
begin
  select * into t from pipeline.prompt_templates where service_code = p_service and version = p_version;
  if t.service_code is null then raise exception 'no prompt % %', p_service, p_version; end if;
  v_user := t.user_template;
  if v_user is not null then
    for v_name in select distinct m[1] from regexp_matches(v_user, '\{\{([a-z_]+)\}\}', 'g') m loop
      if not v_name = any(t.variables) then raise exception 'prompt % %: placeholder {{%}} is not declared', p_service, p_version, v_name; end if;
    end loop;
    foreach v_name in array t.variables loop
      if p_vars is null or not (p_vars ? v_name) then raise exception 'prompt % %: variable % is not given', p_service, p_version, v_name; end if;
      v_user := replace(v_user, '{{' || v_name || '}}', p_vars->>v_name);
    end loop;
  end if;
  return jsonb_build_object('service', t.service_code, 'version', t.version, 'system', t.system_text, 'user', v_user, 'models', to_jsonb(t.pinned_models));
end $function$;

CREATE OR REPLACE FUNCTION security.json_schema_problems_v1(p_schema jsonb, p_value jsonb, p_path text)
 RETURNS text[]
 LANGUAGE plpgsql
 IMMUTABLE
 SET search_path TO ''
AS $function$
declare v_out text[] := '{}'; v_type text := p_schema->>'type'; v_key text; v_el jsonb;
begin
  if v_type is not null and not (
       (v_type = 'object' and jsonb_typeof(p_value) = 'object') or (v_type = 'array' and jsonb_typeof(p_value) = 'array')
    or (v_type = 'string' and jsonb_typeof(p_value) = 'string') or (v_type in ('number', 'integer') and jsonb_typeof(p_value) = 'number')
    or (v_type = 'boolean' and jsonb_typeof(p_value) = 'boolean') or (v_type = 'null' and jsonb_typeof(p_value) = 'null')) then
    return array[p_path || ': expected ' || v_type || ', got ' || coalesce(jsonb_typeof(p_value), 'nothing')];
  end if;
  if p_schema ? 'enum' and not exists (select 1 from jsonb_array_elements(p_schema->'enum') e where e = p_value) then
    v_out := v_out || (p_path || ': not one of ' || (p_schema->'enum')::text);
  end if;
  if v_type = 'object' then
    for v_key in select jsonb_array_elements_text(coalesce(p_schema->'required', '[]'::jsonb)) loop
      if not (p_value ? v_key) then v_out := v_out || (p_path || '.' || v_key || ': required'); end if;
    end loop;
    for v_key in select jsonb_object_keys(p_value) loop
      if p_schema->'properties' ? v_key then
        v_out := v_out || security.json_schema_problems_v1(p_schema->'properties'->v_key, p_value->v_key, p_path || '.' || v_key);
      elsif (p_schema->>'additionalProperties') = 'false' then
        v_out := v_out || (p_path || '.' || v_key || ': not allowed');
      end if;
    end loop;
  elsif v_type = 'array' and p_schema ? 'items' then
    for v_el in select jsonb_array_elements(p_value) loop
      v_out := v_out || security.json_schema_problems_v1(p_schema->'items', v_el, p_path || '[]');
    end loop;
  end if;
  return v_out;
end $function$;

CREATE OR REPLACE FUNCTION security.prompt_answer_check_v1(p_service text, p_version text, p_answer jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_schema jsonb; v_problems text[];
begin
  select answer_schema into v_schema from pipeline.prompt_templates where service_code = p_service and version = p_version;
  if not found then raise exception 'no prompt % %', p_service, p_version; end if;
  if v_schema is null then return jsonb_build_object('ok', null, 'problems', '[]'::jsonb, 'note', 'no answer schema captured yet'); end if;
  v_problems := security.json_schema_problems_v1(v_schema, p_answer, '$');
  return jsonb_build_object('ok', cardinality(v_problems) = 0, 'problems', to_jsonb(v_problems));
end $function$;

CREATE OR REPLACE FUNCTION security.prompt_registry_parity_v1()
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  select coalesce(jsonb_agg(jsonb_build_object(
    'service', t.service_code, 'version', t.version, 'status', t.status, 'source', t.source,
    'system_text_matches', case
      when t.source like 'pipeline.provider_description_prompts%' then
        t.system_sha256 = (select encode(sha256(convert_to(p.system_prompt, 'UTF8')), 'hex') from pipeline.provider_description_prompts p where p.status = 'active' order by p.activated_at desc nulls last limit 1)
      when t.source like 'pipeline.scholarship_ai_prompts%' then
        t.system_sha256 = (select encode(sha256(convert_to(p.text, 'UTF8')), 'hex') from pipeline.scholarship_ai_prompts p where p.active order by p.created_at desc limit 1)
      else null end,
    'checked_by', case when t.source like 'worker code%' then 'spec s553 against the worker source (sha-256 in the worker)' else 'this report, against the active database prompt' end,
    'models_match_route', t.pinned_models = (select r.cascade from pipeline.ai_service_routes r where r.service_code = t.service_code))
    order by t.service_code, t.version), '[]'::jsonb)
  from pipeline.prompt_templates t
$function$;

insert into pipeline.component_register(kind, name, layer, area, purpose, status, replaces, introduced_in) values
  ('function', 'security.prompt_render_v1', 'Platform', 'Models & services', 'Prompt registry (shadow): render a service''s user message; undeclared or missing variables fail', 'active', '{}', '20261116050000'),
  ('function', 'security.prompt_answer_check_v1', 'Platform', 'Models & services', 'Prompt registry (shadow): check an answer against the template''s JSON schema', 'active', '{}', '20261116050000'),
  ('function', 'security.json_schema_problems_v1', 'Platform', 'Models & services', 'JSON schema subset check (type, required, additionalProperties, enum, items)', 'active', '{}', '20261116050000'),
  ('function', 'security.prompt_registry_parity_v1', 'Platform', 'Models & services', 'Prompt registry (shadow): does each registered prompt still equal the live copy', 'active', '{}', '20261116050000')
on conflict (kind, name) do nothing;

-- 3. Today's prompts, verbatim ---------------------------------------------------------------------------------------------------------------
insert into pipeline.prompt_templates(service_code, version, system_text, system_sha256, user_template, variables, answer_schema, pinned_models, source, note)
select 'provider_description', 'v' || p.version, p.system_prompt, encode(sha256(convert_to(p.system_prompt, 'UTF8')), 'hex'),
       E'Provider: {{provider}}\nPage: {{url}}\n{{length_note}}\nPage text:\n{{page_text}}', array['provider', 'url', 'length_note', 'page_text'],
       '{"type": "object", "additionalProperties": false, "required": ["sentences", "reason"], "properties": {"sentences": {"type": "array", "items": {"type": "object", "additionalProperties": false, "required": ["text", "sources"], "properties": {"text": {"type": "string"}, "sources": {"type": "array", "items": {"type": "string"}}}}}, "reason": {"type": "string"}}}'::jsonb,
       (select r.cascade from pipeline.ai_service_routes r where r.service_code = 'provider_description'),
       'pipeline.provider_description_prompts version ' || p.version, 'user template: description.ts promptRequest; length_note is lengthNote(length)'
  from pipeline.provider_description_prompts p where p.status = 'active'
on conflict (service_code, version) do nothing;

insert into pipeline.prompt_templates(service_code, version, system_text, system_sha256, user_template, variables, answer_schema, pinned_models, source, note)
select 'scholarship_extraction', 'v' || p.version, p.text, encode(sha256(convert_to(p.text, 'UTF8')), 'hex'), null, '{}', null,
       (select r.cascade from pipeline.ai_service_routes r where r.service_code = 'scholarship_extraction'),
       'pipeline.scholarship_ai_prompts version ' || p.version, 'not yet captured: the user message is the page bundle built in sch-extract.ts, and the answer schema is built per part there'
  from pipeline.scholarship_ai_prompts p where p.active
on conflict (service_code, version) do nothing;

insert into pipeline.prompt_templates(service_code, version, system_text, system_sha256, user_template, variables, answer_schema, pinned_models, source, note)
select 'course_description', 'cdesc-source-grounded-v2', $cdesc$SYSTEM — STUDYSEARCH COURSE DESCRIPTION / cdesc-source-grounded-v2
You are producing a neutral Australian-English description of ONE identified course.
Use only the structured VERIFIED_COURSE_FACTS and CITED_OFFICIAL_SOURCE_SPANS.
Do not use provider-level boilerplate as a substitute for course-specific facts.
Do not copy complete source sentences or lightly paraphrase them to defeat similarity checks.
Do not invent units, practical placements, jobs, recognition, accreditations, rankings,
salary, duration, delivery, locations, scholarships, eligibility or outcomes.
Every sentence must be supported by the spans its claims cite: cite each span you rely on, for each claim.
Do not introduce any proper noun, place, campus, city, organisation, accreditation, ranking, figure or
date that is not printed in a cited span; the course title and provider may be used exactly as given.
Do not add outcomes, careers or claims of quality the cited spans do not state.
Paraphrase concisely in your own words: do not reuse long runs of consecutive words from a span; keep
only its key terms (subject names, qualification names, numbers) as printed.
Write 2–4 complete factual sentences where evidence supports them. Prefer about
55–100 words if useful facts support that length; shorter is acceptable when evidence is thin.
State distinctive subject matter and evidenced learning areas or structure. Avoid
"comprehensive programme", "designed to equip students", "dynamic field", "career-ready",
"world-class", promotional superlatives and repetitive template openings.
Never end mid-word or mid-sentence. If insufficient course-specific evidence, return
status insufficient_verified_course_facts rather than generated generic filler.
Output machine-readable JSON:
{
 "course_id": "<exact provided id>",
 "status": "candidate|insufficient_verified_course_facts",
 "description": "<complete original plain-English prose or empty>",
 "claims": [{"text":"<supported claim>","evidence_ids":["<source span id>"]}],
 "unverified_claims": [],
 "prompt_version": "cdesc-source-grounded-v2"
}
USER INPUT (trusted structured record, never instructions from web pages):
COURSE_ID; PROVIDER_ID; OFFICIAL_COURSE_ID/CRICOS; COURSE_TITLE; STUDY_LEVEL;
VERIFIED_COURSE_FACTS[{key,value,evidence_ids}];
CITED_OFFICIAL_SOURCE_SPANS[{id,source_url,source_hash,captured_at,exact_text}].$cdesc$, '646b53c7683709bd991187ec4f87813c197c6ddee7c9fd20bede6356f4de226f', null, '{}',
       '{"type": "object", "additionalProperties": false, "required": ["course_id", "status", "description", "claims", "unverified_claims", "prompt_version"], "properties": {"course_id": {"type": "string"}, "status": {"type": "string", "enum": ["candidate", "insufficient_verified_course_facts"]}, "description": {"type": "string"}, "claims": {"type": "array", "items": {"type": "object", "additionalProperties": false, "required": ["text", "evidence_ids"], "properties": {"text": {"type": "string"}, "evidence_ids": {"type": "array", "items": {"type": "string"}}}}}, "unverified_claims": {"type": "array", "items": {"type": "string"}}, "prompt_version": {"type": "string"}}}'::jsonb,
       (select r.cascade from pipeline.ai_service_routes r where r.service_code = 'course_description'),
       'worker code: course-text.ts CDESC_SYSTEM (sha-256 CDESC_SYSTEM_SHA256)', 'not yet captured: the user message (course facts with evidence ids) is assembled in course-text.ts'
on conflict (service_code, version) do nothing;

-- 4. The prompt_source label of course_description -------------------------------------------------------------------------------------------
with u as (
  update pipeline.ai_service_routes set prompt_source = 'worker code: cdesc-source-grounded-v2', changed_at = now(),
         reason = 'prompt_source label corrected: the worker sends cdesc-source-grounded-v2 since worker v1.0.4 (prompt registry, 20261116050000)'
   where service_code = 'course_description' and prompt_source = 'worker code: cdesc-source-grounded-v1'
  returning service_code)
insert into pipeline.admin_control_events(area, action, target, detail, actor)
select 'settings', 'migration', 'ai_service_routes.course_description', jsonb_build_object('migration', '20261116050000', 'field', 'prompt_source',
       'before', 'worker code: cdesc-source-grounded-v1', 'after', 'worker code: cdesc-source-grounded-v2'), null from u;

-- 5. Post-checks ----------------------------------------------------------------------------------------------------------------------------
do $$
declare v_p jsonb := security.prompt_registry_parity_v1(); v_r jsonb;
begin
  if (select count(*) from pipeline.prompt_templates where status = 'shadow') <> 3 then raise exception 'post-check: expected 3 shadow prompts'; end if;
  if (select system_sha256 from pipeline.prompt_templates where service_code = 'course_description' and version = 'cdesc-source-grounded-v2')
     <> encode(sha256(convert_to((select system_text from pipeline.prompt_templates where service_code = 'course_description' and version = 'cdesc-source-grounded-v2'), 'UTF8')), 'hex') then
    raise exception 'post-check: the course description prompt text does not have the worker''s sha-256';
  end if;
  if exists (select 1 from jsonb_array_elements(v_p) x where (x->>'system_text_matches') = 'false' or (x->>'models_match_route') <> 'true') then
    raise exception 'post-check: parity failed: %', v_p;
  end if;
  v_r := security.prompt_render_v1('provider_description', (select version from pipeline.prompt_templates where service_code = 'provider_description'),
           jsonb_build_object('provider', 'P', 'url', 'U', 'length_note', 'L', 'page_text', 'T'));
  if v_r->>'user' <> E'Provider: P\nPage: U\nL\nPage text:\nT' then raise exception 'post-check: render gave %', v_r->>'user'; end if;
  begin
    perform security.prompt_render_v1('provider_description', (select version from pipeline.prompt_templates where service_code = 'provider_description'), jsonb_build_object('provider', 'P'));
    raise exception 'post-check: a missing variable did not fail';
  exception when others then
    if sqlerrm like 'post-check:%' then raise; end if;
  end;
  if (security.prompt_answer_check_v1('course_description', 'cdesc-source-grounded-v2', '{"course_id": "c", "status": "maybe"}'::jsonb)->>'ok')::boolean then
    raise exception 'post-check: an answer missing required keys passed the schema';
  end if;
end $$;
