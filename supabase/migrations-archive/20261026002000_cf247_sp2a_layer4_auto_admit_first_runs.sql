-- CF-247 SP-2a (26 Oct 2026). Platform Admin decision 26 Oct 2026 08:25: "Layer 4 stops being the stopgap. Apply the learning-loop
-- auto-admit escalation now, with its designed safeguards. My attendance becomes audit, not gate." Record: admin
-- docs/platform/ui-audit/2026-10-26-auto-admit-escalation.md.
--
-- A no-page or conjoint first run (SP-1, Layer 4 field codes no_page_first_run / conjoint_rule_first_run) is approved without a person
-- when all three hold, checked by the machine from stored data (no fetch):
--   1 the provider's own course list is current and verified: a course list page read within layer4.auto_admit_list_days, whose links
--     hold at least layer4.auto_admit_list_recall of the provider's bound official pages (at least layer4.auto_admit_min_bound of them);
--   2 the sample is confirmed: at least layer4.auto_admit_sample_pct of the sample (and at least layer4.auto_admit_min_sample courses)
--     has no unbound address on that list whose words cover layer4.auto_admit_match_share of the course title. A sample course that does
--     have such an address is marked "has a page" (it stays in the search), exactly as a person's edit-and-approve would;
--   3 the list shape matches a provider a person already approved: shape = how the list was read (map, sitemap, direct, firecrawl),
--     provider type, the depth of its course page addresses, plus "pdf" for a PDF list and "extra-domain" for a provider with an extra
--     course domain (NZIST / ITO sites). The CMS itself is not visible in stored data, so the shape is the stand-in. A shape no person has
--     approved yet is NOVEL and stays in Layer 4 (the first PDF list, the first ITO / extra-domain site, the first of any new shape),
--     with a note that approving it lets the others of that shape through.
-- Sampling audit: 1 in layer4.auto_admit_sample_rate (10) of the first runs that pass stays in Layer 4 for a person anyway.
-- Every outcome is recorded in pipeline.layer4_auto_admissions with its evidence; every auto-admission is written to
-- pipeline.layer4_decisions (system automation account, Decision 263) and to the Inbox Decided list as "Auto: <reason>".
-- Trust escalation is unchanged (the 60% rule in security.no_page_review_apply_v1); later cases for a trusted provider are recorded by
-- job no-page-propose as before; any later page found re-opens a recorded course. Nothing is deleted.
-- Job layer4-auto-admit (catalogued; hourly at :47) runs while layer4.auto_admit_on is 1 (set to 1 by the Platform Admin's decision).
-- Replaces: nothing
-- Retires: nothing
-- Nothing dropped or deleted. The consumer API is not touched.

insert into pipeline.platform_toolset_settings(toolset_key, key, label, help, kind, value, min_value, max_value, unit, sort, section, used_by, reason) values
 ('pipeline', 'layer4.auto_admit_on', 'Auto-admit first runs: on', '1: job layer4-auto-admit approves no-page and conjoint first runs that pass every check (course list verified, sample confirmed, list shape already approved by a person). 0: every first run waits for a person.', 'number', '1'::jsonb, 0, 1, 'on/off', 880, 'Layer 4', 'security.no_page_auto_admit_v1, job layer4-auto-admit', 'CF-247 SP-2a, Platform Admin 26 Oct 2026 08:25 ("apply now")'),
 ('pipeline', 'layer4.auto_admit_sample_rate', 'Auto-admit first runs: audit 1 in', 'One in this many first runs that pass every check still goes to Layer 4 for a person (sampling audit). Lower it to audit more; 1 sends every one.', 'number', '10'::jsonb, 1, 100, 'first runs', 881, 'Layer 4', 'security.no_page_auto_admit_v1', 'CF-247 SP-2a, Platform Admin 26 Oct 2026 08:25'),
 ('pipeline', 'layer4.auto_admit_sample_pct', 'Auto-admit first runs: sample confirmed from', 'Share of the first-run sample the machine must confirm (no unbound address on the provider''s course list looks like the course). 0.8 is 4 of 5.', 'number', '0.8'::jsonb, 0.6, 1, 'share', 882, 'Layer 4', 'security.no_page_auto_admit_v1', 'CF-247 SP-2a, Platform Admin 26 Oct 2026 08:25 (">= 4/5")'),
 ('pipeline', 'layer4.auto_admit_min_sample', 'Auto-admit first runs: sample at least', 'A first run with a smaller sample than this always goes to a person.', 'number', '3'::jsonb, 1, 20, 'courses', 883, 'Layer 4', 'security.no_page_auto_admit_v1', 'CF-247 SP-2a'),
 ('pipeline', 'layer4.auto_admit_list_recall', 'Auto-admit first runs: course list verified from', 'The provider''s course list counts as verified when its links hold at least this share of the provider''s bound official pages.', 'number', '0.7'::jsonb, 0.5, 1, 'share', 884, 'Layer 4', 'security.no_page_auto_admit_v1', 'CF-247 SP-2a'),
 ('pipeline', 'layer4.auto_admit_min_bound', 'Auto-admit first runs: bound pages at least', 'The list check needs at least this many bound official pages to measure against.', 'number', '20'::jsonb, 5, 500, 'pages', 885, 'Layer 4', 'security.no_page_auto_admit_v1', 'CF-247 SP-2a'),
 ('pipeline', 'layer4.auto_admit_list_days', 'Auto-admit first runs: course list read within', 'The course list page must have been read this recently.', 'number', '30'::jsonb, 7, 120, 'days', 886, 'Layer 4', 'security.no_page_auto_admit_v1', 'CF-247 SP-2a'),
 ('pipeline', 'layer4.auto_admit_match_share', 'Auto-admit first runs: look-alike address from', 'An unbound list address looks like a sample course when its words cover this share of the course title''s words; such a course is kept as "has a page".', 'number', '0.6'::jsonb, 0.3, 1, 'share', 887, 'Layer 4', 'security.no_page_auto_admit_v1', 'CF-247 SP-2a')
on conflict (toolset_key, key) do nothing;

create table if not exists pipeline.layer4_auto_admissions (
  review_item_id uuid primary key references pipeline.layer4_review_items(id),
  provider_id uuid not null,
  field_code text not null,
  shape text,
  outcome text not null check (outcome in ('auto_admitted', 'sampled_to_layer4', 'novel_shape', 'list_not_verified', 'sample_not_confirmed', 'no_list', 'off')),
  reason text not null,
  evidence jsonb not null default '{}'::jsonb,
  evaluated_at timestamptz not null default now(),
  decided_at timestamptz
);
comment on table pipeline.layer4_auto_admissions is 'CF-247 SP-2a (Platform Admin 26 Oct 2026 08:25): the machine check of each no-page / conjoint first run (list verified, sample confirmed, list shape already approved) with its evidence and outcome; auto_admitted and sampled_to_layer4 are final';
create index if not exists layer4_auto_admissions_outcome on pipeline.layer4_auto_admissions(outcome, decided_at);
alter table pipeline.layer4_auto_admissions enable row level security;

-- title or address words, without the level words every course shares
create or replace function security.np_words_v1(p text) returns text[]
language sql immutable set search_path to '' as $$
  select coalesce(array_agg(distinct w), '{}') from unnest(regexp_split_to_array(lower(regexp_replace(coalesce(p, ''), '[^A-Za-z0-9]+', ' ', 'g')), ' ')) w
   where length(w) > 2 and w not in ('the', 'and', 'with', 'for', 'honours', 'hons', 'bachelor', 'master', 'masters', 'diploma', 'graduate', 'postgraduate',
                                     'certificate', 'doctor', 'degree', 'course', 'courses', 'study', 'www', 'https', 'http', 'edu', 'html', 'aspx')
$$;

create or replace function security.np_addr_v1(p text) returns text
language sql immutable set search_path to '' as $$
  select rtrim(lower(regexp_replace(split_part(coalesce(p, ''), '?', 1), '^https?://(www\.)?', '')), '/')
$$;

-- the provider's course list as read: members, the share of its bound official pages on it, and the list shape
create or replace function security.course_list_check_v1(p_provider uuid) returns jsonb
language plpgsql stable security definer set search_path to '' as $$
declare v_bound int; v_on int; v_members int; v_depth int; v_via text; v_url text; v_read timestamptz; v_pdf boolean; v_extra boolean; v_type text;
begin
  select coalesce(l.read_via, l.fetched_via), l.url, l.read_at into v_via, v_url, v_read
    from pipeline.provider_course_lists l where l.provider_id = p_provider and l.status = 'read'
   order by (l.link_pattern is not null) desc, l.links_found desc nulls last limit 1;
  if v_url is null then return jsonb_build_object('list', false); end if;
  with mem as (
    select distinct security.np_addr_v1(x.url) u from pipeline.coverage_provider_urls x join pipeline.provider_course_lists l on l.provider_id = x.provider_id and l.status = 'read'
     where x.provider_id = p_provider and ((l.link_pattern is not null and x.url ~* l.link_pattern) or (l.link_pattern is null and x.source like '%course_list%'))),
  bnd as (
    select security.np_addr_v1(k.url) u,
           cardinality(regexp_split_to_array(trim(both '/' from regexp_replace(split_part(k.url, '?', 1), '^https?://[^/]+', '')), '/')) depth
      from catalogue.courses c join catalogue.course_links k on k.course_id = c.id and k.link_type = 'official_course' and k.status = 'active'
     where c.provider_id = p_provider and c.lifecycle_status = 'active')
  select (select count(*) from mem), (select count(*) from bnd), (select count(*) from bnd where bnd.u in (select mem.u from mem)),
         (select mode() within group (order by bnd.depth) from bnd)
    into v_members, v_bound, v_on, v_depth;
  v_pdf := exists (select 1 from pipeline.provider_course_lists l where l.provider_id = p_provider and l.status = 'read'
                    and (l.url ~* '\.pdf($|\?)' or coalesce(l.read_via, l.fetched_via, '') ilike '%pdf%'));
  v_extra := exists (select 1 from pipeline.provider_extra_domains e where e.provider_id = p_provider);
  select t.code into v_type from catalogue.providers p left join ref.provider_types t on t.id = p.provider_type_id where p.id = p_provider;
  return jsonb_build_object('list', true, 'url', v_url, 'via', v_via, 'read_at', v_read, 'members', v_members, 'bound', v_bound, 'on_list', v_on,
    'recall', case when v_bound > 0 then round(v_on::numeric / v_bound, 2) end,
    'shape', concat_ws('|', coalesce(v_via, 'unknown'), coalesce(v_type, 'unknown'), 'd' || coalesce(v_depth, 0),
                       case when v_pdf then 'pdf' end, case when v_extra then 'extra-domain' end));
end $$;
comment on function security.course_list_check_v1(uuid) is 'CF-247 SP-2a: the provider''s course list as read (members, share of bound official pages on it, list shape) for the auto-admit check';

-- the first-run sample: a sample course is confirmed when no unbound address on the provider's course list looks like it
create or replace function security.no_page_sample_check_v1(p_item uuid) returns jsonb
language plpgsql stable security definer set search_path to '' as $$
declare v_share numeric := security.pipeline_num_v1('layer4.auto_admit_match_share', 0.6); v_pid uuid; v jsonb;
begin
  select entity_id into v_pid from pipeline.layer4_review_items where id = p_item;
  with mem as (
    select distinct security.np_addr_v1(x.url) u from pipeline.coverage_provider_urls x join pipeline.provider_course_lists l on l.provider_id = x.provider_id and l.status = 'read'
     where x.provider_id = v_pid and ((l.link_pattern is not null and x.url ~* l.link_pattern) or (l.link_pattern is null and x.source like '%course_list%'))),
  bnd as (
    select security.np_addr_v1(k.url) u from catalogue.courses c join catalogue.course_links k on k.course_id = c.id and k.status = 'active' where c.provider_id = v_pid),
  unb as materialized (
    select m.u, security.np_words_v1(regexp_replace(m.u, '^[^/]*/', '')) w from mem m where m.u not in (select bnd.u from bnd where bnd.u is not null)),
  s as (
    select n.course_id, c.canonical_title t, security.np_words_v1(c.canonical_title) tw from pipeline.course_no_page n join catalogue.courses c on c.id = n.course_id
     where n.review_item_id = p_item),
  b as (
    select s.course_id, s.t, (select u.u from unb u order by cardinality(array(select unnest(s.tw) intersect select unnest(u.w))) desc limit 1) best_u,
           coalesce((select max(cardinality(array(select unnest(s.tw) intersect select unnest(u.w))))::numeric from unb u), 0) / greatest(cardinality(s.tw), 1) best
      from s)
  select jsonb_build_object('n', count(*), 'confirmed', count(*) filter (where best < v_share),
           'has_page', coalesce(jsonb_agg(jsonb_build_object('course_id', course_id, 'title', t, 'address', best_u, 'share', round(best, 2))) filter (where best >= v_share), '[]'::jsonb))
    into v from b;
  return v;
end $$;
comment on function security.no_page_sample_check_v1(uuid) is 'CF-247 SP-2a: machine confirmation of a no-page / conjoint first-run sample against the provider''s course list';

-- job layer4-auto-admit
create or replace function security.no_page_auto_admit_v1() returns jsonb
language plpgsql security definer set search_path to '' as $$
declare r record; v_sys uuid := 'c0ffee00-0000-4000-8000-000000000150';  -- fixed: the system automation account (Decision 263)
        v_rate int := security.pipeline_num_v1('layer4.auto_admit_sample_rate', 10)::int; v_list jsonb; v_s jsonb; v_out text; v_reason text;
        v_proven text[]; v_by text; v_n int; v_auto int := 0; v_audit int := 0; v_held int := 0; v_has jsonb; v_final jsonb; v_peers int;
begin
  if security.pipeline_num_v1('layer4.auto_admit_on', 0) < 1 then return jsonb_build_object('on', false); end if;
  -- each provider's course list check once a run (waiting first runs and first runs a person approved)
  if to_regclass('pg_temp._aa_list') is not null then drop table pg_temp._aa_list; end if;  -- a second run in one transaction
  create temp table _aa_list on commit drop as
    select x.provider_id, security.course_list_check_v1(x.provider_id) list
      from (select distinct li.entity_id provider_id from pipeline.layer4_review_items li
             where li.field_code in ('no_page_first_run', 'conjoint_rule_first_run') and li.status in ('pending', 'approved', 'edited_approved')) x;
  -- list shapes a person has approved (a first run approved in Layer 4 that this job did not admit)
  select coalesce(array_agg(distinct a.list->>'shape') filter (where a.list->>'shape' is not null), '{}')
    into v_proven
    from pipeline.layer4_review_items li join _aa_list a on a.provider_id = li.entity_id
   where li.field_code in ('no_page_first_run', 'conjoint_rule_first_run') and li.status in ('approved', 'edited_approved')
     and not exists (select 1 from pipeline.layer4_auto_admissions x where x.review_item_id = li.id and x.outcome = 'auto_admitted');

  for r in select li.* from pipeline.layer4_review_items li
            where li.status = 'pending' and li.field_code in ('no_page_first_run', 'conjoint_rule_first_run')
              and not exists (select 1 from pipeline.layer4_auto_admissions a where a.review_item_id = li.id and a.outcome in ('auto_admitted', 'sampled_to_layer4'))
            order by li.created_at loop
    select a.list into v_list from _aa_list a where a.provider_id = r.entity_id;
    v_s := security.no_page_sample_check_v1(r.id);
    v_out := null;
    if not (v_list->>'list')::boolean then
      v_out := 'no_list'; v_reason := 'No course list page read for this provider';
    elsif (v_list->>'read_at')::timestamptz < now() - make_interval(days => security.pipeline_num_v1('layer4.auto_admit_list_days', 30)::int)
       or coalesce((v_list->>'bound')::int, 0) < security.pipeline_num_v1('layer4.auto_admit_min_bound', 20)
       or coalesce((v_list->>'recall')::numeric, 0) < security.pipeline_num_v1('layer4.auto_admit_list_recall', 0.7) then
      v_out := 'list_not_verified';
      v_reason := format('Course list not verified: %s of %s bound pages on %s (read %s)', v_list->>'on_list', v_list->>'bound', v_list->>'url', left(v_list->>'read_at', 10));
    elsif (v_s->>'n')::int < security.pipeline_num_v1('layer4.auto_admit_min_sample', 3)
       or (v_s->>'confirmed')::numeric / greatest((v_s->>'n')::int, 1) < security.pipeline_num_v1('layer4.auto_admit_sample_pct', 0.8)
       or (r.field_code = 'conjoint_rule_first_run' and (v_s->>'confirmed')::int < (v_s->>'n')::int) then  -- a conjoint rule takes every course: none may look like it has a page
      v_out := 'sample_not_confirmed';
      v_reason := format('Sample %s of %s confirmed; the others have a look-alike address on the list', v_s->>'confirmed', v_s->>'n');
    elsif not ((v_list->>'shape') = any (v_proven)) then
      v_out := 'novel_shape';
      select count(*) into v_peers from pipeline.layer4_review_items x
       where x.status = 'pending' and x.field_code in ('no_page_first_run', 'conjoint_rule_first_run') and x.id <> r.id
         and (select a.list->>'shape' from _aa_list a where a.provider_id = x.entity_id) = v_list->>'shape';
      v_reason := format('New list shape %s (no person has approved one yet); approving this one lets %s other waiting first runs of the same shape be checked for auto-admission', v_list->>'shape', v_peers);
    end if;

    v_n := (select count(*) from pipeline.layer4_auto_admissions a where a.outcome in ('auto_admitted', 'sampled_to_layer4'));
    if v_out is null and v_rate > 0 and (v_n + 1) % v_rate = 0 then
      v_out := 'sampled_to_layer4';
      v_reason := format('Sampling audit (1 in %s): passed every check, kept for a person', v_rate);
    end if;

    if v_out is null then
      -- every check passed: approve as a person would, marking look-alike sample courses as having a page
      select coalesce(jsonb_agg(h->'course_id'), '[]'::jsonb) into v_has from jsonb_array_elements(v_s->'has_page') h;
      v_final := case when r.field_code = 'no_page_first_run' then jsonb_build_object('has_page_course_ids', v_has) else '{}'::jsonb end;
      select coalesce(p.display_name, p.canonical_name) into v_by from pipeline.layer4_review_items li join catalogue.providers p on p.id = li.entity_id
       where li.field_code in ('no_page_first_run', 'conjoint_rule_first_run') and li.status in ('approved', 'edited_approved')
         and not exists (select 1 from pipeline.layer4_auto_admissions a where a.review_item_id = li.id and a.outcome = 'auto_admitted')
         and (select a.list->>'shape' from _aa_list a where a.provider_id = li.entity_id) = v_list->>'shape' order by li.decided_at limit 1;
      v_reason := format('Auto: own course list verified (%s of %s bound pages on %s, read %s); sample %s of %s confirmed not on the list; list shape %s already approved for %s',
                         v_list->>'on_list', v_list->>'bound', v_list->>'url', left(v_list->>'read_at', 10), v_s->>'confirmed', v_s->>'n', v_list->>'shape', coalesce(v_by, 'a person-approved provider'));
      perform security.no_page_review_apply_v1(r.id, 'approve', v_final, v_reason);
      update pipeline.layer4_review_items set status = case when jsonb_array_length(v_has) > 0 then 'edited_approved' else 'approved' end, decided_at = now()
       where id = r.id and status = 'pending';
      insert into pipeline.layer4_decisions(review_item_id, action, actor_id, reason, before_value, proposed_value, final_value, evidence_id, layer2_state, layer3_state, change_control_ref)
      values (r.id, case when jsonb_array_length(v_has) > 0 then 'edit_and_approve' else 'approve' end, v_sys, v_reason, r.before_value, r.proposed_value, v_final, null,
              jsonb_build_object('list', v_list, 'sample', v_s), '{}'::jsonb, 'CF-CHG-20260915-247; SP-2a auto-admit (Platform Admin 26 Oct 2026 08:25)');
      insert into pipeline.admin_control_events(area, action, target, detail, actor)
      values ('layer4', 'inbox_decide', r.id::text, jsonb_build_object('kind', 'course_link', 'ref', r.id::text, 'choice', 'approve', 'value', null, 'reason', v_reason,
              'provider_id', r.entity_id, 'auto', true, 'field_code', r.field_code), v_sys);
      v_out := 'auto_admitted'; v_auto := v_auto + 1;
    elsif v_out = 'sampled_to_layer4' then
      update pipeline.layer4_review_items set escalation_reason = 'Sampling audit: passed every auto-admit check; please confirm. ' || coalesce(escalation_reason, '')
       where id = r.id and coalesce(escalation_reason, '') not like 'Sampling audit:%';
      v_audit := v_audit + 1;
    else
      v_held := v_held + 1;
      if v_out = 'novel_shape' then
        update pipeline.layer4_review_items set escalation_reason = v_reason || '. ' || regexp_replace(coalesce(escalation_reason, ''), '^New list shape [^.]*\. ', '')
         where id = r.id;
      end if;
    end if;

    insert into pipeline.layer4_auto_admissions(review_item_id, provider_id, field_code, shape, outcome, reason, evidence, evaluated_at, decided_at)
    values (r.id, r.entity_id, r.field_code, v_list->>'shape', v_out, v_reason, jsonb_build_object('list', v_list, 'sample', v_s), now(),
            case when v_out in ('auto_admitted', 'sampled_to_layer4') then now() end)
    on conflict (review_item_id) do update set shape = excluded.shape, outcome = excluded.outcome, reason = excluded.reason, evidence = excluded.evidence,
      evaluated_at = now(), decided_at = excluded.decided_at;
  end loop;
  return jsonb_build_object('on', true, 'auto_admitted', v_auto, 'sampled_to_layer4', v_audit, 'held', v_held, 'proven_shapes', to_jsonb(v_proven));
end $$;
comment on function security.no_page_auto_admit_v1() is 'CF-247 SP-2a (Platform Admin 26 Oct 2026 08:25): approves no-page / conjoint first runs whose course list is verified, sample confirmed and list shape already person-approved; 1 in layer4.auto_admit_sample_rate kept for a person';

revoke all on function security.no_page_auto_admit_v1() from public, anon, authenticated;
revoke all on function security.course_list_check_v1(uuid) from public, anon, authenticated;
revoke all on function security.no_page_sample_check_v1(uuid) from public, anon, authenticated;

insert into pipeline.automation_catalogue(jobname, area, sort, label, description, control_rank, batch_editable, layer23_stage) values
 ('layer4-auto-admit', 'Course pages', 37, 'Layer 4 first runs: auto-admit proven shapes',
  'Hourly at :47, while Auto-admit first runs: on is 1: checks each waiting no-page or conjoint first run against stored data. Approved without a person when the provider''s own course list is current and holds the set share of its bound pages, the set share of the sample has no look-alike address on that list, and a person has already approved a provider with the same list shape. New shapes (the first PDF list, the first extra-domain or ITO site, any shape not yet approved) stay in Layer 4; one in the set number that pass is kept for a person as an audit. Every outcome is recorded with its evidence; auto-admissions show in Decided as "Auto: <reason>".',
  6, false, null)
on conflict (jobname) do nothing;
select cron.schedule('layer4-auto-admit', '47 * * * *', $$select security.no_page_auto_admit_v1()$$);

insert into pipeline.component_register(kind, name, layer, purpose, status, replaces, introduced_in) values
 ('table', 'pipeline.layer4_auto_admissions', 'Layer 4', 'SP-2a: machine check and outcome of each no-page / conjoint first run', 'active', '{}', '20261026002000'),
 ('function', 'security.no_page_auto_admit_v1', 'Layer 4', 'SP-2a: auto-admit proven-shape first runs (job layer4-auto-admit)', 'active', '{}', '20261026002000'),
 ('function', 'security.course_list_check_v1', 'Layer 4', 'SP-2a: course list verified and list shape', 'active', '{}', '20261026002000'),
 ('function', 'security.no_page_sample_check_v1', 'Layer 4', 'SP-2a: first-run sample confirmed against the course list', 'active', '{}', '20261026002000')
on conflict do nothing;
