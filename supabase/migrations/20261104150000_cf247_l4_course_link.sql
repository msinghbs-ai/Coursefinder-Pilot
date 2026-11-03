-- CF-247 Layer 4 course link: stored copies on the cards, "Course page needed" (Decision 179), an honest refuse, a duplicate route for held
-- scholarships, wording for non-Australian providers, and validation of the approved university rules (Platform Admin mandate 3 Nov 2026 20:47,
-- admin docs/platform/nz-enrichment-brief/2026-11-03-layer4-integration-evidence-recovery-mandate-2047.md §5, §6; handover
-- 2026-11-03-layer4-integrator-handover-prompt.md Priority 2 and 2a; decisions of 20:29 and after 20:40 in
-- 2026-11-03-layer4-course-link-growth-review.md; playbook v6).
-- Why (live, read-only, 3 Nov 2026 20:50-21:08 AEDT):
--   * 3,233 official-link items wait; 2,412 have no stored copy linked, and 2,086 of those have a stored copy of the proposed address already
--     (no read needed). Fee cards (course fee holds) show "No stored copy is linked" although the course's page is stored (its binding has one).
--   * 2,295 waiting official-link items are binding refusals of a course with no held page: the page is already refused and recorded in
--     pipeline.page_rejections (all 2,295), and "Keep the page we hold" is false for them. What the course needs is a correct page.
--   * No choice closes a held scholarship as a duplicate (Macquarie ref 1184 duplicates published a347e086).
--   * The CRICOS-differs reason names a CRICOS code for 117 Canadian and 38 New Zealand items.
-- What:
--   1 Evidence: security.layer4_stored_copy_v1(url) finds the newest stored copy of an address however written. Trigger
--     layer4_review_items_zz_evidence links it to a new official-link or fee item that arrives without one (every generator passes there);
--     security.layer4_evidence_backfill_v1(limit, apply) links the waiting ones (run by the Integration Controller; audited). Fee and other
--     course-hold cards show the stored copy of the course's bound page. No read is made.
--   2 Decision 179: pipeline.course_page_needed, one row per course. security.binding_refusal_route_v1 (md5-guarded edit) records a refusal of a
--     course with no held page on that list instead of raising a review item (the refusal stays in pipeline.page_rejections; switch
--     layer4.page_needed_on). security.course_page_needed_convert_v1(provider, limit, apply) moves waiting refusal items of a university onto
--     the list (item superseded with the reason; history kept; never deleted), run by the Integration Controller one university at a time.
--     The list is a Layer 4 kind, "Course page needed", grouped by university like every kind, with Add the page (a person's verified page,
--     through the existing course edit), Search again (the existing course-link search, within its caps) and No page exists (evidence-backed,
--     recorded through the existing pipeline.course_no_page). Items where a held page is in dispute stay in Layer 4.
--   3 Course link: "Refuse this proposal", which records the refusal and claims no held page.
--   4 Held scholarship: "Duplicate of a published scholarship" closes the held item as refused, naming the published one
--     (pipeline.scholarship_duplicate_closures). The decision stays with the reviewer.
--   5 Wording: the CRICOS-differs reason and the code label say "course code" for providers outside Australia (display; stored text unchanged).
--   6 security.layer4_refusal_search_cost_v1(days): Firecrawl credits of the search lanes that feed refusals against the refusals they raised.
--   7 pipeline.layer4_course_link_rules (the three approved university rules), pipeline.layer4_review_owners (the ownership register in data),
--     security.layer4_course_link_rule_validate_v1(rule, item): pass or fail per item with reasons, and
--     security.layer4_course_link_rule_execute_v1(rule, limit, apply): item by item, validated again at execution, decided through
--     security.layer4_review_decide_impl under the system automation account with the rule and its approval reference; failed items stay
--     waiting with their reasons (pipeline.layer4_rule_runs, layer4_rule_run_items). Overnight mandate 3 Nov 2026 21:59 D1 and D2.
-- Edited live functions (md5-guarded, before -> after):
--   security.layer4_inbox_kinds_v1()                       f5fc812e0971a415b664926ec5dbdf8c -> e79ce1815952b4a0e59108981bf62c36
--   security.layer4_inbox_items_v1()                       a56bc3313e02ac0611deb5657da95ce0 -> 4fc05d14f4ba49335ff90496a20f582d
--   public.admin_layer4_inbox(text,jsonb)                  f1f0d760b682d6d132af0e8b55151292 -> 1fb975482d29c7c9f1ecdf3cdb011a10
--   security.binding_refusal_route_v1(uuid,text,jsonb,text,uuid) 488ef1836fa2ba842009168b9e499d73 -> 717fb44dd693550cb58f41a400aff455
-- Replaces: security.layer4_inbox_kinds_v1, security.layer4_inbox_items_v1, public.admin_layer4_inbox, security.binding_refusal_route_v1 (same
--   names; md5-guarded edits: new kind and choices, stored copies on course holds, wording, the refusal route for courses with no held page)
-- Retires: nothing (the per-proposal refusal item for a course with no held page is no longer raised while layer4.page_needed_on is 1)
-- Nothing is dropped or deleted. No consumer API object changes (G3). No Firecrawl or AI spend by this change (Search again is a person's
-- request through the existing search lane and its caps).

create or replace function pg_temp.edit_once(p_sig text, p_before text, p_after text, p_edits text[][], p_times int[]) returns text language plpgsql as $f$
declare v_def text := pg_get_functiondef(p_sig::regprocedure); i int; v_c int; v_old text; v_new text;
begin
  if md5(v_def) = p_after then return p_sig || ': already applied'; end if;
  if md5(v_def) <> p_before then raise exception 'live % differs from the definition this change edits (md5 %)', p_sig, md5(v_def); end if;
  for i in 1 .. array_length(p_edits, 1) loop
    -- fixed: line endings are normalised, so the edit applies the same however the text arrives
    v_old := replace(p_edits[i][1], chr(13), ''); v_new := replace(p_edits[i][2], chr(13), '');
    v_c := (length(v_def) - length(replace(v_def, v_old, ''))) / length(v_old);
    if v_c <> p_times[i] then raise exception '%: edit % must apply exactly % times (found %)', p_sig, i, p_times[i], v_c; end if;
    v_def := replace(v_def, v_old, v_new);
  end loop;
  execute v_def;
  if md5(pg_get_functiondef(p_sig::regprocedure)) <> p_after then
    raise exception '% after the edit has md5 %, expected %', p_sig, md5(pg_get_functiondef(p_sig::regprocedure)), p_after;
  end if;
  return p_sig || ': applied';
end $f$;

