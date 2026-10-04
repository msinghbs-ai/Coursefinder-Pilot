-- CF-247 Decision 253 (4 Oct 2026). University adapters, set in the UI (Platform Admin, 15:51: "keep setting ui based
-- uni adapters for field mappings"). One adapter per university says how that university names its pages (patterns
-- taken off page titles and catalogue titles before comparing), where a page keeps its data as JSON (a script id and a
-- path for each field) and where on the page each field is (a heading pattern). An adapter is tried on stored pages
-- first (Preview, no Firecrawl credits) and then applied to that university's stored pages. A page it confirms gets
-- the identity basis adapter_code or adapter_title. Nothing is admitted until the Platform Admin allows that basis for
-- a country and field in Platform settings › Pipeline settings (the existing country admission rules). A page bound by
-- hand, a confirmed value or a value entered by hand is never changed by an adapter. Every change is logged.
-- No text value in this file contains a semicolon.

create table if not exists pipeline.uni_adapters (
  provider_id uuid primary key,
  enabled boolean not null default false,
  title_strip text,
  course_title_strip text,
  json_source text,
  json_paths jsonb not null default '{}'::jsonb,
  sections jsonb not null default '{}'::jsonb,
  section_chars int not null default 2000,
  notes text,
  reason text not null,
  updated_by uuid,
  updated_at timestamptz not null default now()
);
alter table pipeline.uni_adapters enable row level security;
revoke all on pipeline.uni_adapters from anon, authenticated;

create table if not exists pipeline.uni_adapter_previews (
  id uuid primary key default gen_random_uuid(),
  provider_id uuid not null,
  adapter jsonb not null,
  result jsonb,
  requested_by uuid,
  created_at timestamptz not null default now(),
  done_at timestamptz
);
alter table pipeline.uni_adapter_previews enable row level security;
revoke all on pipeline.uni_adapter_previews from anon, authenticated;

create table if not exists pipeline.uni_adapter_results (
  id bigserial primary key,
  provider_id uuid not null,
  course_id uuid not null,
  before_read_status text,
  before_identity text,
  identity text,
  how text,
  fields jsonb,
  at timestamptz not null default now()
);
create index if not exists uni_adapter_results_provider on pipeline.uni_adapter_results(provider_id, at);
alter table pipeline.uni_adapter_results enable row level security;
revoke all on pipeline.uni_adapter_results from anon, authenticated;

-- A pattern the database cannot read is refused when saved.
create or replace function security.uni_adapter_pattern_ok(p text) returns boolean
language plpgsql immutable set search_path = '' as $f$
begin
  if p is null or btrim(p) = '' then return true; end if;
  perform '' ~* p;
  return true;
exception when others then return false;
end $f$;

create or replace function security.uni_adapter_json(p_provider uuid) returns jsonb
language sql stable security definer set search_path = '' as $f$
  select jsonb_build_object('title_strip', a.title_strip, 'course_title_strip', a.course_title_strip, 'json_source', a.json_source, 'json_paths', a.json_paths,
                            'sections', a.sections, 'section_chars', a.section_chars, 'enabled', a.enabled, 'notes', a.notes, 'reason', a.reason, 'updated_at', a.updated_at)
  from pipeline.uni_adapters a where a.provider_id = p_provider
$f$;
revoke all on function security.uni_adapter_json(uuid) from public, anon, authenticated;

-- The adapter of one university, what its pages look like now, its latest previews and what applying it changed.
create or replace function public.admin_uni_adapter_read(p_provider_id uuid) returns jsonb
language plpgsql stable security definer set search_path = '' as $f$
declare v_rank int := security.current_role_rank();
begin
  if auth.uid() is null or coalesce(v_rank, 0) < 5 then raise exception 'Platform Admin or Operator required' using errcode = '42501'; end if;
  return jsonb_build_object(
    'can_manage', coalesce(v_rank, 0) >= 6,
    'provider', (select jsonb_build_object('id', p.id, 'name', coalesce(p.display_name, p.canonical_name), 'website', p.website) from catalogue.providers p where p.id = p_provider_id),
    'adapter', security.uni_adapter_json(p_provider_id),
    'pages', (select jsonb_object_agg(coalesce(s, 'none'), n) from (select pg.read_status s, count(*) n from pipeline.coverage_course_pages pg where pg.provider_id = p_provider_id group by 1) x),
    'previews', coalesce((select jsonb_agg(jsonb_build_object('id', v.id, 'created_at', v.created_at, 'done_at', v.done_at, 'adapter', v.adapter, 'result', v.result) order by v.created_at desc) from (select * from pipeline.uni_adapter_previews v where v.provider_id = p_provider_id order by created_at desc limit 3) v), '[]'::jsonb),
    'applied', coalesce((select jsonb_agg(jsonb_build_object('identity', r.identity, 'before', r.before_read_status, 'n', r.n, 'last_at', r.last_at)) from (select identity, before_read_status, count(*) n, max(at) last_at from pipeline.uni_adapter_results where provider_id = p_provider_id group by 1, 2) r), '[]'::jsonb),
    'allowed', (select jsonb_agg(jsonb_build_object('country', k.iso_alpha2::text, 'identities', c.identities)) from pipeline.coverage_admission_countries c join ref.countries k on k.id = c.country_id)
  );
