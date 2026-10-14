-- CF-247 v2.15.273 (Platform Admin, 14 Oct 2026 10:41: "create a job to enrich data for specific or multiple fields across uni or countries
-- using scraper and ai in layer 2 and layer 3. Keep it simple"; plan docs/platform/FIELD-GAPS-AND-ENRICHMENT-PLAN.md v1.0; decisions 11:2x:
-- "Build the full job first", campus lists "Auto when sources agree", international "Institution rule").
--   1 Field sources (pipeline.field_source_rules): for each country (or all), which sources fill each field and in what order. Changed on
--     Settings with a reason (Platform Admin). Sources: adapter (values the university adapter already read from the stored course page),
--     institution_rule, ai_stored (the pinned AI model reads the stored page and must quote it), ai_title (the AI classifies from the title
--     and level), scraper (one new read through Firecrawl, only where allowed).
--   2 Job kind enrich_fields (Task manager): scope (countries or universities), fields, AI on or off, scraper on or off. One item per course
--     and field (pipeline.field_enrich_items); the job fills only missing values, never a value entered or locked by hand, and records the
--     source, value and quote of each.
--   3 Campuses: per university the AI turns the campus names its course pages give into one campus list; a campus is admitted when the AI
--     list and the course pages agree (the name stands for at least enrich.campus_min_pages course pages); the courses are then linked.
--   4 International: Canada, every course at an IRCC-listed institution; otherwise what the course page says (adapter or AI).
--   5 Provider address: from a stored contact page, else (scraper on) the provider's home page read once; the AI must quote the address.
-- Nothing dropped or deleted.

do $guard$
declare v_expected jsonb := '{"security.admin_job_slice_v1(uuid,integer)": "07273bfdec334c015ac67c27ffaf72ac", "security.ai_spend_today_v1()": "940334680d0d9fc520f097c7bfeadf47"}'::jsonb;
  v_sig text;
begin
  for v_sig in select jsonb_object_keys(v_expected) loop
    if md5(replace(pg_get_functiondef(v_sig::regprocedure), E'\r', '')) <> v_expected->>v_sig then
      raise exception 'live % differs from the definition this change replaces', v_sig;
    end if;
  end loop;
end $guard$;

-- 1 Field sources -------------------------------------------------------------------------------------------------------------------
create table if not exists pipeline.field_source_rules (
  country_code text not null,      -- 'ALL' or an ISO country code; a country row replaces the ALL row for that country
  field text not null,
  sources text[] not null,
  reason text,
  updated_by uuid,
  updated_at timestamptz not null default now(),
  primary key (country_code, field));
alter table pipeline.field_source_rules enable row level security;
insert into pipeline.field_source_rules(country_code, field, sources, reason) values
 ('ALL', 'campus', array['adapter', 'ai_stored'], 'CF-247 v2.15.273: starting order'),
 ('ALL', 'duration', array['adapter', 'ai_stored'], 'CF-247 v2.15.273: starting order'),
 ('ALL', 'level', array['adapter', 'ai_title'], 'CF-247 v2.15.273: starting order'),
 ('ALL', 'delivery', array['adapter', 'ai_stored'], 'CF-247 v2.15.273: starting order'),
 ('ALL', 'field_of_study', array['ai_title'], 'CF-247 v2.15.273: starting order'),
 ('ALL', 'international', array['institution_rule', 'adapter', 'ai_stored'], 'CF-247 v2.15.273: institution rule (Platform Admin 14 Oct 2026)'),
 ('ALL', 'provider_address', array['ai_stored', 'scraper'], 'CF-247 v2.15.273: starting order')
on conflict do nothing;

CREATE OR REPLACE FUNCTION security.enrich_fields_v1()
 RETURNS TABLE(field text, label text, level text, sources text[], sort int)
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO ''
AS $function$
  select * from (values
    ('campus', 'Campus (with the campus list)', 'course', array['adapter', 'ai_stored'], 1),
    ('duration', 'Duration', 'course', array['adapter', 'ai_stored'], 2),
    ('level', 'Study level', 'course', array['adapter', 'ai_title'], 3),
    ('delivery', 'Delivery mode', 'course', array['adapter', 'ai_stored'], 4),
    ('field_of_study', 'Field of study', 'course', array['ai_title'], 5),
    ('international', 'Open to international students', 'course', array['institution_rule', 'adapter', 'ai_stored'], 6),
    ('provider_address', 'Provider street address', 'provider', array['ai_stored', 'scraper'], 7)) v(field, label, level, sources, sort)
$function$;

-- the order of sources for a field in a country
CREATE OR REPLACE FUNCTION security.field_sources_for_v1(p_country text, p_field text)
 RETURNS text[]
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  select coalesce((select r.sources from pipeline.field_source_rules r where r.country_code = upper(coalesce(p_country, '')) and r.field = p_field),
                  (select r.sources from pipeline.field_source_rules r where r.country_code = 'ALL' and r.field = p_field), '{}'::text[])
$function$;

-- 2 Items ---------------------------------------------------------------------------------------------------------------------------
create table if not exists pipeline.field_enrich_items (
  id bigserial primary key,
  job_id uuid not null references pipeline.admin_jobs(id) on delete cascade,
  provider_id uuid not null references catalogue.providers(id) on delete cascade,
  course_id uuid references catalogue.courses(id) on delete cascade,
  field text not null,
  state text not null default 'queued' check (state in ('queued', 'waiting', 'ai', 'leased', 'filled', 'review', 'skipped', 'failed')),
  source text,
  tried text[] not null default '{}',
  value jsonb,
  quote text,
  reason text,
  evidence_id uuid,
  storage_path text,
  attempts int not null default 0,
  leased_until timestamptz,
  cost_usd numeric,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique nulls not distinct (job_id, provider_id, course_id, field));
create index if not exists idx_uni_adapter_results_course on pipeline.uni_adapter_results (course_id, at desc);
create index if not exists idx_field_enrich_items_job_state on pipeline.field_enrich_items (job_id, state);
create index if not exists idx_field_enrich_items_state on pipeline.field_enrich_items (state) where state in ('queued', 'waiting', 'ai', 'leased');
alter table pipeline.field_enrich_items enable row level security;

insert into pipeline.admin_job_kinds(kind, label, what, can_pause, added_in)
values ('enrich_fields', 'Enrich fields', 'Fills chosen missing fields for chosen countries or universities: values the university adapters already read, the institution rule, the AI reading stored pages or classifying titles, and (only when allowed) one new read through the scraper. Values entered or locked by hand are never changed.', false, 'v2.15.273')
on conflict (kind) do nothing;

