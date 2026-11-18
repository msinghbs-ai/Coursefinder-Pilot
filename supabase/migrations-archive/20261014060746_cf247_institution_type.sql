-- CF-247 v2.15.276 (14 Oct 2026) Decision 258: institution type for every provider, from the registers.
-- Platform Admin decisions (multiple choice, 14 Oct): types mirror the registers. Australian universities come from the TEQSA
-- National Register (data.gov.au). A CRICOS Government provider that offers VET is TAFE. NZ types come from NZQA. Canada stays
-- empty. training.gov.au is left for a later release.
--  1. Type list: university, university_college, higher_education_institute, tafe_polytechnic, private_vet, school, wananga,
--     other. The unused tafe and college rows are retired (kept, not dropped).
--  2. catalogue.provider_register_facts: one value per provider and register fact, with its source and evidence.
--  3. pipeline.provider_type_rules: ordered, editable rules (Settings > Pipeline settings). The first enabled rule that matches
--     sets the type. A persons choice (manual lock on provider_type_id) always wins. No rule, no type: the reason is kept.
--  4. security.provider_type_classify_v1(): set-based. Daily job provider-type-classify, and after every register read.
--  5. svc_provider_register_facts_put: the new Layer 1 reader layer1-provider-facts writes facts keyed by CRICOS code.
--  6. svc_layer1_apply_register_records keeps the NZQA organisation type it was dropping (md5-guarded).
--  7. Two Layer 1 sources (TEQSA National Register providers, CRICOS Institutions), read through data.gov.au.
--  8. Providers screen: type, its basis and the reason. admin_provider_set_type (PIM Admin and above, no reason asked).
--  9. Website API v2: institution_type on providers and courses, the institution_types filter, and the reference list.
-- Nothing is dropped or deleted. Every replaced function is md5-checked first.

-- 1. Type list
update ref.provider_types set status = 'retired', description = 'Retired 14 Oct 2026 (Decision 258), replaced by the register types' where code in ('tafe', 'college');
update ref.provider_types set name = 'University', description = 'TEQSA Australian University, NZQA university', status = 'active' where code = 'university';
update ref.provider_types set name = 'Other', description = 'Registered provider that fits no other type, such as English language or foundation only', status = 'active' where code = 'other';
insert into ref.provider_types (code, name, description, status) values
  ('university_college', 'University College', 'TEQSA University College', 'active'),
  ('higher_education_institute', 'Higher Education Institute', 'TEQSA Institute of Higher Education', 'active'),
  ('tafe_polytechnic', 'TAFE / Polytechnic', 'Public vocational institute: CRICOS Government provider offering VET, NZ institute of technology or polytechnic', 'active'),
  ('private_vet', 'Private VET college', 'Private vocational provider: CRICOS Private provider offering VET, NZ private training establishment', 'active'),
  ('school', 'School', 'Provider of school-level courses only', 'active'),
  ('wananga', 'Wānanga', 'NZQA wānanga', 'active')
on conflict (code) do update set name = excluded.name, description = excluded.description, status = 'active';

-- 2. Register facts
create table if not exists catalogue.provider_register_facts (
  provider_id uuid not null references catalogue.providers(id),
  fact_code text not null,
  value text,
  source_id uuid references pipeline.sources(id),
  evidence_id uuid,
  observed_at timestamptz not null default now(),
  primary key (provider_id, fact_code)
);
alter table catalogue.provider_register_facts enable row level security;
revoke all on catalogue.provider_register_facts from public, anon, authenticated;

-- Basis of the type on each provider
alter table catalogue.providers add column if not exists provider_type_basis text;
alter table catalogue.providers add column if not exists provider_type_set_at timestamptz;

