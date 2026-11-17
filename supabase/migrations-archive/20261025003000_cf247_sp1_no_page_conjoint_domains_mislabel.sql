-- CF-247 SP-1 (speed programme release 1). Record: admin docs/platform/ui-audit/2026-10-25-speed-reconfiguration.md (mandate 22:05,
-- decisions 22:27, correction 22:50). Merge queue (Platform Admin 22:27): #694 gate consolidation → SP-1 → #695. Built on #694.
-- Accuracy gates unchanged: identity per kind, quote-on-page, floors, page_rejections consumed, manual bindings never touched.
--
-- 1 "No page published by the provider" (approved 22:27 exactly as designed). A course with a fresh inventory (discovery mapped within
--   bind.map_refresh_days) whose last bind.no_page_after_passes AI page matches all said none is proposed. The first case per provider
--   goes to Layer 4 (no_page_first_run: bind.no_page_sample courses beside the provider's inventory). The person marks any sample course
--   that does have a page; at least bind.no_page_trust_pct of the sample confirmed → the provider is trusted and its later cases are
--   recorded without a person; below it → not trusted, nothing recorded automatically. A recorded course leaves the course search (the one
--   stop gate returns 'no_page_by_provider') and the AI match (until a newer map); any later official page (any path) or AI-chosen page
--   re-opens it. Never deleted.
-- 2 Conjoint rule (approved 22:27): conjoint / combined / double degrees get one Layer 4 first run per provider (conjoint_rule_first_run)
--   with the provider's conjoint page from its inventory (or none: component pages). Approve → the rule is recorded and the provider's
--   conjoint courses leave the search lane with gap cause "conjoint or double degree". Binding them to the parent page needs a conjoint
--   identity kind (the page names both component degrees) so the identity gate holds: that is SP-2, stated in the PR, not done here.
-- 3 Extra course domains per provider (correction 22:50): a person adds one (Platform Admin, logged); discovery maps it and keeps its
--   addresses for the AI match. NZIST / ITO domains are the first candidates (PR lists them for confirmation).
-- 4 Gap causes: 'no page: not published by the provider', 'no page: conjoint or double degree (no page of its own)', 'no page: provider
--   site not answering' (discovery failed with 0 addresses).
-- 5 AI match gate widened (AU only; other countries are already in): providers with a tranche override, plus the top bind.match_scope_top_n
--   Australian providers by courses without a page, read from pipeline.bind_match_scope (refreshed by the job). AI only, no credits.
-- 6 Mislabel fix (S4-3): target-list refusals are recorded in firecrawl_budget_refusals / firecrawl_refusals_by_provider as
--   'target_list_refused' (public.svc_fc_refusal_note_v1, called by the worker v0.47.0), and the worker names the reason everywhere.
-- Job no-page-propose (catalogued; hourly at :37) runs only while bind.no_page_on is 1 (default 0: activation is the Platform Admin's step).
-- Replaces: nothing
-- Retires: nothing
-- Nothing dropped or deleted. The consumer API is not touched.

create or replace function pg_temp.edit_n(p_sig text, p_md5 text, p_edits text[][], p_times int[]) returns void language plpgsql as $f$
declare v_def text := pg_get_functiondef(p_sig::regprocedure); i int; v_c int;
begin
  if md5(v_def) <> p_md5 then raise exception 'live % differs from the definition this change edits (md5 %)', p_sig, md5(v_def); end if;
  for i in 1 .. array_length(p_edits, 1) loop
    v_c := (length(v_def) - length(replace(v_def, p_edits[i][1], ''))) / length(p_edits[i][1]);
    if v_c <> p_times[i] then raise exception '%: edit % must apply exactly % times (found %)', p_sig, i, p_times[i], v_c; end if;
    v_def := replace(v_def, p_edits[i][1], p_edits[i][2]);
  end loop;
  execute v_def;
end $f$;

-- ---------------------------------------------------------------- tables
create table pipeline.course_no_page (
  course_id uuid primary key references catalogue.courses(id),
  provider_id uuid not null references catalogue.providers(id),
  kind text not null check (kind in ('no_page', 'conjoint')),
  state text not null check (state in ('proposed', 'confirmed', 'confirmed_auto', 'conjoint', 'rejected', 'reopened')),
  basis jsonb not null default '{}'::jsonb,
  inventory_at timestamptz,
  review_item_id uuid references pipeline.layer4_review_items(id),
  proposed_at timestamptz not null default now(),
  decided_at timestamptz,
  reopened_at timestamptz,
  reopened_reason text,
  updated_at timestamptz not null default now()
);
comment on table pipeline.course_no_page is 'CF-247 SP-1: courses recorded as having no page published by the provider (kind no_page) or as a conjoint / double degree without a page of its own (kind conjoint). Proposed per provider in Layer 4 first, then trusted at the 60% rule; held out of course search and AI match; re-opened by any later page found; never deleted.';
create index course_no_page_provider_idx on pipeline.course_no_page (provider_id, kind, state);
create index course_no_page_review_idx on pipeline.course_no_page (review_item_id);
alter table pipeline.course_no_page enable row level security;

create table pipeline.no_page_trust (
  provider_id uuid not null references catalogue.providers(id),
  kind text not null check (kind in ('no_page', 'conjoint')),
  state text not null check (state in ('first_run', 'trusted', 'not_trusted')),
  sample int,
  confirmed int,
  parent_url text,
  review_item_id uuid references pipeline.layer4_review_items(id),
  decided_at timestamptz,
  created_at timestamptz not null default now(),
  primary key (provider_id, kind)
);
comment on table pipeline.no_page_trust is 'CF-247 SP-1: per provider and kind (no_page / conjoint), the Layer 4 first-run result: trusted (at least bind.no_page_trust_pct of the sample confirmed, or the conjoint rule approved with its parent page) or not trusted.';
create index no_page_trust_review_idx on pipeline.no_page_trust (review_item_id);
alter table pipeline.no_page_trust enable row level security;

create table pipeline.provider_extra_domains (
  provider_id uuid not null references catalogue.providers(id),
  domain text not null check (domain ~ '^[a-z0-9.-]+\.[a-z]{2,}$'),
  state text not null default 'approved' check (state in ('approved', 'withdrawn')),
  reason text not null,
  added_by uuid,
  added_at timestamptz not null default now(),
  mapped_at timestamptz,
  primary key (provider_id, domain)
);
comment on table pipeline.provider_extra_domains is 'CF-247 SP-1: extra course domains of a provider whose courses are published on another website (e.g. NZIST work-based learning on the ITO domains). Added by a person (Platform Admin, logged); discovery maps each and keeps its addresses for the AI page match.';
alter table pipeline.provider_extra_domains enable row level security;

create table pipeline.bind_match_scope (
  provider_id uuid primary key references catalogue.providers(id),
  why text not null,
  unbound int,
  refreshed_at timestamptz not null default now()
);
comment on table pipeline.bind_match_scope is 'CF-247 SP-1: Australian providers added to the AI page match beyond the focus set (tranche overrides and the top bind.match_scope_top_n by courses without a page), refreshed hourly by job no-page-propose; a row not refreshed in two hours is out of scope (nothing deleted).';
alter table pipeline.bind_match_scope enable row level security;

-- ---------------------------------------------------------------- settings
insert into pipeline.platform_toolset_settings(toolset_key, key, label, help, kind, value, min_value, max_value, unit, sort, section, used_by, reason) values
 ('pipeline', 'bind.no_page_on', 'No page published: proposals on', '1: job no-page-propose proposes courses with no page published by the provider (first run per provider to Layer 4) and records them for trusted providers. 0: off. Off until the Platform Admin activates it.', 'number', '0'::jsonb, 0, 1, 'on/off', 790, 'Course page search', 'security.no_page_propose_v1, job no-page-propose', 'CF-247 SP-1, Platform Admin 25 Oct 2026 22:27 (approved as designed)'),
 ('pipeline', 'bind.no_page_after_passes', 'No page published: AI passes first', 'A course is proposed only after this many AI page matches in a row found no page in a fresh inventory.', 'number', '2'::jsonb, 1, 5, 'AI passes', 791, 'Course page search', 'security.no_page_propose_v1', 'CF-247 SP-1'),
 ('pipeline', 'bind.map_refresh_days', 'No page published: inventory fresh within', 'The provider''s address inventory (discovery map) must be this recent for a course to be proposed.', 'number', '30'::jsonb, 7, 120, 'days', 792, 'Course page search', 'security.no_page_propose_v1', 'CF-247 SP-1'),
 ('pipeline', 'bind.no_page_sample', 'No page published: first-run sample', 'Courses shown to a person in the provider''s first run.', 'number', '5'::jsonb, 3, 20, 'courses', 793, 'Course page search', 'security.no_page_propose_v1', 'CF-247 SP-1'),
 ('pipeline', 'bind.no_page_trust_pct', 'No page published: trust from', 'Share of the first-run sample a person confirms (no page) for the provider to be trusted; the same 60% rule as tranches.', 'number', '0.6'::jsonb, 0.5, 1, 'share', 794, 'Course page search', 'security.no_page_review_apply_v1', 'CF-247 SP-1, 60% rule'),
 ('pipeline', 'bind.no_page_providers_per_run', 'No page published: providers a run', 'Providers looked at in one run of job no-page-propose.', 'number', '40'::jsonb, 1, 500, 'providers', 795, 'Course page search', 'job no-page-propose', 'CF-247 SP-1'),
 ('pipeline', 'bind.no_page_first_runs_per_run', 'No page published: new first runs a run', 'New Layer 4 first runs (no page or conjoint) opened in one hourly run, universities first, so Layer 4 is never flooded.', 'number', '10'::jsonb, 1, 100, 'first runs', 797, 'Course page search', 'security.no_page_propose_v1', 'CF-247 SP-1'),
 ('pipeline', 'bind.match_scope_top_n', 'AI page match: extra Australian providers', 'Australian providers outside the focus set whose courses without a page go to the AI page match (largest by such courses first); tranche overrides are always in.', 'number', '100'::jsonb, 0, 1000, 'providers', 796, 'Course page search', 'security.bind_match_scope_refresh_v1', 'CF-247 SP-1 (speed S1)')
on conflict (toolset_key, key) do nothing;

-- ---------------------------------------------------------------- helpers
create or replace function security.no_page_hold_v1(p_course uuid) returns boolean
language sql stable security definer set search_path to '' as $$
  -- held out of search and AI match: recorded no page / conjoint, and no newer inventory since it was recorded
  select exists (select 1 from pipeline.course_no_page n
                  where n.course_id = p_course and n.state in ('confirmed', 'confirmed_auto', 'conjoint')
                    and not exists (select 1 from pipeline.coverage_provider_discovery d where d.provider_id = n.provider_id
                                     and d.mapped_at > coalesce(n.inventory_at, n.proposed_at)))
$$;
comment on function security.no_page_hold_v1(uuid) is 'CF-247 SP-1: true while a course is recorded as having no page (or as conjoint) and no newer inventory exists; the stop gate and the AI match prepare ask it';

create or replace function security.conjoint_shape_v1(p_title text) returns boolean
language sql immutable set search_path to '' as $$
  select coalesce(p_title, '') ~* '\m(conjoint|combined|double degree|dual degree)\M|\m(bachelor|master|diploma)\M[^/]*/\s*\m(bachelor|master|diploma)\M'
$$;

create or replace function security.bind_match_scope_v1(p_provider uuid) returns boolean
language sql stable security definer set search_path to '' as $$
  select exists (select 1 from pipeline.bind_match_scope s where s.provider_id = p_provider and s.refreshed_at > now() - interval '2 hours')  -- fixed: two hourly refreshes; older rows have dropped out of the scope
$$;

create or replace function security.bind_match_scope_refresh_v1() returns int
language plpgsql security definer set search_path to '' as $$
declare v_n int;
begin
  insert into pipeline.bind_match_scope(provider_id, why, unbound)
  select x.provider_id, x.why, x.unbound from (
    select c.provider_id, case when exists (select 1 from pipeline.firecrawl_targets t where t.provider_id = c.provider_id and t.included) then 'tranche override' else 'top by courses without a page' end why,
           count(*) unbound, row_number() over (order by count(*) desc) rn,
           bool_or(exists (select 1 from pipeline.firecrawl_targets t where t.provider_id = c.provider_id and t.included)) ovr
      from catalogue.courses c join catalogue.providers p on p.id = c.provider_id join ref.countries k on k.id = p.country_id
     where c.lifecycle_status = 'active' and k.iso_alpha2 = 'AU'
       and not exists (select 1 from security.provider_hidden_v1 h where h.provider_id = c.provider_id)
       and not exists (select 1 from catalogue.course_links l where l.course_id = c.id and l.link_type = 'official_course' and l.status = 'active')
       and not security.enrich_focus_v1(c.provider_id)
     group by c.provider_id) x
   where x.ovr or x.rn <= security.pipeline_num_v1('bind.match_scope_top_n', 100)
  on conflict (provider_id) do update set why = excluded.why, unbound = excluded.unbound, refreshed_at = now();
  get diagnostics v_n = row_count;
  return v_n;
end $$;

-- ---------------------------------------------------------------- proposals (job no-page-propose)
create or replace function security.no_page_propose_v1() returns jsonb
language plpgsql security definer set search_path to '' as $$
declare r record; v_sample int := security.pipeline_num_v1('bind.no_page_sample', 5)::int; v_item uuid; v_first int := 0; v_auto int := 0; v_conj int := 0;
        v_passes int := security.pipeline_num_v1('bind.no_page_after_passes', 2)::int; v_scope int; v_parent text;
begin
  v_scope := security.bind_match_scope_refresh_v1();
  if security.pipeline_num_v1('bind.no_page_on', 0) < 1 then return jsonb_build_object('on', false, 'scope', v_scope); end if;
  if to_regclass('pg_temp._np_cand') is not null then drop table pg_temp._np_cand; end if;  -- a second run in one transaction
  create temp table _np_cand on commit drop as
    with pv as (select u.provider_id, count(*) inv from pipeline.coverage_provider_urls u group by 1)
    select c.id course_id, c.provider_id, c.canonical_title t, c.course_code code, security.conjoint_shape_v1(c.canonical_title) conj, d.mapped_at inv_at,
           coalesce(pv.inv, 0) inv
      from catalogue.courses c join pipeline.coverage_provider_discovery d on d.provider_id = c.provider_id left join pv on pv.provider_id = c.provider_id
     where c.lifecycle_status = 'active'
       and not exists (select 1 from security.provider_hidden_v1 h where h.provider_id = c.provider_id)
       and not exists (select 1 from catalogue.course_links l where l.course_id = c.id and l.link_type = 'official_course' and l.status = 'active')
       and not exists (select 1 from pipeline.coverage_course_pages pp where pp.course_id = c.id and pp.status = 'bound')
       and not exists (select 1 from pipeline.course_no_page n where n.course_id = c.id and n.state <> 'reopened')
       and d.status = 'mapped' and d.mapped_at > now() - make_interval(days => security.pipeline_num_v1('bind.map_refresh_days', 30)::int)
       and (security.conjoint_shape_v1(c.canonical_title)
            or (select count(*) = v_passes and bool_and(q.state in ('none', 'no_candidates'))
                  from (select q2.state from pipeline.coverage_ai_match q2 where q2.course_id = c.id order by q2.created_at desc limit v_passes) q))
       and c.provider_id in (select x.provider_id from (
             select c2.provider_id, count(*) n from catalogue.courses c2 where c2.lifecycle_status = 'active'
               and not exists (select 1 from catalogue.course_links l2 where l2.course_id = c2.id and l2.link_type = 'official_course' and l2.status = 'active')
             group by 1 order by 2 desc limit security.pipeline_num_v1('bind.no_page_providers_per_run', 40)::int * 10) x);

  -- universities first (Platform Admin 25 Oct 22:34: "top tiered universities ... finish them first"), then by courses without a page
  for r in select cd.provider_id, cd.conj from _np_cand cd join catalogue.providers p on p.id = cd.provider_id left join ref.provider_types pt on pt.id = p.provider_type_id
            group by cd.provider_id, cd.conj, pt.code order by (pt.code = 'university') desc nulls last, count(*) desc loop
    -- at most bind.no_page_first_runs_per_run new first runs a run, so Layer 4 is never flooded (universities come first)
    if (v_first + v_conj) >= security.pipeline_num_v1('bind.no_page_first_runs_per_run', 10)
       and not exists (select 1 from pipeline.no_page_trust t where t.provider_id = r.provider_id and t.kind = case when r.conj then 'conjoint' else 'no_page' end) then
      continue;
    end if;
    if r.conj then
      -- conjoint: one rule per provider, decided in Layer 4
      if not exists (select 1 from pipeline.no_page_trust t where t.provider_id = r.provider_id and t.kind = 'conjoint') then
        select u.url into v_parent from pipeline.coverage_provider_urls u where u.provider_id = r.provider_id
           and u.url ~* '(conjoint|double[-_]?degree|combined[-_]?degree|dual[-_]?degree)' order by length(u.url) limit 1;
        insert into pipeline.layer4_review_items(entity_type, entity_id, field_code, before_value, proposed_value, layer2_state, layer3_state, status, escalation_reason, change_control_ref)
        values ('provider', r.provider_id, 'conjoint_rule_first_run', jsonb_build_object('conjoint_courses_without_page', (select count(*) from _np_cand x where x.provider_id = r.provider_id and x.conj)),
                jsonb_build_object('parent_url', v_parent, 'mode', case when v_parent is null then 'components' else 'parent_page' end,
                  'sample', (select jsonb_agg(jsonb_build_object('course_id', x.course_id, 'title', x.t, 'code', x.code)) from (select * from _np_cand x2 where x2.provider_id = r.provider_id and x2.conj order by x2.t limit v_sample) x)),
                jsonb_build_object('source', 'SP-1 conjoint rule', 'inventory', (select max(x.inv) from _np_cand x where x.provider_id = r.provider_id)), '{}'::jsonb, 'pending',
                'Conjoint or double degrees: decide once for this provider whether they share its conjoint page (edit to correct the page) or have none; approved, they leave the course search',
                'CF-CHG-20260915-247')
        returning id into v_item;
        insert into pipeline.no_page_trust(provider_id, kind, state, parent_url, review_item_id) values (r.provider_id, 'conjoint', 'first_run', v_parent, v_item);
        insert into pipeline.course_no_page(course_id, provider_id, kind, state, basis, inventory_at, review_item_id)
        select x.course_id, x.provider_id, 'conjoint', 'proposed', jsonb_build_object('rule', 'conjoint shape', 'parent_url', v_parent), x.inv_at, v_item
          from _np_cand x where x.provider_id = r.provider_id and x.conj
        on conflict (course_id) do nothing;
        v_conj := v_conj + 1;
      elsif exists (select 1 from pipeline.no_page_trust t where t.provider_id = r.provider_id and t.kind = 'conjoint' and t.state = 'trusted') then
        insert into pipeline.course_no_page(course_id, provider_id, kind, state, basis, inventory_at, decided_at)
        select x.course_id, x.provider_id, 'conjoint', 'conjoint', jsonb_build_object('rule', 'conjoint shape, provider rule approved'), x.inv_at, now()
          from _np_cand x where x.provider_id = r.provider_id and x.conj
        on conflict (course_id) do update set state = 'conjoint', kind = 'conjoint', inventory_at = excluded.inventory_at, decided_at = now(), updated_at = now()
          where pipeline.course_no_page.state = 'reopened';
      end if;
    else
      if not exists (select 1 from pipeline.no_page_trust t where t.provider_id = r.provider_id and t.kind = 'no_page') then
        insert into pipeline.layer4_review_items(entity_type, entity_id, field_code, before_value, proposed_value, layer2_state, layer3_state, status, escalation_reason, change_control_ref)
        values ('provider', r.provider_id, 'no_page_first_run', jsonb_build_object('courses_proposed', (select count(*) from _np_cand x where x.provider_id = r.provider_id and not x.conj)),
                jsonb_build_object('sample', (select jsonb_agg(jsonb_build_object('course_id', x.course_id, 'title', x.t, 'code', x.code)) from (select * from _np_cand x2 where x2.provider_id = r.provider_id and not x2.conj order by md5(x2.course_id::text) limit v_sample) x),
                                   'inventory_addresses', (select max(x.inv) from _np_cand x where x.provider_id = r.provider_id), 'inventory_at', (select max(x.inv_at) from _np_cand x where x.provider_id = r.provider_id),
                                   'how', 'Approve if none of the sample courses has its own page on the provider''s site. If any has one, edit and approve with {"has_page_course_ids": [...]} (and the page address in the note); the provider is trusted only at the 60% rule.'),
                jsonb_build_object('source', 'SP-1 no page published by the provider', 'ai_passes', v_passes), '{}'::jsonb, 'pending',
                'No page published by the provider: check the sample once; trusted at the 60% rule, then later cases are recorded without a person (re-opened by any page found later)',
                'CF-CHG-20260915-247')
        returning id into v_item;
        insert into pipeline.no_page_trust(provider_id, kind, state, review_item_id) values (r.provider_id, 'no_page', 'first_run', v_item);
        insert into pipeline.course_no_page(course_id, provider_id, kind, state, basis, inventory_at, review_item_id)
        select x.course_id, x.provider_id, 'no_page', 'proposed', jsonb_build_object('ai_passes', v_passes, 'inventory_addresses', x.inv, 'sample', true), x.inv_at, v_item
          from (select * from _np_cand x2 where x2.provider_id = r.provider_id and not x2.conj order by md5(x2.course_id::text) limit v_sample) x
        on conflict (course_id) do nothing;
        v_first := v_first + 1;
      elsif exists (select 1 from pipeline.no_page_trust t where t.provider_id = r.provider_id and t.kind = 'no_page' and t.state = 'trusted') then
        insert into pipeline.course_no_page(course_id, provider_id, kind, state, basis, inventory_at, decided_at)
        select x.course_id, x.provider_id, 'no_page', 'confirmed_auto', jsonb_build_object('ai_passes', v_passes, 'inventory_addresses', x.inv, 'trusted_provider', true), x.inv_at, now()
          from _np_cand x where x.provider_id = r.provider_id and not x.conj
        on conflict (course_id) do update set state = 'confirmed_auto', kind = 'no_page', basis = excluded.basis, inventory_at = excluded.inventory_at, decided_at = now(), updated_at = now()
          where pipeline.course_no_page.state = 'reopened';
      end if;
    end if;
  end loop;
  select count(*) into v_auto from pipeline.course_no_page where state = 'confirmed_auto' and decided_at > now() - interval '5 minutes';  -- fixed: this run
  return jsonb_build_object('on', true, 'scope', v_scope, 'first_runs_no_page', v_first, 'first_runs_conjoint', v_conj, 'recorded_auto', v_auto);
end $$;

-- Layer 4 decision for the two first runs
create or replace function security.no_page_review_apply_v1(p_item uuid, p_action text, p_final jsonb, p_reason text) returns jsonb
language plpgsql security definer set search_path to '' as $$
declare t pipeline.no_page_trust%rowtype; v_sample int; v_has uuid[]; v_conf int; v_trusted boolean;
begin
  select * into t from pipeline.no_page_trust where review_item_id = p_item for update;
  if t.provider_id is null then raise exception 'no first run for this review item'; end if;
  if t.kind = 'no_page' then
    select count(*) into v_sample from pipeline.course_no_page where review_item_id = p_item;
    v_has := coalesce(array(select jsonb_array_elements_text(coalesce(p_final->'has_page_course_ids', '[]'::jsonb))::uuid), '{}');
    if p_action = 'approve' then
      update pipeline.course_no_page set state = case when course_id = any (v_has) then 'rejected' else 'confirmed' end, decided_at = now(), updated_at = now(),
             basis = basis || jsonb_build_object('decided', p_reason) where review_item_id = p_item;
      v_conf := v_sample - (select count(*) from pipeline.course_no_page where review_item_id = p_item and state = 'rejected');
      v_trusted := v_sample > 0 and v_conf::numeric / v_sample >= security.pipeline_num_v1('bind.no_page_trust_pct', 0.6);
    else
      update pipeline.course_no_page set state = 'rejected', decided_at = now(), updated_at = now(), basis = basis || jsonb_build_object('decided', p_reason)
       where review_item_id = p_item and state = 'proposed';
      v_conf := 0; v_trusted := false;
    end if;
    update pipeline.no_page_trust set state = case when v_trusted then 'trusted' else 'not_trusted' end, sample = v_sample, confirmed = v_conf, decided_at = now()
     where provider_id = t.provider_id and kind = 'no_page';
    return jsonb_build_object('no_page', true, 'sample', v_sample, 'confirmed', v_conf, 'trusted', v_trusted);
  else
    if p_action = 'approve' then
      update pipeline.no_page_trust set state = 'trusted', decided_at = now(), parent_url = coalesce(nullif(p_final->>'parent_url', ''), parent_url)
       where provider_id = t.provider_id and kind = 'conjoint';
      update pipeline.course_no_page set state = 'conjoint', decided_at = now(), updated_at = now(),
             basis = basis || jsonb_build_object('decided', p_reason, 'parent_url', coalesce(nullif(p_final->>'parent_url', ''), t.parent_url)) where review_item_id = p_item;
    else
      update pipeline.no_page_trust set state = 'not_trusted', decided_at = now() where provider_id = t.provider_id and kind = 'conjoint';
      update pipeline.course_no_page set state = 'rejected', decided_at = now(), updated_at = now(), basis = basis || jsonb_build_object('decided', p_reason)
       where review_item_id = p_item and state = 'proposed';
    end if;
    return jsonb_build_object('conjoint', true, 'approved', p_action = 'approve');
  end if;
end $$;

create or replace function security.no_page_review_trg_v1() returns trigger
language plpgsql security definer set search_path to '' as $$
begin
  if new.status in ('rejected', 'more_evidence', 'returned_layer2', 'returned_layer3', 'superseded') then
    perform security.no_page_review_apply_v1(new.id, new.status, null, 'Layer 4 ' || new.status);
  end if;
  return new;
end $$;
create trigger layer4_review_items_no_page after update of status on pipeline.layer4_review_items
  for each row when (old.status = 'pending' and new.status <> 'pending' and new.field_code in ('no_page_first_run', 'conjoint_rule_first_run'))
  execute function security.no_page_review_trg_v1();

-- re-open: any official page bound later, or the AI match choosing a page; a new "none" after a newer map refreshes the hold
create or replace function security.no_page_reopen_link_trg_v1() returns trigger
language plpgsql security definer set search_path to '' as $$
begin
  if new.link_type = 'official_course' and new.status = 'active' then
    update pipeline.course_no_page set state = 'reopened', reopened_at = now(), reopened_reason = 'official page bound: ' || left(coalesce(new.url, ''), 300), updated_at = now()
     where course_id = new.course_id and state <> 'reopened';
  end if;
  return new;
end $$;
create trigger course_links_no_page_reopen after insert or update of status on catalogue.course_links
  for each row execute function security.no_page_reopen_link_trg_v1();

create or replace function security.no_page_reopen_match_trg_v1() returns trigger
language plpgsql security definer set search_path to '' as $$
begin
  if new.state = 'chosen' then
    update pipeline.course_no_page set state = 'reopened', reopened_at = now(), reopened_reason = 'AI page match chose ' || left(coalesce(new.chosen_url, ''), 300), updated_at = now()
     where course_id = new.course_id and state <> 'reopened';
  elsif new.state in ('none', 'no_candidates') then
    update pipeline.course_no_page set inventory_at = now(), updated_at = now() where course_id = new.course_id and state in ('confirmed', 'confirmed_auto', 'conjoint');
  end if;
  return new;
end $$;
create trigger coverage_ai_match_no_page after insert or update of state on pipeline.coverage_ai_match
  for each row execute function security.no_page_reopen_match_trg_v1();

-- ---------------------------------------------------------------- Layer 4: the two first runs decide here (md5-guarded)
select pg_temp.edit_n('security.layer4_review_decide_impl(uuid,text,text,jsonb)', 'cd2ef4b97a3a88a78703f8aa53acc8b9', array[
  array[$o$    elsif v_item.entity_type='scholarship' and v_item.field_code='scope_resolution' then$o$,
        $n$    elsif v_item.entity_type='provider' and v_item.field_code in ('no_page_first_run','conjoint_rule_first_run') then
      -- CF-247 SP-1: first run per provider (no page published / conjoint rule); reject etc. are applied by trigger
      v_scalar:=security.no_page_review_apply_v1(v_item.id,'approve',v_final,trim(p_reason));
      v_scalar_id:=null;
    elsif v_item.entity_type='scholarship' and v_item.field_code='scope_resolution' then$n$]], array[1]);

select pg_temp.edit_n('security.layer4_review_desk_v1_impl(text,integer)', 'e93e9aea6d150000ff00a4b18559cd4d', array[
  array[$o$      else b.entity_type='course' end,false),$o$,
        $n$      when b.field_code in ('no_page_first_run','conjoint_rule_first_run') then jsonb_typeof(b.proposed_value)='object'
      else b.entity_type='course' end,false),$n$]], array[1]);