-- 1 settings (G2; Settings > Pipeline settings, section Layer 4 readiness) -----------------------------------------------------------------
insert into pipeline.platform_toolset_settings(toolset_key, key, label, help, kind, value, min_value, max_value, unit, sort, section, used_by, reason) values
 ('pipeline', 'layer4.evidence_link_on', 'Layer 4: link the stored copy of a proposed page',
  'On (1): a new official-link or fee item that arrives without a stored copy gets the newest stored copy of its proposed address (no read is made). Off (0): items arrive as raised.',
  'number', to_jsonb(1), 0, 1, 'on (1) or off (0)', 1230, 'Layer 4 readiness', 'trigger layer4_review_items_zz_evidence (security.layer4_evidence_link_trg_v1); security.layer4_evidence_backfill_v1',
  'Platform Admin mandate 3 Nov 2026 20:47 §5 "link existing stored page evidence"; records only, so it ships on'),
 ('pipeline', 'layer4.evidence_link_kinds', 'Layer 4: item kinds that get the stored copy linked',
  'Field codes whose new items get the newest stored copy of their proposed page when they arrive without one.',
  'list', '["official_course_url", "provider_current_tuition_validation", "provider_current_tuition"]'::jsonb, null, null, 'field codes', 1231, 'Layer 4 readiness',
  'security.layer4_evidence_link_trg_v1; security.layer4_evidence_backfill_v1', 'Handover 3 Nov 2026 Priority 2 item 6'),
 ('pipeline', 'layer4.page_needed_on', 'Layer 4: a refused page of a course with no held page goes to Course page needed',
  'On (1): when the binding check refuses a page for a course that has no official page, the refusal is recorded and the course joins the Course page needed list (grouped by university) instead of raising a review item. Off (0): a review item is raised as before.',
  'number', to_jsonb(1), 0, 1, 'on (1) or off (0)', 1232, 'Layer 4 readiness', 'security.binding_refusal_route_v1',
  'Platform Admin decision 3 Nov 2026 20:29 (Decision 179: one Course page needed list); admits nothing'),
 ('pipeline', 'layer4.page_needed_search_max', 'Course page needed: searches a person may ask for one course',
  'Search again is refused for a course after this many requests from the list (the search lane''s own monthly cap still applies).',
  'number', to_jsonb(3), 1, 20, 'searches', 1233, 'Layer 4 readiness', 'security.course_page_needed_decide_v1', 'Decision 179 (search again)'),
 ('pipeline', 'layer4.evidence_backfill_batch', 'Layer 4: items linked to their stored copy in one backfill call',
  'At most this many waiting items are linked to a stored copy in one call of the backfill.',
  'number', to_jsonb(500), 10, 5000, 'items', 1234, 'Layer 4 readiness', 'security.layer4_evidence_backfill_v1', 'Mandate 20:47 §5'),
 ('pipeline', 'layer4.page_needed_convert_batch', 'Course page needed: items moved onto the list in one call',
  'At most this many waiting refusal items are moved onto the Course page needed list in one call (one university at a time).',
  'number', to_jsonb(500), 10, 5000, 'items', 1235, 'Layer 4 readiness', 'security.course_page_needed_convert_v1', 'Platform Admin decision 3 Nov 2026 20:29'),
 ('pipeline', 'layer4.refusal_lane_purposes', 'Layer 4: search lanes and the Firecrawl purpose each one spends under',
  'lane=purpose pairs: the search lane recorded on a refused page and the Firecrawl ledger purpose of its searches. Used to report credits against refusals.',
  'list', '["firecrawl_search=fc_search", "cricos_search=course_link_search", "title_search=course_link_search"]'::jsonb, null, null, 'lane=purpose', 1236, 'Layer 4 readiness',
  'security.layer4_refusal_search_cost_v1', 'Handover 3 Nov 2026 Priority 2a "measure Firecrawl credit use by the search lanes that feed refusals"'),
 ('pipeline', 'layer4.rule_execute_batch', 'Layer 4 rules: items decided in one executor call',
  'At most this many items of an approved course-link rule are validated and decided in one call of the rule executor.',
  'number', to_jsonb(50), 1, 500, 'items', 1237, 'Layer 4 readiness', 'security.layer4_course_link_rule_execute_v1', 'Decision 263; overnight mandate 3 Nov 2026 21:59 D1, D2 (item by item)'),
 ('pipeline', 'layer4.rule_evidence_max_age_days', 'Layer 4 rules: oldest stored copy a strict rule accepts',
  'A strict rule (Simon Fraser) decides an item only when the stored copy of the page it uses is no older than this.',
  'number', to_jsonb(90), 1, 365, 'days', 1238, 'Layer 4 readiness', 'security.layer4_course_link_rule_validate_v1', 'Overnight mandate 3 Nov 2026 21:59 D2 ("current evidence")')
on conflict do nothing;