-- settings (G2)
insert into pipeline.platform_toolset_settings(toolset_key, key, label, help, kind, value, min_value, max_value, unit, sort, reason, section, used_by) values
 ('pipeline', 'batch.enrich_fields', 'Enrich fields: items a minute', 'Course fields the Enrich fields job settles each minute from stored values and rules.', 'number', to_jsonb(400), 20, 5000, 'items a minute', 100, 'CF-247 v2.15.273: new job', 'Job sizes', 'Enrich fields tasks (every minute)'),
 ('pipeline', 'enrich.ai_calls_at_once', 'Enrich fields: AI calls at once', 'Worker calls reading with AI at the same time.', 'number', to_jsonb(2), 1, 6, 'calls', 101, 'CF-247 v2.15.273: new job', 'Job sizes', 'Enrich fields tasks'),
 ('pipeline', 'enrich.campus_min_pages', 'Campus admitted when named on at least', 'A campus from the AI list is admitted without review when this many of the university''s course pages name it.', 'number', to_jsonb(2), 1, 20, 'course pages', 102, 'CF-247 v2.15.273: Auto when sources agree (Platform Admin 14 Oct 2026)', 'Onboarding', 'Enrich fields: campus lists'),
 ('pipeline', 'enrich.wait_page_hours', 'Wait for a requested page read', 'How long an item waits for a course page asked for through the scraper before it is skipped.', 'number', to_jsonb(6), 1, 72, 'hours', 103, 'CF-247 v2.15.273: new job', 'Re-read and retry', 'Enrich fields tasks')
on conflict do nothing;
insert into pipeline.platform_toolset_settings(toolset_key, key, label, help, kind, value, min_value, max_value, unit, sort, reason, section, used_by)
select 'openrouter', 'guard_enrich_fields', 'Daily guard: Enrich fields with AI', 'Most spent a day reading stored pages and titles for Enrich fields.', 'number', to_jsonb(2), 0, 50, 'US$ a day', 60, 'CF-247 v2.15.273: new AI use', s.section, 'Enrich fields tasks'
  from (select coalesce((select section from pipeline.platform_toolset_settings where toolset_key = 'openrouter' and key like 'guard\_%' limit 1), 'Daily guards') section) s
on conflict do nothing;

-- 3 Reading a value from text (adapter values and AI answers share these) ---------------------------------------------------------
CREATE OR REPLACE FUNCTION security.enrich_parse_duration_v1(p text)
 RETURNS jsonb
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO ''
AS $function$
  select case when m is null then null else jsonb_build_object('value', m[1]::numeric,
           'unit', case when m[3] ~* '^(year|yr)' then 'years' when m[3] ~* '^month' then 'months' when m[3] ~* '^week' then 'weeks'
                        when m[3] ~* '^(semester|trimester|term)' then 'semesters' end) end
    from (select regexp_match(coalesce(p, ''), '(\d+(?:\.\d+)?)\s*(-\s*\d+(?:\.\d+)?\s*|to\s*\d+(?:\.\d+)?\s*)?(years?|yrs?|months?|weeks?|semesters?|trimesters?|terms?)\M', 'i') m) x
$function$;

CREATE OR REPLACE FUNCTION security.enrich_parse_delivery_v1(p text)
 RETURNS text
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO ''
AS $function$
  select case when p is null or btrim(p) = '' then null
              when p ~* '(blended|hybrid)' then 'blended'
              when p ~* '(on[- ]?campus|in[- ]person|face[- ]to[- ]face|campus)' and p ~* '(online|distance)' then 'on_campus_and_online'
              when p ~* '(100\s*%\s*online|fully online|online only|online$|^online|distance)' then 'online'
              when p ~* '(on[- ]?campus|in[- ]person|face[- ]to[- ]face)' then 'on_campus'
              else null end
$function$;

-- a level code from a short text (Bachelor, Masters, Graduate Diploma ...)
CREATE OR REPLACE FUNCTION security.enrich_parse_level_v1(p text)
 RETURNS uuid
 LANGUAGE sql
 STABLE
 SET search_path TO ''
AS $function$
  select sl.id from ref.study_levels sl
   where sl.short_code = (case when p is null or length(p) > 60 then null
                               when p ~* '(ph\.?d|doctor)' then 'DR'
                               when p ~* 'master' then 'MA'
                               when p ~* 'graduate diploma|post-?graduate diploma' then 'GD'
                               when p ~* 'graduate certificate|post-?graduate certificate' then 'GC'
                               when p ~* 'honours' then 'BH'
                               when p ~* 'bachelor|baccalaur|degree' then 'BA'
                               when p ~* 'associate' then 'AS'
                               when p ~* 'advanced diploma' then 'AD'
                               when p ~* 'diploma|dipl[oô]me' then 'DP'
                               when p ~* 'certificate|certificat' then 'CT' end)
   limit 1
$function$;

-- 4 Applying a value (only where the field is empty and not locked by hand) -----------------------------------------------------------
CREATE OR REPLACE FUNCTION security.enrich_apply_v1(p_item bigint)
 RETURNS text
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare i pipeline.field_enrich_items%rowtype; v_n int := 0; v_lock boolean;
begin
  select * into i from pipeline.field_enrich_items where id = p_item for update;
  if i.id is null or i.value is null then return 'nothing'; end if;
  v_lock := exists (select 1 from pipeline.manual_locks l where l.entity = case when i.course_id is null then 'provider' else 'course' end
                     and l.entity_id = coalesce(i.course_id, i.provider_id) and l.field in (i.field, 'all'));
  if v_lock then
    update pipeline.field_enrich_items set state = 'skipped', reason = 'locked by hand', updated_at = now() where id = i.id; return 'locked';
  end if;
  if i.field = 'duration' then
    update catalogue.courses set duration_value = (i.value->>'value')::numeric, duration_unit = i.value->>'unit', updated_at = now()
     where id = i.course_id and duration_value is null;
  elsif i.field = 'level' then
    update catalogue.courses set study_level_id = (i.value->>'level_id')::uuid, updated_at = now() where id = i.course_id and study_level_id is null;
  elsif i.field = 'delivery' then
    update catalogue.courses set delivery_mode = i.value->>'mode', updated_at = now() where id = i.course_id and nullif(btrim(delivery_mode), '') is null;
  elsif i.field = 'field_of_study' then
    update catalogue.courses set primary_field_id = (i.value->>'field_id')::uuid, updated_at = now() where id = i.course_id and primary_field_id is null;
  elsif i.field = 'international' then
    update catalogue.courses set open_to_international = (i.value->>'open')::boolean, updated_at = now() where id = i.course_id and open_to_international is null;
  elsif i.field = 'provider_address' then
    update catalogue.providers set address_line1 = left(i.value->>'street', 200), postcode = coalesce(postcode, left(i.value->>'postcode', 20)),
           primary_city = coalesce(nullif(btrim(primary_city), ''), left(i.value->>'city', 120)), updated_at = now()
     where id = i.provider_id and nullif(btrim(address_line1), '') is null;
  elsif i.field = 'campus' and i.course_id is not null then
    insert into catalogue.course_campuses(course_id, campus_id, delivery_mode, is_primary, evidence_id)
    select i.course_id, (x->>'campus_id')::uuid, coalesce((select nullif(btrim(c.delivery_mode), '') from catalogue.courses c where c.id = i.course_id and c.delivery_mode in ('on_campus', 'blended', 'on_campus_and_online')), 'on_campus'),
           row_number() over () = 1, i.evidence_id
      from jsonb_array_elements(i.value->'campuses') x
     where not exists (select 1 from catalogue.course_campuses cc where cc.course_id = i.course_id and cc.campus_id = (x->>'campus_id')::uuid)
    on conflict do nothing;
  end if;
  get diagnostics v_n = row_count;
  update pipeline.field_enrich_items set state = case when v_n > 0 then 'filled' else 'skipped' end,
         reason = case when v_n > 0 then reason else coalesce(reason, 'already filled') end, updated_at = now() where id = i.id;
  return case when v_n > 0 then 'filled' else 'already' end;