end $f$;
revoke all on function public.admin_uni_adapter_read(uuid) from public, anon;
grant execute on function public.admin_uni_adapter_read(uuid) to authenticated;

-- Save, preview or apply an adapter (Platform Admin, with a reason).
create or replace function public.admin_uni_adapter_write(p_action text, p_args jsonb) returns jsonb
language plpgsql security definer set search_path = '' as $f$
declare v_rank int := security.current_role_rank(); v_reason text := btrim(coalesce(p_args->>'reason', '')); v_pid uuid := (p_args->>'provider_id')::uuid; v_a jsonb := coalesce(p_args->'adapter', '{}'::jsonb);
        v_id uuid; k text; v text; v_before jsonb;
begin
  if auth.uid() is null or coalesce(v_rank, 0) < 6 then raise exception 'Platform Admin required' using errcode = '42501'; end if;
  if length(v_reason) < 4 then raise exception 'give a reason (kept in the log)'; end if;
  if not exists (select 1 from catalogue.providers p where p.id = v_pid) then raise exception 'unknown provider'; end if;
  if p_action in ('save', 'preview') then
    if jsonb_typeof(coalesce(v_a->'json_paths', '{}'::jsonb)) <> 'object' or jsonb_typeof(coalesce(v_a->'sections', '{}'::jsonb)) <> 'object' then raise exception 'json_paths and sections must be field to text maps'; end if;
    for k, v in select x.key, x.value from jsonb_each_text(coalesce(v_a->'sections', '{}'::jsonb)) x union all select 'title_strip', v_a->>'title_strip' union all select 'course_title_strip', v_a->>'course_title_strip' loop
      if not security.uni_adapter_pattern_ok(v) then raise exception 'the pattern for % cannot be read: %', k, v; end if;
    end loop;
    if coalesce(v_a->>'json_source', '') !~ '^[A-Za-z0-9_-]*$' then raise exception 'the JSON script id may only hold letters, digits, _ and -'; end if;
  end if;
  if p_action = 'save' then
    v_before := security.uni_adapter_json(v_pid);
    insert into pipeline.uni_adapters(provider_id, enabled, title_strip, course_title_strip, json_source, json_paths, sections, section_chars, notes, reason, updated_by, updated_at)
      values (v_pid, coalesce((v_a->>'enabled')::boolean, false), nullif(btrim(v_a->>'title_strip'), ''), nullif(btrim(v_a->>'course_title_strip'), ''), nullif(btrim(v_a->>'json_source'), ''),
              coalesce(v_a->'json_paths', '{}'::jsonb), coalesce(v_a->'sections', '{}'::jsonb), greatest(200, least(coalesce((v_a->>'section_chars')::int, 2000), 10000)), v_a->>'notes', v_reason, auth.uid(), now())
    on conflict (provider_id) do update set enabled = excluded.enabled, title_strip = excluded.title_strip, course_title_strip = excluded.course_title_strip, json_source = excluded.json_source, json_paths = excluded.json_paths, sections = excluded.sections, section_chars = excluded.section_chars, notes = excluded.notes, reason = excluded.reason, updated_by = excluded.updated_by, updated_at = now() where pipeline.uni_adapters.provider_id = excluded.provider_id;
    insert into pipeline.admin_control_events(area, action, target, detail, actor) values ('toolsets', 'uni_adapter_save', v_pid::text, jsonb_build_object('before', v_before, 'after', security.uni_adapter_json(v_pid), 'reason', v_reason), auth.uid());
    return jsonb_build_object('ok', true, 'adapter', security.uni_adapter_json(v_pid));
  elsif p_action = 'preview' then
    insert into pipeline.uni_adapter_previews(provider_id, adapter, requested_by) values (v_pid, v_a, auth.uid()) returning id into v_id;
    perform pipeline.svc_pilot_submit_nonce('coverage-sweep', jsonb_build_object('mode', 'adapter_preview', 'preview_id', v_id));
    return jsonb_build_object('ok', true, 'preview_id', v_id);
  elsif p_action = 'apply' then
    if not exists (select 1 from pipeline.uni_adapters a where a.provider_id = v_pid and a.enabled) then raise exception 'save the adapter switched on first'; end if;
    insert into pipeline.admin_control_events(area, action, target, detail, actor) values ('toolsets', 'uni_adapter_apply', v_pid::text, jsonb_build_object('adapter', security.uni_adapter_json(v_pid), 'reason', v_reason), auth.uid());
    perform pipeline.svc_pilot_submit_nonce('coverage-sweep', jsonb_build_object('mode', 'adapter_apply', 'provider_id', v_pid));
    return jsonb_build_object('ok', true);
  end if;
  raise exception 'unknown action';