-- 3. Rules
create table if not exists pipeline.provider_type_rules (
  id uuid primary key default gen_random_uuid(),
  position integer not null,
  country_code text not null,
  teqsa_category text,
  teqsa_status text,
  register_type text,
  nz_org_type text,
  course_profile text check (course_profile is null or course_profile in ('vet', 'school_no_vet', 'non_aqf_only')),
  result_type text not null references ref.provider_types(code),
  enabled boolean not null default true,
  label text not null,
  updated_at timestamptz not null default now(),
  updated_by uuid
);
alter table pipeline.provider_type_rules enable row level security;
revoke all on pipeline.provider_type_rules from public, anon, authenticated;
comment on table pipeline.provider_type_rules is 'Decision 258: institution type rules. Text fields are case-insensitive patterns matched against register facts. First enabled match by position wins.';

insert into pipeline.provider_type_rules (position, country_code, teqsa_category, teqsa_status, register_type, nz_org_type, course_profile, result_type, label)
select * from (values
  (10, 'AU', '^Australian University$', '^Active$', null, null, null, 'university', 'TEQSA register: Australian University'),
  (20, 'AU', null, null, '^Government$', null, 'vet', 'tafe_polytechnic', 'CRICOS Government provider offering VET'),
  (30, 'AU', '^University College$', '^Active$', null, null, null, 'university_college', 'TEQSA register: University College'),
  (40, 'AU', '^Institute of Higher Education$', '^Active$', null, null, null, 'higher_education_institute', 'TEQSA register: Institute of Higher Education'),
  (50, 'AU', null, null, '^(Government|Private)$', null, 'school_no_vet', 'school', 'CRICOS provider of school courses only'),
  (60, 'AU', null, null, '^Private$', null, 'vet', 'private_vet', 'CRICOS Private provider offering VET'),
  (70, 'AU', null, null, '^(Government|Private)$', null, 'non_aqf_only', 'other', 'CRICOS provider of English language or foundation courses only'),
  (110, 'NZ', null, null, null, '^(UNI|University)$', null, 'university', 'NZQA: university'),
  (120, 'NZ', null, null, null, '^(POLLY|ITP|Polytechnic|Institute of Technology.*|Te Pūkenga.*)$', null, 'tafe_polytechnic', 'NZQA: institute of technology or polytechnic'),
  (130, 'NZ', null, null, null, '^(WANA|Wānanga|Wananga)$', null, 'wananga', 'NZQA: wānanga'),
  (140, 'NZ', null, null, null, '^(PTE|Private Training Establishment)$', null, 'private_vet', 'NZQA: private training establishment'),
  (150, 'NZ', null, null, null, '^(GTE|Government Training Establishment)$', null, 'other', 'NZQA: government training establishment')
) v(position, country_code, teqsa_category, teqsa_status, register_type, nz_org_type, course_profile, result_type, label)
where not exists (select 1 from pipeline.provider_type_rules);

-- Course profile from the providers active courses
create or replace function security.provider_course_profile_v1(p_provider_id uuid)
returns jsonb language sql stable security definer set search_path to '' as $$
  select jsonb_build_object(
    'vet', coalesce(bool_or(sl.code ~ '^(certificate|diploma|advanced_diploma|vocational|associate_degree)'), false),
    'school', coalesce(bool_or(sl.code ~ '(school|secondary)'), false),
    'non_aqf_only', coalesce(bool_and(coalesce(sl.code, 'non_aqf_award') = 'non_aqf_award'), false),
    'courses', count(c.id))
  from catalogue.courses c left join ref.study_levels sl on sl.id = c.study_level_id
  where c.provider_id = p_provider_id and coalesce(c.lifecycle_status, 'active') = 'active'
$$;
revoke all on function security.provider_course_profile_v1(uuid) from public, anon, authenticated;