-- 2 tables ------------------------------------------------------------------------------------------------------------------------------------
create table if not exists pipeline.course_page_needed (
  course_id uuid primary key references catalogue.courses(id),
  provider_id uuid not null references catalogue.providers(id),
  state text not null default 'open' check (state in ('open', 'page_added', 'search_requested', 'no_page_exists')),
  refused int not null default 0,
  last_refused_url text,
  last_refused_reason text,
  last_refused_lane text,
  last_refused_evidence uuid,
  last_refused_at timestamptz,
  converted_items uuid[] not null default '{}',
  searches_requested int not null default 0,
  decided_by uuid,
  decided_at timestamptz,
  decision jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
comment on table pipeline.course_page_needed is 'CF-247 Decision 179 (Platform Admin 30 Sep 2026; decided for refusals 3 Nov 2026 20:29): courses that need a correct official page. One row per course. A refusal by the binding check of a course with no held page lands here (security.binding_refusal_route_v1) instead of raising a review item; the refusal itself stays in pipeline.page_rejections. Waiting refusal items moved here by security.course_page_needed_convert_v1 are listed in converted_items (each item superseded with the reason). Shown in Layer 4 as the kind Course page needed, grouped by university, while state is open and the course still has no official page; a person adds the page (state page_added), asks for another search (search_requested; the row reopens on the next refusal) or records an evidence-backed absence (no_page_exists, through pipeline.course_no_page). Never deleted. Never read by the consumer API.';
create index if not exists course_page_needed_open_idx on pipeline.course_page_needed (provider_id) where state = 'open';
alter table pipeline.course_page_needed enable row level security;
revoke all on pipeline.course_page_needed from public, anon, authenticated;

create table if not exists pipeline.scholarship_duplicate_closures (
  id bigserial primary key,
  review_id bigint not null,
  held_scholarship_id uuid,
  duplicate_of uuid not null,
  provider_id uuid,
  reason text not null,
  actor uuid,
  at timestamptz not null default now()
);
comment on table pipeline.scholarship_duplicate_closures is 'CF-247 (handover 3 Nov 2026 Priority 2 item 8): held scholarship reviews a person closed in Layer 4 as a duplicate of a published scholarship of the same provider (duplicate_of). The review itself is refused through the existing scholarship review path with the same reason; nothing on the published scholarship changes. Never read by the consumer API.';
create index if not exists scholarship_duplicate_closures_review_idx on pipeline.scholarship_duplicate_closures (review_id);
alter table pipeline.scholarship_duplicate_closures enable row level security;
revoke all on pipeline.scholarship_duplicate_closures from public, anon, authenticated;
revoke all on sequence pipeline.scholarship_duplicate_closures_id_seq from public, anon, authenticated;

create table if not exists pipeline.layer4_course_link_rules (
  code text primary key,
  provider_id uuid not null references catalogue.providers(id),
  choice text not null check (choice in ('keep', 'use')),
  reason_like text not null,
  held_regex text not null,
  proposed_replace text not null,
  identity_bases text[] not null,
  approved_by text not null,
  approved_at text not null,
  approved_items int not null,
  approval_ref text not null,
  strict boolean not null default false,
  note text,
  created_at timestamptz not null default now()
);
comment on table pipeline.layer4_course_link_rules is 'CF-247 Decision 263 logged rules for course links, as approved by the Platform Admin (3 Nov 2026, after 20:40 AEDT; admin 2026-11-03-layer4-course-link-growth-review.md): per university, the address pattern (held_regex on the held page key and proposed_replace giving the proposed page key), the choice (keep the held page or use the proposed one) the stored-copy identity bases accepted as exact course identity, the approval reference recorded on every decision, and strict (the course level and a current stored copy are verified too: Simon Fraser, overnight mandate 21:59 D2). Validated by security.layer4_course_link_rule_validate_v1; executed item by item only by security.layer4_course_link_rule_execute_v1 (Integration Controller, one university at a time). Never read by the consumer API.';
alter table pipeline.layer4_course_link_rules enable row level security;
revoke all on pipeline.layer4_course_link_rules from public, anon, authenticated;
insert into pipeline.layer4_course_link_rules(code, provider_id, choice, reason_like, held_regex, proposed_replace, identity_bases, approved_by, approved_at, approved_items, approval_ref, strict, note)
select x.code, x.pid, x.choice, x.reason_like, x.held_regex, x.proposed_replace, x.bases, 'Platform Admin', '3 Nov 2026, after 20:40 AEDT', x.n, x.ref, x.strict, x.note
  from (values
   ('adelaide_keep_held', 'de2201a1-69ee-40ff-b6aa-0e54e535e6c0'::uuid, 'keep', '%CRICOS code is a different address%', '^adelaide\.edu\.au/', 'adelaideuni.edu.au/', array['cricos_code'], 207,
    'Platform Admin 3 Nov 2026 after 20:40 (course-link growth review); overnight mandate 21:59 D1 (title-only matches stay for a person)', false,
    'Keep the held adelaide.edu.au page (international view, shows the course''s CRICOS code); stop raising the adelaideuni.edu.au pattern'),
   ('canberra_no_year', '0e1532b8-de30-4761-87fe-460684608633'::uuid, 'use', '%CRICOS code is a different address%', '/20[0-9]{2}$', '', array['cricos_code'], 100,
    'Platform Admin 3 Nov 2026 after 20:40 (course-link growth review); overnight mandate 21:59 D1 (title-only matches stay for a person)', false,
    'Use the address with no year (its canonical; it states the current year and will not date)'),
   ('sfu_no_term', 'd47b6006-396a-4785-b2ae-15186c3e7709'::uuid, 'use', '%CRICOS code is a different address%', '^(sfu\.ca/students/calendar/)20[0-9]{2}/(spring|summer|fall)/', '\1',
    array['field_award'], 59,
    'Platform Admin 3 Nov 2026 after 20:40 (course-link growth review); overnight mandate 21:59 D2 (field-and-award matches with identity, current evidence and course level verified)', true,
    'Use the address with no term (current calendar); the other 46 Simon Fraser items stay for separate review')) x(code, pid, choice, reason_like, held_regex, proposed_replace, bases, n, ref, strict, note)
 where exists (select 1 from catalogue.providers p where p.id = x.pid)
on conflict (code) do nothing;

-- 3 stored copies on the cards ------------------------------------------------------------------------------------------------------------
create or replace function security.layer4_stored_copy_v1(p_url text) returns uuid
language sql stable security definer set search_path to '' as $function$
-- The newest stored copy of an address however it is written (http or https, with or without www., a trailing slash or a fragment).
  select e.id from pipeline.evidence_artifacts e
   where lower(e.source_url) = any (array(select s || h || security.layer4_url_key_v1(p_url) || t
                                           from unnest(array['https://', 'http://']) s, unnest(array['', 'www.']) h, unnest(array['', '/']) t))
     and security.layer4_url_key_v1(p_url) is not null
   order by e.captured_at desc nulls last, e.created_at desc limit 1
$function$;
revoke all on function security.layer4_stored_copy_v1(text) from public, anon, authenticated;

create or replace function security.layer4_item_page_v1(p_field text, p_value jsonb, p_l2 jsonb) returns text
language sql immutable set search_path to '' as $function$
-- The page an item is about: the proposed address of a course link, the page a fee was read from.
  select nullif(btrim(coalesce(case jsonb_typeof(p_value) when 'string' then p_value #>> '{}' when 'object' then coalesce(p_value->>'course_url', p_value->>'url', p_value->>'page') end,
                               p_l2->>'page')), '')
$function$;
revoke all on function security.layer4_item_page_v1(text, jsonb, jsonb) from public, anon, authenticated;

create or replace function security.layer4_evidence_link_trg_v1() returns trigger
language plpgsql security definer set search_path to '' as $function$
-- Trigger layer4_review_items_zz_evidence (BEFORE INSERT): a new waiting item of a kind in layer4.evidence_link_kinds that arrives without a
-- stored copy gets the newest stored copy of its page. No read is made; nothing else changes.
begin
  if new.evidence_id is null and new.status = 'pending' and security.pipeline_num_v1('layer4.evidence_link_on', 1) >= 1
     and new.field_code = any (security.pipeline_list_v1('layer4.evidence_link_kinds', '[]'::jsonb)) then
    new.evidence_id := security.layer4_stored_copy_v1(security.layer4_item_page_v1(new.field_code, new.proposed_value, new.layer2_state));
  end if;
  return new;
end $function$;
revoke all on function security.layer4_evidence_link_trg_v1() from public, anon, authenticated;
do $t$ begin
  if not exists (select 1 from pg_trigger where tgname = 'layer4_review_items_zz_evidence' and tgrelid = 'pipeline.layer4_review_items'::regclass) then
    create trigger layer4_review_items_zz_evidence before insert on pipeline.layer4_review_items for each row execute function security.layer4_evidence_link_trg_v1();
  end if;
end $t$;

create or replace function security.layer4_evidence_backfill_v1(p_limit int, p_apply boolean) returns jsonb
language plpgsql security definer set search_path to '' as $function$
-- Links the newest stored copy of their page to waiting items of the kinds in layer4.evidence_link_kinds that have none (only evidence_id is
-- set; the item stays waiting). p_apply false counts only. Run by the Integration Controller; each applied call is audited.
declare r record; v_ev uuid; v_seen int := 0; v_link int := 0; v_none int := 0; v_by jsonb := '{}'::jsonb;
begin
  for r in select i.id, i.field_code, i.proposed_value, i.layer2_state from pipeline.layer4_review_items i
            where i.status = 'pending' and i.evidence_id is null and i.field_code = any (security.pipeline_list_v1('layer4.evidence_link_kinds', '[]'::jsonb))
            order by i.created_at, i.id limit least(greatest(coalesce(p_limit, 0), 0), security.pipeline_num_v1('layer4.evidence_backfill_batch', 500)::int) loop
    v_seen := v_seen + 1;
    v_ev := security.layer4_stored_copy_v1(security.layer4_item_page_v1(r.field_code, r.proposed_value, r.layer2_state));
    if v_ev is null then v_none := v_none + 1; continue; end if;
    v_by := jsonb_set(v_by, array[r.field_code], to_jsonb(coalesce((v_by->>r.field_code)::int, 0) + 1));
    if p_apply then
      update pipeline.layer4_review_items set evidence_id = v_ev where id = r.id and status = 'pending' and evidence_id is null;
      if found then v_link := v_link + 1; end if;
    end if;
  end loop;
  if p_apply then
    insert into pipeline.admin_control_events(area, action, target, detail, actor)
    values ('layer4', 'evidence_backfill', 'pipeline.layer4_review_items', jsonb_build_object('examined', v_seen, 'linked', v_link, 'no_copy', v_none, 'by_kind', v_by), auth.uid());
  end if;
  return jsonb_build_object('apply', p_apply, 'examined', v_seen, 'linkable', v_seen - v_none, 'linked', v_link, 'no_copy', v_none, 'by_kind', v_by,
                            'left', (select count(*) from pipeline.layer4_review_items i where i.status = 'pending' and i.evidence_id is null
                                       and i.field_code = any (security.pipeline_list_v1('layer4.evidence_link_kinds', '[]'::jsonb))));
end $function$;
revoke all on function security.layer4_evidence_backfill_v1(int, boolean) from public, anon, authenticated;

-- 4 Course page needed (Decision 179) -------------------------------------------------------------------------------------------------------
create or replace function security.course_page_needed_add_v1(p_course uuid, p_url text, p_reason text, p_lane text, p_evidence uuid, p_item uuid) returns text
language plpgsql security definer set search_path to '' as $function$
-- A refused page of a course with no held page: the course is on the list (opened again if a search was asked for and refused again).
declare v_prov uuid;
begin
  select c.provider_id into v_prov from catalogue.courses c where c.id = p_course;
  if v_prov is null then return 'nothing'; end if;
  insert into pipeline.course_page_needed as n(course_id, provider_id, refused, last_refused_url, last_refused_reason, last_refused_lane, last_refused_evidence, last_refused_at, converted_items)
  values (p_course, v_prov, 1, p_url, p_reason, p_lane, p_evidence, now(), case when p_item is null then '{}'::uuid[] else array[p_item] end)
  on conflict (course_id) do update set refused = n.refused + 1, last_refused_url = excluded.last_refused_url, last_refused_reason = excluded.last_refused_reason,
     last_refused_lane = excluded.last_refused_lane, last_refused_evidence = coalesce(excluded.last_refused_evidence, n.last_refused_evidence), last_refused_at = now(),
     converted_items = case when p_item is null or p_item = any (n.converted_items) then n.converted_items else n.converted_items || p_item end,
     state = case when n.state = 'search_requested' then 'open' else n.state end, updated_at = now();
  return 'page_needed';
end $function$;
revoke all on function security.course_page_needed_add_v1(uuid, text, text, text, uuid, uuid) from public, anon, authenticated;

create or replace function security.course_page_needed_convert_v1(p_provider uuid, p_limit int, p_apply boolean) returns jsonb
language plpgsql security definer set search_path to '' as $function$
-- Moves waiting binding-refusal items of one university whose course has no held page (none when raised, none now) and whose page is recorded
-- as refused onto the Course page needed list: the item is superseded with the reason (history kept, never deleted), the course listed once.
-- Items claimed by a reviewer, and every item with a held page, stay in Layer 4. p_apply false counts only. Platform Admin or the Integration
-- Controller (no signed-in user); each applied call is audited.
declare r record; v_seen int := 0; v_moved int := 0; v_skip jsonb := '{}'::jsonb; v_why text;
begin
  if auth.uid() is not null and coalesce(security.current_role_rank(), 0) < 6 then raise exception 'Platform Admin role required' using errcode = '42501'; end if;
  if p_provider is null then raise exception 'one university at a time: give its provider id' using errcode = '22023'; end if;
  for r in select i.id, i.entity_id, i.before_value, i.layer2_state, i.claimed_at, i.assigned_to, i.evidence_id, i.escalation_reason,
                  security.layer4_item_page_v1(i.field_code, i.proposed_value, i.layer2_state) url
             from pipeline.layer4_review_items i join catalogue.courses c on c.id = i.entity_id
            where i.status = 'pending' and i.field_code = 'official_course_url' and i.entity_type = 'course' and c.provider_id = p_provider
              and i.layer2_state->>'source' = 'binding check'
            order by i.created_at, i.id limit least(greatest(coalesce(p_limit, 0), 0), security.pipeline_num_v1('layer4.page_needed_convert_batch', 500)::int) loop
    v_seen := v_seen + 1;
    v_why := case
      when r.claimed_at is not null or r.assigned_to is not null then 'claimed_by_reviewer'
      when jsonb_typeof(r.before_value) = 'array' and jsonb_array_length(r.before_value) > 0 then 'held_page_when_raised'
      when exists (select 1 from catalogue.course_links l where l.course_id = r.entity_id and l.link_type = 'official_course' and l.status = 'active') then 'held_page_now'
      when not exists (select 1 from pipeline.page_rejections x where x.course_id = r.entity_id and security.layer4_url_key_v1(x.url) = security.layer4_url_key_v1(r.url)) then 'refusal_not_recorded'
    end;
    if v_why is not null then v_skip := jsonb_set(v_skip, array[v_why], to_jsonb(coalesce((v_skip->>v_why)::int, 0) + 1)); continue; end if;
    if p_apply then
      update pipeline.layer4_review_items set status = 'superseded', decided_at = now(),
             change_control_ref = coalesce(change_control_ref || '; ', '') || 'Decision 179 (Platform Admin 3 Nov 2026 20:29): moved to Course page needed (refused page, no held page)'
       where id = r.id and status = 'pending';
      if not found then continue; end if;
      perform security.course_page_needed_add_v1(r.entity_id, r.url, r.escalation_reason, r.layer2_state->>'lane', r.evidence_id, r.id);
    end if;
    v_moved := v_moved + 1;
  end loop;
  if p_apply then
    insert into pipeline.admin_control_events(area, action, target, detail, actor)
    values ('layer4', 'page_needed_convert', p_provider::text, jsonb_build_object('examined', v_seen, 'moved', v_moved, 'kept_in_layer4', v_skip), auth.uid());
  end if;
  return jsonb_build_object('apply', p_apply, 'provider_id', p_provider, 'examined', v_seen, 'moved', v_moved, 'kept_in_layer4', v_skip);
end $function$;
revoke all on function security.course_page_needed_convert_v1(uuid, int, boolean) from public, anon, authenticated;

create or replace function security.course_page_needed_decide_v1(p_course uuid, p_choice text, p_value text, p_reason text) returns jsonb
language plpgsql security definer set search_path to '' as $function$
-- A person's choice on the Course page needed list (through public.admin_layer4_inbox, which checks the role and the reason):
--   add_page      the verified page becomes the course's official page through the existing course edit (a person's value; read first in line)
--   search_again  the existing course-link search is asked again for this course (its own caps apply), at most layer4.page_needed_search_max
--   no_page       an evidence-backed absence: the address that shows the course has no page of its own, recorded in pipeline.course_no_page
--                 (confirmed), which stops further searching; reopened by any page found later
declare n pipeline.course_page_needed; v_r jsonb; v_url text := nullif(btrim(coalesce(p_value, '')), '');
begin
  select * into n from pipeline.course_page_needed where course_id = p_course for update;
  if n.course_id is null or n.state <> 'open' then raise exception 'this course is no longer on the Course page needed list' using errcode = 'P0002'; end if;
  if p_choice = 'add_page' then
    v_r := public.admin_course_edit(p_course, 'set_official_url', jsonb_build_object('url', v_url, 'reason', 'Course page needed: ' || p_reason));
    update pipeline.course_page_needed set state = 'page_added', decided_by = auth.uid(), decided_at = now(),
           decision = jsonb_build_object('choice', p_choice, 'url', v_url, 'reason', p_reason), updated_at = now() where course_id = p_course;
  elsif p_choice = 'search_again' then
    if n.searches_requested >= security.pipeline_num_v1('layer4.page_needed_search_max', 3) then
      raise exception 'another search was already asked for % times for this course: add the page or record that none exists', n.searches_requested;
    end if;
    insert into pipeline.course_link_search as s(course_id, provider_id, stage, state, attempts, requested_at)
    values (p_course, n.provider_id, 'cricos', 'queued', 0, now())
    on conflict (course_id) do update set stage = 'cricos', state = 'queued', attempts = 0, done_at = null, requested_at = now();
    update pipeline.course_page_needed set state = 'search_requested', searches_requested = searches_requested + 1, decided_by = auth.uid(), decided_at = now(),
           decision = jsonb_build_object('choice', p_choice, 'reason', p_reason), updated_at = now() where course_id = p_course;
    v_r := jsonb_build_object('requeued', true, 'searches_requested', n.searches_requested + 1);
  elsif p_choice = 'no_page' then
    if v_url is null or v_url !~* '^https://[^\s/]+\.[^\s]+$' then raise exception 'give the address (https://…) that shows the course has no page of its own'; end if;
    if length(btrim(coalesce(p_reason, ''))) < 10 then raise exception 'say what that page shows (kept as the evidence)'; end if;
    insert into pipeline.course_no_page as x(course_id, provider_id, kind, state, basis, decided_at, updated_at)
    values (p_course, n.provider_id, 'no_page', 'confirmed',
            jsonb_build_object('source', 'course_page_needed', 'evidence_url', v_url, 'evidence_copy', security.layer4_stored_copy_v1(v_url), 'reason', p_reason, 'by', auth.uid()), now(), now())
    on conflict (course_id) do update set kind = 'no_page', state = 'confirmed', basis = x.basis || excluded.basis, decided_at = now(), updated_at = now()
     where x.state in ('proposed', 'rejected', 'reopened');
    if not found then raise exception 'this course already has a no-page or conjoint record that a person decided; open the course instead'; end if;
    update pipeline.course_page_needed set state = 'no_page_exists', decided_by = auth.uid(), decided_at = now(),
           decision = jsonb_build_object('choice', p_choice, 'evidence_url', v_url, 'reason', p_reason), updated_at = now() where course_id = p_course;
    v_r := jsonb_build_object('no_page', 'confirmed', 'evidence_url', v_url);
  else
    raise exception 'choice % is not handled on the Course page needed list', p_choice;
  end if;
  return coalesce(v_r, '{}'::jsonb) || jsonb_build_object('course_id', p_course, 'state', (select state from pipeline.course_page_needed where course_id = p_course));
