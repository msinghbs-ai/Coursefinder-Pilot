-- CF-247 S2 - BOOST (Platform Admin 18 Nov 2026 11:57, directive item 2: "surface clean candidate rows into Layer 4 review" for the 57
-- scholarships waiting to link to courses).
-- What the audit found (read 18 Nov 2026 12:10): 57 scholarships hold 18,023 proposed course links (scholarship.course_mapping_candidates,
-- status needs_review), all for one reason: provider_owned_but_no_explicit_course_or_provider_scope. Each is proposed against every course
-- of its provider (for example a School of Business scholarship against all 575 courses), so the rows are not clean one by one; what is
-- needed is a scope decision per scholarship. The decision path already exists (Course links screen, public.admin_scholarship_links_decide:
-- all courses, only matching courses by level, field or title word, or none, applied by security.scholarship_scope_apply_v1 with a
-- layer4_mass_operations row). These 57 were not in Layer 4 › Inbox.
-- What it does:
--   1. A rule-based scope suggestion per waiting scholarship (pipeline.scholarship_scope_suggestions), read only from the scholarship's own
--      name and description: study levels from words such as postgraduate, masters, doctoral, PhD, undergraduate, bachelor, first year,
--      school leavers; subject words from setting scholarship.scope_suggest_subjects found in that text, used as course title words. It
--      records the words found and how many of the proposed courses the filter keeps. No AI is called.
--   2. Inbox kind "Scholarship course links" (scholarship_course_links): one item per waiting scholarship, with the suggestion, its course
--      count and the text it rests on. Choices (Pipeline Operator or above, as on the Course links screen): Accept the suggested scope;
--      All courses of the provider; No courses. Each calls public.admin_scholarship_links_decide unchanged, so the decision is recorded
--      in pipeline.scholarship_scope_decisions and pipeline.layer4_mass_operations exactly as the Course links screen records it.
-- What it does not do: it decides nothing by itself, changes no existing function and nothing the consumer API reads in shape.
-- G1: no new job (suggestions are worked out when the migration runs and again when a suggestion is accepted). G2: the subject word list is a setting.
-- G3: no consumer API object is changed.
-- Replaces: nothing
-- Retires: nothing

set local lock_timeout = '5s';

do $pre$
begin
  if to_regprocedure('public.admin_scholarship_links_decide(uuid,text,jsonb,text)') is null or to_regprocedure('security.scholarship_scope_match(uuid,text,jsonb)') is null then
    raise exception 'the Course links decision path is not present';
  end if;
  if exists (select 1 from pipeline.layer4_inbox_kind_hooks where kind = 'scholarship_course_links') then raise exception 'Inbox kind scholarship_course_links already exists'; end if;
end $pre$;

-- 1. Setting: subject words looked for in a scholarship's name and description
insert into pipeline.platform_toolset_settings(toolset_key, key, label, help, kind, value, min_value, max_value, unit, sort, reason, section, used_by) values
 ('pipeline', 'scholarship.scope_suggest_subjects', 'Scholarship course links: subject words for the suggested scope',
  'Words looked for in a waiting scholarship''s own name and description. Each word found becomes a course title word of the suggested scope shown in Layer 4 › Inbox (Scholarship course links). A suggestion is only a starting point; the reviewer accepts it or chooses all or no courses.',
  'list', '["Accounting", "Agriculture", "Animal Science", "Architecture", "Art", "Business", "Commerce", "Computer", "Creative", "Dentistry", "Design", "Economics", "Education", "Engineering", "Finance", "Fine Arts", "Health", "Horticulture", "Human Resource", "Law", "Leadership", "Marine", "Medical", "Medicine", "Music", "Nursing", "Pharmacy", "Property", "Psychology", "Science", "Social", "Veterinary"]'::jsonb,
  0, null, 'words', 340, 'CF-247 S2 - BOOST, Platform Admin 18 Nov 2026 11:57 (scholarship course links into Layer 4)', 'Scholarships',
  'security.scholarship_scope_suggest_v1 (Layer 4 Inbox kind scholarship_course_links)')
on conflict (toolset_key, key) do nothing;