-- 4. Classifier. Set-based over all AU and NZ providers. Locked (hand-set) types are left alone.
create or replace function security.provider_type_classify_v1()
returns jsonb language plpgsql security definer set search_path to '' as $$
declare v_out jsonb;
begin
  with p as (
    select pr.id, trim(co.iso_alpha2::text) cc
    from catalogue.providers pr join ref.countries co on co.id = pr.country_id
    where trim(co.iso_alpha2::text) in (select distinct country_code from pipeline.provider_type_rules)
      and not exists (select 1 from pipeline.manual_locks l where l.entity = 'provider' and l.entity_id = pr.id and l.field = 'provider_type_id')
  ), f as (
    select p.*,
      (select value from catalogue.provider_register_facts x where x.provider_id = p.id and x.fact_code = 'teqsa_category') teqsa_category,
      (select value from catalogue.provider_register_facts x where x.provider_id = p.id and x.fact_code = 'teqsa_status') teqsa_status,
      (select value from catalogue.provider_register_facts x where x.provider_id = p.id and x.fact_code = 'cricos_institution_type') register_type,
      (select value from catalogue.provider_register_facts x where x.provider_id = p.id and x.fact_code = 'nzqa_org_type') nz_org_type,
      security.provider_course_profile_v1(p.id) prof
    from p
  ), calc as (
    select f.id, r.result_type, r.label rule_label,
      (select t.id from ref.provider_types t where t.code = r.result_type) type_id,
      case when r.id is null then
        'No rule matched: ' || concat_ws(', ',
          case when f.cc = 'AU' then 'TEQSA ' || coalesce(f.teqsa_category || ' (' || coalesce(f.teqsa_status, '?') || ')', 'none') end,
          case when f.cc = 'AU' then 'CRICOS ' || coalesce(nullif(f.register_type, ''), 'none') end,
          case when f.cc = 'NZ' then 'NZQA ' || coalesce(nullif(f.nz_org_type, ''), 'none') end,
          case when (f.prof->>'courses')::int = 0 then 'no active courses' else
            nullif(concat_ws('/', case when (f.prof->>'vet')::boolean then 'VET' end, case when (f.prof->>'school')::boolean then 'school' end,
                      case when (f.prof->>'non_aqf_only')::boolean then 'non-AQF only' end), '') end)
      end reason
    from f
    left join lateral (
      select ru.* from pipeline.provider_type_rules ru
      where ru.enabled and ru.country_code = f.cc
        and (ru.teqsa_category is null or coalesce(f.teqsa_category, '') ~* ru.teqsa_category)
        and (ru.teqsa_status is null or coalesce(f.teqsa_status, '') ~* ru.teqsa_status)
        and (ru.register_type is null or coalesce(f.register_type, '') ~* ru.register_type)
        and (ru.nz_org_type is null or coalesce(f.nz_org_type, '') ~* ru.nz_org_type)
        and (ru.course_profile is null
             or (ru.course_profile = 'vet' and (f.prof->>'vet')::boolean)
             or (ru.course_profile = 'school_no_vet' and (f.prof->>'school')::boolean and not (f.prof->>'vet')::boolean)
             or (ru.course_profile = 'non_aqf_only' and (f.prof->>'courses')::int > 0 and (f.prof->>'non_aqf_only')::boolean))
      order by ru.position limit 1
    ) r on true
  ), set_type as (
    update catalogue.providers pr
       set provider_type_id = c.type_id, provider_type_basis = c.rule_label, provider_type_set_at = now()
      from calc c
     where pr.id = c.id and c.result_type is not null
       and (pr.provider_type_id is distinct from c.type_id or pr.provider_type_basis is distinct from c.rule_label)
    returning 1
  ), set_reason as (
    update catalogue.providers pr
       set provider_type_id = null, provider_type_basis = c.reason, provider_type_set_at = now()
      from calc c
     where pr.id = c.id and c.result_type is null
       and (pr.provider_type_id is not null or pr.provider_type_basis is distinct from c.reason)
    returning 1
  )
  select jsonb_build_object(
    'classified', (select count(*) from calc where result_type is not null),
    'no_rule', (select count(*) from calc where result_type is null),
    'by_type', (select jsonb_object_agg(coalesce(result_type, 'none'), n) from (select result_type, count(*) n from calc group by 1) z),
    'changed', (select count(*) from set_type), 'reason_updated', (select count(*) from set_reason), 'at', now())
  into v_out;
  return v_out;