end $function$;
revoke all on function security.course_page_needed_decide_v1(uuid, text, text, text) from public, anon, authenticated;

-- the refusal route: a course with no held page goes to the list (the pending-item and decided-before checks are unchanged)
select pg_temp.edit_once('security.binding_refusal_route_v1(uuid,text,jsonb,text,uuid)', '488ef1836fa2ba842009168b9e499d73', '717fb44dd693550cb58f41a400aff455', array[
 array[$o$  select e.id into v_ev from pipeline.evidence_artifacts e where e.id = p_evidence;
$o$, $n$  -- Decision 179 (Platform Admin 3 Nov 2026 20:29): a refused page of a course with no held page raises no review item; the course joins the
  -- Course page needed list (the refusal is recorded above). A held page in dispute still comes to Layer 4.
  if security.pipeline_num_v1('layer4.page_needed_on', 1) >= 1
     and not exists (select 1 from catalogue.course_links l where l.course_id = p_course and l.link_type = 'official_course' and l.status = 'active') then
    return security.course_page_needed_add_v1(p_course, p_url, 'The page found automatically was not linked: ' || coalesce(p_check->>'reason', 'it is not proved to be this course''s page'),
                                              p_lane, (select e.id from pipeline.evidence_artifacts e where e.id = p_evidence), null);
  end if;
  select e.id into v_ev from pipeline.evidence_artifacts e where e.id = p_evidence;
$n$]], array[1]);

-- 5 honest refuse and the duplicate route ----------------------------------------------------------------------------------------------------
create or replace function security.layer4_course_link_refuse_v1(p_item uuid, p_reason text) returns jsonb
language plpgsql security definer set search_path to '' as $function$
-- "Refuse this proposal": the proposed page is recorded as refused for the course (pipeline.page_rejections, source layer4_refuse) and the item
-- is closed through the existing decision path (reject). Nothing is said about a held page; any page held stays as it is.
declare i pipeline.layer4_review_items; v_url text;
begin
  select * into i from pipeline.layer4_review_items where id = p_item;
  if i.id is null or i.status <> 'pending' then raise exception 'this item is no longer waiting (someone may have decided it)'; end if;
  if i.field_code <> 'official_course_url' or i.entity_type <> 'course' then raise exception 'this item is a fee, not a proposed page: use its own choices'; end if;
  v_url := security.layer4_item_page_v1(i.field_code, i.proposed_value, i.layer2_state);
  if v_url is not null then
    insert into pipeline.page_rejections(course_id, url, provider_id, evidence_id, source, reason, signals, rejected_by)
    select i.entity_id, v_url, c.provider_id, i.evidence_id, 'layer4_refuse', left(p_reason, 500), jsonb_build_object('review_item_id', i.id), auth.uid()
      from catalogue.courses c where c.id = i.entity_id
    on conflict (course_id, url) do nothing;
  end if;
  return public.layer4_review_decide(p_item, 'reject', p_reason, null);
