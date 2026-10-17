-- CF-247 Decision 265 (18 Oct 2026): English for the last four universities. Platform Admin 18 Oct 2026 09:27 "Help resolve 'still to do for
-- english'"; choices: Melbourne "Yes, build and read (Recommended)"; Wollongong and Torrens "Check CRICOS first"; ACU "Yes, UAC for ACU (Recommended)".
-- Found (18 Oct): Melbourne names each course's level on a handbook sub-page ("Entry and participation requirements"); Wollongong and Torrens
-- courses without English are mostly not on the university's current site (6 of 111 and 7 of 75 codes found on the 206 and 186 current course
-- pages, against 76% and 92% for courses with English); the CRICOS register loaded 26 Sep 2026 still lists all of them; ACU's course pages
-- print no scores and refer to a schedule ACU has rescinded; UAC publishes ACU's requirements by course group.
-- 1 Companion pages (Melbourne first): a page beside the bound course page (the bound address plus a suffix), read for named fields with the
--   university's own patterns (pipeline.uni_adapter_companions). Job companion-read (hourly) reads due pages through the scraper or directly,
--   keeps a stored copy and the values (pipeline.course_companion_pages). Re-read and retry times are settings.
-- 2 security.english_level_apply_v1 takes a level from the companion page when the course page names none, and from the policy's course group
--   rules (level_rules: title pattern and study level group, in order) when no page names one (ACU from UAC, next).
-- 3 Melbourne written-out level policy (Levels 1 to 3 and the older "performance band" wording) from its stored English language
--   requirements page: proposed; a Platform Admin approves.
-- 4 Course page relinking by rule (security.course_page_rebind_v1, logged with the old page): 1 Torrens and 5 Wollongong courses to the current
--   page that prints their CRICOS code; 6 Torrens professional doctorates and 1 Wollongong course read again (their page now prints IELTS);
--   Melbourne courses bound to an older handbook year move to the 2026 handbook page of the same course code. The reader checks identity as usual.
-- 5 Wollongong (111) and Torrens (68) courses whose code is on no current course page: CRICOS still lists them (26 Sep 2026), so they stay
--   active; a soft flag not_on_provider_site asks a person to confirm they are still offered.
-- 6 ACU: UAC's ACU English language proficiency page added as an English policy source (manual), read by the provider facts job.
-- Replaces: security.english_level_apply_v1 (md5-guarded)
-- Retires: nothing
-- Nothing dropped or deleted.

do $guard$
begin
  if md5(pg_get_functiondef('security.english_level_apply_v1(uuid,boolean)'::regprocedure)) <> '11a449a791a5a3ec06cf88527897bbb5' then
    raise exception 'live security.english_level_apply_v1 differs from the definition this change replaces';
  end if;
end $guard$;

create table if not exists pipeline.uni_adapter_companions (
  provider_id uuid primary key references catalogue.providers(id),
  url_pattern text not null,
  suffix text not null,
  patterns jsonb not null default '{}'::jsonb,
  read_via text not null default 'direct_then_scraper' check (read_via in ('direct', 'scraper', 'direct_then_scraper')),
  reason text not null,
  updated_by uuid,
  updated_at timestamptz not null default now()
);
comment on table pipeline.uni_adapter_companions is 'CF-247 Decision 265: a university''s companion page (a page beside the bound course page, the bound address plus a suffix) and the patterns read on it (field -> pattern with one bracketed value). Read by job companion-read.';
alter table pipeline.uni_adapter_companions enable row level security;