end $f$;
revoke all on function public.admin_uni_adapter_write(text, jsonb) from public, anon;
grant execute on function public.admin_uni_adapter_write(text, jsonb) to authenticated;

-- Worker: the preview's adapter and up to 8 stored pages of that university (refused ones first).
create or replace function public.svc_adapter_preview_next(p_preview_id uuid) returns jsonb
language plpgsql security definer set search_path = '' as $f$
declare v_p pipeline.uni_adapter_previews%rowtype;
begin
  if current_user <> 'postgres' and coalesce(auth.role(), '') <> 'service_role' then raise exception 'service_role required'; end if;
  select * into v_p from pipeline.uni_adapter_previews where id = p_preview_id;
  if v_p.id is null then return null; end if;
  return jsonb_build_object('adapter', v_p.adapter, 'pages', coalesce((select jsonb_agg(x) from (
    select jsonb_build_object('course_id', pg.course_id, 'url', pg.url, 'title', coalesce(c.display_title, c.canonical_title), 'code', c.course_code, 'country', k.iso_alpha2::text,
                              'status', pg.status, 'read_status', pg.read_status, 'identity_basis', pg.identity_basis, 'storage_path', e.storage_path) x
    from pipeline.coverage_course_pages pg join catalogue.courses c on c.id = pg.course_id join catalogue.providers p on p.id = pg.provider_id join ref.countries k on k.id = p.country_id
    join pipeline.evidence_artifacts e on e.id = pg.evidence_id
    where pg.provider_id = v_p.provider_id and pg.read_status in ('identity_mismatch', 'read') and e.storage_path is not null and c.lifecycle_status = 'active'
    order by (pg.read_status = 'identity_mismatch') desc, md5(pg.course_id::text || v_p.id::text) limit 8) q), '[]'::jsonb));
end $f$;
revoke all on function public.svc_adapter_preview_next(uuid) from public, anon, authenticated;
grant execute on function public.svc_adapter_preview_next(uuid) to service_role;

create or replace function public.svc_adapter_preview_record(p_preview_id uuid, p_result jsonb) returns void
language plpgsql security definer set search_path = '' as $f$
begin
  if current_user <> 'postgres' and coalesce(auth.role(), '') <> 'service_role' then raise exception 'service_role required'; end if;
  update pipeline.uni_adapter_previews set result = p_result, done_at = now() where id = p_preview_id;
end $f$;
revoke all on function public.svc_adapter_preview_record(uuid, jsonb) from public, anon, authenticated;
grant execute on function public.svc_adapter_preview_record(uuid, jsonb) to service_role;

-- Worker: the next stored pages of a university to apply its (switched on) adapter to.
create or replace function public.svc_adapter_apply_next(p_provider_id uuid, p_after uuid, p_limit int) returns jsonb
language plpgsql security definer set search_path = '' as $f$
begin
  if current_user <> 'postgres' and coalesce(auth.role(), '') <> 'service_role' then raise exception 'service_role required'; end if;
  if not exists (select 1 from pipeline.uni_adapters a where a.provider_id = p_provider_id and a.enabled) then return jsonb_build_object('adapter', null, 'pages', '[]'::jsonb); end if;
  return jsonb_build_object('adapter', security.uni_adapter_json(p_provider_id), 'pages', coalesce((select jsonb_agg(x) from (
    select jsonb_build_object('course_id', pg.course_id, 'url', pg.url, 'title', coalesce(c.display_title, c.canonical_title), 'code', c.course_code, 'country', k.iso_alpha2::text,
                              'status', pg.status, 'read_status', pg.read_status, 'identity_basis', pg.identity_basis, 'storage_path', e.storage_path) x
    from pipeline.coverage_course_pages pg join catalogue.courses c on c.id = pg.course_id join catalogue.providers p on p.id = pg.provider_id join ref.countries k on k.id = p.country_id
    join pipeline.evidence_artifacts e on e.id = pg.evidence_id
    where pg.provider_id = p_provider_id and pg.read_status in ('identity_mismatch', 'read') and e.storage_path is not null and c.lifecycle_status = 'active'
      and (p_after is null or pg.course_id > p_after)
    order by pg.course_id limit greatest(1, least(coalesce(p_limit, 100), 300))) q), '[]'::jsonb));