end $function$;
revoke all on function security.layer4_course_link_refuse_v1(uuid, text) from public, anon, authenticated;

create or replace function security.scholarship_duplicate_close_v1(p_review bigint, p_target text, p_reason text) returns jsonb
language plpgsql security definer set search_path to '' as $function$
-- "Duplicate of a published scholarship": the named scholarship must be published, active and of the same provider, and not the held one.
-- The held review is refused through the existing scholarship review path with the duplicate named in the reason; the link is recorded.
declare r pipeline.scholarship_ai_reviews; v_t uuid; v_name text; v_res jsonb;
begin
  select * into r from pipeline.scholarship_ai_reviews where id = p_review;
  if r.id is null or r.status <> 'pending' then raise exception 'this held scholarship is no longer waiting'; end if;
  begin v_t := btrim(coalesce(p_target, ''))::uuid; exception when others then raise exception 'give the published scholarship''s id'; end;
  select s.name into v_name from scholarship.scholarships s
   where s.id = v_t and s.publication_status = 'published' and s.lifecycle_status = 'active' and s.provider_id = r.provider_id and s.id is distinct from r.scholarship_id;
  if v_name is null then raise exception 'that is not a published, active scholarship of the same provider'; end if;
  v_res := public.admin_scholarship_ai('review_decide', jsonb_build_object('review_id', p_review, 'decision', 'refuse',
             'reason', left('Duplicate of published scholarship ' || v_t || ' (' || v_name || '): ' || p_reason, 500)));
  insert into pipeline.scholarship_duplicate_closures(review_id, held_scholarship_id, duplicate_of, provider_id, reason, actor)
  values (p_review, r.scholarship_id, v_t, r.provider_id, p_reason, auth.uid());
  return jsonb_build_object('duplicate_of', v_t, 'name', v_name, 'review', v_res->'applied');
end $function$;
revoke all on function security.scholarship_duplicate_close_v1(bigint, text, text) from public, anon, authenticated;

-- 6 the Layer 4 kinds, items and decide router (md5-guarded edits) ---------------------------------------------------------------------------
select pg_temp.edit_once('security.layer4_inbox_kinds_v1()', 'f5fc812e0971a415b664926ec5dbdf8c', 'e79ce1815952b4a0e59108981bf62c36', array[
 array[$o${"key": "enter", "label": "Enter another address", "input": "url", "returns": "That address becomes the official page; it is read again and the adapter applies"}]},$o$,
       $n${"key": "enter", "label": "Enter another address", "input": "url", "returns": "That address becomes the official page; it is read again and the adapter applies"},
     {"key": "refuse", "label": "Refuse this proposal", "returns": "Closed; this page is recorded as refused for the course and is not asked again. Any page we hold stays as it is"}]},$n$],
 array[$o${"key": "not_scholarship", "label": "Not a scholarship", "reason": "Not a scholarship page", "returns": "Refused; the same page copy is not asked again"}]},$o$,
       $n${"key": "not_scholarship", "label": "Not a scholarship", "reason": "Not a scholarship page", "returns": "Refused; the same page copy is not asked again"},
     {"key": "duplicate", "label": "Duplicate of a published scholarship", "input": "scholarship", "returns": "Closed as a duplicate of the published scholarship you name (same provider); nothing on that scholarship changes"}]},$n$],
 array[$o$   "provider_departure": {$o$,
       $n$   "course_page_needed": {"label": "Course page needed", "order": 19, "choices": [
     {"key": "add_page", "label": "Add the page", "input": "url", "returns": "The verified page becomes the course''s official page (a person''s value, never overwritten); it is read first in line"},
     {"key": "search_again", "label": "Search again", "returns": "The course-link search looks for the page again within its own limits; the course comes back here if the next page found is refused"},
     {"key": "no_page", "label": "No page exists", "input": "url", "returns": "Recorded as no page of its own, with the address you give as evidence; searching stops until a page is found"}]},
   "provider_departure": {$n$]], array[1, 1, 1]);