-- ---------------------------------------------------------------- the one stop gate (#694) holds recorded courses out of search
select pg_temp.edit_n('security.search_stop_gate_v1(uuid,uuid,boolean,boolean)', '6c23c9b70a40247ef1e28f55ab9bfead', array[
  array[$o$  -- the course stop (R2): too many different pages rejected for this course$o$,
        $n$  -- SP-1: recorded as no page published by the provider, or a conjoint degree under an approved rule
  if p_course is not null and security.no_page_hold_v1(p_course) then
    return 'no_page_by_provider';
  end if;
  -- the course stop (R2): too many different pages rejected for this course$n$]], array[1]);

-- ---------------------------------------------------------------- AI match: widened gate (AU), held courses skipped until a newer map
select pg_temp.edit_n('security.coverage_ai_match_prepare_v1(integer,integer)', '049a7cabd3a8140b2c300a3eed2ae73b', array[
  array[$o$              or security.course_list_read_v1(co.provider_id))  -- 22 Oct 2026: and any provider with a read course list page$o$,
        $n$              or security.course_list_read_v1(co.provider_id)  -- 22 Oct 2026: and any provider with a read course list page
              or security.bind_match_scope_v1(co.provider_id))  -- SP-1: tranche overrides and the top Australian providers by courses without a page$n$],
  array[$o$         and (p.course_id is null or p.status = 'mismatch')$o$,
        $n$         and (p.course_id is null or p.status = 'mismatch')
         and not security.no_page_hold_v1(co.id)  -- SP-1: recorded no page / conjoint, until a newer map$n$]], array[1, 2]);