end $f$;
revoke all on function public.svc_adapter_apply_next(uuid, uuid, int) from public, anon, authenticated;
grant execute on function public.svc_adapter_apply_next(uuid, uuid, int) to service_role;

-- Worker: record what an adapter found on one stored page. A refused page the adapter confirms becomes the course's
-- page (read, with the adapter's identity basis). On a page already confirmed, only fields the page had nothing for are
-- filled. A page whose link was entered by hand is left alone. Every change is logged.
create or replace function public.svc_adapter_page_record(p_course_id uuid, p_identity text, p_how text, p_candidates jsonb) returns text
language plpgsql security definer set search_path = '' as $f$
declare v_pg pipeline.coverage_course_pages%rowtype; v_c jsonb;
begin
  if current_user <> 'postgres' and coalesce(auth.role(), '') <> 'service_role' then raise exception 'service_role required'; end if;
  if p_identity not in ('adapter_code', 'adapter_title') or p_candidates is null then return 'nothing'; end if;
  select * into v_pg from pipeline.coverage_course_pages where course_id = p_course_id;
  if v_pg.course_id is null or v_pg.evidence_id is null then return 'no_page'; end if;
  if exists (select 1 from pipeline.manual_locks k where k.entity = 'course' and k.entity_id = p_course_id and k.field = 'official_url') then return 'entered_by_hand'; end if;
  if v_pg.read_status = 'identity_mismatch' then
    update pipeline.coverage_course_pages set read_status = 'read', status = 'bound', identity_basis = p_identity, candidates = p_candidates || jsonb_build_object('final_url', v_pg.url), next_read_at = now() + interval '90 days' where course_id = p_course_id and read_status = 'identity_mismatch';
    update pipeline.search_pass_links set state = 'verified', updated_at = now() where course_id = p_course_id and bound_url = v_pg.url;
  elsif v_pg.read_status = 'read' and v_pg.identity_basis is not null then
    v_c := coalesce(v_pg.candidates, '{}'::jsonb);
    if jsonb_array_length(coalesce(v_c->'intakes', '[]'::jsonb)) = 0 and jsonb_array_length(coalesce(p_candidates->'intakes', '[]'::jsonb)) > 0 then v_c := v_c || jsonb_build_object('intakes', p_candidates->'intakes', 'intake_context', p_candidates->'intake_context'); end if;
    if coalesce(v_c->'english'->>'ielts_overall', v_c->'english'->>'pte_overall', v_c->'english'->>'toefl_overall') is null and coalesce(p_candidates->'english'->>'ielts_overall', p_candidates->'english'->>'pte_overall', p_candidates->'english'->>'toefl_overall') is not null then v_c := v_c || jsonb_build_object('english', p_candidates->'english'); end if;
    if coalesce(v_c->'fee'->>'value', '') = '' and coalesce(p_candidates->'fee'->>'value', '') <> '' then v_c := v_c || jsonb_build_object('fee', p_candidates->'fee'); end if;
    if v_c = coalesce(v_pg.candidates, '{}'::jsonb) then return 'no_new_field'; end if;
    update pipeline.coverage_course_pages set candidates = v_c || jsonb_build_object('adapter', true) where course_id = p_course_id;
  else
    return 'not_applicable';
  end if;
  insert into pipeline.uni_adapter_results(provider_id, course_id, before_read_status, before_identity, identity, how, fields)
    values (v_pg.provider_id, p_course_id, v_pg.read_status, v_pg.identity_basis, p_identity, p_how, jsonb_build_object('intakes', p_candidates->'intakes', 'english', p_candidates->'english'->'ielts_overall', 'fee', p_candidates->'fee'->'value'));
  return case when v_pg.read_status = 'identity_mismatch' then 'confirmed' else 'fields_added' end;
end $f$;
revoke all on function public.svc_adapter_page_record(uuid, text, text, jsonb) from public, anon, authenticated;
grant execute on function public.svc_adapter_page_record(uuid, text, text, jsonb) to service_role;
