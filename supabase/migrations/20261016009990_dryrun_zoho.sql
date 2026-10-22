-- CF-247 (22 Oct 2026). Platform Admin 19:53, Canadian inactive courses: "Investigate first, then decide (Recommended)". Findings given at
-- 20:05: the 5,615 inactive Canadian courses were retired on purpose by the 18 Aug scope ca-intl-bachelor-plus-v1 (bachelor and above
-- only, level from the source); but the 8 Oct re-read of 15 college catalogues made 2,121 college courses active with a level below
-- bachelor or no level at all, and they are on the website. Platform Admin choice: "Widen to colleges, level required (Recommended)":
-- diplomas, certificates and graduate certificates count, but only with a level the source gives; anything without a level stays hidden.
-- The college catalogues name no credential, so the level is read from the course's own page ("Credential: Ontario College Diploma",
-- "Designation: Ontario College Advanced Diploma", "Credential: Diploma", French "Diplome d'etudes collegiales de l'Ontario").
-- 1 pipeline.credential_rules (what to look for on a page: a labelled credential, or an Ontario credential name) and
--   pipeline.credential_level_map (credential wording to study level), both by country and edited as data.
-- 2 Job credential-read (worker mode credential_read): reads the stored course page of each Canadian course without a level (no fetch, no
--   AI). A labelled credential decides; otherwise an Ontario credential name decides when the page names only one level. The finding is
--   kept as a study level observation (scheme provider_page) and the course takes the level when it has none (a level given by a
--   register is never replaced; manual locks are kept).
-- 3 pipeline.country_scope_levels: the levels in scope per country (scope ca-intl-college-plus-v2). Job country-scope-gate (hourly):
--   hides active Canadian courses whose level is missing or out of scope, once their page has been read for a credential (or they have
--   no read page); shows inactive ones whose level is in scope at a DLI provider when their page was read in the last
--   country_scope.page_fresh_days days and nothing else retired them (Layer 1 departures, a person, Not offered). Every change is logged
--   in pipeline.course_scope_changes with the rule that made it, so it can be reversed.
-- 4 public.svc_layer1_apply_course_scope no longer retires a course whose level is in its country's scope (the EducationPlannerBC and
--   ALIS readers would otherwise retire the colleges' diplomas again on each run).
-- Replaces: the Canadian Layer 1 scope ca-intl-bachelor-plus-v1 (18 Aug 2026) by ca-intl-college-plus-v2 for which levels are shown;
--   public.svc_layer1_apply_course_scope (md5-guarded edit: in-scope levels are not retired)
-- Retires: nothing (pipeline.ca_course_scope_keys stays the record of the register's bachelor-plus keys)

-- settings ---------------------------------------------------------------------------------------------------------------------------
insert into pipeline.platform_toolset_settings(toolset_key, key, label, help, kind, value, min_value, max_value, unit, sort, reason, section, used_by) values
 ('pipeline', 'batch.credential_read', 'Course pages read for a credential per run', 'Each run of the credential-read job reads this many stored course pages for the credential they state (no fetch, no AI).', 'number', to_jsonb(100), 1, 200, 'pages', 330, 'CF-247 22 Oct 2026 (Canadian colleges: level required)', 'Enrichment', 'job credential-read; coverage-sweep credential_read'),
 ('pipeline', 'country_scope.page_fresh_days', 'Course shown again only with a page read within', 'An inactive course whose level is now in scope is shown again only when its own page was read in this many days (proof it is still offered).', 'number', to_jsonb(180), 7, 730, 'days', 331, 'CF-247 22 Oct 2026 (Canadian colleges: level required)', 'Enrichment', 'security.country_scope_gate_v1'),
 ('pipeline', 'batch.country_scope_gate', 'Courses hidden or shown per scope run', 'The country-scope-gate job changes at most this many courses each run, hidden first.', 'number', to_jsonb(1000), 10, 10000, 'courses', 332, 'CF-247 22 Oct 2026 (Canadian colleges: level required)', 'Enrichment', 'security.country_scope_gate_v1')
on conflict do nothing;

-- 1 rules ----------------------------------------------------------------------------------------------------------------------------
create table if not exists pipeline.credential_rules (
  id bigserial primary key,
  country_code text not null,
  kind text not null check (kind in ('labelled', 'phrase')),
  regex text not null,
  note text,
  enabled boolean not null default true,
  created_at timestamptz not null default now()
);
comment on table pipeline.credential_rules is 'CF-247 22 Oct 2026: what the credential-read job looks for on a stored course page, by country. regex is a JavaScript regular expression read case-insensitively; capture group 1 is the credential. kind labelled (after a label such as Credential or Designation) decides on its own; kind phrase (an official credential name) decides only when the page names one level.';

create table if not exists pipeline.credential_level_map (
  id bigserial primary key,
  country_code text not null,
  sort int not null,
  match_regex text not null,
  study_level_code text references ref.study_levels(code),
  note text,
  unique (country_code, sort)
);
comment on table pipeline.credential_level_map is 'CF-247 22 Oct 2026: credential wording to study level, by country; the first row (by sort) whose match_regex (PostgreSQL, case-insensitive) matches the credential decides. A null level means the wording names no level (for example a bare "degree").';

create table if not exists pipeline.country_scope_levels (
  country_code text not null,
  study_level_code text not null references ref.study_levels(code),
  scope_tag text not null,
  decided text not null,
  primary key (country_code, study_level_code)
);
comment on table pipeline.country_scope_levels is 'CF-247 22 Oct 2026: the study levels shown per country (a course of another level, or with no level, is hidden by job country-scope-gate). Canada: scope ca-intl-college-plus-v2, Platform Admin 22 Oct 2026 "Widen to colleges, level required".';

create table if not exists pipeline.course_credential_reads (
  course_id uuid primary key references catalogue.courses(id),
  evidence_id uuid,
  outcome text not null check (outcome in ('leased', 'level', 'ambiguous', 'none', 'failed')),
  study_level_code text,
  basis text,
  found jsonb not null default '[]'::jsonb,
  leased_until timestamptz,
  attempts int not null default 0,
  read_at timestamptz,
  applied boolean not null default false
);
comment on table pipeline.course_credential_reads is 'CF-247 22 Oct 2026: the credential-read result for each course page read (evidence), with what was found and the level it gave; a page read again (new evidence) is read again.';

create table if not exists pipeline.course_scope_changes (
  id bigserial primary key,
  course_id uuid not null references catalogue.courses(id),
  at timestamptz not null default now(),
  from_status text not null, to_status text not null,
  scope_tag text not null, rule text not null,
  study_level_code text
);
create index if not exists course_scope_changes_course_idx on pipeline.course_scope_changes(course_id, at desc);
comment on table pipeline.course_scope_changes is 'CF-247 22 Oct 2026: every course hidden or shown by the country scope gate, with the scope and rule, so a change can be reversed.';

insert into pipeline.credential_rules(country_code, kind, regex, note) values
 ('CA', 'labelled', $r$(?:credentials?(?:\s+awarded|\s+type|\s+earned)?|designation|program\s+credential|sanction\s+des\s+[ée]tudes|titre\s+de\s+comp[ée]tence|dipl[ôo]me\s+obtenu)\s*[:\-–]?\s*((?:ontario\s+college\s+)?(?:advanced\s+diploma|graduate\s+certificate|diploma|certificate)|honours\s+bachelor(?:['’]s)?(?:\s+(?:of|degree)[^.;,|]{0,50})?|bachelor(?:['’]s)?\s+(?:of|degree)[^.;,|]{0,50}|post-?\s?graduate\s+(?:certificate|diploma)|graduate\s+(?:certificate|diploma)|associate\s+degree|master(?:['’]s)?\s+(?:of|degree)[^.;,|]{0,40}|dipl[ôo]me\s+d['’][ée]tudes\s+coll[ée]giales(?:\s+de\s+l['’]ontario)?(?:\s*[-–]\s*niveau\s+avanc[ée])?|certificat\s+d['’][ée]tudes\s+(?:coll[ée]giales|sup[ée]rieures)(?:\s+de\s+l['’]ontario)?|attestation\s+d['’][ée]tudes\s+coll[ée]giales)$r$,
  'A credential after its label (Credential, Credential awarded, Designation, Sanction des études, Titre de compétence)'),
 ('CA', 'phrase', $r$\b(ontario\s+college\s+(?:advanced\s+diploma|graduate\s+certificate|diploma|certificate)|dipl[ôo]me\s+d['’][ée]tudes\s+coll[ée]giales\s+de\s+l['’]ontario(?:\s*[-–]\s*niveau\s+avanc[ée])?|certificat\s+d['’][ée]tudes\s+(?:coll[ée]giales|sup[ée]rieures)\s+de\s+l['’]ontario)\b$r$,
  'Ontario credential names (English and French); used only when the page names one level')
on conflict do nothing;

insert into pipeline.credential_level_map(country_code, sort, match_regex, study_level_code, note) values
 ('CA', 10, 'advanced diploma|niveau avanc', 'advanced_diploma', null),
 ('CA', 20, '(post-?\s?graduate|graduate) diploma', 'graduate_diploma', null),
 ('CA', 30, '(post-?\s?graduate|graduate) certificate|certificat d.[ée]tudes sup[ée]rieures', 'graduate_certificate', null),
 ('CA', 40, 'honours bachelor|bachelor.*honours', 'bachelor_honours', null),
 ('CA', 50, 'bachelor', 'bachelor', null),
 ('CA', 60, 'master', 'masters', null),
 ('CA', 70, 'associate degree', 'associate_degree', null),
 ('CA', 80, 'diploma|dipl[ôo]me d.[ée]tudes coll[ée]giales', 'diploma', null),
 ('CA', 90, 'certificate|certificat d.[ée]tudes coll[ée]giales|attestation d.[ée]tudes', 'certificate', null)
on conflict do nothing;

insert into pipeline.country_scope_levels(country_code, study_level_code, scope_tag, decided) values
 ('CA', 'bachelor', 'ca-intl-college-plus-v2', 'Platform Admin 22 Oct 2026'), ('CA', 'bachelor_honours', 'ca-intl-college-plus-v2', 'Platform Admin 22 Oct 2026'),
 ('CA', 'masters', 'ca-intl-college-plus-v2', 'Platform Admin 22 Oct 2026'), ('CA', 'masters_coursework', 'ca-intl-college-plus-v2', 'Platform Admin 22 Oct 2026'),
 ('CA', 'masters_research', 'ca-intl-college-plus-v2', 'Platform Admin 22 Oct 2026'), ('CA', 'masters_extended', 'ca-intl-college-plus-v2', 'Platform Admin 22 Oct 2026'),
 ('CA', 'doctorate', 'ca-intl-college-plus-v2', 'Platform Admin 22 Oct 2026'), ('CA', 'professional_degree', 'ca-intl-college-plus-v2', 'Platform Admin 22 Oct 2026'),
 ('CA', 'graduate_certificate', 'ca-intl-college-plus-v2', 'Platform Admin 22 Oct 2026'), ('CA', 'graduate_diploma', 'ca-intl-college-plus-v2', 'Platform Admin 22 Oct 2026'),
 ('CA', 'advanced_diploma', 'ca-intl-college-plus-v2', 'Platform Admin 22 Oct 2026'), ('CA', 'diploma', 'ca-intl-college-plus-v2', 'Platform Admin 22 Oct 2026'),
 ('CA', 'certificate', 'ca-intl-college-plus-v2', 'Platform Admin 22 Oct 2026'), ('CA', 'associate_degree', 'ca-intl-college-plus-v2', 'Platform Admin 22 Oct 2026')
on conflict do nothing;

-- helpers ----------------------------------------------------------------------------------------------------------------------------
create or replace function security.credential_level_v1(p_country text, p_text text)
returns text language sql stable security definer set search_path = '' as $function$
  select m.study_level_code from pipeline.credential_level_map m where m.country_code = p_country and p_text ~* m.match_regex order by m.sort limit 1  -- fixed: the first matching wording decides
$function$;
revoke all on function security.credential_level_v1(text, text) from public, anon, authenticated;

create or replace function security.course_in_country_scope_v1(p_course_id uuid)
returns boolean language sql stable security definer set search_path = '' as $function$
  select exists (select 1 from catalogue.courses c join ref.study_levels sl on sl.id = c.study_level_id
                   join pipeline.country_scope_levels s on s.study_level_code = sl.code and s.country_code = security.coverage_country(c.provider_id)
                  where c.id = p_course_id)
$function$;
revoke all on function security.course_in_country_scope_v1(uuid) from public, anon, authenticated;

-- 2 credential read ------------------------------------------------------------------------------------------------------------------
create or replace function public.svc_credential_next(p_limit integer default 50)
returns jsonb language plpgsql security definer set search_path = '' as $function$
declare v jsonb;
begin
  if current_user <> 'postgres' and coalesce(auth.role(), '') <> 'service_role' then raise exception 'service_role required'; end if;
  with pick as (
    select c.id course_id, pg.evidence_id, e.storage_path
      from catalogue.courses c
      join pipeline.coverage_course_pages pg on pg.course_id = c.id and pg.read_status = 'read' and pg.evidence_id is not null
      join pipeline.evidence_artifacts e on e.id = pg.evidence_id and e.storage_path is not null
      left join pipeline.course_credential_reads r on r.course_id = c.id
     where c.study_level_id is null and c.lifecycle_status in ('active', 'inactive')
       and security.coverage_country(c.provider_id) in (select distinct x.country_code from pipeline.credential_rules x where x.enabled)
       and (r.course_id is null or (r.evidence_id is distinct from pg.evidence_id and (r.outcome <> 'leased' or r.leased_until < now()))
            or (r.outcome = 'leased' and r.leased_until < now()))
     order by (c.lifecycle_status = 'active') desc, pg.read_at desc
     limit greatest(1, least(coalesce(p_limit, 50), 200))  -- fixed: per-call safety cap; the run size is batch.credential_read
     for update of c skip locked),
  lease as (insert into pipeline.course_credential_reads as r (course_id, evidence_id, outcome, leased_until, attempts)
            select p.course_id, p.evidence_id, 'leased', now() + interval '10 minutes', 1 from pick p  -- fixed: lease for one call
            on conflict (course_id) do update set evidence_id = excluded.evidence_id, outcome = 'leased', leased_until = excluded.leased_until, attempts = r.attempts + 1
            returning r.course_id)
  select jsonb_build_object(
    'rows', (select coalesce(jsonb_agg(jsonb_build_object('course_id', p.course_id, 'evidence_id', p.evidence_id, 'storage_path', p.storage_path)), '[]'::jsonb) from pick p where p.course_id in (select course_id from lease)),
    'rules', (select coalesce(jsonb_agg(jsonb_build_object('id', x.id, 'kind', x.kind, 'regex', x.regex) order by x.kind, x.id), '[]'::jsonb) from pipeline.credential_rules x where x.enabled))
    into v;
  return v;
end $function$;
revoke all on function public.svc_credential_next(integer) from public, anon, authenticated;
grant execute on function public.svc_credential_next(integer) to service_role;

create or replace function public.svc_credential_record(p_course_id uuid, p_evidence_id uuid, p_found jsonb)
returns jsonb language plpgsql security definer set search_path = '' as $function$
declare v_country text; v_levels text[]; v_basis text; v_level text; v_outcome text; v_ev record; v_text text; v_applied boolean := false;
begin
  if current_user <> 'postgres' and coalesce(auth.role(), '') <> 'service_role' then raise exception 'service_role required'; end if;
  select security.coverage_country(c.provider_id) into v_country from catalogue.courses c where c.id = p_course_id;
  if p_found is null then
    update pipeline.course_credential_reads set outcome = 'failed', leased_until = null, read_at = now() where course_id = p_course_id;
    return jsonb_build_object('outcome', 'failed');
  end if;
  -- a labelled credential decides; otherwise the official credential names decide when they give one level
  select array_agg(distinct security.credential_level_v1(v_country, f->>'text')) filter (where security.credential_level_v1(v_country, f->>'text') is not null)
    into v_levels from jsonb_array_elements(p_found) f where f->>'kind' = 'labelled';
  v_basis := 'labelled';
  if coalesce(cardinality(v_levels), 0) = 0 then
    select array_agg(distinct security.credential_level_v1(v_country, f->>'text')) filter (where security.credential_level_v1(v_country, f->>'text') is not null)
      into v_levels from jsonb_array_elements(p_found) f where f->>'kind' = 'phrase';
    v_basis := 'phrase';
  end if;
  v_outcome := case when coalesce(cardinality(v_levels), 0) = 1 then 'level' when coalesce(cardinality(v_levels), 0) > 1 then 'ambiguous' else 'none' end;
  v_level := case when v_outcome = 'level' then v_levels[1] end;
  select (select f->>'text' from jsonb_array_elements(p_found) f where f->>'kind' = v_basis and security.credential_level_v1(v_country, f->>'text') is not null limit 1) into v_text;  -- fixed: the first credential found is kept as the quote
  update pipeline.course_credential_reads set outcome = v_outcome, study_level_code = v_level, basis = case when v_outcome = 'none' then null else v_basis end,
         found = p_found, leased_until = null, read_at = now(), evidence_id = p_evidence_id
   where course_id = p_course_id;
  if v_outcome in ('level', 'ambiguous') then
    select e.id, e.source_id, coalesce(e.captured_at, e.created_at) at, coalesce(e.content_hash, md5(e.id::text)) h into v_ev from pipeline.evidence_artifacts e where e.id = p_evidence_id;
    if v_ev.source_id is not null then
      insert into catalogue.course_study_level_observations(course_id, study_level_id, source_id, evidence_id, scheme, registration_code, source_value, mapping_status, source_snapshot_at, content_hash)
      values (p_course_id, (select sl.id from ref.study_levels sl where sl.code = v_level), v_ev.source_id, v_ev.id, 'provider_page', v_basis,
              left(coalesce(v_text, (select string_agg(f->>'text', ' | ') from jsonb_array_elements(p_found) f)), 300),
              case when v_outcome = 'level' then 'mapped' else 'review_required' end, v_ev.at, v_ev.h)
      on conflict (course_id, source_id, scheme, registration_code, source_snapshot_at) do nothing;
    end if;
  end if;
  if v_outcome = 'level' then
    update catalogue.courses c set study_level_id = (select sl.id from ref.study_levels sl where sl.code = v_level), updated_at = now()
     where c.id = p_course_id and c.study_level_id is null
       and not exists (select 1 from pipeline.manual_locks l where l.entity = 'course' and l.entity_id = c.id and l.field = 'study_level_id');
    v_applied := found;
    update pipeline.course_credential_reads set applied = v_applied where course_id = p_course_id;
  end if;
  return jsonb_build_object('outcome', v_outcome, 'level', v_level, 'applied', v_applied);
end $function$;
revoke all on function public.svc_credential_record(uuid, uuid, jsonb) from public, anon, authenticated;
grant execute on function public.svc_credential_record(uuid, uuid, jsonb) to service_role;

-- 3 scope gate -----------------------------------------------------------------------------------------------------------------------
create or replace function security.country_scope_gate_v1(p_apply boolean default true, p_country text default 'CA')
returns jsonb language plpgsql security definer set search_path = '' set statement_timeout to '120s' as $function$
declare
  v_tag text := (select max(s.scope_tag) from pipeline.country_scope_levels s where s.country_code = p_country);
  v_cap int := security.pipeline_num_v1('batch.country_scope_gate', 1000)::int;
  v_fresh interval := make_interval(days => security.pipeline_num_v1('country_scope.page_fresh_days', 180)::int);
  v_hide int := 0; v_show int := 0; v_hide_n int; v_show_n int;
begin
  if v_tag is null then return jsonb_build_object('country', p_country, 'note', 'no scope levels for this country'); end if;
  create temp table if not exists _scope_hide(course_id uuid, level text, rule text) on commit drop;
  create temp table if not exists _scope_show(course_id uuid, level text, rule text) on commit drop;
  truncate _scope_hide; truncate _scope_show;
  -- hide: active, level missing or out of scope, and not waiting for its page to be read for a credential
  insert into _scope_hide
  select c.id, sl.code, case when c.study_level_id is null then 'no_level' else 'level_out_of_scope' end
    from catalogue.courses c
    join catalogue.providers p on p.id = c.provider_id
    left join ref.study_levels sl on sl.id = c.study_level_id
   where c.lifecycle_status = 'active' and security.coverage_country(c.provider_id) = p_country
     and not exists (select 1 from pipeline.country_scope_levels s where s.country_code = p_country and s.study_level_code = sl.code)
     and not exists (select 1 from pipeline.manual_locks l where l.entity = 'course' and l.entity_id = c.id and l.field = 'lifecycle_status')
     and not exists (select 1 from pipeline.coverage_course_pages pg where pg.course_id = c.id and pg.read_status = 'read' and pg.evidence_id is not null
                       and not exists (select 1 from pipeline.course_credential_reads r where r.course_id = c.id and r.evidence_id = pg.evidence_id and r.outcome <> 'leased'));
  -- show: inactive, level in scope, provider a DLI, own page read recently, and nothing else retired it
  insert into _scope_show
  select c.id, sl.code, 'level_in_scope'
    from catalogue.courses c
    join catalogue.providers p on p.id = c.provider_id and p.enrols_international is true and coalesce(p.lifecycle_status, 'active') = 'active'
    join ref.study_levels sl on sl.id = c.study_level_id
    join pipeline.country_scope_levels s on s.country_code = p_country and s.study_level_code = sl.code
    join pipeline.coverage_course_pages pg on pg.course_id = c.id and pg.read_status = 'read' and pg.status = 'bound' and pg.read_at > now() - v_fresh
   where c.lifecycle_status = 'inactive' and security.coverage_country(c.provider_id) = p_country
     and not exists (select 1 from pipeline.manual_locks l where l.entity = 'course' and l.entity_id = c.id and l.field = 'lifecycle_status')
     and not exists (select 1 from pipeline.layer1_course_retirements r where r.course_id = c.id and r.reactivated_at is null)
     and not exists (select 1 from pipeline.enrichment_flags f where f.entity = 'course' and f.entity_key = c.id::text and f.state = 'raised' and f.reason_code = 'not_offered');
  select count(*) into v_hide_n from _scope_hide; select count(*) into v_show_n from _scope_show;
  if p_apply then
    with h as (select x.* from _scope_hide x order by x.course_id limit v_cap),
         u as (update catalogue.courses c set lifecycle_status = 'inactive', updated_at = now() from h where c.id = h.course_id and c.lifecycle_status = 'active' returning c.id, h.level, h.rule),
         l as (insert into pipeline.course_scope_changes(course_id, from_status, to_status, scope_tag, rule, study_level_code) select u.id, 'active', 'inactive', v_tag, u.rule, u.level from u returning 1)
    select count(*) into v_hide from l;
    with s as (select x.* from _scope_show x order by x.course_id limit greatest(0, v_cap - v_hide)),
         u as (update catalogue.courses c set lifecycle_status = 'active', updated_at = now() from s where c.id = s.course_id and c.lifecycle_status = 'inactive' returning c.id, s.level, s.rule),
         l as (insert into pipeline.course_scope_changes(course_id, from_status, to_status, scope_tag, rule, study_level_code) select u.id, 'inactive', 'active', v_tag, u.rule, u.level from u returning 1)
    select count(*) into v_show from l;
  end if;
  return jsonb_build_object('country', p_country, 'scope', v_tag, 'would_hide', v_hide_n, 'would_show', v_show_n, 'hidden', v_hide, 'shown', v_show, 'applied', p_apply,
    'hide_by_rule', (select coalesce(jsonb_object_agg(rule, n), '{}'::jsonb) from (select rule, count(*) n from _scope_hide group by 1) z),
    'show_by_level', (select coalesce(jsonb_object_agg(level, n), '{}'::jsonb) from (select level, count(*) n from _scope_show group by 1) z));
end $function$;
revoke all on function security.country_scope_gate_v1(boolean, text) from public, anon, authenticated;

-- 4 the Layer 1 scope apply keeps in-scope levels -------------------------------------------------------------------------------------
do $edit$
declare v_def text := pg_get_functiondef('public.svc_layer1_apply_course_scope(uuid,text,text)'::regprocedure);
        v_old text := $o$  UPDATE catalogue.courses c
     SET lifecycle_status = 'inactive',
         publication_status = 'unpublished',
         updated_at = now()
   WHERE c.canonical_source_id = p_source_id$o$;
begin
  if position('course_in_country_scope_v1' in v_def) > 0 then return; end if;
  if md5(v_def) <> 'c25496f235831a85b3a3efe00c9aee0d' then raise exception 'live public.svc_layer1_apply_course_scope differs from the definition this change edits'; end if;
  if (length(v_def) - length(replace(v_def, v_old, ''))) / length(v_old) <> 1 then raise exception 'retire statement must occur once'; end if;
  execute replace(v_def, v_old, v_old || $n$
     AND NOT security.course_in_country_scope_v1(c.id)  -- CF-247 22 Oct 2026: a level in the country's scope (ca-intl-college-plus-v2) is not retired$n$);
end $edit$;

-- 5 watchdog, jobs, register ---------------------------------------------------------------------------------------------------------
insert into pipeline.queue_watch(key, label, area, purpose, jobnames, tools, pending_sql, progress_sql, done_sql, failed_sql, exhausted_sql, exhausted_label, fix_at, sort) values
('credential_read', 'Credential from course pages', 'Enrichment', 'Reads the credential each Canadian college course page states, for its study level.',
 '{credential-read}', '{}',
 $q$select count(*) from catalogue.courses c join pipeline.coverage_course_pages pg on pg.course_id = c.id and pg.read_status = 'read' and pg.evidence_id is not null left join pipeline.course_credential_reads r on r.course_id = c.id where c.study_level_id is null and c.lifecycle_status in ('active', 'inactive') and security.coverage_country(c.provider_id) in (select distinct x.country_code from pipeline.credential_rules x where x.enabled) and (r.course_id is null or r.evidence_id is distinct from pg.evidence_id or (r.outcome = 'leased' and r.leased_until < now()))$q$,
 $q$select max(read_at) from pipeline.course_credential_reads$q$,
 $q$select count(*) from pipeline.course_credential_reads where read_at >= $1 and outcome <> 'failed'$q$,
 $q$select count(*) from pipeline.course_credential_reads where read_at >= $1 and outcome = 'failed'$q$,
 $q$select count(*) from pipeline.course_credential_reads where outcome in ('none', 'ambiguous') and not applied$q$,
 'Course pages that state no credential, or more than one level', '#layer-2-discovery?tab=operations', 150)
on conflict (key) do nothing;

insert into pipeline.automation_catalogue(jobname, area, sort, label, description, control_rank, batch_editable, layer23_stage) values
 ('credential-read', 'Enrichment', 50, 'Credential from course pages', 'Every 10 minutes while pages wait: reads the credential a Canadian college course page states (for example "Credential: Ontario College Diploma") from the stored page, with the patterns in pipeline.credential_rules (no fetch, no AI), and gives the course that study level when it has none. Run size batch.credential_read.', 4, true, 'pages'),
 ('country-scope-gate', 'Enrichment', 51, 'Country course scope', 'Hourly: hides active Canadian courses whose level is missing or out of scope (ca-intl-college-plus-v2) once their page was read for a credential, and shows inactive ones whose level is in scope at a DLI provider with a page read recently. Every change logged in pipeline.course_scope_changes. Run size batch.country_scope_gate.', 4, true, null)
on conflict (jobname) do nothing;
select cron.schedule('credential-read', '6-59/10 * * * *',
  $c$select pipeline.svc_pilot_submit_nonce('coverage-sweep', jsonb_build_object('mode', 'credential_read', 'limit', security.pipeline_num_v1('batch.credential_read', 100)::int)) where exists (select 1 from pipeline.queue_watch_state s where s.key = 'credential_read' and s.pending > 0) or not exists (select 1 from pipeline.queue_watch_state s where s.key = 'credential_read')$c$);
select cron.schedule('country-scope-gate', '38 * * * *', $c$select security.country_scope_gate_v1(true, 'CA')$c$);
-- switched on after the first credential pass is checked (Platform Admin is told the numbers first); until then it stays off
select cron.alter_job((select jobid from cron.job where jobname = 'country-scope-gate'), active := false);

insert into pipeline.component_register(kind, name, layer, purpose, status, replaces, introduced_in) values
 ('table', 'pipeline.credential_rules', 'Layer 2', 'What the credential reader looks for, by country', 'active', '{}', '20261022034000'),
 ('table', 'pipeline.credential_level_map', 'Layer 2', 'Credential wording to study level, by country', 'active', '{}', '20261022034000'),
 ('table', 'pipeline.country_scope_levels', 'Layer 1', 'Study levels shown per country', 'active', '{}', '20261022034000'),
 ('table', 'pipeline.course_credential_reads', 'Layer 2', 'Credential read per course page', 'active', '{}', '20261022034000'),
 ('table', 'pipeline.course_scope_changes', 'Layer 1', 'Courses hidden or shown by the scope gate', 'active', '{}', '20261022034000'),
 ('function', 'public.svc_credential_next', 'Layer 2', 'Course pages to read for a credential', 'active', '{}', '20261022034000'),
 ('function', 'public.svc_credential_record', 'Layer 2', 'Credential found to study level', 'active', '{}', '20261022034000'),
 ('function', 'security.credential_level_v1', 'Layer 2', 'Credential wording to study level', 'active', '{}', '20261022034000'),
 ('function', 'security.course_in_country_scope_v1', 'Layer 1', 'Course level in its country''s scope', 'active', '{}', '20261022034000'),
 ('function', 'security.country_scope_gate_v1', 'Layer 1', 'Hide and show courses by country scope', 'active', '{}', '20261022034000')
do $dry$
declare n jsonb; g jsonb; r1 jsonb; r2 jsonb; r3 jsonb; c1 uuid; c2 uuid; c3 uuid; e1 uuid; e2 uuid; e3 uuid; t timestamptz := clock_timestamp(); t_next int; t_gate int;
begin
  n := public.svc_credential_next(5); t_next := round(extract(epoch from clock_timestamp()-t)*1000);
  c1 := (n->'rows'->0->>'course_id')::uuid; e1 := (n->'rows'->0->>'evidence_id')::uuid;
  c2 := (n->'rows'->1->>'course_id')::uuid; e2 := (n->'rows'->1->>'evidence_id')::uuid;
  c3 := (n->'rows'->2->>'course_id')::uuid; e3 := (n->'rows'->2->>'evidence_id')::uuid;
  r1 := public.svc_credential_record(c1, e1, '[{"rule":1,"kind":"labelled","text":"Ontario College Diploma"},{"rule":2,"kind":"phrase","text":"Ontario College Graduate Certificate"}]'::jsonb);
  r2 := public.svc_credential_record(c2, e2, '[{"rule":2,"kind":"phrase","text":"Ontario College Diploma"},{"rule":2,"kind":"phrase","text":"Ontario College Advanced Diploma"}]'::jsonb);
  r3 := public.svc_credential_record(c3, e3, '[]'::jsonb);
  t := clock_timestamp(); g := security.country_scope_gate_v1(false, 'CA'); t_gate := round(extract(epoch from clock_timestamp()-t)*1000);
  raise exception 'DRYRUN OK next_rows=% rules=% next_ms=% r1=% lvl1=% obs=% r2=% r3=% gate=% gate_ms=% map=% scopefn=% gatejob=%',
    jsonb_array_length(n->'rows'), jsonb_array_length(n->'rules'), t_next, r1,
    (select sl.code from catalogue.courses c join ref.study_levels sl on sl.id=c.study_level_id where c.id=c1),
    (select count(*) from catalogue.course_study_level_observations where scheme='provider_page'), r2, r3, g, t_gate,
    (select string_agg(x||'='||coalesce(security.credential_level_v1('CA', x),'-'), ', ') from unnest(array['Ontario College Advanced Diploma','Diplôme d''études collégiales de l''Ontario – niveau avancé','Honours Bachelor of Design','Postgraduate Certificate','Certificat d''études supérieures de l''Ontario','Diploma','Certificate','degree']) x),
    (select position('course_in_country_scope_v1' in pg_get_functiondef('public.svc_layer1_apply_course_scope(uuid,text,text)'::regprocedure)) > 0),
    (select active from cron.job where jobname='country-scope-gate');
end $dry$;