select pg_temp.edit_once('security.layer4_inbox_items_v1()', 'a56bc3313e02ac0611deb5657da95ce0', '4fc05d14f4ba49335ff90496a20f582d', array[
 array[$o$         coalesce(nullif(r.escalation_reason, ''), 'Needs a decision'), null::text, r.created_at,
         jsonb_build_object('field_code', r.field_code, 'course_id', c.id, 'course_code', c.course_code, 'before', r.before_value, 'proposed', r.proposed_value,$o$,
       $n$         -- mandate 3 Nov 2026 20:47 §5: a CRICOS code is named only for Australian providers
         case when coalesce(kc.iso_alpha2, 'AU') <> 'AU' and r.escalation_reason ilike '%CRICOS%'
              then replace(replace(r.escalation_reason, 'this course''s CRICOS code', 'this course''s code'), 'CRICOS code', 'course code')
              else coalesce(nullif(r.escalation_reason, ''), 'Needs a decision') end, null::text, r.created_at,
         jsonb_build_object('field_code', r.field_code, 'course_id', c.id, 'course_code', c.course_code, 'before', r.before_value, 'proposed', r.proposed_value,
                            'code_label', case when coalesce(kc.iso_alpha2, 'AU') = 'AU' then 'CRICOS' else 'Course code' end,$n$],
 array[$o$    left join pipeline.evidence_artifacts ev on ev.id = r.evidence_id
   where r.status = 'pending'$o$,
       $n$    left join pipeline.evidence_artifacts ev on ev.id = r.evidence_id
    left join catalogue.providers pv on pv.id = coalesce(c.provider_id, s.provider_id)
    left join ref.countries kc on kc.id = pv.country_id
   where r.status = 'pending'$n$],
 array[$o$         jsonb_build_object('flag_id', f.id, 'course_id', c.id, 'course_code', c.course_code)
    from pipeline.enrichment_flags f left join catalogue.courses c on c.id::text = f.entity_key$o$,
       $n$         jsonb_build_object('flag_id', f.id, 'course_id', c.id, 'course_code', c.course_code,
                            -- mandate 3 Nov 2026 20:47 §5: the stored copy of the course's bound page, so a fee or course hold shows its evidence
                            'evidence_id', g.evidence_id, 'captured_at', gev.captured_at, 'source_url', gev.source_url)
    from pipeline.enrichment_flags f left join catalogue.courses c on c.id::text = f.entity_key
    left join pipeline.coverage_course_pages g on g.course_id = c.id
    left join pipeline.evidence_artifacts gev on gev.id = g.evidence_id$n$],
 array[$o$  union all
  -- counsellor reports from Zoho$o$,
       $n$  union all
  -- Decision 179 (Platform Admin 3 Nov 2026 20:29): courses that need a correct page, while open and still without an official page
  select 'course_page_needed', n.course_id::text, n.provider_id, coalesce(nullif(c.display_title, ''), c.canonical_title),
         'No page of this course has been verified. ' || n.refused || ' page' || case when n.refused = 1 then ' was' else 's were' end || ' found and refused, the last: '
           || coalesce(n.last_refused_reason, 'not proved to be this course''s page'),
         null, n.created_at,
         jsonb_build_object('course_id', c.id, 'course_code', c.course_code, 'code_label', case when coalesce(kc.iso_alpha2, 'AU') = 'AU' then 'CRICOS' else 'Course code' end,
                            'proposed', jsonb_build_object('course_url', n.last_refused_url), 'refused', n.refused, 'lane', n.last_refused_lane, 'converted_items', to_jsonb(n.converted_items),
                            'searches_requested', n.searches_requested, 'evidence_id', n.last_refused_evidence, 'captured_at', nev.captured_at, 'source_url', nev.source_url)
    from pipeline.course_page_needed n join catalogue.courses c on c.id = n.course_id
    left join catalogue.providers pv on pv.id = n.provider_id left join ref.countries kc on kc.id = pv.country_id
    left join pipeline.evidence_artifacts nev on nev.id = n.last_refused_evidence
   where n.state = 'open' and c.lifecycle_status = 'active'
     and not exists (select 1 from catalogue.course_links l where l.course_id = n.course_id and l.link_type = 'official_course' and l.status = 'active')
  union all
  -- counsellor reports from Zoho$n$]], array[1, 1, 1, 1]);

select pg_temp.edit_once('public.admin_layer4_inbox(text,jsonb)', 'f1f0d760b682d6d132af0e8b55151292', '1fb975482d29c7c9f1ecdf3cdb011a10', array[
 array[$o$  elsif v_kind = 'course_link' then
    v_r := public.layer4_review_decide($o$,
       $n$  elsif v_kind = 'course_link' and v_choice = 'refuse' then
    -- mandate 3 Nov 2026 20:47 §5: refuse the proposed page without claiming a held page
    v_r := security.layer4_course_link_refuse_v1(v_ref::uuid, v_reason);
  elsif v_kind = 'course_page_needed' then
    -- Decision 179 (Platform Admin 3 Nov 2026 20:29): add the page, search again, or record that no page exists
    v_r := security.course_page_needed_decide_v1(v_ref::uuid, v_choice, v_value, v_reason);
  elsif v_kind = 'held_scholarship' and v_choice = 'duplicate' then
    -- handover 3 Nov 2026 Priority 2 item 8: close a held scholarship as a duplicate of a published one (the reviewer names it)
    v_r := security.scholarship_duplicate_close_v1(v_ref::bigint, v_value, v_reason);
  elsif v_kind = 'course_link' then
    v_r := public.layer4_review_decide($n$]], array[1]);

-- 7 Firecrawl credits of the search lanes that feed refusals (read only) ------------------------------------------------------------------
create or replace function security.layer4_refusal_search_cost_v1(p_days int) returns jsonb
language sql stable security definer set search_path to '' as $function$
-- Per search lane (layer4.refusal_lane_purposes): refusals raised in the window (review items from the binding check, and courses put on the
-- Course page needed list) against the Firecrawl credits its purpose spent in the same window. Credits also buy pages that were verified,
-- so credits per refusal is an upper bound, not an attribution.
  with lanes as (select split_part(x, '=', 1) lane, split_part(x, '=', 2) purpose from unnest(security.pipeline_list_v1('layer4.refusal_lane_purposes', '[]'::jsonb)) x),
       since as (select now() - make_interval(days => greatest(coalesce(p_days, 1), 1)) t),
       ref as (select coalesce(i.layer2_state->>'lane', '-') lane, count(*) n from pipeline.layer4_review_items i, since
                where i.field_code = 'official_course_url' and i.layer2_state->>'source' = 'binding check' and i.created_at >= since.t group by 1
               union all
               select coalesce(n.last_refused_lane, '-'), count(*) from pipeline.course_page_needed n, since where n.last_refused_at >= since.t and cardinality(n.converted_items) = 0 group by 1),
       spend as (select u.purpose, sum(u.units) credits, count(*) calls from pipeline.coverage_vendor_usage u, since where u.at >= since.t group by 1)
  select jsonb_build_object('days', p_days, 'lanes', coalesce((select jsonb_agg(jsonb_build_object('lane', l.lane, 'purpose', l.purpose,
             'refusals', coalesce((select sum(r.n) from ref r where r.lane = l.lane), 0),
             'purpose_credits', coalesce((select s.credits from spend s where s.purpose = l.purpose), 0),
             'purpose_calls', coalesce((select s.calls from spend s where s.purpose = l.purpose), 0)) order by l.lane) from lanes l), '[]'::jsonb),
           'other_lanes', (select coalesce(jsonb_object_agg(r.lane, r.n), '{}'::jsonb) from (select lane, sum(n) n from ref where lane not in (select lane from lanes) group by 1) r))
$function$;
revoke all on function security.layer4_refusal_search_cost_v1(int) from public, anon, authenticated;

-- 8 approved university rules (Decision 263): who owns which review, per-item validation, and the item-by-item executor ---------------------
-- the ownership register in data (admin docs/platform/nz-enrichment-brief/2026-11-03-layer4-review-ownership.md is its source of record)
create table if not exists pipeline.layer4_review_owners (
  id bigserial primary key,
  provider_id uuid not null references catalogue.providers(id),
  field_code text not null,
  owner text not null check (owner in ('claude', 'chatgpt', 'engineering')),
  scope text not null,
  basis text not null,
  since timestamptz not null default now(),
  closed_at timestamptz,
  note text
);
comment on table pipeline.layer4_review_owners is 'CF-247 Layer 4 review ownership (mandate 3 Nov 2026 20:47 §3): which reviewer owns the items of a university and kind, mirrored from the ownership register in the admin repo (2026-11-03-layer4-review-ownership.md) by the Integration Controller. owner claude: the Integration Controller (approved logged rules); chatgpt: the parallel browser reviewer; engineering: no person decides. A row is open while closed_at is null. security.layer4_course_link_rule_execute_v1 decides only items of a university with an open claude row and no open chatgpt row. Never deleted. Never read by the consumer API.';
create index if not exists layer4_review_owners_open_idx on pipeline.layer4_review_owners (provider_id, field_code) where closed_at is null;
alter table pipeline.layer4_review_owners enable row level security;
revoke all on pipeline.layer4_review_owners from public, anon, authenticated;
revoke all on sequence pipeline.layer4_review_owners_id_seq from public, anon, authenticated;
-- the register's rows for the three approved rules (3 Nov 2026 21:00, Claude: Adelaide, Canberra, Simon Fraser approved address rules)
insert into pipeline.layer4_review_owners(provider_id, field_code, owner, scope, basis, since, note)
select r.provider_id, 'official_course_url', 'claude', 'approved address rule ' || r.code, 'Platform Admin decision 3 Nov 2026 after 20:40; ownership register 21:00',
       '2026-11-03 10:00:00+00'::timestamptz, 'Items outside the rule''s validated scope are not covered'
  from pipeline.layer4_course_link_rules r
 where not exists (select 1 from pipeline.layer4_review_owners o where o.provider_id = r.provider_id and o.field_code = 'official_course_url' and o.owner = 'claude' and o.scope = 'approved address rule ' || r.code);

create table if not exists pipeline.layer4_rule_runs (
  id bigserial primary key,
  rule text not null references pipeline.layer4_course_link_rules(code),
  apply boolean not null,
  invoked_by uuid,
  approval_ref text not null,
  at timestamptz not null default now(),
  examined int not null default 0,
  decided int not null default 0,
  would_decide int not null default 0,
  failed int not null default 0,
  result jsonb not null default '{}'::jsonb
);
comment on table pipeline.layer4_rule_runs is 'CF-247 Decision 263: every call of security.layer4_course_link_rule_execute_v1 (counting or applying): the rule, who invoked it, the approval reference, and how many items were examined, decided, would be decided and failed. Items are in pipeline.layer4_rule_run_items. Never read by the consumer API.';
alter table pipeline.layer4_rule_runs enable row level security;
revoke all on pipeline.layer4_rule_runs from public, anon, authenticated;
revoke all on sequence pipeline.layer4_rule_runs_id_seq from public, anon, authenticated;

create table if not exists pipeline.layer4_rule_run_items (
  run_id bigint not null references pipeline.layer4_rule_runs(id),
  item_id uuid not null,
  course_id uuid,
  outcome text not null check (outcome in ('decided', 'would_decide', 'failed')),
  reasons text[] not null default '{}',
  decision_id uuid,
  action text,
  at timestamptz not null default now(),
  primary key (run_id, item_id)
);
comment on table pipeline.layer4_rule_run_items is 'CF-247 Decision 263: each item a rule run examined: decided (with the Layer 4 decision it saved through the existing decision path), would_decide (a counting run) or failed (left waiting, with the reasons found at execution time). Never read by the consumer API.';
create index if not exists layer4_rule_run_items_item_idx on pipeline.layer4_rule_run_items (item_id);
alter table pipeline.layer4_rule_run_items enable row level security;
revoke all on pipeline.layer4_rule_run_items from public, anon, authenticated;

create or replace function security.layer4_course_link_rule_validate_v1(p_rule text, p_item uuid default null)
returns table(rule text, item_id uuid, course_id uuid, course_code text, choice text, held_url text, proposed_url text, target_url text, pass boolean, reasons text[], detail jsonb)
language sql stable security definer set search_path to '' as $function$
-- For one approved rule (pipeline.layer4_course_link_rules), every waiting official-link item of its university with the CRICOS-differs reason
-- (or only p_item): still waiting and not claimed; the university owned by the Integration Controller in the ownership register and not by the
-- parallel reviewer; exactly one held page; the addresses follow the approved pattern; course active; a stored copy of the page the rule keeps or
-- uses, read for this course with an exact-course identity basis; open to international students (and a CRICOS code for an Australian
-- course); the course's active official page is still exactly the held page; the binding was not set by hand; no manual lock; for a rule that
-- uses the proposed page, that page is not refused for the course. A strict rule also needs the course's level on the page (the binding
-- check's level reading, security.course_page_check_v1) and a stored copy no older than layer4.rule_evidence_max_age_days. A failed item
-- stays in Layer 4 with its reasons.
  with rule as (select * from pipeline.layer4_course_link_rules r where r.code = p_rule),
  own as (select bool_or(o.owner = 'claude') claude, bool_or(o.owner = 'chatgpt') chatgpt from pipeline.layer4_review_owners o, rule
           where o.provider_id = rule.provider_id and o.field_code = 'official_course_url' and o.closed_at is null),
  it as (
    select i.id item_id, i.entity_id course_id, i.claimed_at, i.assigned_to, i.status, i.before_value, i.layer2_state, i.escalation_reason,
           security.layer4_url_key_v1(case when jsonb_typeof(i.before_value) = 'array' then i.before_value->>0 end) held_key,
           case when jsonb_typeof(i.before_value) = 'array' then i.before_value->>0 end held_url,
           security.layer4_url_key_v1(coalesce(i.proposed_value->>'course_url', i.proposed_value->>'url')) prop_key,
           coalesce(i.proposed_value->>'course_url', i.proposed_value->>'url') prop_url,
           case when jsonb_typeof(i.before_value) = 'array' then jsonb_array_length(i.before_value) else 0 end n_held
      from pipeline.layer4_review_items i join catalogue.courses c on c.id = i.entity_id join rule on c.provider_id = rule.provider_id
     where i.status = 'pending' and i.field_code = 'official_course_url' and i.escalation_reason ilike rule.reason_like and (p_item is null or i.id = p_item)),
  m as (
    select it.*, rule.code, rule.choice, rule.identity_bases, rule.strict,
           it.held_key ~ rule.held_regex and it.prop_key = regexp_replace(it.held_key, rule.held_regex, rule.proposed_replace) pattern_ok,
           case when rule.choice = 'keep' then it.held_url else it.prop_url end target_url,
           case when rule.choice = 'keep' then it.held_key else it.prop_key end target_key
      from it cross join rule),
  e as (
    select m.*, c.lifecycle_status, c.course_code, c.open_to_international, k.iso_alpha2 country,
           (select jsonb_build_object('id', ev.id, 'captured_at', ev.captured_at, 'course_id', ev.metadata->>'course_id', 'identity_basis', ev.metadata->>'identity_basis')
              from pipeline.evidence_artifacts ev
             where lower(ev.source_url) = any (array['https://' || m.target_key, 'https://' || m.target_key || '/', 'https://www.' || m.target_key, 'https://www.' || m.target_key || '/',
                                                     'http://' || m.target_key, 'http://' || m.target_key || '/', 'http://www.' || m.target_key, 'http://www.' || m.target_key || '/'])
             order by (ev.metadata->>'course_id' = m.course_id::text) desc, ev.captured_at desc nulls last limit 1) copy,
           (select array_agg(security.layer4_url_key_v1(l.url) order by l.url) from catalogue.course_links l
             where l.course_id = m.course_id and l.link_type = 'official_course' and l.status = 'active') active_keys,
           (select g.basis from pipeline.coverage_course_pages g where g.course_id = m.course_id) binding_basis,
           exists (select 1 from pipeline.manual_locks l where l.entity = 'course' and l.entity_id = m.course_id and l.field in ('official_url', 'course_url')) locked,
           exists (select 1 from pipeline.page_rejections r where r.course_id = m.course_id and security.layer4_url_key_v1(r.url) = m.target_key) target_refused,
           case when m.strict then security.course_page_check_v1(m.course_id, m.target_url) end chk
      from m join catalogue.courses c on c.id = m.course_id
      left join catalogue.providers p on p.id = c.provider_id left join ref.countries k on k.id = p.country_id),
  lv as (
    select e.*,
           coalesce((select array_agg(x) from jsonb_array_elements_text(case when jsonb_typeof(e.chk->'checks'->'course_levels') = 'array' then e.chk->'checks'->'course_levels' else '[]'::jsonb end) x), '{}') course_lv,
           coalesce((select array_agg(x) from jsonb_array_elements_text(case when jsonb_typeof(e.chk->'checks'->'page_levels') = 'array' then e.chk->'checks'->'page_levels' else '[]'::jsonb end) x), '{}') page_lv
      from e),
  v as (
    select lv.*, array_remove(array[
             case when lv.claimed_at is not null or lv.assigned_to is not null then 'claimed by a reviewer' end,
             case when coalesce((select chatgpt from own), false) then 'university owned by the parallel reviewer (ownership register)' end,
             case when not coalesce((select claude from own), false) then 'no ownership row for the Integration Controller (ownership register)' end,
             case when lv.n_held <> 1 then 'not exactly one page held (' || lv.n_held || ')' end,
             case when not coalesce(lv.pattern_ok, false) then 'addresses do not follow the approved pattern' end,
             case when lv.lifecycle_status is distinct from 'active' then 'course not active' end,
             case when lv.copy is null then 'no stored copy of the ' || case when lv.choice = 'keep' then 'held' else 'proposed' end || ' page' end,
             case when lv.copy is not null and lv.copy->>'course_id' is distinct from lv.course_id::text then 'stored copy was read for another course' end,
             case when lv.copy is not null and not (coalesce(lv.copy->>'identity_basis', '') = any (lv.identity_bases)) then 'stored copy identity basis ' || coalesce(lv.copy->>'identity_basis', 'none') || ' is not an exact-course basis' end,
             case when lv.open_to_international is false then 'course not open to international students' end,
             case when lv.country = 'AU' and coalesce(lv.course_code, '') !~ '^[0-9]{6}[0-9A-Z]$' then 'no CRICOS code on the course record' end,
             case when lv.active_keys is distinct from array[lv.held_key] then 'active official page is no longer exactly the held page' end,
             case when lv.binding_basis = 'manual' then 'page binding was set by hand' end,
             case when lv.locked then 'manual lock on the official page' end,
             case when lv.choice = 'use' and lv.target_refused then 'the proposed page was refused for this course' end,
             case when lv.strict and (cardinality(lv.course_lv) = 0 or cardinality(lv.page_lv) = 0 or not (lv.course_lv && lv.page_lv))
                  then 'course level not verified on the page (course ' || coalesce(nullif(array_to_string(lv.course_lv, ','), ''), 'unknown') || ', page ' || coalesce(nullif(array_to_string(lv.page_lv, ','), ''), 'none') || ')' end,
             case when lv.strict and lv.copy is not null and (lv.copy->>'captured_at')::timestamptz < now() - make_interval(days => security.pipeline_num_v1('layer4.rule_evidence_max_age_days', 90)::int)
                  then 'stored copy is older than ' || security.pipeline_num_v1('layer4.rule_evidence_max_age_days', 90) || ' days' end], null) reasons
      from lv)
  select v.code, v.item_id, v.course_id, v.course_code, v.choice, v.held_url, v.prop_url, v.target_url, coalesce(cardinality(v.reasons), 0) = 0, v.reasons,
         jsonb_build_object('stored_copy', v.copy, 'active_pages', to_jsonb(v.active_keys), 'binding_basis', v.binding_basis, 'country', v.country, 'claimed_at', v.claimed_at,
                            'course_levels', to_jsonb(v.course_lv), 'page_levels', to_jsonb(v.page_lv), 'page_check', v.chk->>'verdict')
    from v order by v.course_code, v.item_id
$function$;
revoke all on function security.layer4_course_link_rule_validate_v1(text, uuid) from public, anon, authenticated;

create or replace function security.layer4_course_link_rule_execute_v1(p_rule text, p_limit int, p_apply boolean) returns jsonb
language plpgsql security definer set search_path to '' as $function$
-- Executes an approved rule item by item (Decision 263; overnight mandate 3 Nov 2026 21:59 D1, D2). For each item, at execution time: the item is
-- locked (an item another reviewer is deciding is skipped, never waited for), validated again on its own (security.layer4_course_link_rule_validate_v1:
-- waiting, not claimed, ownership, same binding, no manual lock, identity, evidence, and the course level for a strict rule), then decided
-- through the existing decision path (security.layer4_review_decide_impl) under the system automation account: keep the held page (reject) or use
-- the proposed page (approve). The reason names the rule and its approval reference. One decision per item; an item that fails, or whose
-- decision is refused, stays waiting with its reason (pipeline.layer4_rule_run_items). p_apply false only counts. Platform Admin or the
-- Integration Controller (no signed-in user).
declare r pipeline.layer4_course_link_rules; v record; w record; v_run bigint; v_res jsonb; v_reason text; v_prev text; v_n int := 0; v_ok int := 0; v_would int := 0; v_fail int := 0;
        v_sys uuid := 'c0ffee00-0000-4000-8000-000000000150';  -- fixed: the system automation account that records Decision 263 rule decisions
        v_caller uuid := auth.uid(); v_lock int; v_by jsonb := '{}'::jsonb; v_why text;
begin
  if v_caller is not null and coalesce(security.current_role_rank(), 0) < 6 then raise exception 'Platform Admin role required' using errcode = '42501'; end if;
  select * into r from pipeline.layer4_course_link_rules where code = p_rule;
  if r.code is null then raise exception 'no approved rule %', p_rule using errcode = 'P0002'; end if;
  insert into pipeline.layer4_rule_runs(rule, apply, invoked_by, approval_ref) values (r.code, coalesce(p_apply, false), v_caller, r.approval_ref) returning id into v_run;
  for v in select x.item_id from security.layer4_course_link_rule_validate_v1(r.code, null) x
            order by x.item_id limit least(greatest(coalesce(p_limit, 0), 0), security.pipeline_num_v1('layer4.rule_execute_batch', 50)::int) loop
    v_n := v_n + 1;
    begin
      -- the item, locked for this decision; one another reviewer holds is skipped
      begin
        select 1 into v_lock from pipeline.layer4_review_items i where i.id = v.item_id and i.status = 'pending' for update nowait;
      exception when lock_not_available then
        raise exception using errcode = 'P0001', message = 'l4rule:another reviewer is deciding this item';
      end;
      if v_lock is null then raise exception using errcode = 'P0001', message = 'l4rule:no longer waiting'; end if;
      v_lock := null;
      -- validated again, on its own, now
      w := null;
      select x.item_id, x.pass, x.reasons, x.course_id, x.target_url into w from security.layer4_course_link_rule_validate_v1(r.code, v.item_id) x;
      if w.item_id is null then raise exception using errcode = 'P0001', message = 'l4rule:no longer in the rule''s scope'; end if;
      if not w.pass then raise exception using errcode = 'P0001', message = 'l4rule:' || array_to_string(w.reasons, '; '); end if;
      if not coalesce(p_apply, false) then
        insert into pipeline.layer4_rule_run_items(run_id, item_id, course_id, outcome, action) values (v_run, v.item_id, w.course_id, 'would_decide', case r.choice when 'keep' then 'reject' else 'approve' end);
        v_would := v_would + 1;
        continue;
      end if;
      v_reason := left(format('[rule %s] %s. %s: %s. Approved by %s (%s)', r.code,
                              case r.choice when 'keep' then 'Keep the page we hold' else 'Use the new page' end, 'Decision 263 logged rule, validated item by item',
                              coalesce(w.target_url, ''), r.approved_by, r.approval_ref), 1000);
      -- the existing decision path, under the system automation account (Decision 263), then the caller's identity again
      v_prev := current_setting('request.jwt.claim.sub', true);
      perform set_config('request.jwt.claim.sub', v_sys::text, true);
      begin
        v_res := security.layer4_review_decide_impl(v.item_id, case r.choice when 'keep' then 'reject' else 'approve' end, v_reason, null);
      exception when others then
        perform set_config('request.jwt.claim.sub', coalesce(v_prev, ''), true);
        raise;
      end;
      perform set_config('request.jwt.claim.sub', coalesce(v_prev, ''), true);
      insert into pipeline.layer4_rule_run_items(run_id, item_id, course_id, outcome, decision_id, action)
      values (v_run, v.item_id, w.course_id, 'decided', nullif(v_res->>'decision_id', '')::uuid, v_res->>'action');
      v_ok := v_ok + 1;
    exception when others then
      v_why := case when sqlerrm like 'l4rule:%' then substr(sqlerrm, 8) else 'decision refused: ' || left(sqlerrm, 300) end;
      insert into pipeline.layer4_rule_run_items(run_id, item_id, outcome, reasons) values (v_run, v.item_id, 'failed', string_to_array(v_why, '; '))
      on conflict (run_id, item_id) do update set outcome = 'failed', reasons = excluded.reasons, decision_id = null, action = null;
      v_by := jsonb_set(v_by, array[left(v_why, 120)], to_jsonb(coalesce((v_by->>left(v_why, 120))::int, 0) + 1));
      v_fail := v_fail + 1;
    end;
  end loop;
  update pipeline.layer4_rule_runs set examined = v_n, decided = v_ok, would_decide = v_would, failed = v_fail,
         result = jsonb_build_object('failed_by_reason', v_by) where id = v_run;
  insert into pipeline.admin_control_events(area, action, target, detail, actor)
  values ('layer4', case when coalesce(p_apply, false) then 'rule_execute' else 'rule_count' end, r.code,
          jsonb_build_object('run_id', v_run, 'examined', v_n, 'decided', v_ok, 'would_decide', v_would, 'failed', v_fail, 'failed_by_reason', v_by, 'approval_ref', r.approval_ref), v_caller);
  return jsonb_build_object('run_id', v_run, 'rule', r.code, 'apply', coalesce(p_apply, false), 'examined', v_n, 'decided', v_ok, 'would_decide', v_would, 'failed', v_fail,
                            'failed_by_reason', v_by, 'approval_ref', r.approval_ref);
end $function$;
revoke all on function security.layer4_course_link_rule_execute_v1(text, int, boolean) from public, anon, authenticated;

-- 9 component register --------------------------------------------------------------------------------------------------------------------
insert into pipeline.component_register(kind, name, layer, purpose, status, replaces, introduced_in) values
 ('table', 'pipeline.course_page_needed', 'Layer 4', 'Decision 179: courses that need a correct page (Course page needed list)', 'active', '{}', '20261104150000'),
 ('table', 'pipeline.scholarship_duplicate_closures', 'Layer 4', 'Held scholarships closed as duplicates of a published one', 'active', '{}', '20261104150000'),
 ('table', 'pipeline.layer4_course_link_rules', 'Layer 4', 'Decision 263 course-link rules approved per university (validated, not executed here)', 'active', '{}', '20261104150000'),
 ('function', 'security.layer4_stored_copy_v1', 'Layer 4', 'Newest stored copy of an address', 'active', '{}', '20261104150000'),
 ('function', 'security.layer4_evidence_backfill_v1', 'Layer 4', 'Link stored copies to waiting items (Integration Controller)', 'active', '{}', '20261104150000'),
 ('function', 'security.course_page_needed_convert_v1', 'Layer 4', 'Move refusal items of one university onto Course page needed', 'active', '{}', '20261104150000'),
 ('function', 'security.course_page_needed_decide_v1', 'Layer 4', 'Course page needed choices', 'active', '{}', '20261104150000'),
 ('function', 'security.layer4_course_link_refuse_v1', 'Layer 4', 'Refuse this proposal', 'active', '{}', '20261104150000'),
 ('function', 'security.scholarship_duplicate_close_v1', 'Layer 4', 'Close a held scholarship as a duplicate', 'active', '{}', '20261104150000'),
 ('function', 'security.layer4_refusal_search_cost_v1', 'Layer 4', 'Firecrawl credits of the lanes that feed refusals', 'active', '{}', '20261104150000'),
 ('function', 'security.layer4_course_link_rule_validate_v1', 'Layer 4', 'Validate an approved course-link rule per item', 'active', '{}', '20261104150000'),
 ('function', 'security.layer4_course_link_rule_execute_v1', 'Layer 4', 'Execute an approved course-link rule item by item through the decision path', 'active', '{}', '20261104150000'),
 ('table', 'pipeline.layer4_review_owners', 'Layer 4', 'Layer 4 review ownership register in data', 'active', '{}', '20261104150000'),
 ('table', 'pipeline.layer4_rule_runs', 'Layer 4', 'Runs of the course-link rule executor', 'active', '{}', '20261104150000'),
 ('table', 'pipeline.layer4_rule_run_items', 'Layer 4', 'Items of each rule run: decided, would decide or failed with reasons', 'active', '{}', '20261104150000')
on conflict do nothing;