select pg_temp.edit_n('security.page_match_bonus_v1(uuid,uuid)', '3c43fbdda1033db836b500c48342a73b', array[
  array[$o$  select greatest(security.course_list_bonus_v1(p_course, p_provider), security.page_rejection_bonus_v1(p_course))$o$,
        $n$  select greatest(security.course_list_bonus_v1(p_course, p_provider), security.page_rejection_bonus_v1(p_course),
                  -- SP-1: one more AI pass for a recorded course once a newer map exists (the re-open path)
                  case when exists (select 1 from pipeline.course_no_page n join pipeline.coverage_provider_discovery d on d.provider_id = n.provider_id
                                     where n.course_id = p_course and n.state in ('confirmed', 'confirmed_auto', 'conjoint') and d.mapped_at > coalesce(n.inventory_at, n.proposed_at))
                       then 1 else 0 end)$n$]], array[1]);

-- ---------------------------------------------------------------- gap causes (md5-guarded)
select pg_temp.edit_n('security.gap_causes_snapshot_v1()', '3ef32e232f373732e722a1a2054dbc83', array[
  array[$o$        when e.gs is null or e.gs <> 'bound' then case when e.ls = 'stopped'$o$,
        $n$        when (e.gs is null or e.gs <> 'bound') and exists (select 1 from pipeline.course_no_page np where np.course_id = e.id and np.state in ('confirmed', 'confirmed_auto')) then 'no page: not published by the provider'
        when (e.gs is null or e.gs <> 'bound') and exists (select 1 from pipeline.course_no_page np where np.course_id = e.id and np.state = 'conjoint') then 'no page: conjoint or double degree (no page of its own)'
        when (e.gs is null or e.gs <> 'bound') and exists (select 1 from pipeline.coverage_provider_discovery d where d.provider_id = e.provider_id and d.status = 'failed' and coalesce(d.url_count, 0) = 0) then 'no page: provider site not answering'
        when e.gs is null or e.gs <> 'bound' then case when e.ls = 'stopped'$n$],
  array[$o$           when z.cause like 'no page%' then$o$,
        $n$           when z.cause = 'no page: not published by the provider' then 'none: recorded (Layer 4 first run per provider, then the 60% rule); re-opened when a later map or a person finds a page'
           when z.cause = 'no page: conjoint or double degree (no page of its own)' then 'conjoint rule (Layer 4 first run per provider); binding to the parent page comes with SP-2'
           when z.cause = 'no page: provider site not answering' then 'discovery re-tries on its schedule; a person can correct the website or add a course domain'
           when z.cause like 'no page%' then$n$]], array[1, 1]);

