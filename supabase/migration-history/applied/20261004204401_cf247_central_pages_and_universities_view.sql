-- CF-247 Decision 254 (5 Oct 2026, Platform Admin 07:36): "build central rule and we can associate unis as applicable",
-- and a Universities tab under Completeness and Coverage with each university and its courses in tables.
--   * Central pages: the Platform Admin attaches a university's central English requirements page or key-dates page.
--     The provider-facts job reads it through Firecrawl (evidence kept in the evidence bucket), the policy parser turns it
--     into a proposal, and the proposal is approved in Layer 4 Review › Attributes as before. An approved English policy
--     fills only courses with no English requirement, so a course page reading (adapter) always comes first and a value
--     entered by hand is never changed.
--   * admin_universities_read: one row per target university (adapter state, admitted fields, exclusions, central
--     English rule and calendar state, coverage of intakes, English and fees with where each value came from).
--   * admin_university_courses_read: the courses of one university with each field's value and where it came from.
-- New functions only. No text value in this file contains a semicolon.

create or replace function public.admin_provider_central_page(p_action text, p_args jsonb) returns jsonb
language plpgsql security definer set search_path = '' as $f$
declare v_rank int := security.current_role_rank(); v_reason text := btrim(coalesce(p_args->>'reason', '')); v_pid uuid := (p_args->>'provider_id')::uuid;
        v_kind text := p_args->>'kind'; v_url text := btrim(coalesce(p_args->>'url', '')); v_id uuid;
begin
  if auth.uid() is null or coalesce(v_rank, 0) < 6 then raise exception 'Platform Admin required' using errcode = '42501'; end if;
  if p_action not in ('add', 'read_again') then raise exception 'unknown action'; end if;
  if length(v_reason) < 4 then raise exception 'give a reason (kept in the log)'; end if;
  if not exists (select 1 from catalogue.providers p where p.id = v_pid) then raise exception 'unknown provider'; end if;
  if coalesce(v_kind, '') not in ('english_policy', 'intake_calendar') then raise exception 'kind must be english_policy or intake_calendar'; end if;
  if v_url !~ '^https?://[^ ]{4,500}$' then raise exception 'give the full page address (http or https)'; end if;
  insert into pipeline.provider_fact_sources(provider_id, kind, url, title, rank, found_via, status)
    values (v_pid, v_kind, v_url, nullif(btrim(coalesce(p_args->>'title', '')), ''), 9, 'manual', 'found')
  on conflict (provider_id, kind, url) do update set status = 'found', attempts = 0, rank = 9, updated_at = now() where pipeline.provider_fact_sources.provider_id = excluded.provider_id
  returning id into v_id;
  insert into pipeline.admin_control_events(area, action, target, detail, actor)
    values ('toolsets', 'central_page_' || p_action, v_pid::text, jsonb_build_object('source_id', v_id, 'kind', v_kind, 'url', v_url, 'reason', v_reason), auth.uid());
  return jsonb_build_object('ok', true, 'source_id', v_id, 'note', 'The page is read through Firecrawl by the provider-facts job within about 10 minutes, then parsed into a proposal for approval in Layer 4 Review › Attributes.');
end $f$;
revoke all on function public.admin_provider_central_page(text, jsonb) from public, anon;
grant execute on function public.admin_provider_central_page(text, jsonb) to authenticated;