create table if not exists pipeline.course_companion_pages (
  course_id uuid primary key references catalogue.courses(id),
  provider_id uuid not null references catalogue.providers(id),
  url text not null,
  status text not null default 'due' check (status in ('due', 'read', 'blocked', 'failed', 'gone', 'waiting_scraper', 'too_thin')),
  http_status integer,
  fetched_via text,
  storage_path text,
  sha256 text,
  "values" jsonb not null default '{}'::jsonb,
  read_attempts integer not null default 0,
  next_read_at timestamptz not null default now(),
  leased_until timestamptz,
  read_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
comment on table pipeline.course_companion_pages is 'CF-247 Decision 265: one companion page per course (pipeline.uni_adapter_companions), its stored copy and the values read on it (for example english_level). Used by security.english_level_apply_v1.';
create index if not exists course_companion_pages_due on pipeline.course_companion_pages(next_read_at) where leased_until is null;
alter table pipeline.course_companion_pages enable row level security;

insert into pipeline.platform_toolset_settings(toolset_key, key, label, help, kind, value, min_value, max_value, unit, sort, reason, section, used_by) values
 ('pipeline', 'batch.companion_read', 'Companion pages read per run', 'Each run of the companion-read job reads this many due companion pages (for example a course''s entry requirements page).', 'number', to_jsonb(40), 5, 200, 'pages', 313, 'CF-247 Decision 265, 18 Oct 2026', 'Enrichment', 'job companion-read; coverage-sweep companion_read'),
 ('pipeline', 'companion.reread_days', 'Companion page read again after', 'A companion page that was read is read again after this many days.', 'number', to_jsonb(60), 7, 365, 'days', 314, 'CF-247 Decision 265, 18 Oct 2026', 'Enrichment', 'public.svc_companion_record'),
 ('pipeline', 'companion.retry_hours', 'Companion page tried again after', 'A companion page that could not be read (blocked, failed, scraper not available) is tried again after this many hours.', 'number', to_jsonb(12), 1, 168, 'hours', 315, 'CF-247 Decision 265, 18 Oct 2026', 'Enrichment', 'public.svc_companion_record'),
 ('pipeline', 'companion.max_attempts', 'Companion page attempts', 'A companion page is given up after this many failed reads in a row (it shows as failed).', 'number', to_jsonb(4), 1, 20, 'reads', 316, 'CF-247 Decision 265, 18 Oct 2026', 'Enrichment', 'public.svc_companion_next')
on conflict (toolset_key, key) do nothing;

-- due companion pages for every course whose bound page matches its university's companion address
create or replace function security.companion_sync_v1()
returns integer language plpgsql security definer set search_path = '' as $function$
declare n int;
begin
  with t as (
    select g.course_id, c.provider_id, regexp_replace(g.url, '/+$', '') || c.suffix url
      from pipeline.uni_adapter_companions c
      join catalogue.courses co on co.provider_id = c.provider_id and co.lifecycle_status = 'active'
      join pipeline.coverage_course_pages g on g.course_id = co.id and g.status = 'bound'
     where g.url ~ c.url_pattern),
  up as (
    insert into pipeline.course_companion_pages(course_id, provider_id, url)
    select course_id, provider_id, url from t
    on conflict (course_id) do update set url = excluded.url, status = 'due', "values" = '{}'::jsonb, read_attempts = 0, next_read_at = now(), updated_at = now()
     where pipeline.course_companion_pages.url <> excluded.url
    returning 1)
  select count(*) into n from up;
  return n;
end $function$;

create or replace function public.svc_companion_next(p_limit integer)
returns jsonb language plpgsql security definer set search_path = '' as $function$
declare v jsonb;
begin
  if current_user <> 'postgres' and coalesce(auth.role(), '') <> 'service_role' then raise exception 'service_role required'; end if;
  with pick as (
    select p.course_id from pipeline.course_companion_pages p
     where p.next_read_at <= now() and (p.leased_until is null or p.leased_until < now())
       and p.read_attempts < security.pipeline_num_v1('companion.max_attempts', 4)
       and p.status <> 'gone'
     order by p.next_read_at
     limit greatest(1, least(coalesce(p_limit, 40), 200))  -- fixed: per-call safety cap; the run size is batch.companion_read
     for update skip locked),
  upd as (update pipeline.course_companion_pages p set leased_until = now() + interval '10 minutes', updated_at = now()  -- fixed: lease for one call
            from pick where p.course_id = pick.course_id returning p.*)
  select coalesce(jsonb_agg(jsonb_build_object('course_id', u.course_id, 'provider_id', u.provider_id, 'url', u.url, 'via', c.read_via, 'patterns', c.patterns,
           'code', co.course_code, 'country', (select k.iso_alpha2 from catalogue.providers pr join ref.countries k on k.id = pr.country_id where pr.id = u.provider_id))), '[]'::jsonb)
    into v
    from upd u join pipeline.uni_adapter_companions c on c.provider_id = u.provider_id join catalogue.courses co on co.id = u.course_id;
  return v;
end $function$;

create or replace function public.svc_companion_record(p_course_id uuid, p_status text, p_http integer, p_via text, p_path text, p_sha text, p_values jsonb)
returns text language plpgsql security definer set search_path = '' as $function$
begin
  if current_user <> 'postgres' and coalesce(auth.role(), '') <> 'service_role' then raise exception 'service_role required'; end if;
  update pipeline.course_companion_pages
     set status = case when p_status in ('due', 'read', 'blocked', 'failed', 'gone', 'waiting_scraper', 'too_thin') then p_status else 'failed' end,
         http_status = p_http, fetched_via = p_via, leased_until = null, updated_at = now(),
         storage_path = coalesce(p_path, storage_path), sha256 = coalesce(p_sha, sha256),
         "values" = case when p_status = 'read' then coalesce(p_values, '{}'::jsonb) else "values" end,
         read_at = case when p_status = 'read' then now() else read_at end,
         read_attempts = case when p_status = 'read' then 0 when p_status = 'waiting_scraper' then read_attempts else read_attempts + 1 end,
         next_read_at = case when p_status = 'read' then now() + make_interval(days => security.pipeline_num_v1('companion.reread_days', 60)::int)
                             else now() + make_interval(hours => security.pipeline_num_v1('companion.retry_hours', 12)::int) end
   where course_id = p_course_id;
  return p_status;
end $function$;

revoke execute on function security.companion_sync_v1(), public.svc_companion_next(integer), public.svc_companion_record(uuid, text, integer, text, text, text, jsonb) from public, anon, authenticated;
grant execute on function public.svc_companion_next(integer), public.svc_companion_record(uuid, text, integer, text, text, text, jsonb) to service_role;

create or replace function security.english_level_apply_v1(p_provider_id uuid, p_apply boolean default true)
returns jsonb language plpgsql security definer set search_path = '' as $function$
declare x pipeline.provider_policy_proposals%rowtype; r record; v_lv jsonb; v_write jsonb; v_tests text[]; v_src uuid; v_name text; v_out int;
        v_written int := 0; v_same int := 0; v_own_differs int := 0; v_own int := 0; v_held int := 0; v_withdrawn int := 0; v_unknown jsonb := '{}'::jsonb;
        v_courses uuid[] := '{}'; v_err int := 0; v_last text; v_label text; v_k text; v_how text; v_rule text;
        v_day text := to_char(now() at time zone 'Australia/Melbourne', 'FMDD Mon YYYY');
begin
  -- the approved English policy in force that names levels (Decision 262 keeps one in force per level; the latest decision wins here)
  select * into x from pipeline.provider_policy_proposals
   where provider_id = p_provider_id and kind = 'english_policy' and status = 'approved' and jsonb_typeof(proposal->'levels') = 'object'
   order by decided_at desc nulls last limit 1;
  if x.id is null then return jsonb_build_object('skipped', 'no approved English policy with levels'); end if;
  if x.evidence_id is null or coalesce(x.content_hash, '') = '' then return jsonb_build_object('skipped', 'the policy page has no stored evidence'); end if;
  v_src := security.coverage_sweep_source(x.provider_id);
  select coalesce(p.display_name, p.canonical_name) into v_name from catalogue.providers p where p.id = x.provider_id;
  for r in
    select co.id course_id, co.canonical_title title, security.english_level_group(sl.code) grp,
           -- Decision 265: the level the course page names, else the one its companion page names (Melbourne's entry requirements page)
           case when coalesce(g.candidates->'adapter_extra'->>'english_level', '') <> '' then g.candidates->'adapter_extra'->>'english_level'
                when cp.status = 'read' then nullif(cp.values->>'english_level', '') end raw,
           case when coalesce(g.candidates->'adapter_extra'->>'english_level', '') <> '' then g.url else cp.url end page_url,
           exists (select 1 from pipeline.manual_locks l where l.entity = 'course' and l.entity_id = co.id and l.field in ('english', 'english_requirements', 'course_english')) locked,
           exists (select 1 from pipeline.layer4_review_items i where i.entity_type = 'course' and i.entity_id = co.id and i.field_code = 'course_english' and i.status = 'pending') in_review
      from catalogue.courses co
      join pipeline.coverage_course_pages g on g.course_id = co.id
      left join pipeline.course_companion_pages cp on cp.course_id = co.id
      left join ref.study_levels sl on sl.id = co.study_level_id
     where co.provider_id = x.provider_id and co.lifecycle_status = 'active' and g.read_status = 'read'
  loop
    v_k := security.english_level_key(r.raw); v_how := format('named on the course page (%s)', r.page_url);
    -- Decision 265: no level named on a page: the policy's course group rules, in order (title pattern, and study level group when given)
    if v_k is null then
      select q->>'level', q->>'group_name' into v_k, v_rule
        from jsonb_array_elements(coalesce(x.proposal->'level_rules', '[]'::jsonb)) with ordinality t(q, n)
       where r.title ~* (q->>'title_regex')
         and (jsonb_typeof(q->'groups') is distinct from 'array' or r.grp in (select jsonb_array_elements_text(q->'groups')))
       order by n limit 1;
      if v_k is null then continue; end if;
      v_k := security.english_level_key(v_k); v_how := format('for this course group ("%s")', v_rule);
    end if;
    v_lv := x.proposal->'levels'->v_k;
    v_label := coalesce(x.proposal->'level_names'->>v_k, btrim(coalesce(r.raw, v_k)));
    if jsonb_typeof(v_lv) is distinct from 'array' or jsonb_array_length(v_lv) = 0 then
      v_unknown := jsonb_set(v_unknown, array[coalesce(v_k, '?')], to_jsonb(coalesce((v_unknown->>coalesce(v_k, '?'))::int, 0) + 1)); continue;
    end if;
    if r.locked or r.in_review then v_held := v_held + 1; continue; end if;
    -- the course page prints its own score for a test of the level, and it differs: the page has its own requirement (an accreditation
    -- standard, for example), so the level is not used for this course and rows this rule wrote before are withdrawn
    if exists (select 1 from jsonb_array_elements(v_lv) q
                join ref.english_tests t on t.code = upper(q->>'test_code')
                join catalogue.course_english_requirements e on e.course_id = r.course_id and e.english_test_id = t.id and e.status = 'active'
               where coalesce(e.source_requirement_key, '') not like 'policy:%' and e.overall_score <> (q->>'overall_score')::numeric) then
      v_own_differs := v_own_differs + 1;
      if p_apply then
        with w as (
          update catalogue.course_english_requirements e set status = 'withdrawn', last_verified_at = now(),
                 notes = coalesce(e.notes, '') || format(' Withdrawn %s: the course page prints its own English score, which differs from level "%s" (Decision 264).', v_day, v_label)
           where e.course_id = r.course_id and e.status = 'active' and e.source_requirement_key like 'policy:%' and e.notes like 'English level %Decision 264%'
          returning e.course_id)
        select count(*) into v_out from w;
        v_withdrawn := v_withdrawn + v_out;
        if v_out > 0 then v_courses := v_courses || r.course_id; end if;
      end if;
      continue;
    end if;
    v_tests := array(select upper(q->>'test_code') from jsonb_array_elements(v_lv) q);
    -- the course's own reading (any key that is not a policy's) is never replaced
    v_own := v_own + (select count(*) from jsonb_array_elements(v_lv) q
                       where exists (select 1 from catalogue.course_english_requirements e join ref.english_tests t on t.id = e.english_test_id
                                      where e.course_id = r.course_id and t.code = upper(q->>'test_code') and e.status = 'active'
                                        and coalesce(e.source_requirement_key, '') not like 'policy:%'))::int;
    select coalesce(jsonb_agg(jsonb_build_object(
             'test_code', upper(q->>'test_code'), 'overall_score', q->'overall_score', 'component_scores', coalesce(q->'component_scores', '{}'::jsonb),
             'source_requirement_key', 'policy:' || x.id || ':' || lower(q->>'test_code'),
             'notes', format('English level "%s" %s; scores for that level from %s''s English language requirements (%s), approved by a Platform Admin (Decision 264, 265).',
                             v_label, v_how, v_name, x.url))), '[]'::jsonb)
      into v_write
      from jsonb_array_elements(v_lv) q
     where upper(q->>'test_code') in (select t.code from ref.english_tests t where t.status = 'active')
       and not exists (select 1 from catalogue.course_english_requirements e join ref.english_tests t on t.id = e.english_test_id
                        where e.course_id = r.course_id and t.code = upper(q->>'test_code') and e.status = 'active'
                          and (coalesce(e.source_requirement_key, '') not like 'policy:%'
                               or (e.source_requirement_key = 'policy:' || x.id || ':' || lower(q->>'test_code')
                                   and e.overall_score = (q->>'overall_score')::numeric
                                   and e.component_scores = coalesce(q->'component_scores', '{}'::jsonb)
                                   and e.notes like 'English level %Decision 264%')));
    if jsonb_array_length(v_write) = 0 then v_same := v_same + 1; continue; end if;
    if not p_apply then v_written := v_written + 1; continue; end if;
    begin
      perform security.coverage_apply_course_v1(r.course_id, v_src, x.evidence_id, x.url, x.content_hash, jsonb_build_object('english_requirements', v_write));
      -- policy rows for tests this level does not give are withdrawn (kept, not deleted)
      with w as (
        update catalogue.course_english_requirements e set status = 'withdrawn', last_verified_at = now(),
               notes = coalesce(e.notes, '') || format(' Withdrawn %s: the course page names English level "%s", which does not give this test (Decision 264).', v_day, v_label)
          from ref.english_tests t
         where t.id = e.english_test_id and e.course_id = r.course_id and e.status = 'active'
           and e.source_requirement_key like 'policy:%' and t.code <> all (v_tests)
        returning 1)
      select count(*) into v_out from w;
      v_withdrawn := v_withdrawn + v_out;
      v_written := v_written + 1; v_courses := v_courses || r.course_id;
    exception when others then v_err := v_err + 1; v_last := left(sqlerrm, 200);
    end;
  end loop;
  if cardinality(v_courses) > 0 then
    insert into search.enrichment_source_gates(projection_code, domain_code, source_id, gate_status, approval_ref, approved_at, created_at, updated_at)
    select 'courses', 'course_english', v_src, 'approved', 'CF-CHG-20260915-247; Decision 227 (English from the provider''s policy, approved by a Platform Admin)', now(), now(), now()
     where not exists (select 1 from search.enrichment_source_gates g where g.projection_code = 'courses' and g.domain_code = 'course_english' and g.source_id = v_src);
    perform search.refresh_course_enrichment_scoped_v1(v_courses, true);
    insert into pipeline.admin_control_events(area, action, target, detail, actor)
    values ('policies', 'english_levels', 'english_policy: ' || x.url,
            jsonb_build_object('proposal_id', x.id, 'provider_id', x.provider_id, 'courses', cardinality(v_courses), 'withdrawn_rows', v_withdrawn,
                               'unknown_levels', v_unknown, 'decision', 264), null);
  end if;
  update pipeline.provider_policy_proposals
     set apply_summary = coalesce(apply_summary, '{}'::jsonb) || jsonb_build_object('levels', jsonb_build_object(
           'courses_written', v_written, 'unchanged', v_same, 'own_reading_tests', v_own, 'own_differs', v_own_differs, 'held', v_held, 'withdrawn_rows', v_withdrawn,
           'unknown_levels', v_unknown, 'refused', v_err, 'last_error', v_last, 'checked_at', now(), 'applied', p_apply)), updated_at = now()
   where id = x.id and p_apply;
  return jsonb_build_object('policy', x.id, 'courses_written', v_written, 'unchanged', v_same, 'own_reading_tests', v_own, 'own_differs', v_own_differs, 'own_differs', v_own_differs, 'held', v_held,
                            'withdrawn_rows', v_withdrawn, 'unknown_levels', v_unknown, 'refused', v_err, 'last_error', v_last);
end $function$;

revoke execute on function security.english_level_apply_v1(uuid, boolean) from public, anon, authenticated;

-- relink a course to another page of the university's own site by rule; the reader then reads it and checks identity as for any bound page
create or replace function security.course_page_rebind_v1(p_course_id uuid, p_url text, p_basis text, p_reason text)
returns text language plpgsql security definer set search_path = '' as $function$
declare v_old text; v_pid uuid;
begin
  select provider_id into v_pid from catalogue.courses where id = p_course_id;
  if v_pid is null then return 'unknown course'; end if;
  if exists (select 1 from pipeline.manual_locks l where l.entity = 'course' and l.entity_id = p_course_id and l.field in ('official_url', 'course_url')) then return 'locked'; end if;
  if exists (select 1 from pipeline.course_page_blocks b where b.course_id = p_course_id and b.url = p_url) then return 'blocked'; end if;
  select url into v_old from pipeline.coverage_course_pages where course_id = p_course_id;
  insert into pipeline.coverage_course_pages(course_id, provider_id, url, basis, status, bound_at, next_read_at, read_attempts)
  values (p_course_id, v_pid, p_url, p_basis, 'bound', now(), now(), 0)
  on conflict (course_id) do update set url = excluded.url, basis = excluded.basis, status = 'bound', bound_at = now(),
         score = null, runner_up = null, read_status = null, read_at = null, http_status = null, fetched_via = null,
         identity_basis = null, evidence_id = null, candidates = null, leased_until = null, read_attempts = 0, next_read_at = now();
  insert into pipeline.admin_control_events(area, action, target, detail, actor)
  values ('coverage', 'rebind', 'course: ' || p_course_id, jsonb_build_object('course_id', p_course_id, 'old_url', v_old, 'new_url', p_url, 'basis', p_basis, 'reason', p_reason), null);
  return case when v_old is not distinct from p_url then 'read again' else 'relinked' end;
end $function$;
revoke execute on function security.course_page_rebind_v1(uuid, text, text, text) from public, anon, authenticated;

-- 4 relinking by rule
select v.c, security.course_page_rebind_v1(v.c::uuid, v.u, 'cricos_code_on_page', 'Decision 265: ' || v.r)
  from (values
   ('34e20db3-0bdb-44df-9f75-7b28a11fe999', 'https://www.torrens.edu.au/courses/design/advanced-diploma-of-graphic-design', 'the current Torrens page with this title prints the course''s CRICOS code 121355M'),
   ('0ef299be-3f03-4e52-bd69-d150355df50a', 'https://www.uow.edu.au/study/courses/bachelor-of-engineering-honours-double-major/', 'the current UOW page printing CRICOS code 083340D (was a 2015 handbook page)'),
   ('d8dc2635-31a5-47ca-beb1-31a1bbf5111f', 'https://www.uow.edu.au/study/courses/bachelor-of-engineering-honours---bachelor-of-science-physics/', 'the current UOW page printing CRICOS code 083343A (was a 2015 handbook page)'),
   ('9e72b1b3-bf29-4045-a360-3242414859f0', 'https://www.uow.edu.au/study/courses/bachelor-of-laws-direct-entry/', 'the current UOW page printing CRICOS code 094205J (was a 2020 handbook page)'),
   ('95fc1a5d-8f13-4387-89c1-04cb0f897fb0', 'https://www.uow.edu.au/study/courses/bachelor-of-laws-graduate-entry/', 'the current UOW page printing CRICOS code 094206G (was a 2020 handbook page)'),
   ('5688b52a-81f9-40a7-82a1-7fcd8559a7e4', 'https://www.uow.edu.au/study/courses/bachelor-of-laws-honours-direct-entry/', 'the current UOW page printing CRICOS code 094207G (was a 2019 handbook page)'),
   ('54d2e511-b291-4ace-9a5a-2572a4abc42e', 'https://www.torrens.edu.au/courses/higher-degrees-by-research/professional-doctorate-ai-futures', 'read again: the page now prints IELTS'),
   ('e1fbdf48-c689-46b2-8d80-bfcb2569ebd7', 'https://www.torrens.edu.au/courses/higher-degrees-by-research/professional-doctorate-business-transformation', 'read again: the page now prints IELTS'),
   ('b93adbd5-2d0d-40db-8006-114bbc89364a', 'https://www.torrens.edu.au/courses/higher-degrees-by-research/professional-doctorate-living-systems-tourism-and-technology', 'read again: the page now prints IELTS'),
   ('4a250faa-230f-4326-9e6b-b6dd3d5ac6fa', 'https://www.torrens.edu.au/courses/higher-degrees-by-research/professional-doctorate-translational-biological-discovery', 'read again: the page now prints IELTS'),
   ('0fbd5aa8-ae41-4d7e-a427-a6cfeab8541c', 'https://www.torrens.edu.au/courses/higher-degrees-by-research/professional-doctorate-design-innovation-and-creative-practice', 'read again: the page now prints IELTS'),
   ('1b90fe02-eff5-4156-a55f-1468ebc155af', 'https://www.torrens.edu.au/courses/higher-degrees-by-research/professional-doctorate-edtech', 'read again: the page now prints IELTS'),
   ('27064417-f78e-4474-b35b-8a35f26d4f0b', 'https://www.uow.edu.au/study/courses/bachelor-of-politics-philosophy-and-economics-honours/', 'read again: current page')
  ) v(c, u, r);

-- Melbourne: courses without English bound to an older handbook year move to the 2026 handbook page of the same course code
select g.course_id, security.course_page_rebind_v1(g.course_id, 'https://handbook.unimelb.edu.au/2026/courses/' || lower((regexp_match(g.url, '/courses/([A-Za-z0-9-]+)'))[1]), 'cms_path_public',
         'Decision 265: same course code in the 2026 handbook (was ' || g.url || ')')
  from pipeline.coverage_course_pages g join catalogue.courses c on c.id = g.course_id
 where c.provider_id = 'de6d32b0-f91b-4dd0-a3da-a542f1aba5f2' and c.lifecycle_status = 'active'
   and g.url ~ '^https://(archive\.)?handbook\.unimelb\.edu\.au/(?:view/)?(?:20(?:1[0-9]|2[0-5]))/(?:courses/)?[A-Za-z0-9-]+'
   and g.url ~ '/courses/[A-Za-z0-9-]+'
   and not exists (select 1 from catalogue.course_english_requirements r where r.course_id = c.id and r.status = 'active');

-- 5 not on the university's current site (CRICOS still lists them): a soft flag for a person
insert into pipeline.enrichment_flags(entity, entity_key, provider_id, field, reason_code, reason, source, kind, state, raised_by_kind)
select 'course', c.id::text, c.provider_id, 'official_url', 'not_on_provider_site',
       format('The CRICOS register (loaded 26 Sep 2026) still lists %s (%s), but its code is on none of %s''s current course pages (read 18 Oct 2026), so there is no current page to read English from. Check whether it is still offered (Decision 265).',
              c.canonical_title, c.course_code, coalesce(p.display_name, p.canonical_name)),
       'decision-265', 'soft', 'raised', 'auto'
  from catalogue.courses c join catalogue.providers p on p.id = c.provider_id
 where c.id in ('a75ef974-7ef2-4e54-ab47-b432dddf769b','f385f9ba-ffb7-4102-a449-ad42db2acce6','66978c89-1f62-4298-8053-c0771ece4c16','6d77e456-c093-4aaa-a6dc-0e7a32ac5028','085ed030-4f50-4007-867e-eb5d6a59ab15','5b679cd3-e219-4561-bb74-71fc492e89a9','3a8f640e-f9ed-465c-8136-7ce6c79ac051','ce049e1a-423a-4750-945e-1df765f3553a','d2e59bcc-7466-4484-867b-71d8fc36c3d3','87f5e642-b60a-4b32-9c5c-37e6762939a7','25e82c82-9293-4c26-9e4d-ef6274655265','7740dce0-dda0-4c83-95d2-696eebf6f7b3','9baa5569-3594-4782-a2d2-6241844d72f3','e113ebf9-3deb-4d02-a3bc-de8ec32a020d','e68218de-4a41-4d03-b589-597ddc5521dc','accd41d7-01a9-457d-b709-00436b84450a','21a8a62b-a5c9-4bb5-a59e-eb944ecdf7ee','fa31ba52-3389-41e5-9a21-d64809f01198','b766b38e-45d9-4f11-9835-61cbbb9bd148','6a921ef9-c1b8-4720-b317-208c0e27b985','23ecc142-1990-4eaf-a2f8-f39d73988924','f86eab60-8263-435d-93a5-585df12d417a','26a5502b-bdcd-46b4-adec-5832133b4402','bf9cf0f6-363e-47ad-b101-43a484c8839d','300732b4-6760-423d-8880-50e26da968e2','20cc47d8-c390-4f8c-a39f-7db60b715b73','1308184f-4300-4476-88e7-3bfad6cbd806','1128f503-e19e-41ae-994b-1b42b98054da','3543a1c6-7b74-4ec9-8396-23d95ab63dc0','6fe6bd58-a1ec-4112-aa4c-59d6f56605f9','b7a1779a-a7ed-403d-b055-dca2cd05834a','3febd2cd-20b3-4c59-ade8-86ecda4c3b68','eec6cc44-df9c-4b20-987f-0ec2b9a4fe75','0b72ebca-e9a8-4ad1-a2c7-4a0b9aa4d98c','11b127b4-1382-4dc6-a663-2ef54bee8a3f','f2f99fc9-ce04-44d5-a2a7-8dea65db6d56','4d9978f6-1873-4b67-82a7-d4639ce34bb9','4a7bff86-fae0-4bb3-8b87-c6a92e62b828','9c9209c3-9e4d-44be-914a-5bf4ac0316f5','26b7fe6e-e2f0-4b19-98cf-1519d1da1119','09e9bf86-b0d9-4234-bb01-3a08cb4dee30','7bbc6bc7-8e25-48de-9bdd-fe6d21fc40c4','96c5fa99-079d-4d29-8cca-029c0bfc4b6b','000c78f4-3a69-446f-85c4-9ad25210412f','bcc85acf-95ac-483f-a528-47deb2653d40','7af39919-aa35-497a-a4ec-0813b9c320f9','eb5b7b87-08b6-4778-9b7d-26ad6bd98b7a','b19702af-7b0b-4cd6-a65e-12f589a63979','d5a261de-a063-4f56-898e-65e9635cdc8e','2b776373-92a0-4296-bbeb-a38381c86895','3c3d206d-78c6-4096-9906-5ad8fc5239db','7d9511dc-5981-4544-9f87-16f0047fe43d','94ca2180-1c11-4f57-b332-8ddfc7e1352f','1f82af54-828c-4019-ae0d-a620bff07553','024d9088-22df-4e75-a35a-5e1c93b589bd','7c41a036-5b0d-437f-b9c5-2fdbb977e8ed','bbb8c59d-dec8-4681-a696-39dbd3ffb164','d5abe7f9-5ffa-434a-af04-cb219e773c81','fdc53d81-910d-4c8e-a191-0b4dea63b91a','6fba8fb3-fb72-4a0c-90df-87d1160385f1','0f6fbfd9-a0a1-440f-84d7-6c64571167ea','f77de65e-84e8-4037-b969-b540747fef20','dfdaceac-bf20-469a-b746-1b5692fcdaef','9b18f510-8ac6-419a-91e7-a55347e38a8b','0bbb60e7-fd61-409b-90e7-bd2dbfe7dea9','6732e68a-977b-493a-9702-5d0f1d865b83','d7172ddd-8d79-4ade-a067-9972c02e39da','41b6b6b4-be61-4de5-a132-66d890133d88','df87fc1a-a8f3-4af3-81f2-b91c83054bfe','41e44bfe-a540-4b64-8f41-eac54ddb52e6','0a667712-86a8-4abf-b385-2cd3da5bf37c','baf1c023-7728-4b9c-842b-29e44d7da7d6','44f78ddf-bfaf-48c8-ab25-8c1dc0c6b92c','b66984fa-1bf9-454a-a607-cc08895433ea','5fd2f5ab-99c2-4c59-9c7c-b97fac57a640','e3b0e9e1-bab1-446f-82bd-17fa335ed278','f18fef97-eb76-496d-8510-b20d2938dbd0','68c3f37c-e9bf-4950-8981-aa2ad4360ec5','7e6cbdc5-69ab-411b-89f5-7109dc5b0f8f','cbd9aa6b-eab1-4a96-a6d1-8639fe787c87','f8ed58e1-a2e9-44db-a55b-a6ccb9fd7c1a','4099eef8-f21a-4c5a-a58d-91091fbbab4c','22ec3ddc-f514-44af-9283-99598975aa9d','69de8142-3215-4ed9-8e01-e3a9ffe0a533','051bfab9-db91-4a24-b70a-a3a356e1aeb8','88679c17-f107-4247-af32-97fc18ee1222','ef48f591-18b3-47bb-8aa9-292077825f34','892d03df-c57b-4e12-8c36-170371b3c6a6','fbbccdf3-8f14-4efe-b6df-2c5c224a607a','04776667-4cdb-4eff-a6cb-e67cbc1c1fca','c5e6b558-8802-4661-b2d0-c68790d219d5','9bf77800-03c0-42c2-bf06-6623faa02bc2','786622f1-00a0-4fc9-86e1-a78df5e1db90','01d214e8-6ebf-403e-8cc3-8b507bcc0e37','fb59f0a9-e389-42e5-a082-23e600a194bd','dbd0e936-91b5-4aa2-92d4-1e234fa6802b','7f93e7e5-9036-4db3-8dc8-c220aa3a3b02','c61bc1bc-992f-4cf4-b4e1-8ae85d177a85','5a2c8234-a63a-46f5-aa59-28859e34fc03','5b14b93a-ecdc-4e13-b464-618fb6cb808e','f1a311e4-1566-46c6-bc9b-027873af3343','3b61e1fd-9f69-4a9f-9977-d18b2f1bf9d2','8c047706-d5ad-48a6-a61c-064f21214e47','fb66114e-1a82-4b1b-a443-9b21e0b33a75','581e4574-4c0d-43d9-98cf-254505cccffb','49241bcf-757b-455d-83b5-246e3e781e11','c5b69c35-4819-4c7a-b755-7ef6894d398e','6c6c65e3-2386-4fd0-9264-b98d8516ea44','89f5618c-ae41-45e2-952c-dfbe88f69b76','bb4eeea4-b1b3-407e-9ad3-b59c6bdaf654','0b98c4f2-66ec-45c9-9423-365b43c1dbe1','42a605bc-d5d0-4c25-b538-9a69e2a3014c','8f6545e9-9fb9-4cb0-abb8-7fcf53205f1a','f40fe085-4037-49fd-a551-34eb9312dd46','43ba360c-6b8c-4819-bd0b-a3f6b4dffd91','2395a21e-0c00-4ecb-bfb4-264981af5394','fea74a9e-39f2-4484-8aee-f5998e92f160','3bd7e52f-4b21-4317-82a6-0d11d12c821e','05cce6d8-5f4b-40b0-bb1f-fd95a285de27','e65d90c1-edf1-476b-985f-0e8f36c2db86','dedb5497-5775-43f9-a24b-d69290c1cc53','bf586cb1-6e94-45e6-be5d-8ccfdd1a7dbc','9ccab8e7-aca4-4790-a2ea-64bead63bd83','5b1d6196-b793-44a5-983d-1f747fb1c3cb','74483276-dce3-4814-8807-75196b8c7033','9988b6aa-9632-443e-a53e-d967ee90dda3','a3b8f2fd-23be-45d3-86aa-77824b51aa56','78b19aa2-431d-4916-bfac-29fd8abd6f41','99d7e6a3-db8c-4acd-aa6b-15d9bcaba21d','e8cb770a-e5e6-4255-bd9a-2b5606c44ce5','a26d0ec6-0b74-4d94-99a2-41ad4ef3fadb','eeb24063-1aef-4896-9b8c-7ada718f28a6','25dcf995-174c-45ab-85f7-97745fb42424','40b92918-f4b6-4a30-92e1-03b9a34bd92c','7eedd300-b32a-46af-805e-ecca916d3e35','366a7cc6-10c2-4dda-ad55-ea323440ccc3','06a590ff-6879-422e-b28e-57f774df80a7','f4d20a90-431e-4175-8fb3-492da5d35a9b','a22bb529-89c4-4338-b817-acc06bc846c9','31113894-88ce-499b-8e06-dd57e202f1fc','3a6cdefd-3103-494b-96c4-7889f34ea54b','973c4b2a-92f0-4f04-87e1-b303ee64349a','7d0990bb-7844-471e-9bd4-a054b5cd67e6','2c9a9250-6b50-452d-985e-d307b4f87a43','5fd194a7-b78a-4a91-bd19-9bab5f1eb5b6','0bead47a-00ed-410e-8062-4c4b036c4be8','ba656eaf-a8c6-4d1e-9525-b112d127d05b','566b0d11-d6f2-49ba-a4c5-526f27d3c2ff','13bbe651-ab9c-49e7-ab04-c0b4bdb50711','418542b0-da60-482b-8029-fe43fadce034','c16c96c0-6318-40c5-959d-71be55fdbb63','f4e2b1b5-15f9-496b-bc0b-3482076dadec','c0d1256a-e17a-4e44-9dc7-72ddd8e21955','051e9db8-b4bb-4756-9093-a235bbdca2a7','f900eda7-e0dd-41f7-b927-693c38bcd9dc','b780ebde-292b-4802-91bf-12486b109e4d','5353f2f6-9426-441c-948d-ad98e4ee3176','5932861c-e0bf-4421-9cd2-9fcef4a837b6','be43cc90-c957-4729-8d91-c4939d435c57','eb171e58-c2a4-414d-94c5-f92602965dbb','41678656-e051-4a13-a9f8-a29572c5174a','fb77d7eb-2164-475b-b10a-8cdad2a4e81d','617e8a82-419d-4c23-8cde-918a61011724','36472ee9-257e-4014-a514-50ce7f6c0ac8','c1421635-6bca-4840-bd31-39c889f21793','aef29e2c-e475-48ac-9ba7-0bf7d7fbbd25','82cc0921-771e-4cbf-bde3-fb009241c07d','ee0e1259-66c0-49d6-9938-c4827e273a27','b3c2431b-e9f0-408c-8b14-903183f96961','2cc1a111-8d77-4d96-b958-5ee743971db3','060a8216-008c-49d8-868e-3cf040da670a','35806990-aaa4-49e6-90c0-a409af19533d','12fc2014-447d-4fec-a77f-c6cae62354d5','fc360377-d82a-4cd6-91eb-5e44926d105d','4df1181b-8842-44e3-85a7-ac043688878e','520eae21-9424-48ac-87f0-e7572b35be35','865d000f-8360-4474-b942-6c2584977b88','e857dc07-65c8-4ebc-be68-ed177c1aea38','a12b8900-8dde-486e-bd33-fe59f3bea3f9')
   and c.lifecycle_status = 'active'
on conflict (entity, entity_key, field, reason_code) do nothing;

-- 1 Melbourne companion page: Entry and participation requirements
insert into pipeline.uni_adapter_companions(provider_id, url_pattern, suffix, patterns, read_via, reason)
values ('de6d32b0-f91b-4dd0-a3da-a542f1aba5f2', '^https://handbook\.unimelb\.edu\.au/2026/courses/[a-z0-9-]+/?$', '/entry-participation-requirements',
        jsonb_build_object('english_level', '((?:band [6-8](?:\.[05])?(?= is required))|(?:Level [1-5][ab]?(?= English scores are required)))'),
        'scraper', 'Decision 265 (Platform Admin 18 Oct 2026 "Yes, build and read"): the handbook names the course''s English level on its Entry and participation requirements page; the handbook refuses quick direct reads, so the scraper reads it')
on conflict (provider_id) do nothing;

-- 3 Melbourne written-out level policy (proposed)
insert into pipeline.provider_policy_proposals(provider_id, fact_source_id, kind, parser, content_hash, evidence_id, url, style, proposal, status)
select fs.provider_id, fs.id, 'english_policy', 'written out from the central page', fs.content_hash, fs.evidence_id, fs.url, 'level_map', $j${"style": "level_map", "parser": "written out from the central page", "decision": 265, "level_reading": "Each handbook course's Entry and participation requirements page names its level (\"Level 1 English scores are required for this course\") or, on older pages, an IELTS band (\"performance band 7 is required\"). A band gives the overall scores of the levels with that IELTS overall; the skill minimums vary within a band and are not given.", "defaults": {}, "named": [], "exceptions": [], "caveats": ["band_gives_overall_only", "research_degrees_state_no_level"], "signals": [], "conflicts": [], "level_names": {"level 1": "Level 1", "level 1a": "Level 1a", "level 1b": "Level 1b", "level 2": "Level 2", "level 2a": "Level 2a", "level 2b": "Level 2b", "level 3": "Level 3", "band 6.5": "performance band 6.5", "band 7": "performance band 7", "band 7.5": "performance band 7.5"}, "levels": {"level 1": [{"test_code": "IELTS", "overall_score": 6.5, "component_scores": {"writing": 6.0, "speaking": 6.0, "reading": 6.0, "listening": 6.0}, "quote": "| Level 1 | 6.5 Overall, with at least   <br>6.0 Writing  <br>6.0 Speaking  <br>6.0 Reading  <br>6.0 Listening |"}, {"test_code": "TOEFL_IBT", "overall_score": 81, "component_scores": {"writing": 19, "speaking": 19, "reading": 16, "listening": 16}, "quote": "81 Overall, with at least   <br>19 Writing  <br>19 Speaking  <br>16 Reading  <br>16 Listening"}, {"test_code": "PTE", "overall_score": 64, "component_scores": {"writing": 60, "speaking": 60, "reading": 60, "listening": 60}, "quote": "64 Overall, with at least   <br>60 Writing  <br>60 Speaking  <br>60 Reading  <br>60 Listening"}, {"test_code": "CAE", "overall_score": 169, "component_scores": {"writing": 170, "speaking": 179, "reading": 163, "listening": 163}, "quote": "169 Overall, with at least   <br>170 Writing  <br>179 Speaking  <br>163 Reading  <br>163 Listening"}], "level 1a": [{"test_code": "IELTS", "overall_score": 6.5, "component_scores": {"writing": 6.5, "speaking": 6.0, "reading": 6.0, "listening": 6.0}, "quote": "| Level 1a | 6.5 Overall, with at least   <br>6.5 Writing  <br>6.0 Speaking  <br>6.0 Reading  <br>6.0 Listening |"}, {"test_code": "TOEFL_IBT", "overall_score": 81, "component_scores": {"writing": 23, "speaking": 19, "reading": 16, "listening": 16}, "quote": "81 Overall, with at least   <br>23 Writing  <br>19 Speaking  <br>16 Reading  <br>16 Listening"}, {"test_code": "PTE", "overall_score": 64, "component_scores": {"writing": 65, "speaking": 60, "reading": 60, "listening": 60}, "quote": "64 Overall, with at least   <br>65 Writing  <br>60 Speaking  <br>60 Reading  <br>60 Listening"}, {"test_code": "CAE", "overall_score": 169, "component_scores": {"writing": 180, "speaking": 179, "reading": 163, "listening": 163}, "quote": "169 Overall, with at least   <br>180 Writing  <br>179 Speaking  <br>163 Reading  <br>163 Listening"}], "level 1b": [{"test_code": "IELTS", "overall_score": 6.5, "component_scores": {"writing": 6.5, "speaking": 6.5, "reading": 6.5, "listening": 6.5}, "quote": "| Level 1b | 6.5 Overall, with at least   <br>6.5 Writing  <br>6.5 Speaking  <br>6.5 Reading  <br>6.5 Listening |"}, {"test_code": "TOEFL_IBT", "overall_score": 81, "component_scores": {"writing": 23, "speaking": 22, "reading": 19, "listening": 19}, "quote": "81 Overall, with at least   <br>23 Writing  <br>22 Speaking  <br>19 Reading  <br>19 Listening"}, {"test_code": "PTE", "overall_score": 64, "component_scores": {"writing": 65, "speaking": 66, "reading": 64, "listening": 64}, "quote": "64 Overall, with at least   <br>65 Writing  <br>66 Speaking  <br>64 Reading  <br>64 Listening"}, {"test_code": "CAE", "overall_score": 169, "component_scores": {"writing": 180, "speaking": 187, "reading": 168, "listening": 168}, "quote": "169 Overall, with at least   <br>180 Writing  <br>187 Speaking  <br>168 Reading  <br>168 Listening"}], "level 2": [{"test_code": "IELTS", "overall_score": 7.0, "component_scores": {"writing": 6.5, "speaking": 6.5, "reading": 6.5, "listening": 6.5}, "quote": "| Level 2 | 7.0 Overall, with at least   <br>6.5 Writing  <br>6.5 Speaking  <br>6.5 Reading  <br>6.5 Listening |"}, {"test_code": "TOEFL_IBT", "overall_score": 91, "component_scores": {"writing": 23, "speaking": 22, "reading": 19, "listening": 19}, "quote": "91 Overall, with at least   <br>23 Writing  <br>22 Speaking  <br>19 Reading  <br>19 Listening"}, {"test_code": "PTE", "overall_score": 72, "component_scores": {"writing": 65, "speaking": 66, "reading": 64, "listening": 64}, "quote": "72 Overall, with at least   <br>65 Writing  <br>66 Speaking  <br>64 Reading  <br>64 Listening"}, {"test_code": "CAE", "overall_score": 178, "component_scores": {"writing": 180, "speaking": 187, "reading": 168, "listening": 168}, "quote": "178 Overall, with at least   <br>180 Writing  <br>187 Speaking  <br>168 Reading  <br>168 Listening"}], "level 2a": [{"test_code": "IELTS", "overall_score": 7.0, "component_scores": {"writing": 7.0, "speaking": 6.5, "reading": 6.5, "listening": 6.5}, "quote": "| Level 2a | 7.0 Overall, with at least   <br>7.0 Writing  <br>6.5 Speaking  <br>6.5 Reading  <br>6.5 Listening |"}, {"test_code": "TOEFL_IBT", "overall_score": 91, "component_scores": {"writing": 26, "speaking": 22, "reading": 19, "listening": 19}, "quote": "91 Overall, with at least   <br>26 Writing  <br>22 Speaking  <br>19 Reading  <br>19 Listening"}, {"test_code": "PTE", "overall_score": 72, "component_scores": {"writing": 75, "speaking": 66, "reading": 64, "listening": 64}, "quote": "72 Overall, with at least   <br>75 Writing  <br>66 Speaking  <br>64 Reading  <br>64 Listening"}, {"test_code": "CAE", "overall_score": 178, "component_scores": {"writing": 193, "speaking": 187, "reading": 168, "listening": 168}, "quote": "178 Overall, with at least   <br>193 Writing  <br>187 Speaking  <br>168 Reading  <br>168 Listening"}], "level 2b": [{"test_code": "IELTS", "overall_score": 7.0, "component_scores": {"writing": 7.0, "speaking": 7.0, "reading": 7.0, "listening": 7.0}, "quote": "| Level 2b | 7.0 Overall, with at least   <br>7.0 Writing  <br>7.0 Speaking  <br>7.0 Reading  <br>7.0 Listening |"}, {"test_code": "TOEFL_IBT", "overall_score": 91, "component_scores": {"writing": 26, "speaking": 24, "reading": 22, "listening": 22}, "quote": "91 Overall, with at least   <br>26 Writing  <br>24 Speaking  <br>22 Reading  <br>22 Listening"}, {"test_code": "PTE", "overall_score": 72, "component_scores": {"writing": 75, "speaking": 76, "reading": 72, "listening": 72}, "quote": "72 Overall, with at least   <br>75 Writing  <br>76 Speaking  <br>72 Reading  <br>72 Listening"}, {"test_code": "CAE", "overall_score": 178, "component_scores": {"writing": 193, "speaking": 194, "reading": 179, "listening": 175}, "quote": "178 Overall, with at least   <br>193 Writing  <br>194 Speaking  <br>179 Reading  <br>175 Listening"}], "level 3": [{"test_code": "IELTS", "overall_score": 7.5, "component_scores": {"writing": 7.0, "speaking": 7.0, "reading": 7.0, "listening": 7.0}, "quote": "| Level 3 | 7.5 Overall, with at least   <br>7.0 Writing  <br>7.0 Speaking  <br>7.0 Reading  <br>7.0 Listening |"}, {"test_code": "TOEFL_IBT", "overall_score": 100, "component_scores": {"writing": 26, "speaking": 24, "reading": 22, "listening": 22}, "quote": "100 Overall, with at least   <br>26 Writing  <br>24 Speaking  <br>22 Reading  <br>22 Listening"}, {"test_code": "PTE", "overall_score": 78, "component_scores": {"writing": 75, "speaking": 76, "reading": 72, "listening": 72}, "quote": "78 Overall, with at least   <br>75 Writing  <br>76 Speaking  <br>72 Reading  <br>72 Listening"}, {"test_code": "CAE", "overall_score": 187, "component_scores": {}, "quote": "187 Overall, with at least   <br>193 Writing  <br>194 Speaking  <br>179179 Reading  <br>175 Listening"}], "band 6.5": [{"test_code": "IELTS", "overall_score": 6.5, "component_scores": {}, "quote": "| Level 1 | 6.5 Overall, with at least   <br>6.0 Writing  <br>6.0 Speaking  <br>6.0 Reading  <br>6.0 Listening |"}, {"test_code": "TOEFL_IBT", "overall_score": 81, "component_scores": {}, "quote": "81 Overall, with at least   <br>19 Writing  <br>19 Speaking  <br>16 Reading  <br>16 Listening"}, {"test_code": "PTE", "overall_score": 64, "component_scores": {}, "quote": "64 Overall, with at least   <br>60 Writing  <br>60 Speaking  <br>60 Reading  <br>60 Listening"}, {"test_code": "CAE", "overall_score": 169, "component_scores": {}, "quote": "169 Overall, with at least   <br>170 Writing  <br>179 Speaking  <br>163 Reading  <br>163 Listening"}], "band 7": [{"test_code": "IELTS", "overall_score": 7.0, "component_scores": {}, "quote": "| Level 2 | 7.0 Overall, with at least   <br>6.5 Writing  <br>6.5 Speaking  <br>6.5 Reading  <br>6.5 Listening |"}, {"test_code": "TOEFL_IBT", "overall_score": 91, "component_scores": {}, "quote": "91 Overall, with at least   <br>23 Writing  <br>22 Speaking  <br>19 Reading  <br>19 Listening"}, {"test_code": "PTE", "overall_score": 72, "component_scores": {}, "quote": "72 Overall, with at least   <br>65 Writing  <br>66 Speaking  <br>64 Reading  <br>64 Listening"}, {"test_code": "CAE", "overall_score": 178, "component_scores": {}, "quote": "178 Overall, with at least   <br>180 Writing  <br>187 Speaking  <br>168 Reading  <br>168 Listening"}], "band 7.5": [{"test_code": "IELTS", "overall_score": 7.5, "component_scores": {}, "quote": "| Level 3 | 7.5 Overall, with at least   <br>7.0 Writing  <br>7.0 Speaking  <br>7.0 Reading  <br>7.0 Listening |"}, {"test_code": "TOEFL_IBT", "overall_score": 100, "component_scores": {}, "quote": "100 Overall, with at least   <br>26 Writing  <br>24 Speaking  <br>22 Reading  <br>22 Listening"}, {"test_code": "PTE", "overall_score": 78, "component_scores": {}, "quote": "78 Overall, with at least   <br>75 Writing  <br>76 Speaking  <br>72 Reading  <br>72 Listening"}, {"test_code": "CAE", "overall_score": 187, "component_scores": {}, "quote": "187 Overall, with at least   <br>193 Writing  <br>194 Speaking  <br>179179 Reading  <br>175 Listening"}]}}$j$::jsonb, 'proposed'
  from pipeline.provider_fact_sources fs where fs.id = '39f775ed-a07b-4e50-bd58-c3d95479a44d'
on conflict on constraint provider_policy_proposals_key do nothing;

-- 6 ACU: UAC's page for ACU as an English policy source (Platform Admin: "Yes, UAC for ACU")
insert into pipeline.provider_fact_sources(provider_id, kind, url, title, rank, found_via, status, attempts)
values ('030992c3-72c6-452d-8a3b-10ceb0fd77f2', 'english_policy', 'https://uac.edu.au/institutions/australian-catholic-university/english-language-proficiency',
        'ACU English language proficiency (UAC, published for ACU; Platform Admin 18 Oct 2026)', 0, 'manual', 'found', 0)
on conflict (provider_id, kind, url) do nothing;

-- job
insert into pipeline.automation_catalogue(jobname, area, sort, label, description, control_rank, batch_editable) values
 ('companion-read', 'Enrichment', 48, 'Companion pages (for example entry requirements)', 'Hourly: lists the companion page of every course whose university has one (the bound page address plus a suffix) and reads the due ones (scraper or direct, as set per university), keeping a stored copy and the values its patterns find (first: the English level on Melbourne''s Entry and participation requirements pages).', 4, true)
on conflict (jobname) do nothing;
select cron.schedule('companion-read', '41 * * * *',
  $$select security.companion_sync_v1(); select pipeline.svc_pilot_submit_nonce('coverage-sweep', jsonb_build_object('mode', 'companion_read', 'limit', security.pipeline_num_v1('batch.companion_read', 40)::int))$$);

insert into pipeline.component_register(kind, name, layer, purpose, status, introduced_in) values
 ('table', 'pipeline.uni_adapter_companions', 'Layer 2', 'Companion page of a university (suffix and patterns)', 'active', '20261018010000'),
 ('table', 'pipeline.course_companion_pages', 'Layer 2', 'Companion page of each course, its stored copy and values', 'active', '20261018010000'),
 ('job', 'companion-read', 'Layer 2', 'Reads due companion pages', 'active', '20261018010000'),
 ('function', 'security.companion_sync_v1', 'Layer 2', 'Lists companion pages for bound course pages', 'active', '20261018010000'),
 ('function', 'public.svc_companion_next', 'Layer 2', 'Due companion pages for the worker', 'active', '20261018010000'),
 ('function', 'public.svc_companion_record', 'Layer 2', 'Records a companion page reading', 'active', '20261018010000'),
 ('function', 'security.course_page_rebind_v1', 'Layer 2', 'Relinks a course to another page of the university''s site by rule (logged)', 'active', '20261018010000')
on conflict (kind, name) do nothing;

do $post$
begin
  if not exists (select 1 from cron.job where jobname = 'companion-read' and active) then raise exception 'Decision 265 post-check: job'; end if;
  if (select count(*) from pipeline.provider_policy_proposals where fact_source_id = '39f775ed-a07b-4e50-bd58-c3d95479a44d' and parser = 'written out from the central page' and status = 'proposed') <> 1 then
    raise exception 'Decision 265 post-check: Melbourne policy';
  end if;
  if (select count(*) from pipeline.enrichment_flags where reason_code = 'not_on_provider_site' and source = 'decision-265') < 170 then raise exception 'Decision 265 post-check: flags'; end if;
  if security.companion_sync_v1() < 0 then raise exception 'Decision 265 post-check: sync'; end if;
end $post$;