-- ---------------------------------------------------------------- extra course domains: discovery maps them
create or replace function public.admin_provider_extra_domain(p_provider uuid, p_domain text, p_reason text) returns jsonb
language plpgsql security definer set search_path to '' as $$
declare v_d text := lower(regexp_replace(regexp_replace(trim(coalesce(p_domain, '')), '^https?://', ''), '/.*$', ''));
begin
  if auth.uid() is null or security.current_role_rank() < 6 then raise exception 'Platform Admin required' using errcode = '42501'; end if;
  if length(trim(coalesce(p_reason, ''))) < 5 then raise exception 'reason required'; end if;
  if security.third_party_host_v1('https://' || v_d) then raise exception 'a directory or third-party site is never a provider course domain'; end if;
  insert into pipeline.provider_extra_domains(provider_id, domain, reason, added_by) values (p_provider, v_d, trim(p_reason), auth.uid())
  on conflict (provider_id, domain) do update set state = 'approved', reason = excluded.reason, added_by = excluded.added_by, added_at = now();
  -- discovery runs again for the provider (status back to pending; nothing deleted)
  update pipeline.coverage_provider_discovery set status = 'pending', attempts = 0, next_due_at = now(), updated_at = now() where provider_id = p_provider;
  insert into pipeline.admin_control_events(area, action, target, detail, actor)
  values ('binding', 'extra_domain', 'pipeline.provider_extra_domains', jsonb_build_object('provider_id', p_provider, 'domain', v_d, 'reason', trim(p_reason)), auth.uid());
  return jsonb_build_object('ok', true, 'domain', v_d);