-- 2. Suggestions
create table if not exists pipeline.scholarship_scope_suggestions (
  scholarship_id    uuid primary key references scholarship.scholarships(id),
  filter            jsonb not null default '{}'::jsonb,
  levels_found      text[] not null default '{}',
  subjects_found    text[] not null default '{}',
  basis             text,
  candidate_courses int not null default 0,
  matched_courses   int not null default 0,
  computed_at       timestamptz not null default now()
);
comment on table pipeline.scholarship_scope_suggestions is 'CF-247 (Platform Admin 18 Nov 2026 11:57): a rule-based course scope suggested for a scholarship waiting to link to courses, read only from its own name and description: the study levels and subject words found, the filter they make, and how many of its proposed courses that filter keeps. Shown in Layer 4 › Inbox (Scholarship course links); accepting it calls the Course links decision.';
alter table pipeline.scholarship_scope_suggestions enable row level security;

create or replace function security.scholarship_scope_suggest_v1(p_scholarship_id uuid)
returns jsonb language plpgsql security definer set search_path to '' as $function$
declare s record; v_text text; v_levels text[] := '{}'; v_subj text[] := '{}'; v_ids jsonb; v_filter jsonb := '{}'::jsonb; v_cand int; v_match int := 0; w text;
begin
  select x.id, x.name, coalesce(x.description, '') description into s from scholarship.scholarships x where x.id = p_scholarship_id;
  if not found then return null; end if;
  v_text := s.name || ' ' || s.description;
  -- study levels, from the scholarship's own words
  if v_text ~* '\m(doctoral|doctorate|ph\.?d)\M' then v_levels := v_levels || array['doctorate']; end if;
  if v_text ~* '\m(masters?|master''s)\M' then v_levels := v_levels || array['masters', 'masters_coursework', 'masters_extended', 'masters_research']; end if;
  if v_text ~* '\mpostgraduate\M|\mgraduate (research|study|studies|students?)\M' and not (v_text ~* '\m(masters?|master''s|doctoral|doctorate|ph\.?d)\M') then
    v_levels := v_levels || array['graduate_certificate', 'graduate_diploma', 'masters', 'masters_coursework', 'masters_extended', 'masters_research', 'doctorate'];
  end if;
  if v_text ~* '\m(undergraduate|bachelor|first[- ]year|school leavers?|entry[- ]level|entrance)\M' then v_levels := v_levels || array['bachelor', 'bachelor_honours']; end if;
  select coalesce(array_agg(distinct l), '{}') into v_levels from unnest(v_levels) l;
  select coalesce(jsonb_agg(sl.id::text order by sl.code), '[]'::jsonb) into v_ids from ref.study_levels sl where sl.code = any (v_levels);
  -- subject words from the setting found in the scholarship's own words
  for w in select jsonb_array_elements_text(coalesce(security.toolset_setting('pipeline', 'scholarship.scope_suggest_subjects'), '[]'::jsonb)) loop
    if v_text ~* ('\m' || regexp_replace(w, '([.*+?^${}()|\[\]\\])', '\\\1', 'g') || '\M') then v_subj := v_subj || w; end if;
  end loop;
  if jsonb_array_length(v_ids) > 0 then v_filter := v_filter || jsonb_build_object('levels', v_ids); end if;
  if cardinality(v_subj) > 0 then v_filter := v_filter || jsonb_build_object('title', array_to_string(v_subj, ', ')); end if;
  select count(*) into v_cand from scholarship.course_mapping_candidates c where c.scholarship_id = p_scholarship_id and c.status = 'needs_review';
  if v_filter <> '{}'::jsonb then
    select count(*) into v_match from scholarship.course_mapping_candidates c
     where c.scholarship_id = p_scholarship_id and c.status = 'needs_review' and security.scholarship_scope_match(c.course_id, 'filter', v_filter);
  end if;
  insert into pipeline.scholarship_scope_suggestions (scholarship_id, filter, levels_found, subjects_found, basis, candidate_courses, matched_courses, computed_at)
  values (p_scholarship_id, v_filter, v_levels, v_subj, left(v_text, 600), v_cand, v_match, now())
  on conflict (scholarship_id) do update set filter = excluded.filter, levels_found = excluded.levels_found, subjects_found = excluded.subjects_found, basis = excluded.basis,
         candidate_courses = excluded.candidate_courses, matched_courses = excluded.matched_courses, computed_at = now();
  return jsonb_build_object('scholarship_id', p_scholarship_id, 'filter', v_filter, 'levels', v_levels, 'subjects', v_subj, 'candidates', v_cand, 'matched', v_match);