end $$;
revoke all on function security.provider_type_classify_v1() from public, anon, authenticated;

create or replace function public.svc_provider_type_classify()
returns jsonb language plpgsql security definer set search_path to '' as $$
begin
  if current_user <> 'postgres' and coalesce(auth.role(), '') <> 'service_role' then raise exception 'service_role required'; end if;
  return security.provider_type_classify_v1();
end $$;
revoke all on function public.svc_provider_type_classify() from public, anon, authenticated;
grant execute on function public.svc_provider_type_classify() to service_role;

-- 5. Facts writer. Rows: [{"codes": ["00025B", ...], "facts": {"teqsa_category": "...", ...}}]. Providers are found by their
-- registration code in the given scheme (CRICOS), else by stable key.
create or replace function security.provider_register_fact_put_v1(p_provider_id uuid, p_fact_code text, p_value text, p_source_id uuid, p_evidence_id uuid)
returns void language sql security definer set search_path to '' as $$
  insert into catalogue.provider_register_facts (provider_id, fact_code, value, source_id, evidence_id, observed_at)
  values (p_provider_id, p_fact_code, nullif(btrim(p_value), ''), p_source_id, p_evidence_id, now())
  on conflict (provider_id, fact_code) do update set value = excluded.value, source_id = excluded.source_id,
    evidence_id = coalesce(excluded.evidence_id, catalogue.provider_register_facts.evidence_id), observed_at = now()
$$;
revoke all on function security.provider_register_fact_put_v1(uuid, text, text, uuid, uuid) from public, anon, authenticated;

create or replace function public.svc_provider_register_facts_put(p_source_id uuid, p_evidence_id uuid, p_scheme text, p_rows jsonb)
returns jsonb language plpgsql security definer set search_path to '' as $$
declare r jsonb; c text; k text; v_pid uuid; v_rows int := 0; v_matched int := 0; v_unmatched int := 0; v_facts int := 0; v_seen uuid[] := '{}';
begin
  if current_user <> 'postgres' and coalesce(auth.role(), '') <> 'service_role' then raise exception 'service_role required'; end if;
  for r in select value from jsonb_array_elements(coalesce(p_rows, '[]'::jsonb)) loop
    v_rows := v_rows + 1;
    for c in select upper(btrim(x)) from jsonb_array_elements_text(coalesce(r->'codes', '[]'::jsonb)) x loop
      select pr.provider_id into v_pid from catalogue.provider_registrations pr
       where lower(pr.registration_scheme) = lower(p_scheme) and upper(pr.registration_code) = c
       order by pr.checked_at desc nulls last limit 1;
      if v_pid is null then
        select p.id into v_pid from catalogue.providers p where p.stable_key = 'provider:' || lower(p_scheme) || ':' || lower(c) limit 1;
      end if;
      if v_pid is null then v_unmatched := v_unmatched + 1; continue; end if;
      if not (v_pid = any(v_seen)) then v_matched := v_matched + 1; v_seen := v_seen || v_pid; end if;
      for k in select jsonb_object_keys(coalesce(r->'facts', '{}'::jsonb)) loop
        perform security.provider_register_fact_put_v1(v_pid, k, r->'facts'->>k, p_source_id, p_evidence_id);
        v_facts := v_facts + 1;
      end loop;
      v_pid := null;
    end loop;
  end loop;
  return jsonb_build_object('rows', v_rows, 'providers_matched', v_matched, 'codes_unmatched', v_unmatched, 'facts_written', v_facts);
end $$;
revoke all on function public.svc_provider_register_facts_put(uuid, uuid, text, jsonb) from public, anon, authenticated;
grant execute on function public.svc_provider_register_facts_put(uuid, uuid, text, jsonb) to service_role;