-- Where a held value came from: hand, central (policy or calendar), adapter (course page, the adapter's own reading),
-- reader (course page, general reader), other (another source), missing.
create or replace function security.university_course_fields_v1(p_provider_id uuid)
returns table(course_id uuid, course text, code text, level text, url text, read_status text, evidence_id uuid,
              intakes text[], intakes_src text, intakes_x boolean,
              ielts numeric, english_src text, english_x boolean,
              fee numeric, fee_year int, fee_currency text, fee_src text, fee_x boolean)
language sql stable security definer set search_path = '' as $f$
  select c.id, coalesce(c.display_title, c.canonical_title), c.course_code, sl.code, pg.url, pg.read_status, pg.evidence_id,
         i.months,
         case when i.months is null then 'missing'
              when exists (select 1 from pipeline.manual_locks k where k.entity = 'course' and k.entity_id = c.id and k.field in ('intakes', 'intake')) then 'hand'
              when i.calendar then 'central'
              when pg.evidence_id is not null and i.from_page then case when pg.candidates->>'intakes_by' = 'adapter' then 'adapter' else 'reader' end
              else 'other' end,
         security.uni_adapter_excluded(c.id, 'intakes'),
         e.overall_score,
         case when e.id is null then 'missing'
              when exists (select 1 from pipeline.manual_locks k where k.entity = 'course' and k.entity_id = c.id and k.field in ('english', 'english_requirements')) then 'hand'
              when e.source_requirement_key like 'policy:%' then 'central'
              when pg.evidence_id is not null and e.evidence_id = pg.evidence_id then case when pg.candidates->>'english_by' = 'adapter' then 'adapter' else 'reader' end
              else 'other' end,
         security.uni_adapter_excluded(c.id, 'english'),
         f.amount, f.fee_year, f.currency_code,
         case when f.id is null then 'missing'
              when exists (select 1 from pipeline.manual_locks k where k.entity = 'course' and k.entity_id = c.id and k.field in ('tuition', 'fee', 'fees')) then 'hand'
              when pg.evidence_id is not null and f.evidence_id = pg.evidence_id then case when pg.candidates->>'fee_by' = 'adapter' then 'adapter' else 'reader' end
              else 'other' end,
         security.uni_adapter_excluded(c.id, 'fee')
  from catalogue.courses c
  left join ref.study_levels sl on sl.id = c.study_level_id
  left join pipeline.coverage_course_pages pg on pg.course_id = c.id
  left join lateral (select array_agg(distinct x.intake_label order by x.intake_label) months,
                            bool_or(coalesce(x.source_intake_key, '') like 'calendar%') calendar,
                            bool_or(pg.evidence_id is not null and x.evidence_id = pg.evidence_id) from_page
                       from catalogue.course_intakes x where x.course_id = c.id and x.status = 'active') i on true
  left join lateral (select r.id, r.overall_score, r.source_requirement_key, r.evidence_id from catalogue.course_english_requirements r join ref.english_tests t on t.id = r.english_test_id
                      where r.course_id = c.id and t.code = 'IELTS' and coalesce(r.status, 'active') = 'active' order by r.last_verified_at desc nulls last limit 1) e on true
  left join lateral (select x.id, x.amount, x.fee_year, x.currency_code, x.evidence_id from catalogue.course_fees x
                      where x.course_id = c.id and x.status = 'active' and x.fee_type = 'provider_current_tuition' and x.audience = 'international'
                      order by x.fee_year desc nulls last, x.updated_at desc nulls last limit 1) f on true
  where c.provider_id = p_provider_id and c.lifecycle_status = 'active'
$f$;
revoke all on function security.university_course_fields_v1(uuid) from public, anon, authenticated;

create or replace function public.admin_universities_read(p_args jsonb default '{}'::jsonb) returns jsonb
language plpgsql stable security definer set search_path = '' as $f$
declare v_rank int := security.current_role_rank(); v_country text := nullif(upper(btrim(coalesce(p_args->>'country', ''))), ''); v_q text := nullif(btrim(coalesce(p_args->>'query', '')), '');
begin
  if auth.uid() is null or coalesce(v_rank, 0) < 4 then raise exception 'Layer 4 reviewer or Platform Admin required' using errcode = '42501'; end if;
  return jsonb_build_object('as_at', now(), 'universities', coalesce((
    select jsonb_agg(u order by u->>'name') from (
      select jsonb_build_object(
        'provider_id', t.provider_id, 'name', t.name, 'country', t.country, 'domain', t.domain,
        'adapter', (select jsonb_build_object('state', case when a.enabled and a.admit then 'admitting' when a.enabled then 'testing' else 'off' end,
                                              'fields', to_jsonb(a.admit_fields), 'admit_changed_at', a.admit_changed_at,
                                              'exclusions', (select count(*) from pipeline.uni_adapter_exclusions x where x.provider_id = a.provider_id and x.active))
                    from pipeline.uni_adapters a where a.provider_id = t.provider_id),
        'english_policy', (select jsonb_build_object('status', pp.status, 'style', pp.style, 'url', pp.url, 'decided_at', pp.decided_at)
                           from pipeline.provider_policy_proposals pp where pp.provider_id = t.provider_id and pp.kind = 'english_policy' and pp.status in ('approved', 'proposed', 'no_values')
                           order by (pp.status = 'approved') desc, (pp.status = 'proposed') desc, pp.updated_at desc limit 1),
        'calendar', (select jsonb_build_object('status', pp.status, 'style', pp.style, 'url', pp.url, 'decided_at', pp.decided_at)
                     from pipeline.provider_policy_proposals pp where pp.provider_id = t.provider_id and pp.kind = 'intake_calendar' and pp.status in ('approved', 'proposed', 'no_values')
                     order by (pp.status = 'approved') desc, (pp.status = 'proposed') desc, pp.updated_at desc limit 1),
        'central_pages', (select coalesce(jsonb_agg(jsonb_build_object('kind', s.kind, 'url', s.url, 'status', s.status, 'read_at', s.read_at, 'evidence_id', s.evidence_id) order by s.kind, s.rank desc), '[]'::jsonb)
                          from pipeline.provider_fact_sources s where s.provider_id = t.provider_id and s.found_via = 'manual' and s.kind in ('english_policy', 'intake_calendar')),
        'courses', m.courses, 'pages_read', m.pages_read,
        'intakes', jsonb_build_object('held', m.i_held, 'adapter', m.i_adapter, 'central', m.i_central, 'reader', m.i_reader, 'excluded', m.i_x),
        'english', jsonb_build_object('held', m.e_held, 'adapter', m.e_adapter, 'central', m.e_central, 'reader', m.e_reader, 'excluded', m.e_x),
        'fee', jsonb_build_object('held', m.f_held, 'adapter', m.f_adapter, 'reader', m.f_reader, 'excluded', m.f_x)) u
      from security.firecrawl_targets_fast() t
      cross join lateral (select count(*) courses, count(*) filter (where cf.read_status = 'read') pages_read,
                                 count(*) filter (where cf.intakes_src <> 'missing') i_held, count(*) filter (where cf.intakes_src = 'adapter') i_adapter,
                                 count(*) filter (where cf.intakes_src = 'central') i_central, count(*) filter (where cf.intakes_src = 'reader') i_reader, count(*) filter (where cf.intakes_x) i_x,
                                 count(*) filter (where cf.english_src <> 'missing') e_held, count(*) filter (where cf.english_src = 'adapter') e_adapter,
                                 count(*) filter (where cf.english_src = 'central') e_central, count(*) filter (where cf.english_src = 'reader') e_reader, count(*) filter (where cf.english_x) e_x,
                                 count(*) filter (where cf.fee_src <> 'missing') f_held, count(*) filter (where cf.fee_src = 'adapter') f_adapter,
                                 count(*) filter (where cf.fee_src = 'reader') f_reader, count(*) filter (where cf.fee_x) f_x
                          from security.university_course_fields_v1(t.provider_id) cf) m
      where (t.included or exists (select 1 from pipeline.uni_adapters a where a.provider_id = t.provider_id))
        and (v_country is null or t.country = v_country)
        and (v_q is null or t.name ilike '%' || v_q || '%')) z), '[]'::jsonb));
end $f$;
revoke all on function public.admin_universities_read(jsonb) from public, anon;
grant execute on function public.admin_universities_read(jsonb) to authenticated;

create or replace function public.admin_university_courses_read(p_provider_id uuid, p_args jsonb default '{}'::jsonb) returns jsonb
language plpgsql stable security definer set search_path = '' as $f$
declare v_rank int := security.current_role_rank(); v_show text := coalesce(p_args->>'show', 'all');
        v_limit int := greatest(1, least(coalesce((p_args->>'limit')::int, 100), 500)); v_offset int := greatest(0, coalesce((p_args->>'offset')::int, 0));
begin
  if auth.uid() is null or coalesce(v_rank, 0) < 4 then raise exception 'Layer 4 reviewer or Platform Admin required' using errcode = '42501'; end if;
  if v_show not in ('all', 'missing', 'excluded', 'adapter', 'central') then raise exception 'show must be all, missing, excluded, adapter or central'; end if;
  return (with cf as (select * from security.university_course_fields_v1(p_provider_id) x
                       where v_show = 'all'
                          or (v_show = 'missing' and 'missing' in (x.intakes_src, x.english_src, x.fee_src))
                          or (v_show = 'excluded' and (x.intakes_x or x.english_x or x.fee_x))
                          or (v_show = 'adapter' and 'adapter' in (x.intakes_src, x.english_src, x.fee_src))
                          or (v_show = 'central' and 'central' in (x.intakes_src, x.english_src)))
    select jsonb_build_object('total', (select count(*) from cf), 'offset', v_offset, 'limit', v_limit,
      'courses', coalesce((select jsonb_agg(jsonb_build_object('course_id', y.course_id, 'course', y.course, 'code', y.code, 'level', y.level, 'url', y.url, 'read_status', y.read_status, 'evidence_id', y.evidence_id,
                                     'intakes', jsonb_build_object('value', to_jsonb(y.intakes), 'source', y.intakes_src, 'excluded', y.intakes_x),
                                     'english', jsonb_build_object('value', y.ielts, 'source', y.english_src, 'excluded', y.english_x),
                                     'fee', jsonb_build_object('value', y.fee, 'year', y.fee_year, 'currency', y.fee_currency, 'source', y.fee_src, 'excluded', y.fee_x)) order by y.course)
                           from (select * from cf order by cf.course limit v_limit offset v_offset) y), '[]'::jsonb)));
end $f$;
revoke all on function public.admin_university_courses_read(uuid, jsonb) from public, anon;
grant execute on function public.admin_university_courses_read(uuid, jsonb) to authenticated;