end $function$;
revoke all on function security.scholarship_scope_suggest_v1(uuid) from public, anon, authenticated;
comment on function security.scholarship_scope_suggest_v1(uuid) is 'CF-247 (Platform Admin 18 Nov 2026 11:57): works out the rule-based course scope suggested for a waiting scholarship from its own name and description, and how many of its proposed courses that scope keeps.';

-- the scholarships waiting for a course scope decision
create or replace function security.scholarship_links_waiting_v1()
returns table (scholarship_id uuid, provider_id uuid, name text, candidates bigint, oldest timestamptz)
language sql stable security definer set search_path to '' as $function$
  select s.id, s.provider_id, s.name, count(*), min(c.created_at)
    from scholarship.course_mapping_candidates c join scholarship.scholarships s on s.id = c.scholarship_id
   where c.status = 'needs_review' and not exists (select 1 from pipeline.scholarship_scope_decisions d where d.scholarship_id = s.id)
   group by s.id, s.provider_id, s.name
$function$;
revoke all on function security.scholarship_links_waiting_v1() from public, anon, authenticated;
comment on function security.scholarship_links_waiting_v1() is 'CF-247: scholarships with proposed course links waiting for a scope decision (none recorded yet).';

-- 3. The Inbox kind
create or replace function security.layer4_scholarship_links_kind_v1()
returns jsonb language sql immutable set search_path to '' as $function$
  select '{"label": "Scholarship course links", "order": 38, "choices": [
     {"key": "accept_suggested", "label": "Accept the suggested scope", "rank": 4, "returns": "The scholarship links to the proposed courses that match the suggested study levels and title words; the rest are refused"},
     {"key": "all_courses", "label": "All courses of the provider", "rank": 4, "returns": "The scholarship links to every proposed course of its provider"},
     {"key": "no_courses", "label": "No courses", "rank": 4, "returns": "No proposed course is linked; the proposals are refused"}]}'::jsonb
$function$;
revoke all on function security.layer4_scholarship_links_kind_v1() from public, anon, authenticated;

create or replace function security.layer4_scholarship_links_inbox_counts_v1()
returns jsonb language sql stable security definer set search_path to '' as $function$
  with o as (select * from security.scholarship_links_waiting_v1())
  select jsonb_build_object('kind', 'scholarship_course_links', 'n', (select count(*) from o), 'oldest', (select min(o.oldest) from o),
    'late', (select count(*) from o where o.oldest < now() - make_interval(days => security.pipeline_num_v1('layer4.target_days', 7)::int)),
    'by_provider', coalesce((select jsonb_agg(jsonb_build_object('provider_id', z.provider_id, 'n', z.n, 'oldest', z.oldest) order by z.oldest)
                               from (select o.provider_id, count(*) n, min(o.oldest) oldest from o group by 1) z), '[]'::jsonb))
$function$;
revoke all on function security.layer4_scholarship_links_inbox_counts_v1() from public, anon, authenticated;

create or replace function security.layer4_scholarship_links_inbox_page_v1(p_args jsonb)
returns jsonb language sql stable security definer set search_path to '' as $function$
  with o as (select w.* from security.scholarship_links_waiting_v1() w where nullif(p_args->>'provider_id', '') is null or w.provider_id = (p_args->>'provider_id')::uuid),
  x as (select o.* from o
         where nullif(p_args->>'after_ref', '') is null or (o.oldest, o.scholarship_id::text) > ((p_args->>'after_at')::timestamptz, p_args->>'after_ref')
         order by o.oldest, o.scholarship_id::text
         limit least(greatest(coalesce((p_args->>'limit')::int, 50), 1), 200))  -- fixed: page size bounds, as the Inbox's own
  select jsonb_build_object('kind', 'scholarship_course_links',
    'before', case when nullif(p_args->>'after_ref', '') is not null then
                (select count(*) from o where (o.oldest, o.scholarship_id::text) <= ((p_args->>'after_at')::timestamptz, p_args->>'after_ref')) end,
    'items', coalesce((select jsonb_agg(jsonb_build_object('kind', 'scholarship_course_links', 'ref', x.scholarship_id::text, 'provider_id', x.provider_id,
           'provider', (select coalesce(p.display_name, p.canonical_name) from catalogue.providers p where p.id = x.provider_id),
           'subject', x.name || ' · course links',
           'why', x.candidates || ' proposed courses: every course of the provider, because the scholarship page names no course or scope',
           'suggestion', (select case when g.filter = '{}'::jsonb then 'No scope found in its name or description; choose all or no courses'
                                      else 'Suggested scope keeps ' || g.matched_courses || ' of ' || g.candidate_courses || ' courses' end
                            from pipeline.scholarship_scope_suggestions g where g.scholarship_id = x.scholarship_id),
           'created_at', x.oldest,
           'late', x.oldest < now() - make_interval(days => security.pipeline_num_v1('layer4.target_days', 7)::int)) order by x.oldest, x.scholarship_id::text) from x), '[]'::jsonb))