-- 6. NZQA organisation type kept by the register applier (md5-guarded)
do $d$
declare v text; n text;
begin
  v := pg_get_functiondef('public.svc_layer1_apply_register_records'::regproc);
  if md5(v) <> '081d6a57499f286217d663628784bb64' then raise exception 'svc_layer1_apply_register_records changed since the check'; end if;
  n := replace(v, $o$postcode=coalesce(postcode,v_postcode),updated_at=now() where id=v_provider;$o$,
                  $o$postcode=coalesce(postcode,v_postcode),updated_at=now() where id=v_provider;
    if nullif(trim(r->>'provider_type'),'') is not null then perform security.provider_register_fact_put_v1(v_provider, v_scheme||'_org_type', trim(r->>'provider_type'), p_source_id, p_evidence_id); end if;$o$);
  if n = v then raise exception 'applier anchor not found'; end if;
  execute n;
end $d$;

-- 7. Layer 1 sources, read through data.gov.au by layer1-provider-facts
insert into pipeline.sources (source_type, country_id, url, label, trust_rank, status, metadata)
select 'dataset', c.id, x.url, x.label, 100, 'active', x.meta
from ref.countries c, (values
  ('https://data.gov.au/data/dataset/0c4f6591-2aea-4797-a127-ae8f8a0be0e2', 'TEQSA National Register: provider categories',
   jsonb_build_object('source_system', 'PROVIDER_FACTS', 'publisher', 'TEQSA', 'layer', '1', 'operational_surface', 'layer1_register',
     'discovery_url', 'https://data.gov.au/data/api/3/action/package_show?id=0c4f6591-2aea-4797-a127-ae8f8a0be0e2',
     'resource_url_regex', 'providers_[0-9]{8}[.]csv$', 'key_column', 'CRICOS Registration', 'key_pattern', '[0-9]{5}[A-Za-z]', 'scheme', 'cricos',
     'facts', jsonb_build_object('teqsa_category', 'Category', 'teqsa_status', 'RegistrationStatus', 'teqsa_provider_id', 'ProviderID'),
     'licence', 'Creative Commons Attribution 2.5 Australia', 'decision', 'Decision 258')),
  ('https://data.gov.au/data/dataset/cricos', 'CRICOS Institutions: institution type',
   jsonb_build_object('source_system', 'PROVIDER_FACTS', 'publisher', 'Department of Education', 'layer', '1', 'operational_surface', 'layer1_register',
     'discovery_url', 'https://data.gov.au/data/api/3/action/package_show?id=cricos',
     'resource_name_regex', '^CRICOS Institutions[.]csv$', 'key_column', 'CRICOS Provider Code', 'key_pattern', '[0-9]{5}[A-Za-z]', 'scheme', 'cricos',
     'facts', jsonb_build_object('cricos_institution_type', 'Institution Type'),
     'licence', 'Creative Commons Attribution 4.0', 'decision', 'Decision 258'))
) x(url, label, meta)
where trim(c.iso_alpha2::text) = 'AU'
  and not exists (select 1 from pipeline.sources s where s.metadata->>'source_system' = 'PROVIDER_FACTS' and s.label = x.label);

insert into pipeline.layer1_source_operations (source_id, authority_name, authority_domains, expected_format, expected_count_kind, active, paused,
  verification_cadence_days, ingestion_cadence_days, auto_ingest, change_reason, next_verification_at)
select s.id, case when s.metadata->>'publisher' = 'TEQSA' then 'Tertiary Education Quality and Standards Agency (TEQSA) on data.gov.au' else 'Department of Education (CRICOS) on data.gov.au' end,
  array['data.gov.au'], 'CSV resource on data.gov.au, found through its CKAN package', 'providers', true, true, 7, 7, false,
  'Decision 258: institution type from the registers (Platform Admin, 14 Oct 2026). Paused until its reader is deployed', now()
from pipeline.sources s
where s.metadata->>'source_system' = 'PROVIDER_FACTS'
  and not exists (select 1 from pipeline.layer1_source_operations o where o.source_id = s.id);

insert into pipeline.pilot_nonce_functions (function_name, note)
select 'layer1-provider-facts', 'Decision 258: provider register facts reader (TEQSA, CRICOS Institutions)'
where not exists (select 1 from pipeline.pilot_nonce_functions where function_name = 'layer1-provider-facts');