end $function$;

-- campus list for a university: admitted campuses are created (or found) and the university's course campus items are settled
CREATE OR REPLACE FUNCTION security.enrich_campus_list_apply_v1(p_item bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare i pipeline.field_enrich_items%rowtype; x jsonb; v_cid uuid; v_min int := security.pipeline_num_v1('enrich.campus_min_pages', 2)::int;
        v_admitted jsonb := '[]'::jsonb; v_review jsonb := '[]'::jsonb; v_pages int; v_country uuid; v_sub uuid; r record; v_ids jsonb; v_linked int := 0;
begin
  select * into i from pipeline.field_enrich_items where id = p_item for update;
  select p.country_id, p.subdivision_id into v_country, v_sub from catalogue.providers p where p.id = i.provider_id;
  for x in select * from jsonb_array_elements(coalesce(i.value->'campuses', '[]'::jsonb)) loop
    -- agreement: the course pages that name this campus (its raw names) are counted from the job's own campus items
    select count(*) into v_pages from pipeline.field_enrich_items c
     where c.job_id = i.job_id and c.provider_id = i.provider_id and c.field = 'campus' and c.course_id is not null
       and exists (select 1 from jsonb_array_elements_text(coalesce(x->'raw', '[]'::jsonb)) rw where lower(c.quote) like '%' || lower(rw) || '%');
    if v_pages < v_min then v_review := v_review || (x || jsonb_build_object('pages', v_pages)); continue; end if;
    select ca.id into v_cid from catalogue.campuses ca where ca.provider_id = i.provider_id and lower(ca.name) = lower(x->>'name') limit 1;
    if v_cid is null then
      insert into catalogue.campuses(stable_key, provider_id, name, country_id, subdivision_id, city, address_line1, postcode, status, publication_status, evidence_id)
      values ('campus:studysearch:' || i.provider_id || ':' || regexp_replace(lower(x->>'name'), '[^a-z0-9]+', '-', 'g'), i.provider_id, left(x->>'name', 160), v_country, v_sub,
              left(nullif(x->>'city', ''), 120), left(nullif(x->>'street', ''), 200), left(nullif(x->>'postcode', ''), 20), 'active', 'published', i.evidence_id)
      on conflict (stable_key) do update set updated_at = now()
      returning id into v_cid;
    end if;
    v_admitted := v_admitted || (x || jsonb_build_object('campus_id', v_cid, 'pages', v_pages));
  end loop;
  update pipeline.field_enrich_items set state = case when jsonb_array_length(v_admitted) > 0 then 'filled' when jsonb_array_length(v_review) > 0 then 'review' else 'skipped' end,
         value = value || jsonb_build_object('admitted', v_admitted, 'to_review', v_review),
         reason = case when jsonb_array_length(v_review) > 0 then jsonb_array_length(v_review) || ' campus name(s) named on too few course pages: a person decides' else reason end, updated_at = now()
   where id = i.id;
  return jsonb_build_object('admitted', jsonb_array_length(v_admitted), 'review', jsonb_array_length(v_review));
end $function$;

-- course campus items, once their university's campus list is settled: linked to the admitted campuses their page names
CREATE OR REPLACE FUNCTION security.enrich_campus_link_v1(p_job uuid)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare r record; v_ids jsonb; v_linked int := 0;
begin
  for r in select c.id, c.quote, l.state list_state, coalesce(l.value->'admitted', '[]'::jsonb) admitted
             from pipeline.field_enrich_items c
             join pipeline.field_enrich_items l on l.job_id = c.job_id and l.provider_id = c.provider_id and l.field = 'campus_list'
            where c.job_id = p_job and c.field = 'campus' and c.course_id is not null and c.state = 'waiting' and c.quote is not null
              and l.state in ('filled', 'review', 'skipped', 'failed') loop
    select coalesce(jsonb_agg(jsonb_build_object('campus_id', a->>'campus_id', 'name', a->>'name')), '[]'::jsonb) into v_ids
      from jsonb_array_elements(r.admitted) a
     where exists (select 1 from jsonb_array_elements_text(coalesce(a->'raw', '[]'::jsonb)) rw where lower(r.quote) like '%' || lower(rw) || '%');
    if jsonb_array_length(v_ids) > 0 then
      update pipeline.field_enrich_items set value = jsonb_build_object('campuses', v_ids), updated_at = now() where id = r.id;
      if security.enrich_apply_v1(r.id) = 'filled' then v_linked := v_linked + 1; end if;
    elsif r.list_state = 'filled' then
      update pipeline.field_enrich_items set state = 'review', reason = 'the campus named on the page is not in the admitted list', updated_at = now() where id = r.id;
    else
      update pipeline.field_enrich_items set state = 'skipped', reason = 'no campus list was admitted for the university', updated_at = now() where id = r.id;
    end if;
  end loop;
  return v_linked;
end $function$;

-- 5 One step of the job (every minute through admin_jobs_tick_v1) ----------------------------------------------------------------------
CREATE OR REPLACE FUNCTION security.enrich_fields_slice_v1(p_id uuid, p_items integer)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare j pipeline.admin_jobs%rowtype; it record; v_src text; v_srcs text[]; v_ai boolean; v_scr boolean; v_x jsonb; v_txt text; v_val jsonb;
        v_done int := 0; v_batch int := greatest(coalesce(p_items, 0), 1) * security.pipeline_num_v1('batch.enrich_fields', 400)::int / 10;
        v_cc text; v_path text; v_ev uuid; v_settled boolean; v_left int;
begin
  select * into j from pipeline.admin_jobs where id = p_id for update;
  v_ai := coalesce((j.args->>'ai')::boolean, true); v_scr := coalesce((j.args->>'scraper')::boolean, false);
  -- items waiting for a requested page: move on when the page arrived, skip when the wait is over
  update pipeline.field_enrich_items e set state = 'queued', updated_at = now()
   where e.job_id = p_id and e.state = 'waiting' and e.field <> 'campus'
     and exists (select 1 from pipeline.coverage_course_pages g where g.course_id = e.course_id and g.evidence_id is not null and g.read_at >= e.updated_at);
  update pipeline.field_enrich_items e set state = 'skipped', reason = 'the requested page read did not arrive in time', updated_at = now()
   where e.job_id = p_id and e.state = 'waiting' and e.field <> 'campus'
     and e.updated_at < now() - make_interval(hours => security.pipeline_num_v1('enrich.wait_page_hours', 6)::int);
  for it in select e.*, k.iso_alpha2::text cc from pipeline.field_enrich_items e join catalogue.providers p on p.id = e.provider_id join ref.countries k on k.id = p.country_id
             where e.job_id = p_id and e.state = 'queued' order by e.id limit v_batch for update of e skip locked loop
    v_settled := false; v_srcs := security.field_sources_for_v1(it.cc, case when it.field = 'campus_list' then 'campus' else it.field end);
    foreach v_src in array v_srcs loop
      continue when v_src = any (it.tried);
      continue when v_src in ('ai_stored', 'ai_title') and not v_ai;
      continue when v_src = 'scraper' and not v_scr;
      update pipeline.field_enrich_items set tried = tried || v_src where id = it.id;
      if v_src = 'adapter' and it.course_id is not null then
        select r.fields->'extra' into v_x from pipeline.uni_adapter_results r where r.course_id = it.course_id order by r.at desc limit 1;
        v_txt := nullif(btrim(case it.field when 'campus' then coalesce(v_x->>'campus', v_x->>'location') when 'duration' then v_x->>'duration'
                                            when 'level' then v_x->>'study_level' when 'delivery' then v_x->>'mode' when 'international' then v_x->>'student_type' end), '');
        if v_txt is null then continue; end if;
        v_ev := (select g.evidence_id from pipeline.coverage_course_pages g where g.course_id = it.course_id);
        v_val := case it.field when 'duration' then security.enrich_parse_duration_v1(v_txt)
                               when 'level' then (select jsonb_build_object('level_id', l) from (select security.enrich_parse_level_v1(v_txt) l) z where l is not null)
                               when 'delivery' then (select jsonb_build_object('mode', m) from (select security.enrich_parse_delivery_v1(left(v_txt, 120)) m) z where m is not null)
                               when 'international' then case when v_txt ~* 'international' then jsonb_build_object('open', true) end
                               else null end;
        if it.field = 'campus' then
          -- the campus text waits for the university's campus list
          update pipeline.field_enrich_items set state = 'waiting', source = 'adapter', quote = left(v_txt, 300), evidence_id = v_ev, updated_at = now() where id = it.id;
          v_settled := true; exit;
        end if;
        if v_val is null then continue; end if;
        update pipeline.field_enrich_items set source = 'adapter', value = v_val, quote = left(v_txt, 300), evidence_id = v_ev, updated_at = now() where id = it.id;
        perform security.enrich_apply_v1(it.id); v_settled := true; exit;
      elsif v_src = 'institution_rule' and it.field = 'international' then
        if it.cc = 'CA' and exists (select 1 from catalogue.provider_identifiers i where i.provider_id = it.provider_id and i.scheme = 'ircc_dli') then
          update pipeline.field_enrich_items set source = 'institution_rule', value = jsonb_build_object('open', true),
                 quote = 'Listed by IRCC as a designated learning institution (DLI ' || (select i.identifier from catalogue.provider_identifiers i where i.provider_id = it.provider_id and i.scheme = 'ircc_dli' limit 1) || ')', updated_at = now()
           where id = it.id;
          perform security.enrich_apply_v1(it.id); v_settled := true; exit;
        end if;
      elsif v_src = 'ai_stored' then
        if it.field = 'provider_address' then
          select e.storage_path, e.id into v_path, v_ev from pipeline.evidence_artifacts e join pipeline.sources s on s.id = e.source_id
           where s.provider_id = it.provider_id and e.evidence_type in ('provider_contact_html_snapshot', 'enrich_home_page') and e.storage_path is not null order by e.created_at desc limit 1;
        elsif it.field = 'campus_list' then
          v_path := null; v_ev := null;  -- the list is made from the campus names, with the contact page when one is stored
          select e.storage_path, e.id into v_path, v_ev from pipeline.evidence_artifacts e join pipeline.sources s on s.id = e.source_id
           where s.provider_id = it.provider_id and e.evidence_type in ('provider_contact_html_snapshot', 'enrich_home_page') and e.storage_path is not null order by e.created_at desc limit 1;
          update pipeline.field_enrich_items set state = 'ai', source = 'ai_stored', storage_path = v_path, evidence_id = v_ev, updated_at = now() where id = it.id;
          v_settled := true; exit;
        else
          select e.storage_path, e.id into v_path, v_ev from pipeline.coverage_course_pages g join pipeline.evidence_artifacts e on e.id = g.evidence_id where g.course_id = it.course_id;
        end if;
        if v_path is null then continue; end if;
        update pipeline.field_enrich_items set state = 'ai', source = 'ai_stored', storage_path = v_path, evidence_id = v_ev, updated_at = now() where id = it.id;
        v_settled := true; exit;
      elsif v_src = 'ai_title' and it.course_id is not null then
        update pipeline.field_enrich_items set state = 'ai', source = 'ai_title', updated_at = now() where id = it.id;
        v_settled := true; exit;
      elsif v_src = 'scraper' then
        if it.field = 'provider_address' then
          if exists (select 1 from catalogue.providers p where p.id = it.provider_id and p.website ~* '^https?://' and not security.third_party_host_v1(p.website)) then
            update pipeline.field_enrich_items set state = 'ai', source = 'scraper', storage_path = null, updated_at = now() where id = it.id;
            v_settled := true; exit;
          end if;
        elsif it.course_id is not null and exists (select 1 from pipeline.coverage_course_pages g where g.course_id = it.course_id and g.url ~* '^https?://') then
          update pipeline.coverage_course_pages set next_read_at = now() where course_id = it.course_id and coalesce(next_read_at, 'infinity') > now();
          update pipeline.field_enrich_items set state = 'waiting', reason = 'course page asked to be read', updated_at = now() where id = it.id;
          v_settled := true; exit;
        end if;
      end if;
    end loop;
    if not v_settled then
      update pipeline.field_enrich_items set state = 'skipped', reason = coalesce(reason, 'no allowed source had a value'), updated_at = now() where id = it.id and state = 'queued';
    end if;
    v_done := v_done + 1;
  end loop;
  -- a university's campus list goes to the AI once its course campus items have all been read
  update pipeline.field_enrich_items l set state = 'queued', updated_at = now()
   where l.job_id = p_id and l.field = 'campus_list' and l.state = 'waiting'
     and not exists (select 1 from pipeline.field_enrich_items c where c.job_id = p_id and c.provider_id = l.provider_id and c.field = 'campus' and c.state in ('queued', 'ai', 'leased'));
  perform security.enrich_campus_link_v1(p_id);
  -- course campus items whose page named no campus: nothing to link
  update pipeline.field_enrich_items c set state = 'skipped', reason = 'no campus named on the page', updated_at = now()
   where c.job_id = p_id and c.field = 'campus' and c.state = 'waiting' and c.quote is null;
  if exists (select 1 from pipeline.field_enrich_items where job_id = p_id and state = 'ai') then perform security.enrich_ai_fire_v1(); end if;
  select count(*) into v_left from pipeline.field_enrich_items where job_id = p_id and state in ('queued', 'waiting', 'ai', 'leased');
  update pipeline.admin_jobs set progress = (select jsonb_build_object('done', count(*) filter (where state in ('filled', 'review', 'skipped', 'failed')), 'total', count(*),
                                                   'phase', case when v_left = 0 then 'finishing' when count(*) filter (where state in ('ai', 'leased')) > 0 then 'reading with AI' else 'settling stored values' end)
                                               from pipeline.field_enrich_items where job_id = p_id),
         result = (select jsonb_build_object('by_field', jsonb_object_agg(f, s), 'cost_usd', (select round(coalesce(sum(cost_usd), 0), 4) from pipeline.field_enrich_items where job_id = p_id))
                     from (select field f, jsonb_object_agg(state, n) s from (select field, state, count(*) n from pipeline.field_enrich_items where job_id = p_id group by 1, 2) z group by field) y),
         updated_at = now()
   where id = p_id;
  return v_left = 0;
end $function$;

-- 6 Start, preview, rules, items (screen) ---------------------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.admin_enrich_fields(p_action text, p_args jsonb DEFAULT '{}'::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_rank int := security.current_role_rank(); v_cc text[]; v_pids uuid[]; v_fields text[]; v_job uuid; v_reason text; v_n int; v_title text;
begin
  if auth.uid() is null or coalesce(v_rank, 0) < 3 then raise exception 'Curator role or above required' using errcode = '42501'; end if;
  v_cc := array(select upper(x) from jsonb_array_elements_text(coalesce(p_args->'countries', '[]'::jsonb)) x);
  v_pids := array(select x::uuid from jsonb_array_elements_text(coalesce(p_args->'provider_ids', '[]'::jsonb)) x);
  v_fields := array(select x from jsonb_array_elements_text(coalesce(p_args->'fields', '[]'::jsonb)) x where x in (select f.field from security.enrich_fields_v1() f));
  if p_action = 'fields' then
    return jsonb_build_object('fields', (select jsonb_agg(jsonb_build_object('field', f.field, 'label', f.label, 'level', f.level, 'allowed', f.sources) order by f.sort) from security.enrich_fields_v1() f),
      'rules', (select coalesce(jsonb_agg(jsonb_build_object('country', r.country_code, 'field', r.field, 'sources', r.sources, 'reason', r.reason, 'updated_at', r.updated_at) order by r.country_code, r.field), '[]'::jsonb) from pipeline.field_source_rules r),
      'countries', (select jsonb_agg(c order by c) from unnest(security.catalogue_country_codes_v1()) c),
      'can_start', v_rank >= 4, 'can_manage', v_rank >= 6);
  elsif p_action = 'preview' then
    if coalesce(array_length(v_fields, 1), 0) = 0 then raise exception 'choose at least one field'; end if;
    return (with scope as (
              select c.id, c.provider_id, c.study_level_id, c.primary_field_id, c.duration_value, c.delivery_mode, c.open_to_international, k.iso_alpha2::text cc
                from catalogue.courses c join catalogue.providers p on p.id = c.provider_id join ref.countries k on k.id = p.country_id
               where c.lifecycle_status = 'active' and (cardinality(v_cc) = 0 or k.iso_alpha2::text = any (v_cc)) and (cardinality(v_pids) = 0 or c.provider_id = any (v_pids))),
            f as (select x field from unnest(v_fields) x)
            select jsonb_build_object('courses', (select count(*) from scope), 'universities', (select count(distinct provider_id) from scope),
              'fields', jsonb_agg(jsonb_build_object('field', f.field,
                'missing', case f.field when 'campus' then (select count(*) from scope s where not exists (select 1 from catalogue.course_campuses x where x.course_id = s.id))
                                        when 'duration' then (select count(*) from scope s where s.duration_value is null)
                                        when 'level' then (select count(*) from scope s where s.study_level_id is null)
                                        when 'delivery' then (select count(*) from scope s where nullif(btrim(s.delivery_mode), '') is null)
                                        when 'field_of_study' then (select count(*) from scope s where s.primary_field_id is null)
                                        when 'international' then (select count(*) from scope s where s.open_to_international is null)
                                        when 'provider_address' then (select count(*) from catalogue.providers p where p.id in (select provider_id from scope) and nullif(btrim(p.address_line1), '') is null) end,
                'stored_page', case when f.field = 'provider_address' then (select count(distinct s2.provider_id) from pipeline.evidence_artifacts e join pipeline.sources s2 on s2.id = e.source_id
                                                                             where s2.provider_id in (select provider_id from scope) and e.evidence_type in ('provider_contact_html_snapshot', 'enrich_home_page'))
                                    else (select count(*) from scope s join pipeline.coverage_course_pages g on g.course_id = s.id where g.evidence_id is not null) end,
                'adapter_value', case f.field when 'campus' then (select count(*) from scope s where exists (select 1 from pipeline.uni_adapter_results r where r.course_id = s.id and coalesce(r.fields->'extra'->>'campus', r.fields->'extra'->>'location') is not null))
                                              when 'duration' then (select count(*) from scope s where s.duration_value is null and exists (select 1 from pipeline.uni_adapter_results r where r.course_id = s.id and r.fields->'extra'->>'duration' is not null))
                                              when 'delivery' then (select count(*) from scope s where nullif(btrim(s.delivery_mode), '') is null and exists (select 1 from pipeline.uni_adapter_results r where r.course_id = s.id and r.fields->'extra'->>'mode' is not null))
                                              when 'level' then (select count(*) from scope s where s.study_level_id is null and exists (select 1 from pipeline.uni_adapter_results r where r.course_id = s.id and r.fields->'extra'->>'study_level' is not null))
                                              else null end) order by f.field))
              from f);
  elsif p_action = 'start' then
    if v_rank < 4 then raise exception 'Pipeline Operator role or above required' using errcode = '42501'; end if;
    v_reason := btrim(coalesce(p_args->>'reason', ''));
    if length(v_reason) < 4 then raise exception 'give a reason (it is kept with the task)'; end if;
    if coalesce(array_length(v_fields, 1), 0) = 0 then raise exception 'choose at least one field'; end if;
    if cardinality(v_cc) = 0 and cardinality(v_pids) = 0 then raise exception 'choose countries or universities'; end if;
    v_title := 'Enrich ' || array_to_string(v_fields, ', ') || ' · ' || case when cardinality(v_pids) > 0 then cardinality(v_pids) || ' universit' || case when cardinality(v_pids) = 1 then 'y' else 'ies' end else array_to_string(v_cc, ', ') end;
    insert into pipeline.admin_jobs(kind, lane, state, title, args, progress, requested_by, reason, scope)
    values ('enrich_fields', 'enrich', 'queued', left(v_title, 200),
            jsonb_build_object('countries', to_jsonb(v_cc), 'provider_ids', to_jsonb(v_pids), 'fields', to_jsonb(v_fields),
                               'ai', coalesce((p_args->>'ai')::boolean, true), 'scraper', coalesce((p_args->>'scraper')::boolean, false)),
            jsonb_build_object('done', 0, 'total', 0), auth.uid(), v_reason, coalesce(nullif(array_to_string(v_cc, ', '), ''), cardinality(v_pids) || ' universities'))
    returning id into v_job;
    -- one item per course and missing field; one per university for its address and its campus list
    insert into pipeline.field_enrich_items(job_id, provider_id, course_id, field)
    select v_job, c.provider_id, c.id, f.x
      from catalogue.courses c join catalogue.providers p on p.id = c.provider_id join ref.countries k on k.id = p.country_id
      cross join unnest(v_fields) f(x)
     where c.lifecycle_status = 'active' and f.x <> 'provider_address'
       and (cardinality(v_cc) = 0 or k.iso_alpha2::text = any (v_cc)) and (cardinality(v_pids) = 0 or c.provider_id = any (v_pids))
       and case f.x when 'campus' then not exists (select 1 from catalogue.course_campuses x where x.course_id = c.id)
                    when 'duration' then c.duration_value is null when 'level' then c.study_level_id is null
                    when 'delivery' then nullif(btrim(c.delivery_mode), '') is null when 'field_of_study' then c.primary_field_id is null
                    when 'international' then c.open_to_international is null else false end
    on conflict do nothing;
    insert into pipeline.field_enrich_items(job_id, provider_id, course_id, field, state)
    select distinct v_job, e.provider_id, null::uuid, 'campus_list', 'waiting' from pipeline.field_enrich_items e where e.job_id = v_job and e.field = 'campus'
    on conflict do nothing;
    if 'provider_address' = any (v_fields) then
      insert into pipeline.field_enrich_items(job_id, provider_id, course_id, field)
      select v_job, p.id, null::uuid, 'provider_address'
        from catalogue.providers p join ref.countries k on k.id = p.country_id
       where nullif(btrim(p.address_line1), '') is null and coalesce(p.lifecycle_status, 'active') = 'active'
         and exists (select 1 from catalogue.courses c where c.provider_id = p.id and c.lifecycle_status = 'active')
         and (cardinality(v_cc) = 0 or k.iso_alpha2::text = any (v_cc)) and (cardinality(v_pids) = 0 or p.id = any (v_pids))
      on conflict do nothing;
    end if;
    select count(*) into v_n from pipeline.field_enrich_items where job_id = v_job;
    update pipeline.admin_jobs set progress = jsonb_build_object('done', 0, 'total', v_n) where id = v_job;
    insert into pipeline.admin_job_events(job_id, note) values (v_job, v_n || ' item(s) to settle');
    return jsonb_build_object('job_id', v_job, 'items', v_n);
  elsif p_action = 'rule_set' then
    if v_rank < 6 then raise exception 'Platform Admin role required' using errcode = '42501'; end if;
    v_reason := btrim(coalesce(p_args->>'reason', ''));
    if length(v_reason) < 4 then raise exception 'give a reason (kept in the log)'; end if;
    if not exists (select 1 from security.enrich_fields_v1() f where f.field = p_args->>'field') then raise exception 'unknown field'; end if;
    if exists (select 1 from jsonb_array_elements_text(coalesce(p_args->'sources', '[]'::jsonb)) s
                where s not in (select unnest(f.sources) from security.enrich_fields_v1() f where f.field = p_args->>'field')) then
      raise exception 'a source that cannot fill this field';
    end if;
    insert into pipeline.field_source_rules(country_code, field, sources, reason, updated_by, updated_at)
    values (upper(coalesce(nullif(p_args->>'country', ''), 'ALL')), p_args->>'field', array(select jsonb_array_elements_text(p_args->'sources')), v_reason, auth.uid(), now())
    on conflict (country_code, field) do update set sources = excluded.sources, reason = excluded.reason, updated_by = excluded.updated_by, updated_at = now();
    insert into pipeline.admin_control_events(area, action, target, detail, actor)
    values ('field_sources', 'set', upper(coalesce(nullif(p_args->>'country', ''), 'ALL')) || '.' || (p_args->>'field'), jsonb_build_object('sources', p_args->'sources', 'reason', v_reason), auth.uid());
    return public.admin_enrich_fields('fields', '{}'::jsonb);
  elsif p_action = 'items' then
    return (select jsonb_build_object('items', coalesce(jsonb_agg(x order by x->>'id' desc), '[]'::jsonb)) from (
      select jsonb_build_object('id', e.id, 'field', e.field, 'state', e.state, 'source', e.source, 'value', e.value, 'quote', e.quote, 'reason', e.reason,
               'provider', coalesce(p.display_name, p.canonical_name), 'course', c.canonical_title, 'course_id', e.course_id, 'provider_id', e.provider_id) x
        from pipeline.field_enrich_items e join catalogue.providers p on p.id = e.provider_id left join catalogue.courses c on c.id = e.course_id
       where e.job_id = (p_args->>'job_id')::uuid and (nullif(p_args->>'field', '') is null or e.field = p_args->>'field')
         and (nullif(p_args->>'state', '') is null or e.state = p_args->>'state')
       order by e.id desc limit least(greatest(coalesce((p_args->>'limit')::int, 50), 1), 200)) z);
  end if;
  raise exception 'unknown action %', p_action using errcode = '22023';
end $function$;
revoke all on function public.admin_enrich_fields(text, jsonb) from public, anon;
grant execute on function public.admin_enrich_fields(text, jsonb) to authenticated;

-- 7 The worker's side (AI and the one scraper read) -------------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION security.enrich_ai_fire_v1()
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_open int; v_max int := security.pipeline_num_v1('enrich.ai_calls_at_once', 2)::int; v_due int; v_sent int := 0;
begin
  if not security.ai_use_allowed_v1('enrich_fields') then return 0; end if;
  select count(*) into v_due from pipeline.field_enrich_items where state = 'ai' or (state = 'leased' and leased_until < now());
  if v_due = 0 then return 0; end if;
  select count(*) into v_open from pipeline.edge_request_log l where l.function_name = 'coverage-sweep' and l.mode = 'enrich_ai' and l.created_at > now() - make_interval(mins => 3)
     and not exists (select 1 from net._http_response r where r.id = l.request_id);
  while v_open + v_sent < v_max and v_sent * 10 < v_due loop
    perform pipeline.svc_pilot_submit_nonce('coverage-sweep', jsonb_build_object('mode', 'enrich_ai'));
    v_sent := v_sent + 1;
  end loop;
  return v_sent;
end $function$;

-- the next AI work: stored course pages grouped by course, titles in batches, a campus list, an address
CREATE OR REPLACE FUNCTION public.svc_enrich_ai_next(p_limit integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v jsonb; s record; v_lim int := greatest(1, least(coalesce(p_limit, 10), 40));
begin
  if current_user <> 'postgres' and coalesce(auth.role(), '') <> 'service_role' then raise exception 'service_role required'; end if;
  select model_identifier, model_code into s from pipeline.central_ai_settings where id = 1;
  with pick as (select e.id from pipeline.field_enrich_items e
                 where (e.state = 'ai' or (e.state = 'leased' and e.leased_until < now())) and e.attempts < 3
                 order by e.id limit v_lim for update skip locked),
  upd as (update pipeline.field_enrich_items e set state = 'leased', leased_until = now() + make_interval(mins => 4), attempts = e.attempts + 1, updated_at = now()
            from pick where e.id = pick.id returning e.*)
  select jsonb_build_object('model', s.model_identifier, 'model_code', s.model_code,
    'pages', coalesce((select jsonb_agg(jsonb_build_object('course_id', u.course_id, 'storage_path', min(u.storage_path), 'title', min(c.canonical_title), 'provider', min(coalesce(p.display_name, p.canonical_name)),
                         'items', jsonb_agg(jsonb_build_object('item_id', u.id, 'field', u.field)))) from upd u join catalogue.courses c on c.id = u.course_id join catalogue.providers p on p.id = u.provider_id
                       where u.source = 'ai_stored' and u.course_id is not null group by u.course_id), '[]'::jsonb),
    'titles', coalesce((select jsonb_agg(jsonb_build_object('item_id', u.id, 'field', u.field, 'title', c.canonical_title, 'level', sl.name, 'provider', coalesce(p.display_name, p.canonical_name)))
                        from upd u join catalogue.courses c on c.id = u.course_id join catalogue.providers p on p.id = u.provider_id left join ref.study_levels sl on sl.id = c.study_level_id
                       where u.source = 'ai_title'), '[]'::jsonb),
    'campus_lists', coalesce((select jsonb_agg(jsonb_build_object('item_id', u.id, 'provider', coalesce(p.display_name, p.canonical_name), 'storage_path', u.storage_path,
                         'names', (select coalesce(jsonb_agg(jsonb_build_object('text', q, 'pages', n) order by n desc), '[]'::jsonb)
                                     from (select c.quote q, count(*) n from pipeline.field_enrich_items c where c.job_id = u.job_id and c.provider_id = u.provider_id and c.field = 'campus' and c.quote is not null group by c.quote order by 2 desc limit 80) z)))
                        from upd u join catalogue.providers p on p.id = u.provider_id where u.field = 'campus_list'), '[]'::jsonb),
    'addresses', coalesce((select jsonb_agg(jsonb_build_object('item_id', u.id, 'provider_id', u.provider_id, 'provider', coalesce(p.display_name, p.canonical_name), 'storage_path', u.storage_path,
                         'website', case when u.source = 'scraper' then p.website end, 'country', (select k.iso_alpha2 from ref.countries k where k.id = p.country_id)))
                        from upd u join catalogue.providers p on p.id = u.provider_id where u.field = 'provider_address'), '[]'::jsonb),
    'fields', (select jsonb_agg(jsonb_build_object('code', f.code, 'name', f.name) order by f.code) from ref.fields_of_study f where f.code ~ '^asced-\d{4}$' and f.code !~ '00$'),
    'levels', (select jsonb_agg(jsonb_build_object('code', l.short_code, 'name', l.name) order by l.sort_order) from ref.study_levels l where l.short_code is not null))
    into v;
  return v;
end $function$;
revoke all on function public.svc_enrich_ai_next(integer) from public, anon, authenticated;
grant execute on function public.svc_enrich_ai_next(integer) to service_role;

-- what the AI found: each result is checked here again (codes from the lists, quotes kept) and applied
CREATE OR REPLACE FUNCTION public.svc_enrich_ai_record(p_results jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare r jsonb; i pipeline.field_enrich_items%rowtype; v_val jsonb; v_out jsonb := '{}'::jsonb; v_k text; v_ev uuid;
begin
  if current_user <> 'postgres' and coalesce(auth.role(), '') <> 'service_role' then raise exception 'service_role required'; end if;
  for r in select * from jsonb_array_elements(coalesce(p_results, '[]'::jsonb)) loop
    select * into i from pipeline.field_enrich_items where id = (r->>'item_id')::bigint for update;
    if i.id is null then continue; end if;
    v_ev := i.evidence_id;
    if r->>'storage_path' is not null then
      insert into pipeline.evidence_artifacts(source_id, evidence_type, source_url, storage_path, content_hash, mime_type, metadata, capture_version, evidence_group_key)
      values (security.coverage_sweep_source(i.provider_id), 'enrich_home_page', r->>'url', r->>'storage_path', r->>'sha256', 'application/gzip',
              jsonb_build_object('item_id', i.id, 'provider_id', i.provider_id, 'worker', 'coverage-sweep enrich_ai'), 1, 'enrich:' || i.id)
      returning id into v_ev;
    end if;
    update pipeline.field_enrich_items set cost_usd = coalesce(cost_usd, 0) + coalesce((r->>'cost')::numeric, 0), evidence_id = v_ev,
           storage_path = coalesce(r->>'storage_path', storage_path), leased_until = null, updated_at = now() where id = i.id;
    if r->>'retry' = 'true' then
      update pipeline.field_enrich_items set state = case when attempts >= 3 then 'failed' else 'ai' end, reason = left(r->>'reason', 300) where id = i.id;
      v_k := 'retry';
    elsif r->>'error' is not null then
      update pipeline.field_enrich_items set state = case when attempts >= 3 then 'failed' else 'ai' end, reason = left(r->>'error', 300) where id = i.id;
      v_k := 'error';
    elsif i.field = 'campus' then
      if nullif(btrim(r->'value'->>'campus'), '') is not null then
        update pipeline.field_enrich_items set state = 'waiting', quote = left(r->'value'->>'campus', 300) where id = i.id; v_k := 'campus_named';
      else
        update pipeline.field_enrich_items set state = 'skipped', reason = 'the page names no campus' where id = i.id; v_k := 'not_stated';
      end if;
    elsif i.field = 'campus_list' then
      update pipeline.field_enrich_items set value = jsonb_build_object('campuses', coalesce(r->'value'->'campuses', '[]'::jsonb)), quote = left(r->>'quote', 300) where id = i.id;
      v_k := 'campus_list'; perform security.enrich_campus_list_apply_v1(i.id);
    else
      v_val := case i.field
        when 'duration' then security.enrich_parse_duration_v1(r->>'quote')
        when 'delivery' then (select jsonb_build_object('mode', r->'value'->>'mode') where r->'value'->>'mode' in ('on_campus', 'online', 'blended', 'on_campus_and_online'))
        when 'level' then (select jsonb_build_object('level_id', l.id) from ref.study_levels l where l.short_code = r->'value'->>'level')
        when 'field_of_study' then (select jsonb_build_object('field_id', f.id) from ref.fields_of_study f where f.code = r->'value'->>'field' and f.code ~ '^asced-\d{4}$')
        when 'international' then (select jsonb_build_object('open', (r->'value'->>'open')::boolean) where r->'value'->>'open' in ('true', 'false'))
        when 'provider_address' then (select r->'value' where nullif(btrim(r->'value'->>'street'), '') is not null)
        when 'campus' then null end;
      if v_val is null then
        update pipeline.field_enrich_items set state = 'skipped', reason = coalesce(nullif(r->>'reason', ''), 'the page does not state it') where id = i.id;
        v_k := 'not_stated';
      else
        update pipeline.field_enrich_items set value = v_val, quote = left(coalesce(r->>'quote', i.quote), 300) where id = i.id;
        v_k := security.enrich_apply_v1(i.id);
      end if;
    end if;
    v_out := v_out || jsonb_build_object(v_k, coalesce((v_out->>v_k)::int, 0) + 1);
  end loop;
  return v_out;
end $function$;
revoke all on function public.svc_enrich_ai_record(jsonb) from public, anon, authenticated;
grant execute on function public.svc_enrich_ai_record(jsonb) to service_role;

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
  if v_j.kind = 'enrich_fields' then return security.enrich_fields_slice_v1(p_id, p_items); end if;  -- v2.15.273
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

CREATE OR REPLACE FUNCTION security.ai_spend_today_v1()
 RETURNS TABLE(use text, label text, spent numeric, guard numeric, calls bigint)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  with d as (select (date_trunc('day', now() at time zone 'UTC') at time zone 'UTC') t),
  s as (
    select 'scholarship_ai' u, coalesce(sum(x.cost_usd), 0) spent, count(*) calls from pipeline.scholarship_ai_extractions x, d where x.at >= d.t
    union all select 'adapter_builder', coalesce(sum(x.cost_usd), 0), count(*) from pipeline.uni_adapter_drafts x, d where x.created_at >= d.t and coalesce(x.cost_usd, 0) > 0
    union all select 'central_ai', coalesce(sum(x.cost_usd), 0), count(*) from pipeline.central_ai_queue x, d where x.created_at >= d.t and coalesce(x.cost_usd, 0) > 0
    union all select 'course_match', coalesce(sum(x.cost_usd), 0), count(*) from pipeline.coverage_ai_match x, d where coalesce(x.decided_at, x.created_at) >= d.t and coalesce(x.cost_usd, 0) > 0
    union all select 'enrich_fields', coalesce(sum(x.cost_usd), 0), count(*) from pipeline.field_enrich_items x, d where x.updated_at >= d.t and coalesce(x.cost_usd, 0) > 0)
  select s.u, l.label, round(s.spent, 4), (security.toolset_setting('openrouter', 'guard_' || s.u))::text::numeric, s.calls
    from s join (values ('scholarship_ai', 'Read scholarship pages with AI', 1), ('adapter_builder', 'Adapter proposals', 2), ('central_ai', 'Central pages with AI', 3),
                        ('course_match', 'AI course-page matching', 4), ('enrich_fields', 'Enrich fields with AI', 5)) l(u, label, sort) on l.u = s.u
   order by l.sort
$function$;

do $post$
declare v_expected jsonb := '{"security.admin_job_slice_v1(uuid,integer)": "6d9ba8d97a068061566d2790eec103fc", "security.ai_spend_today_v1()": "12943a97ec013cc0f38ec655cfba832d"}'::jsonb;
  v_sig text;
begin
  for v_sig in select jsonb_object_keys(v_expected) loop
    if md5(replace(pg_get_functiondef(v_sig::regprocedure), E'\r', '')) <> v_expected->>v_sig then
      raise exception 'v2.15.273 post-check: % not as intended', v_sig;
    end if;
  end loop;
end $post$;