$function$;
revoke all on function security.layer4_scholarship_links_inbox_page_v1(jsonb) from public, anon, authenticated;

create or replace function security.layer4_scholarship_links_inbox_detail_v1(p_ref text)
returns jsonb language plpgsql stable security definer set search_path to '' as $function$
declare g pipeline.scholarship_scope_suggestions; s record;
begin
  select x.id, x.name, x.source_url into s from scholarship.scholarships x where x.id::text = p_ref;
  if not found then return null; end if;
  select * into g from pipeline.scholarship_scope_suggestions where scholarship_id = s.id;
  return jsonb_build_object(
    'sections', jsonb_build_array(
      jsonb_build_object('key', 'scholarship', 'title', 'Scholarship', 'body', jsonb_build_object('Name', s.name, 'Page', s.source_url, 'Proposed courses', g.candidate_courses)),
      jsonb_build_object('key', 'suggestion', 'title', 'Suggested scope (from its own name and description)',
        'body', jsonb_build_object('Study levels found', coalesce(nullif(array_to_string(g.levels_found, ', '), ''), 'none'),
                                   'Subject words found', coalesce(nullif(array_to_string(g.subjects_found, ', '), ''), 'none'),
                                   'Courses the scope keeps', g.matched_courses || ' of ' || g.candidate_courses,
                                   'Read from', g.basis)),
      jsonb_build_object('key', 'kept', 'title', 'Courses the suggested scope keeps (first 25)',
        'body', coalesce((select jsonb_agg(t.title order by t.title) from (select coalesce(c.display_title, c.canonical_title) title
                                from scholarship.course_mapping_candidates m join catalogue.courses c on c.id = m.course_id
                               where m.scholarship_id = s.id and m.status = 'needs_review' and g.filter <> '{}'::jsonb and security.scholarship_scope_match(m.course_id, 'filter', g.filter)
                               order by 1 limit 25) t), '[]'::jsonb))),
    'actions', jsonb_build_array(jsonb_build_object('key', 'accept_suggested', 'allowed', g.filter <> '{}'::jsonb and g.matched_courses > 0),
                                 jsonb_build_object('key', 'all_courses', 'allowed', true), jsonb_build_object('key', 'no_courses', 'allowed', true)));
end $function$;
revoke all on function security.layer4_scholarship_links_inbox_detail_v1(text) from public, anon, authenticated;

create or replace function security.layer4_scholarship_links_inbox_decide_v1(p_ref text, p_choice text, p_value text, p_reason text)
returns jsonb language plpgsql security definer set search_path to '' as $function$
declare v_id uuid; g pipeline.scholarship_scope_suggestions; v_r jsonb; v_reason text := coalesce(nullif(btrim(coalesce(p_reason, '')), ''), 'Layer 4 Inbox: ' || p_choice);
begin
  select w.scholarship_id into v_id from security.scholarship_links_waiting_v1() w where w.scholarship_id::text = p_ref;
  if v_id is null then
    return jsonb_build_object('ok', false, 'kind', 'scholarship_course_links', 'choice', p_choice, 'ref', p_ref, 'request', 'These course links have already been decided; refresh the Inbox.');
  end if;
  if p_choice = 'accept_suggested' then
    perform security.scholarship_scope_suggest_v1(v_id);
    select * into g from pipeline.scholarship_scope_suggestions where scholarship_id = v_id;
    if g.filter = '{}'::jsonb or g.matched_courses = 0 then
      return jsonb_build_object('ok', false, 'kind', 'scholarship_course_links', 'choice', p_choice, 'ref', p_ref, 'request', 'There is no suggested scope that keeps a course; choose all or no courses, or set a scope on the Course links screen.');
    end if;
    v_r := public.admin_scholarship_links_decide(v_id, 'filter', g.filter, v_reason || ' (suggested scope: ' || coalesce(nullif(array_to_string(g.levels_found, ', '), ''), 'any level') || '; ' || coalesce(nullif(array_to_string(g.subjects_found, ', '), ''), 'any subject') || ')');
  elsif p_choice = 'all_courses' then
    v_r := public.admin_scholarship_links_decide(v_id, 'all', '{}'::jsonb, v_reason);
  elsif p_choice = 'no_courses' then
    v_r := public.admin_scholarship_links_decide(v_id, 'none', '{}'::jsonb, v_reason);
  else
    raise exception 'unknown choice %', p_choice using errcode = '22023';
  end if;
  return jsonb_build_object('ok', true, 'kind', 'scholarship_course_links', 'choice', p_choice, 'ref', p_ref, 'result', v_r->'result',
           'returns', coalesce((v_r->'result'->>'accepted'), '0') || ' course link(s) accepted, ' || coalesce((v_r->'result'->>'rejected'), '0') || ' refused.');