-- Daily classification job (G1 catalogued). No number in the command.
select cron.schedule('provider-type-classify', '47 3 * * *', 'select public.svc_provider_type_classify()');
insert into pipeline.automation_catalogue (jobname, area, sort, label, description, control_rank, batch_editable)
select 'provider-type-classify', 'Layer 1 register', 60, 'Institution type',
  'Every day: sets each provider''s institution type from the register facts with the rules on Settings > Pipeline settings. A type set by a person is kept.', 6, false
where not exists (select 1 from pipeline.automation_catalogue where jobname = 'provider-type-classify');

-- 8. Screens
create or replace function public.admin_provider_set_type(p_provider_id uuid, p_type_code text)
returns jsonb language plpgsql security definer set search_path to '' as $$
declare v_before uuid; v_type uuid; v_code text := nullif(btrim(coalesce(p_type_code, '')), '');
begin
  if auth.uid() is null or coalesce(security.current_role_rank(), 0) < 5 then raise exception 'PIM Admin role or above required' using errcode = '42501'; end if;
  select provider_type_id into v_before from catalogue.providers where id = p_provider_id;
  if not found then raise exception 'provider not found'; end if;
  if v_code is null or v_code = 'auto' then
    delete from pipeline.manual_locks where entity = 'provider' and entity_id = p_provider_id and field = 'provider_type_id';
    insert into pipeline.manual_edit_log(entity, entity_id, field, action, before, after, reason, actor)
    values ('provider', p_provider_id, 'provider_type_id', 'unlock', to_jsonb(v_before), null, 'type from the register rules', auth.uid());
    perform security.provider_type_classify_v1();
  else
    select id into v_type from ref.provider_types where code = v_code and status = 'active';
    if v_type is null then raise exception 'unknown institution type %', v_code; end if;
    perform set_config('cf.manual_edit', 'on', true);
    update catalogue.providers set provider_type_id = v_type, provider_type_basis = 'Set by a person', provider_type_set_at = now(), updated_at = now() where id = p_provider_id;
    insert into pipeline.manual_locks(entity, entity_id, field, mode, set_by) values ('provider', p_provider_id, 'provider_type_id', 'value', auth.uid())
      on conflict (entity, entity_id, field) do update set set_by = excluded.set_by, set_at = now();
    insert into pipeline.manual_edit_log(entity, entity_id, field, action, before, after, reason, actor)
    values ('provider', p_provider_id, 'provider_type_id', 'set', to_jsonb(v_before), to_jsonb(v_type), null, auth.uid());
  end if;
  return (select jsonb_build_object('provider_id', p.id, 'provider_type_code', t.code, 'provider_type_name', t.name, 'provider_type_basis', p.provider_type_basis,
            'provider_type_locked', exists (select 1 from pipeline.manual_locks l where l.entity = 'provider' and l.entity_id = p.id and l.field = 'provider_type_id'))
          from catalogue.providers p left join ref.provider_types t on t.id = p.provider_type_id where p.id = p_provider_id);
end $$;
revoke all on function public.admin_provider_set_type(uuid, text) from public, anon;
grant execute on function public.admin_provider_set_type(uuid, text) to authenticated;