end $$;
revoke all on function public.admin_provider_extra_domain(uuid, text, text) from public, anon;
grant execute on function public.admin_provider_extra_domain(uuid, text, text) to authenticated;

select pg_temp.edit_n('public.svc_coverage_discovery_next(integer)', 'd7a00f4928be0f4ea8b610013e219cc0', array[
  array[$o$  select coalesce(jsonb_agg(jsonb_build_object('provider_id',u.provider_id,'website',u.website,$o$,
        $n$  select coalesce(jsonb_agg(jsonb_build_object('provider_id',u.provider_id,'website',u.website,
           'extra_domains',(select coalesce(jsonb_agg(x.domain order by x.domain),'[]'::jsonb) from pipeline.provider_extra_domains x where x.provider_id=u.provider_id and x.state='approved'),  -- SP-1$n$]], array[1]);

-- ---------------------------------------------------------------- mislabel fix: target-list refusals are recorded under their own name
create or replace function public.svc_fc_refusal_note_v1(p_purpose text, p_provider_id uuid, p_reason text) returns void
language plpgsql security definer set search_path to '' as $$
declare v_grp text := security.fc_purpose_group_v1(p_purpose);
begin
  if current_user <> 'postgres' and coalesce(auth.role(), '') <> 'service_role' then raise exception 'service_role required'; end if;
  if p_reason not in ('target_list_refused', 'credits_reserve', 'scholarship_share', 'no_firecrawl_key') then raise exception 'unknown refusal reason %', p_reason; end if;
  insert into pipeline.firecrawl_budget_refusals(day, grp, reason, n, last_at) values ((now() at time zone 'Australia/Melbourne')::date, v_grp, p_reason, 1, now())
  on conflict (day, grp, reason) do update set n = pipeline.firecrawl_budget_refusals.n + 1, last_at = now();
  if p_provider_id is not null then
    insert into pipeline.firecrawl_refusals_by_provider(day, provider_id, grp, reason, n, last_at) values ((now() at time zone 'Australia/Melbourne')::date, p_provider_id, v_grp, p_reason, 1, now())
    on conflict (day, provider_id, grp, reason) do update set n = pipeline.firecrawl_refusals_by_provider.n + 1, last_at = now();
  end if;
end $$;
revoke all on function public.svc_fc_refusal_note_v1(text, uuid, text) from public, anon, authenticated;
grant execute on function public.svc_fc_refusal_note_v1(text, uuid, text) to service_role;

-- the re-find wave looked for discovery runs stopped by "map:budget"; the worker now names the refusal
select pg_temp.edit_n('security.refind_wave_discovery_v1(text)', 'a52bb7a81beee0d95929375209cb9bf6', array[
  array[$o$coalesce(d.method, '') like '%map:budget%'$o$,
        $n$coalesce(d.method, '') ~ 'map:(budget|credits_refused|credits_reserve|target_list_refused|no_firecrawl_key)'$n$]], array[1]);

-- ---------------------------------------------------------------- job no-page-propose (catalogued; inert while bind.no_page_on is 0)
insert into pipeline.automation_catalogue(jobname, area, sort, label, description, control_rank, batch_editable, layer23_stage) values
 ('no-page-propose', 'Course pages', 36, 'No page published / conjoint: propose',
  'Hourly at :37: refreshes the AI page match scope (tranche overrides and the top Australian providers by courses without a page). While No page published: proposals on is 1, proposes courses with a fresh inventory that the AI page match found no page for after the set number of passes: the first case per provider goes to Layer 4 (a sample beside the inventory), and trusted providers (60% rule) have later cases recorded. Conjoint and double degrees get one Layer 4 rule per provider. Recorded courses leave the course search; any page found later re-opens them.',
  6, false, null)
on conflict (jobname) do nothing;
select cron.schedule('no-page-propose', '37 * * * *', $$select security.no_page_propose_v1()$$);

insert into pipeline.component_register(kind, name, layer, purpose, status, replaces, introduced_in) values
 ('table', 'pipeline.course_no_page', 'Layer 2', 'SP-1: no page published / conjoint, per course', 'active', '{}', '20261025003000'),
 ('table', 'pipeline.no_page_trust', 'Layer 4', 'SP-1: per-provider first-run result (60% rule)', 'active', '{}', '20261025003000'),
 ('table', 'pipeline.provider_extra_domains', 'Layer 2', 'SP-1: extra course domains a person added', 'active', '{}', '20261025003000'),
 ('table', 'pipeline.bind_match_scope', 'Layer 2', 'SP-1: AI page match scope beyond the focus set (AU)', 'active', '{}', '20261025003000'),
 ('function', 'security.no_page_propose_v1', 'Layer 2', 'SP-1 job no-page-propose', 'active', '{}', '20261025003000'),
 ('function', 'security.no_page_review_apply_v1', 'Layer 4', 'SP-1 first-run decisions', 'active', '{}', '20261025003000'),
 ('function', 'security.no_page_hold_v1', 'Layer 2', 'SP-1 hold out of search and AI match', 'active', '{}', '20261025003000'),
 ('function', 'security.bind_match_scope_refresh_v1', 'Layer 2', 'SP-1 AI match scope refresh', 'active', '{}', '20261025003000'),
 ('function', 'public.admin_provider_extra_domain', 'Layer 2', 'SP-1 Platform Admin adds a course domain', 'active', '{}', '20261025003000'),
 ('function', 'public.svc_fc_refusal_note_v1', 'Layer 2', 'SP-1 worker-side Firecrawl refusals recorded by name', 'active', '{}', '20261025003000'),
 ('job', 'no-page-propose', 'Layer 2', 'SP-1 hourly proposals (inert until bind.no_page_on)', 'active', '{}', '20261025003000')
on conflict (kind, name) do nothing;