end $function$;
revoke all on function security.layer4_scholarship_links_inbox_decide_v1(text, text, text, text) from public, anon, authenticated;

insert into pipeline.layer4_inbox_kind_hooks(kind, mode, kind_fn, counts_fn, page_fn, detail_fn, decide_fn, enabled, owner, note)
values ('scholarship_course_links', 'kind', 'security.layer4_scholarship_links_kind_v1()', 'security.layer4_scholarship_links_inbox_counts_v1()', 'security.layer4_scholarship_links_inbox_page_v1(jsonb)',
        'security.layer4_scholarship_links_inbox_detail_v1(text)', 'security.layer4_scholarship_links_inbox_decide_v1(text,text,text,text)', true,
        'Scholarships (decided through public.admin_scholarship_links_decide)', 'Scholarships waiting for a course scope decision (Platform Admin 18 Nov 2026 11:57)')
on conflict (kind, mode) do nothing;

insert into pipeline.component_register (kind, name, layer, area, purpose, status, replaces, introduced_in) values
  ('table', 'pipeline.scholarship_scope_suggestions', 'Layer 4', 'Scholarships', 'Rule-based course scope suggested for each scholarship waiting to link to courses', 'active', '{}', '20261118143000'),
  ('function', 'security.scholarship_scope_suggest_v1', 'Layer 4', 'Scholarships', 'Works out the suggested course scope of a waiting scholarship', 'active', '{}', '20261118143000'),
  ('function', 'security.layer4_scholarship_links_inbox_decide_v1', 'Layer 4', 'Scholarships', 'Layer 4 Inbox decision on a scholarship''s course links (through the Course links decision)', 'active', '{}', '20261118143000')
on conflict do nothing;

-- 4. Suggestions for every waiting scholarship
select security.scholarship_scope_suggest_v1(w.scholarship_id) from security.scholarship_links_waiting_v1() w;

-- 5. Post-checks
do $c$
declare v_wait int; v_sugg int; v_hooks jsonb;
begin
  select count(*) into v_wait from security.scholarship_links_waiting_v1();
  select count(*) into v_sugg from pipeline.scholarship_scope_suggestions g where g.scholarship_id in (select scholarship_id from security.scholarship_links_waiting_v1());
  if v_sugg <> v_wait then raise exception 'post-check: % waiting scholarships but % suggestions', v_wait, v_sugg; end if;
  if (security.layer4_scholarship_links_inbox_counts_v1()->>'n')::int <> v_wait then raise exception 'post-check: the Inbox count is not the waiting scholarships'; end if;
  if exists (select 1 from pipeline.scholarship_scope_suggestions where matched_courses > candidate_courses) then raise exception 'post-check: a suggestion keeps more courses than proposed'; end if;
  v_hooks := security.layer4_inbox_hooks_v1();
  if exists (select 1 from jsonb_array_elements(coalesce(v_hooks->'failed', '[]'::jsonb) || coalesce(v_hooks->'missing', '[]'::jsonb)) x where x->>'id' like 'scholarship_course_links%') then
    raise exception 'post-check: the Inbox does not accept kind scholarship_course_links: %', v_hooks;
  end if;
  raise notice 'Scholarship course links: % waiting; % with a suggested scope', v_wait, (select count(*) from pipeline.scholarship_scope_suggestions where filter <> '{}'::jsonb and matched_courses > 0);
end $c$;