create or replace function public.admin_provider_type_rules(p_action text, p_args jsonb default '{}'::jsonb)
returns jsonb language plpgsql security definer set search_path to '' as $$
declare v_id uuid; v_before jsonb;
begin
  if auth.uid() is null or coalesce(security.current_role_rank(), 0) < 1 then raise exception 'assigned StudySearch role required' using errcode = '42501'; end if;
  if p_action = 'list' then
    return jsonb_build_object(
      'rules', coalesce((select jsonb_agg(to_jsonb(r) order by r.position) from pipeline.provider_type_rules r), '[]'::jsonb),
      'types', coalesce((select jsonb_agg(jsonb_build_object('code', t.code, 'name', t.name, 'description', t.description) order by t.name) from ref.provider_types t where t.status = 'active'), '[]'::jsonb),
      'counts', coalesce((select jsonb_object_agg(coalesce(t.code, 'none'), n) from (select pr.provider_type_id, count(*) n from catalogue.providers pr group by 1) z left join ref.provider_types t on t.id = z.provider_type_id), '{}'::jsonb),
      'can_edit', coalesce(security.current_role_rank(), 0) >= 6);
  elsif p_action = 'save' then
    if coalesce(security.current_role_rank(), 0) < 6 then raise exception 'Platform Admin role required' using errcode = '42501'; end if;
    v_id := (p_args->>'id')::uuid;
    select to_jsonb(r) into v_before from pipeline.provider_type_rules r where r.id = v_id;
    if v_before is null then raise exception 'rule not found'; end if;
    if p_args ? 'result_type' and not exists (select 1 from ref.provider_types t where t.code = p_args->>'result_type' and t.status = 'active') then raise exception 'unknown institution type'; end if;
    update pipeline.provider_type_rules set
      result_type = coalesce(p_args->>'result_type', result_type),
      enabled = coalesce((p_args->>'enabled')::boolean, enabled),
      position = coalesce((p_args->>'position')::int, position),
      updated_at = now(), updated_by = auth.uid()
    where id = v_id;
    insert into pipeline.manual_edit_log(entity, entity_id, field, action, before, after, reason, actor)
    values ('provider', v_id, 'provider_type_rule', 'rule_change', v_before, (select to_jsonb(r) from pipeline.provider_type_rules r where r.id = v_id), nullif(p_args->>'reason', ''), auth.uid());
    return jsonb_build_object('saved', true, 'classify', security.provider_type_classify_v1());
  elsif p_action = 'run' then
    if coalesce(security.current_role_rank(), 0) < 6 then raise exception 'Platform Admin role required' using errcode = '42501'; end if;
    return security.provider_type_classify_v1();
  end if;
  raise exception 'unknown action %', p_action;
end $$;
revoke all on function public.admin_provider_type_rules(text, jsonb) from public, anon;
grant execute on function public.admin_provider_type_rules(text, jsonb) to authenticated;

-- Providers list: type, basis, lock (md5-guarded)
do $d$
declare v text; n text;
begin
  v := pg_get_functiondef('security.admin_providers_page'::regproc);
  if md5(v) <> '4d07ec592074c421890c82c0552c52f2' then raise exception 'admin_providers_page changed since the check'; end if;
  n := replace(v, $o$p.last_verified_at,p.created_at,p.updated_at,$o$,
                  $o$p.last_verified_at,p.created_at,p.updated_at,
        (select pt.code from ref.provider_types pt where pt.id=p.provider_type_id) provider_type_code,
        (select pt.name from ref.provider_types pt where pt.id=p.provider_type_id) provider_type_name,
        p.provider_type_basis,
        exists (select 1 from pipeline.manual_locks ml where ml.entity='provider' and ml.entity_id=p.id and ml.field='provider_type_id') provider_type_locked,$o$);
  n := replace(n, $o$case when v_sort='courses' and v_dir='asc' then course_count end asc,$o$,
                  $o$case when v_sort='type' and v_dir='asc' then coalesce(provider_type_name,'~') end asc,
        case when v_sort='type' and v_dir='desc' then coalesce(provider_type_name,'') end desc,
        case when v_sort='courses' and v_dir='asc' then course_count end asc,$o$);
  if (length(n) - length(v)) < 400 then raise exception 'providers page anchors not found'; end if;
  execute n;
end $d$;

-- 9. Website API v2: institution type
create or replace function api.website_v2_institution_type(p_provider_id uuid)
returns jsonb language sql stable security definer set search_path to '' as $$
  select jsonb_build_object('code', t.code, 'name', t.name, 'basis', p.provider_type_basis)
  from catalogue.providers p join ref.provider_types t on t.id = p.provider_type_id where p.id = p_provider_id
$$;
create or replace function api.website_v2_institution_type_code(p_provider_id uuid)
returns text language sql stable security definer set search_path to '' as $$
  select t.code from catalogue.providers p join ref.provider_types t on t.id = p.provider_type_id where p.id = p_provider_id
$$;
revoke all on function api.website_v2_institution_type(uuid) from public;
revoke all on function api.website_v2_institution_type_code(uuid) from public;

do $d$
declare v text; n text;
begin
  -- course item: provider.institution_type
  v := pg_get_functiondef('api.website_v2_course_item(uuid,text[],text[])'::regprocedure);
  if md5(v) <> 'c9fcc242bd5b5d411a51443f95e1d779' then raise exception 'website_v2_course_item changed since the check'; end if;
  n := replace(v, $o$'legal_name', d.provider_name,$o$, $o$'legal_name', d.provider_name, 'institution_type', api.website_v2_institution_type(d.provider_id),$o$);
  if n = v then raise exception 'course item anchor not found'; end if;
  execute n;

  -- course search: institution_types filter
  v := pg_get_functiondef('public.website_v2_course_search(jsonb,integer,integer,text)'::regprocedure);
  if md5(v) <> '19b602f54ae10b932f1515c55c45d14f' then raise exception 'website_v2_course_search changed since the check'; end if;
  n := replace(v, $o$'has_tuition','changed_since'];$o$, $o$'has_tuition','changed_since','institution_types'];$o$);
  if n = v then raise exception 'course search known-list anchor not found'; end if;
  v := n;
  n := replace(n, $o$and (v_groups is null or exists$o$,
                  $o$and (f->'institution_types' is null or api.website_v2_institution_type_code(d.provider_id) = any(api.website_text_array(f->'institution_types')))
      and (v_groups is null or exists$o$);
  if n = v then raise exception 'course search filter anchor not found'; end if;
  execute n;

  -- providers: institution_type field and filter
  v := pg_get_functiondef('public.website_v2_providers(jsonb,integer,integer,text)'::regprocedure);
  if md5(v) <> '2d4d19097c34cde01897d44e7a27e8f1' then raise exception 'website_v2_providers changed since the check'; end if;
  n := replace(v, $o$'legal_name', o.provider_name,$o$, $o$'legal_name', o.provider_name, 'institution_type', api.website_v2_institution_type(o.provider_id),$o$);
  if n = v then raise exception 'providers field anchor not found'; end if;
  v := n;
  n := replace(n, $o$'has_logo','provider_ids'];$o$, $o$'has_logo','provider_ids','institution_types'];$o$);
  if n = v then raise exception 'providers known-list anchor not found'; end if;
  v := n;
  n := replace(n, $o$and (v_groups is null or exists$o$,
                  $o$and (f->'institution_types' is null or api.website_v2_institution_type_code(a.provider_id) = any(api.website_text_array(f->'institution_types')))
      and (v_groups is null or exists$o$);
  if n = v then raise exception 'providers filter anchor not found'; end if;
  execute n;

  -- reference: institution_types list with provider counts
  v := pg_get_functiondef('public.website_v2_reference()'::regprocedure);
  if md5(v) <> '0204f4336ec28dff7e6bd6af6a5fd701' then raise exception 'website_v2_reference changed since the check'; end if;
  n := replace(v, $o$'university_groups', (select jsonb_agg$o$,
                  $o$'institution_types', (select jsonb_agg(jsonb_build_object('code', t.code, 'name', t.name, 'description', t.description,
                             'providers', (select count(*) from catalogue.providers p where p.provider_type_id = t.id and p.publication_status = 'published' and p.lifecycle_status = 'active')) order by t.name)
                           from ref.provider_types t where t.status = 'active'),
    'university_groups', (select jsonb_agg$o$);
  if n = v then raise exception 'reference anchor not found'; end if;
  execute n;
end $d$;

-- First classification with the facts already held (the register reads add the rest)
select security.provider_type_classify_v1();
