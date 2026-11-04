-- CF-247 Layer 4 operational groups and the kind-audit gaps (Platform Admin mandate 4 Nov 2026 16:32 §2, §7, §8 and §10; admin
-- docs/platform/2026-11-04-layer4-simplification-course-link-aer-recovery-mandate-1632.md; matrix ui-audit/2026-11-04-layer4-kind-audit-matrix.md §5).
-- Why (production, read-only, 4 Nov 2026 17:11-17:27 AEDT; figures in the change-control entry):
--   * Every waiting item looks the same to a reviewer. The platform already classifies review items (pipeline.layer4_item_readiness: judgement
--     ready, technically blocked, resolvable by the platform) and holds the approved Course Link rules (pipeline.layer4_course_link_rules), but
--     nothing groups the Inbox by what a person must do.
--   * The 96 held scholarships "decided twice" were one decision sent twice about 3 s apart (batch L4B-20261030-1138): the first reply was the
--     scholarship screen's status, the item stayed waiting, the second applied it (decided_at = the second audit row). The audit never said that
--     the first had not applied.
--   * Retry, rebuild and release can be repeated on the same stop with nothing changed (playbook: at most once).
--   * Choices that open another screen (Open the course, the adapter, the builder, the central pages) leave no audit row.
--   * Provider and adapter cards (onboarding stops, page and site holds) show a stop reason only; the evidence is in the onboarding result
--     and the hold's evidence.
--   * Items raised again after a valid decision are classified "resolvable: decided before" but the card does not say so.
-- What (shared mechanisms; no new admission authority; no item is decided, superseded or admitted by this change):
--   1 security.layer4_groups_v1(provider, kind, keys): every waiting item (the Inbox's own list, security.layer4_inbox_items_v2, and open Human
--     input needed items) in one of four groups, with its class and, for group A, the existing rule that may settle it:
--       A automatically resolvable: an existing authorised rule covers it, named on the item. For review items other than official links: the
--         platform's resolution rules (security.layer4_reconcile_v1: repeat, decided before with no new evidence, already active, record
--         retired; switch layer4.reconcile_supersede_on). Official links are routed by the Course Link workstream's classifier,
--         security.course_link_route_class_v1(uuid) (migration 20261104570000: Decision 263 rules, Decision 179 conversion, the resolution rules);
--         while it is missing they stay in C.
--       B technical recovery: readiness technically_blocked, kinds that are a technical stop (adapter nothing ready, proposal failed, site down),
--         Human input needed items being analysed or resuming.
--       C human decision: readiness judgement_ready, and kinds that are a protected decision.
--       D human information: kinds that need a URL, pages or a document (website needed, too few pages, pages not found, course page needed),
--         Human input needed items awaiting input, and held AER reads with an open Human input needed item.
--     The kind defaults are a setting (layer4.group_by_kind).
--   1b Stored, never classified at read time (Integration Controller 4 Nov 2026, after the 11:13 time-out): pipeline.layer4_item_groups holds
--     each item's group, class, rule and next action, filled for new and changed items only by job layer4-groups (security.layer4_groups_fill_v1:
--     batches of batch.layer4_groups within layer4.groups_fill_seconds; catalogued). The Inbox, the cards and the lifecycle read the stored row;
--     a missing or stale row counts as C, shown "not grouped yet". The Course Link classifier is called by the job only.
--   2 public.admin_layer4_groups(args): the Inbox's three choices (C "Ready for my decision", D "Information needed from me", B "Technical
--     recovery") with counts, group A as counts with its rules, and paged items in the Inbox's own card shape.
--   3 The lifecycle read (security.layer4_items_lifecycle_v1, security.layer4_item_lifecycle_v1) adds each card's group, whether a person is
--     needed, the evidence of provider and adapter cards (security.layer4_card_evidence_v1), and an earlier decision of the same question.
--   4 public.admin_layer4_inbox('decide'): (a) a decision whose item is still waiting afterwards is recorded as not applied (still_waiting) and
--     acknowledged "Still incomplete"; (b) the same decision on the same item inside layer4.duplicate_decision_seconds returns the first one;
--     (c) retry, rebuild and release (layer4.once_only_choices) are refused, with the reason and the alternatives, when the same choice was
--     already taken on the same university's same stop and the university has not changed since. Refusals and duplicates are audited.
--   5 public.admin_layer4_navigate(kind, ref, choice): a choice that opens another screen writes an inbox_navigate audit row; the lifecycle shows
--     it ("Opened … — the item closes when the work there is saved") and the item's own closing time.
-- Edited live functions (md5-guarded, before -> after):
--   public.admin_layer4_inbox(text,jsonb)                       c0a972a6d6cc0652ce2dcc8f4d9cbbfc -> 1895ed9870fdbcb332639befffd5a6ec
--   security.layer4_lifecycle_one_v1(text,text,boolean)         a93b2bee90704eb3fbd3e09da350ba53 -> e1e3c4a1744663d9793a896816b93f8d
--   security.layer4_items_lifecycle_v1(jsonb)                   f6eeef05b818c8818d9eef144ff91a18 -> 9abc7baa6fb19a660527559bac78df1a
--   security.layer4_item_lifecycle_v1(text,text)                a908288151604a4e3d936be5f05a2fad -> f54065d6b84004b3eb0f6e49be6b1779
--   security.layer4_ack_headline_v1(text,jsonb,jsonb,timestamptz) c715ccb353dcdd77cc6c8f88402595e6 -> 54654848fd9ed4d833e36ad3494dcf3a
--   security.layer4_ack_normalise_v1(text,text,boolean,jsonb,text,jsonb) 50f4b7b6224c852bcecf4f054b3a81ae -> e5f2fee175a931d3d886259f69c27bca
-- Replaces: the five functions above (same names and signatures; additive behaviour)
-- Retires: nothing
-- Nothing is dropped or deleted. No consumer API object changes (G3). One job (layer4-groups, catalogued). No Firecrawl or AI
-- spend. Admission authority, the E13 and D-R3 gates, manual bindings, scholarship rules, fee holds, provider lifecycle rules and role ranks are
-- unchanged.

create or replace function pg_temp.edit_once(p_sig text, p_before text, p_after text, p_edits text[][], p_times int[]) returns text language plpgsql as $f$
declare v_def text := pg_get_functiondef(p_sig::regprocedure); i int; v_c int; v_old text; v_new text;
begin
  if md5(v_def) = p_after then raise notice '%: already applied', p_sig; return p_sig || ': already applied'; end if;
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
  raise notice '%: applied', p_sig;
  return p_sig || ': applied';
end $f$;

-- 1 settings (G2; Settings › Pipeline settings, section Layer 4) ---------------------------------------------------------------------------
insert into pipeline.platform_toolset_settings(toolset_key, key, label, help, kind, value, min_value, max_value, unit, sort, section, used_by, reason) values
 ('pipeline', 'layer4.group_by_kind', 'Layer 4 groups: what each kind needs from a person',
  'For kinds the readiness check does not classify: B technical recovery, C a person''s decision, D information from a person. A kind not listed is C.',
  'list', '["website_needed=D", "too_few_pages=D", "pages_not_found=D", "course_page_needed=D", "nothing_ready=B", "onboarding_failed=B", "site_down=B", "central_to_approve=C", "fee_check=C", "not_offered=C", "not_on_site=C", "counsellor_report=C", "provider_departure=C", "held_scholarship=C", "provider_description=C", "no_page_first_run=C", "conjoint_first_run=C", "course_link=C", "aer_review=C"]'::jsonb,
  null, null, 'kind=group', 342, 'Layer 4', 'security.layer4_groups_v1', 'Platform Admin mandate 4 Nov 2026 16:32 §2 (A, B, C, D) and §7'),
 ('pipeline', 'layer4.once_only_choices', 'Layer 4: choices tried at most once on an unchanged stop',
  'Retry, rebuild and release are refused when the same choice was already taken on the same university''s same stop and the university has not changed since; the card says why and what to do instead.',
  'list', '["retry", "rebuild", "release"]'::jsonb, null, null, 'choices', 343, 'Layer 4', 'public.admin_layer4_inbox (decide); security.layer4_once_only_v1',
  'Playbook v6 §3 ("at most once"); mandate 16:32 §8'),
 ('pipeline', 'layer4.duplicate_decision_seconds', 'Layer 4: the same decision sent again within',
  'The same choice on the same item inside this time returns the first decision instead of being taken again (a double click or a retried batch).',
  'number', to_jsonb(120), 10, 3600, 'seconds', 344, 'Layer 4', 'public.admin_layer4_inbox (decide)',
  'Mandate 16:32 §8 (96 held scholarships decided twice, batch L4B-20261030-1138)'),
 ('pipeline', 'layer4.groups_course_link_router_on', 'Layer 4 groups: route official links with the Course Link classifier',
  'On (1): official-link items are grouped by the Course Link classifier (security.course_link_route_class_v1). Off (0): they stay in Ready for my decision, without calling it (for example if it slows the Inbox).',
  'number', to_jsonb(1), 0, 1, 'on (1) or off (0)', 345, 'Layer 4', 'security.layer4_groups_v1',
  'Mandate 16:32 §2 and §3 (Course Link routing is the Course Link workstream''s)'),
 ('pipeline', 'batch.layer4_groups', 'Layer 4 groups: items grouped a batch',
  'Job layer4-groups groups at most this many new or changed waiting items in one batch, and repeats batches until its time budget is used.',
  'number', to_jsonb(500), 50, 5000, 'items', 346, 'Layer 4', 'security.layer4_groups_fill_v1 (job layer4-groups)',
  'Integration Controller 4 Nov 2026: groups are stored by one scheduled step, never computed when the Inbox is read'),
 ('pipeline', 'layer4.groups_fill_seconds', 'Layer 4 groups: time budget of one run',
  'One run of job layer4-groups stops starting new batches after this many seconds; the rest is grouped by the next run (until then it shows as not grouped yet).',
  'number', to_jsonb(30), 5, 120, 'seconds', 347, 'Layer 4', 'security.layer4_groups_fill_v1 (job layer4-groups)',
  'Integration Controller 4 Nov 2026 (the 11:13 time-out: no per-item classification at read time)')
on conflict do nothing;

-- 1b the stored group (read by the Inbox; filled by job layer4-groups, below) ------------------------------------------------------------
create table if not exists pipeline.layer4_item_groups (
  kind text not null,
  ref text not null,
  provider_id uuid,
  item_created_at timestamptz,
  grp text not null check (grp in ('A', 'B', 'C', 'D')),
  cls text not null,
  rule text,
  next_action text,
  secondary jsonb not null default '[]'::jsonb,
  state text not null default 'waiting' check (state in ('waiting', 'closed')),
  input_at timestamptz,
  classified_at timestamptz not null default now(),
  closed_at timestamptz,
  primary key (kind, ref));
comment on table pipeline.layer4_item_groups is 'CF-247 Layer 4 operational groups (Platform Admin mandate 4 Nov 2026 16:32 §2, §7; Integration Controller 17:4x: stored, never classified at read time). One row per Layer 4 item and one primary disposition (direction 18:08 §5): its group (A settled by an existing rule, B technical recovery, C a person''s decision, D information from a person), class, secondary reasons (never counted), the existing rule for A, the next action, and the input time it was grouped from. Human input needed requests (kind intervention) are stored too and counted on their own line, never added to the groups. Filled for new and changed items only by job layer4-groups (security.layer4_groups_fill_v1); a row whose item left the Inbox is marked closed (history kept, never deleted). The Inbox reads this table only; a missing or stale row counts as C ("not grouped yet").';
create index if not exists layer4_item_groups_waiting_idx on pipeline.layer4_item_groups (grp, item_created_at, kind, ref) where state = 'waiting';
create index if not exists layer4_item_groups_provider_idx on pipeline.layer4_item_groups (provider_id, grp) where state = 'waiting';
alter table pipeline.layer4_item_groups enable row level security;
revoke all on pipeline.layer4_item_groups from public, anon, authenticated;

-- 2 the classifier (§2) --------------------------------------------------------------------------------------------------------------------
create or replace function security.layer4_cl_group_call_v1(p_item uuid) returns jsonb
 language plpgsql stable security definer set search_path to '' as $function$
-- the Course Link workstream's routing for one official-link item (security.course_link_route_class_v1(uuid), migration 20261104570000:
-- {group A|B|C|D or null, class, action, authority, reason, recommended, evidence}) as {grp, cls, rule}; while that function is missing, or for
-- an item it does not route, the item stays in C (Integration Controller 4 Nov 2026)
declare v jsonb;
begin
  if to_regprocedure('security.course_link_route_class_v1(uuid)') is null then return jsonb_build_object('grp', 'C', 'cls', 'course_link:router_missing'); end if;
  execute 'select security.course_link_route_class_v1($1)' into v using p_item;
  return case when v->>'group' in ('A', 'B', 'C', 'D')
              then jsonb_build_object('grp', v->>'group', 'cls', 'course_link:' || coalesce(v->>'class', 'routed'),
                                      'rule', case when v->>'group' = 'A' then coalesce(v->>'authority', v->>'action') end, 'action', v->>'action', 'reason', v->>'reason')
              else jsonb_build_object('grp', 'C', 'cls', 'course_link:not_routed') end;
exception when others then return jsonb_build_object('grp', 'C', 'cls', 'course_link:router_failed');
end $function$;
revoke all on function security.layer4_cl_group_call_v1(uuid) from public, anon, authenticated;

create or replace function security.layer4_groups_v1(p_provider uuid default null, p_kind text default null, p_keys text[] default null)
 returns table(kind text, ref text, provider_id uuid, created_at timestamptz, grp text, cls text, rule text, why text, secondary jsonb)
 language plpgsql stable security definer set search_path to '' as $function$
-- CF-247 mandate 16:32 §2: every waiting Layer 4 item (security.layer4_inbox_items_v2, and Human input needed items) in group A, B, C or D, with
-- its class and, for A, the existing rule that may settle it. Read only: nothing is decided here. The Course Link workstream's classifier
-- (security.course_link_route_class_v1(uuid), through security.layer4_cl_group_call_v1) is used for official-link items when it exists.
declare v_map jsonb := coalesce((select w.value from pipeline.platform_toolset_settings w where w.toolset_key = 'pipeline' and w.key = 'layer4.group_by_kind'), '[]'::jsonb);
        v_cl boolean := security.pipeline_num_v1('layer4.groups_course_link_router_on', 1) >= 1;  -- official links: the Course Link workstream's routing
        v_rec_on boolean := security.pipeline_num_v1('layer4.reconcile_supersede_on', 0) >= 1;
begin
  return query
  with i as (select x.kind, x.ref, x.provider_id, x.created_at, x.why
               from security.layer4_inbox_items_v2(p_provider, case when p_kind = 'intervention' then '-' else p_kind end, p_keys, false) x
              where p_kind is distinct from 'intervention'),
       def as (select split_part(e, '=', 1) k, split_part(e, '=', 2) g from jsonb_array_elements_text(v_map) e),
       ri as (select i.*, r.field_code, r.entity_id, r.escalation_reason, r.before_value, r.proposed_value, rd.readiness, rd.route, rd.reasons
                from i left join pipeline.layer4_review_items r on i.kind in ('course_link', 'aer_review', 'provider_description', 'no_page_first_run', 'conjoint_first_run')
                       and r.id = case when i.ref ~ '^[0-9a-f-]{36}$' then i.ref::uuid end
                left join pipeline.layer4_item_readiness rd on rd.item_id = r.id and rd.item_status = 'pending'),
       clh as (select ri.ref, case when v_cl then security.layer4_cl_group_call_v1(ri.ref::uuid) else '{"grp": "C", "cls": "course_link:router_off"}'::jsonb end j
                 from ri where ri.field_code = 'official_course_url'),
       aiv as (select x.entity, min(x.id) id, bool_or(x.status = 'awaiting_input') waiting from pipeline.layer4_interventions x where x.lane = 'aer_item' and x.status in ('ai_pending', 'awaiting_input', 'resuming') group by 1)
  select ri.kind, ri.ref, ri.provider_id, ri.created_at,
         case when clh.j->>'grp' in ('A', 'B', 'C', 'D') then clh.j->>'grp'
              when ri.readiness = 'resolvable' then 'A' when aiv.id is not null then case when aiv.waiting then 'D' else 'B' end
              when ri.readiness = 'technical_blocked' then 'B' when ri.readiness = 'judgement_ready' then 'C'
              else coalesce((select def.g from def where def.k = ri.kind), 'C') end,
         case when clh.j->>'grp' in ('A', 'B', 'C', 'D') then coalesce(clh.j->>'cls', 'course_link')
              when ri.readiness = 'resolvable' then coalesce(ri.route, 'platform:resolvable')
              when aiv.id is not null then case when aiv.waiting then 'human_input:' else 'human_input_resuming:' end || aiv.id when ri.readiness is not null then ri.route else 'kind:' || ri.kind end,
         case when clh.j->>'grp' in ('A', 'B', 'C', 'D') then clh.j->>'rule'
              when ri.readiness = 'resolvable' then 'security.layer4_reconcile_v1 (' || case when v_rec_on then 'on' else 'off: layer4.reconcile_supersede_on' end || ')'
              end,
         ri.why,
         -- direction 18:08 §5: one primary disposition (grp, cls); every other reason that applies is secondary, never a second count
         to_jsonb(array_remove(array[
           case when clh.j is not null and ri.readiness is not null then 'readiness:' || ri.route end,
           case when clh.j is not null and clh.j->>'action' is not null then 'course_link_action:' || (clh.j->>'action') end,
           case when aiv.id is not null and (coalesce(clh.j->>'grp' in ('A', 'B', 'C', 'D'), false) or coalesce(ri.readiness = 'resolvable', false)) then 'human_input:' || aiv.id end,
           case when aiv.id is not null and not (coalesce(clh.j->>'grp' in ('A', 'B', 'C', 'D'), false) or coalesce(ri.readiness = 'resolvable', false)) and ri.readiness is not null
                then 'readiness:' || ri.route end], null))
    from ri left join aiv on aiv.entity = ri.ref left join clh on clh.ref = ri.ref
  union all
  select 'intervention', x.id::text, x.provider_id, x.created_at, case when x.status = 'awaiting_input' then 'D' else 'B' end, 'intervention:' || x.status, null,
         coalesce(x.required_input->>'ask', x.subject),
         -- a Human input needed request is work of its own, counted on its own line; the item it serves (if any) is named here
         case when x.lane = 'aer_item' then jsonb_build_array('for_item:' || x.entity) else '[]'::jsonb end
    from pipeline.layer4_interventions x
   where x.status in ('ai_pending', 'awaiting_input', 'resuming') and (p_kind is null or p_kind = 'intervention')
     and (p_provider is null or x.provider_id = p_provider) and (p_keys is null or 'intervention:' || x.id = any (p_keys));
end $function$;
revoke all on function security.layer4_groups_v1(uuid, text, text[]) from public, anon, authenticated;

create or replace function security.layer4_group_counts_v1(p_provider uuid default null) returns jsonb
 language sql stable security definer set search_path to '' as $function$
  -- the Inbox's three choices and group A, from the stored groups only (pipeline.layer4_item_groups; mandate 16:32 §7). One primary disposition
  -- per waiting item, so the groups sum to the items waiting (direction 18:08 §5); Human input needed requests are a separate line, never added.
  -- A row whose input changed since it was grouped counts as C until job layer4-groups groups it again ("not grouped yet")
  with g as (select x.kind, x.ref, x.item_created_at, x.rule, x.cls,
                    case when x.grp <> 'C' and ((rd.classified_at is not null and rd.classified_at > x.input_at) or (iv.updated_at is not null and iv.updated_at > x.input_at)) then 'C' else x.grp end grp,
                    (rd.classified_at is not null and rd.classified_at > x.input_at) or (iv.updated_at is not null and iv.updated_at > x.input_at) stale, x.classified_at
               from pipeline.layer4_item_groups x
               left join pipeline.layer4_item_readiness rd on x.kind in ('course_link', 'aer_review', 'provider_description', 'no_page_first_run', 'conjoint_first_run')
                    and rd.item_id = case when x.ref ~ '^[0-9a-f-]{36}$' then x.ref::uuid end
               left join pipeline.layer4_interventions iv on x.kind = 'intervention' and iv.id = case when x.ref ~ '^[0-9]+$' then x.ref::bigint end
              where x.state = 'waiting' and (p_provider is null or x.provider_id = p_provider)),
       it as (select * from g where g.kind <> 'intervention'),
       hi as (select * from g where g.kind = 'intervention')
  select jsonb_build_object(
    'groups', (select coalesce(jsonb_object_agg(grp, n), '{}'::jsonb) from (select grp, count(*) n from it group by 1) z),
    'pending', (select count(*) from it),
    'pending_review_items', (select count(*) from it where it.kind in ('course_link', 'aer_review', 'provider_description', 'no_page_first_run', 'conjoint_first_run')),
    'pending_other_items', (select count(*) from it where it.kind not in ('course_link', 'aer_review', 'provider_description', 'no_page_first_run', 'conjoint_first_run')),
    'human_input_requests', jsonb_build_object('waiting', (select count(*) from hi where hi.grp = 'D'), 'recovering', (select count(*) from hi where hi.grp <> 'D')),
    'by_kind', (select coalesce(jsonb_object_agg(grp, k), '{}'::jsonb) from (select grp, jsonb_object_agg(kind, n) k from (select grp, kind, count(*) n from it group by 1, 2) y group by 1) z),
    'oldest', (select coalesce(jsonb_object_agg(grp, o), '{}'::jsonb) from (select grp, min(item_created_at) o from it group by 1) z),
    'rules', (select coalesce(jsonb_agg(jsonb_build_object('rule', rule, 'class', cls, 'n', n) order by n desc), '[]'::jsonb)
                from (select rule, cls, count(*) n from it where grp = 'A' group by 1, 2) z),
    'waiting', (select count(*) from it), 'regrouping', (select count(*) from it where stale),
    'grouped_at', security.l4_time_v1((select max(classified_at) from pipeline.layer4_item_groups)))
$function$;
revoke all on function security.layer4_group_counts_v1(uuid) from public, anon, authenticated;

-- 2b the stored group (Integration Controller 4 Nov 2026: the Inbox reads the stored value only; one scheduled step fills it) ------------------

create or replace function security.layer4_groups_fill_v1(p_full boolean default false) returns jsonb
 language plpgsql security definer set search_path to '' as $function$
-- Job layer4-groups: the stored group of every waiting Layer 4 item, for new and changed items only. One read of the waiting list (no detail),
-- then batches of batch.layer4_groups items classified by security.layer4_groups_v1 (the Course Link classifier is called here, for the
-- batch's official links only) until layer4.groups_fill_seconds is used. An item whose input changed since it was grouped (readiness
-- reclassified, intervention updated, hold or run moved) is grouped again; an item that left the Inbox is marked closed. p_full regroups every
-- waiting item (once on release), still within the time budget.
declare v_t0 timestamptz := clock_timestamp(); v_batch int := security.pipeline_num_v1('batch.layer4_groups', 500)::int;
        v_budget numeric := security.pipeline_num_v1('layer4.groups_fill_seconds', 30); v_keys text[]; v_done text[] := '{}'; v_n int := 0; v_closed int := 0; v_left int := 0; v_waiting int := 0;
begin
  create temp table if not exists _l4g_now (kind text, ref text, provider_id uuid, created_at timestamptz, input_at timestamptz, primary key (kind, ref)) on commit drop;
  truncate _l4g_now;
  insert into _l4g_now
  select i.kind, i.ref, i.provider_id, i.created_at,
         greatest(i.created_at, rd.classified_at, (select max(x.updated_at) from pipeline.layer4_interventions x where x.lane = 'aer_item' and x.entity = i.ref))
    from security.layer4_inbox_items_v2(null, null, null, false) i
    left join pipeline.layer4_item_readiness rd on i.kind in ('course_link', 'aer_review', 'provider_description', 'no_page_first_run', 'conjoint_first_run')
         and rd.item_id = case when i.ref ~ '^[0-9a-f-]{36}$' then i.ref::uuid end
  union all
  select 'intervention', x.id::text, x.provider_id, x.created_at, x.updated_at from pipeline.layer4_interventions x where x.status in ('ai_pending', 'awaiting_input', 'resuming')
  on conflict do nothing;
  get diagnostics v_waiting = row_count;
  update pipeline.layer4_item_groups g set state = 'closed', closed_at = now()
   where g.state = 'waiting' and not exists (select 1 from _l4g_now n where n.kind = g.kind and n.ref = g.ref);
  get diagnostics v_closed = row_count;
  loop
    v_keys := array(select n.kind || ':' || n.ref from _l4g_now n left join pipeline.layer4_item_groups g on g.kind = n.kind and g.ref = n.ref
                      where (g.kind is null or g.state <> 'waiting' or g.input_at is distinct from n.input_at or (p_full and g.classified_at < v_t0))
                        and not ((n.kind || ':' || n.ref) = any (v_done))
                      order by (g.kind is null) desc, g.classified_at nulls first, n.created_at limit v_batch);
    exit when cardinality(v_keys) = 0;
    insert into pipeline.layer4_item_groups as t(kind, ref, provider_id, item_created_at, grp, cls, rule, next_action, secondary, state, input_at, classified_at, closed_at)
    select c.kind, c.ref, coalesce(c.provider_id, n.provider_id), n.created_at, c.grp, c.cls, c.rule,
           case c.grp when 'A' then 'settled when its rule runs: ' || coalesce(c.rule, 'an existing rule') when 'B' then 'technical recovery continues by itself'
                      when 'C' then 'a person decides' else 'a person gives the missing information' end,
           coalesce(c.secondary, '[]'::jsonb), 'waiting', n.input_at, clock_timestamp(), null
      from security.layer4_groups_v1(null, null, v_keys) c join _l4g_now n on n.kind = c.kind and n.ref = c.ref
    on conflict (kind, ref) do update set provider_id = excluded.provider_id, item_created_at = excluded.item_created_at, grp = excluded.grp, cls = excluded.cls,
           rule = excluded.rule, next_action = excluded.next_action, secondary = excluded.secondary, state = 'waiting', input_at = excluded.input_at, classified_at = excluded.classified_at, closed_at = null;
    -- an item the classifier no longer lists (it left between the two reads) is not tried again in this run
    v_done := v_done || v_keys;
    v_n := v_n + cardinality(v_keys);
    exit when extract(epoch from clock_timestamp() - v_t0) >= v_budget;
  end loop;
  select count(*) into v_left from _l4g_now n left join pipeline.layer4_item_groups g on g.kind = n.kind and g.ref = n.ref
   where g.kind is null or g.state <> 'waiting' or g.input_at is distinct from n.input_at;
  return jsonb_build_object('waiting', v_waiting, 'grouped', v_n, 'closed', v_closed, 'not_grouped_yet', v_left, 'full', p_full,
                            'ms', round(extract(epoch from clock_timestamp() - v_t0) * 1000));
end $function$;
revoke all on function security.layer4_groups_fill_v1(boolean) from public, anon, authenticated;

-- the job (G1: catalogued first). Every 10 minutes away from :35-:42; no number in its command (G2)
insert into pipeline.automation_catalogue(jobname, area, sort, label, description, control_rank, batch_editable, layer23_stage) values
 ('layer4-groups', 'Platform upkeep', 419, 'Layer 4 groups (what each item needs from a person)',
  'At :06, :16, :26, :46 and :56: groups new and changed waiting Layer 4 items (A settled by an existing rule, B technical recovery, C a person''s decision, D information from a person) in batches of batch.layer4_groups within layer4.groups_fill_seconds, and marks items that left the Inbox. Decides, supersedes and admits nothing.',
  5, true, null)
on conflict (jobname) do nothing;
do $j$
begin
  if not exists (select 1 from cron.job where jobname = 'layer4-groups') then
    perform cron.schedule('layer4-groups', '6,16,26,46,56 * * * *', $c$select security.layer4_groups_fill_v1(false)$c$);
  end if;
end $j$;

-- 3 the card's evidence and earlier decision (§7, §8) -------------------------------------------------------------------------------------
create or replace function security.layer4_card_evidence_v1(p_kind text, p_ref text) returns jsonb
 language plpgsql stable security definer set search_path to '' as $function$
-- CF-247 mandate 16:32 §8 ("missing evidence on provider and adapter cards"): what the platform already holds for a university or adapter stop
-- (the onboarding run's result, the hold's evidence) and, for a review item, an earlier decision of the same question (pipeline.
-- layer4_item_readiness resolution "decided before"). Read only.
declare o pipeline.provider_onboarding; f pipeline.enrichment_flags; v_web text; v_courses int; rd record; v jsonb;
begin
  if p_kind in ('website_needed', 'too_few_pages', 'nothing_ready', 'central_to_approve', 'onboarding_failed') then
    select * into o from pipeline.provider_onboarding x where x.id = p_ref::uuid;
    if o.id is null then return null; end if;
    select p.website, (select count(*) from catalogue.courses c where c.provider_id = p.id and c.lifecycle_status = 'active') into v_web, v_courses
      from catalogue.providers p where p.id = o.provider_id;
    v := jsonb_strip_nulls(jsonb_build_object('Website', coalesce(o.result->>'website', v_web), 'Active courses', v_courses,
      'Courses in the run', o.result->'courses', 'Pages read', o.result->'pages_read', 'AI attempts', o.result->'ai_attempts',
      'Fields ready', case when jsonb_typeof(o.result->'ready') = 'array' then jsonb_array_length(o.result->'ready') end,
      'Why each field is held', case when jsonb_typeof(o.result->'held') = 'object' then o.result->'held' end,
      'Central pages', o.result->'central_pages', 'Stop', o.stop_reason, 'Note', o.note,
      'Runs stopped the same way', (select count(*) from pipeline.provider_onboarding y where y.provider_id = o.provider_id and y.status = 'stopped' and y.stop_reason = o.stop_reason)));
    return v;
  elsif p_kind in ('pages_not_found', 'site_down', 'fee_check', 'not_offered', 'not_on_site') then
    select * into f from pipeline.enrichment_flags x where x.id = case when p_ref ~ '^[0-9]+$' then p_ref::bigint end;
    if f.id is null then return null; end if;
    return jsonb_strip_nulls(jsonb_build_object('Site', coalesce(f.evidence->>'site', f.evidence->>'page_url'), 'How it was looked for', f.evidence->>'method',
      'Addresses found', f.evidence->'addresses', 'Pages read', f.evidence->'pages_read', 'Tried', nullif(f.evidence->'tried', '[]'::jsonb),
      'Discovery', f.evidence->>'discovery', 'Checks so far', f.checks, 'Tries so far', f.tries, 'Next automatic check', security.l4_time_v1(f.next_check_at)->>'text'));
  elsif p_kind in ('course_link', 'aer_review', 'provider_description', 'no_page_first_run', 'conjoint_first_run') and p_ref ~ '^[0-9a-f-]{36}$' then
    select r.readiness, r.route, r.resolution into rd from pipeline.layer4_item_readiness r where r.item_id = p_ref::uuid;
    if rd.route in ('platform:decided_before', 'platform:duplicate_pending', 'platform:covered_by_active') then
      return jsonb_build_object('Settled before', jsonb_strip_nulls(jsonb_build_object('Why', replace(substr(rd.route, 10), '_', ' '),
        'Covered by item', rd.resolution->>'covered_by_item', 'Decision', rd.resolution->>'decision', 'Decided', security.l4_time_v1((rd.resolution->>'decided_at')::timestamptz)->>'text',
        'Rule that may settle it', 'security.layer4_reconcile_v1 (layer4.reconcile_supersede_on ' ||
           case when security.pipeline_num_v1('layer4.reconcile_supersede_on', 0) >= 1 then 'on)' else 'off: a person decides until it is switched on)' end)));
    end if;
  end if;
  return null;
end $function$;
revoke all on function security.layer4_card_evidence_v1(text, text) from public, anon, authenticated;

create or replace function security.layer4_card_group_v1(p_items jsonb) returns jsonb
 language sql stable security definer set search_path to '' as $function$
  -- the group of the cards on screen, keyed 'kind:ref', from the stored groups only, with whether a person is needed, what moves the item and
  -- the evidence held (§7 questions 3 and 4). A card not grouped yet, or whose input changed since, shows C "not grouped yet"
  with k as (select distinct x->>'kind' kind, x->>'ref' ref from jsonb_array_elements(case when jsonb_typeof(p_items) = 'array' then p_items else '[]'::jsonb end) x
              where x ? 'kind' and x ? 'ref' limit security.pipeline_num_v1('layer4.lifecycle_batch_max', 50)::int),
       g as (select k.kind, k.ref, x.grp, x.cls, x.rule, x.next_action, x.classified_at,
                    x.kind is null or x.state <> 'waiting' or (rd.classified_at is not null and rd.classified_at > x.input_at) or (iv.updated_at is not null and iv.updated_at > x.input_at) pending
               from k left join pipeline.layer4_item_groups x on x.kind = k.kind and x.ref = k.ref
               left join pipeline.layer4_item_readiness rd on k.kind in ('course_link', 'aer_review', 'provider_description', 'no_page_first_run', 'conjoint_first_run')
                    and rd.item_id = case when k.ref ~ '^[0-9a-f-]{36}$' then k.ref::uuid end
               left join pipeline.layer4_interventions iv on k.kind = 'intervention' and iv.id = case when k.ref ~ '^[0-9]+$' then k.ref::bigint end)
  select coalesce(jsonb_object_agg(g.kind || ':' || g.ref, jsonb_strip_nulls(jsonb_build_object(
           'group', case when g.pending then 'C' else g.grp end, 'class', case when g.pending then 'not_grouped_yet' else g.cls end, 'rule', case when not g.pending then g.rule end,
           'group_label', case when g.pending then 'Ready for my decision (not grouped yet)' when g.grp = 'A' then 'Settled by an existing rule' when g.grp = 'B' then 'Technical recovery'
                               when g.grp = 'C' then 'Ready for my decision' else 'Information needed from me' end,
           'person_needed', case when g.pending then 'treated as a decision until job layer4-groups groups it' when g.grp = 'A' then 'no: an existing rule may settle it'
                                 when g.grp = 'B' then 'not yet: the platform is recovering it' when g.grp = 'C' then 'yes: a decision' else 'yes: information only a person can give' end,
           'grouped_at', security.l4_time_v1(g.classified_at), 'evidence', security.layer4_card_evidence_v1(g.kind, g.ref)))), '{}'::jsonb)
    from g
$function$;
revoke all on function security.layer4_card_group_v1(jsonb) from public, anon, authenticated;

-- 4 the lifecycle read adds the group, the person question, the evidence and navigation (md5-guarded edits of the v2.15.471 functions) -------
select pg_temp.edit_once('security.layer4_items_lifecycle_v1(jsonb)', 'f6eeef05b818c8818d9eef144ff91a18', '9abc7baa6fb19a660527559bac78df1a', array[
 array[$o$  select coalesce(jsonb_object_agg(z.kind || ':' || z.ref, security.layer4_lifecycle_one_v1(z.kind, z.ref, false)), '{}'::jsonb)$o$,
       $n$  -- CF-247 mandate 16:32 §7: each card also carries its group, whether a person is needed, and its evidence (security.layer4_card_group_v1)
  select coalesce(jsonb_object_agg(z.kind || ':' || z.ref, security.layer4_lifecycle_one_v1(z.kind, z.ref, false)
                                   || coalesce(g.j->(z.kind || ':' || z.ref), '{}'::jsonb)), '{}'::jsonb)$n$],
 array[$o$    from (select distinct x->>'kind' kind$o$, $n$    from (select security.layer4_card_group_v1(p_items) j) g, (select distinct x->>'kind' kind$n$]], array[1, 1]);
select pg_temp.edit_once('security.layer4_item_lifecycle_v1(text,text)', 'a908288151604a4e3d936be5f05a2fad', 'f54065d6b84004b3eb0f6e49be6b1779', array[
 array[$o$  select security.layer4_lifecycle_one_v1(p_kind, p_ref, true)$o$,
       $n$  select security.layer4_lifecycle_one_v1(p_kind, p_ref, true)
         || coalesce(security.layer4_card_group_v1(jsonb_build_array(jsonb_build_object('kind', p_kind, 'ref', p_ref)))->(p_kind || ':' || p_ref), '{}'::jsonb)$n$]], array[1]);
-- a choice that opened another screen is part of the item's history (inbox_navigate, §8)
select pg_temp.edit_once('security.layer4_lifecycle_one_v1(text,text,boolean)', 'a93b2bee90704eb3fbd3e09da350ba53', 'e1e3c4a1744663d9793a896816b93f8d', array[
 array[$o$x.target = p_kind || ':' || p_ref and x.action = 'inbox_decide' order by x.id desc limit v_n loop$o$,
       $n$x.target = p_kind || ':' || p_ref and x.action in ('inbox_decide', 'inbox_navigate', 'inbox_refused') order by x.id desc limit v_n loop$n$],
 array[$o$x.target = p_kind || ':' || p_ref and x.action = 'inbox_decide';$o$,
       $n$x.target = p_kind || ':' || p_ref and x.action in ('inbox_decide', 'inbox_navigate');$n$]], array[1, 1]);

-- 5 the decision guard (§8): the same decision sent again, and retries on an unchanged stop -----------------------------------------------------
create or replace function security.layer4_decide_guard_v1(p_kind text, p_ref text, p_choice text, p_pid uuid) returns jsonb
 language plpgsql stable security definer set search_path to '' as $function$
-- null when the decision may go ahead; otherwise the reply: {repeat, existing} for the same decision on the same item inside
-- layer4.duplicate_decision_seconds (unless the first was not applied), or {refused, repeat_of, alternative} for a choice in
-- layer4.once_only_choices already taken on the same university's same stop with nothing about the university changed since
declare e record; v_upd timestamptz;
begin
  select x.id, x.created_at into e from pipeline.admin_control_events x
   where x.area = 'layer4' and x.action = 'inbox_decide' and x.target = p_kind || ':' || p_ref and x.detail->>'choice' = p_choice
     and x.created_at > now() - make_interval(secs => security.pipeline_num_v1('layer4.duplicate_decision_seconds', 120)::int)
     and coalesce(x.detail->'result'->>'still_waiting', 'false') <> 'true'
   order by x.id desc limit 1;
  if e.id is not null then
    return jsonb_build_object('repeat', true, 'existing', jsonb_build_object('event', e.id, 'at', e.created_at),
      'request', 'Already sent: the same decision was recorded at ' || (security.l4_time_v1(e.created_at)->>'text') || ' (audit #' || e.id || '); it was not taken again.');
  end if;
  if p_choice = any (security.pipeline_list_v1('layer4.once_only_choices', '["retry", "rebuild", "release"]'::jsonb)) and p_pid is not null then
    select x.id, x.created_at into e from pipeline.admin_control_events x
     where x.area = 'layer4' and x.action = 'inbox_decide' and x.detail->>'kind' = p_kind and x.detail->>'choice' = p_choice and x.detail->>'provider_id' = p_pid::text
     order by x.id desc limit 1;
    select p.updated_at into v_upd from catalogue.providers p where p.id = p_pid;
    if e.id is not null and (v_upd is null or v_upd <= e.created_at) then
      return jsonb_build_object('refused', 'already tried on this stop', 'repeat_of', e.id,
        'request', 'Not tried again: ' || replace(p_choice, '_', ' ') || ' was already taken for this university at ' || (security.l4_time_v1(e.created_at)->>'text') || ' (audit #' || e.id
                   || ') and it stopped the same way; nothing about the university has changed since. It is tried at most once.',
        'alternative', case p_kind when 'nothing_ready' then 'Open the adapter in the builder to correct its patterns and qualify again, or CRICOS data only'
                                   when 'onboarding_failed' then 'Build by hand in the adapter builder'
                                   when 'pages_not_found' then 'Add page addresses in the builder, or change the website'
                                   else 'Choose another action, or leave the item with its reason' end);
    end if;
  end if;
  return null;
end $function$;
revoke all on function security.layer4_decide_guard_v1(text, text, text, uuid) from public, anon, authenticated;

select pg_temp.edit_once('public.admin_layer4_inbox(text,jsonb)', 'c0a972a6d6cc0652ce2dcc8f4d9cbbfc', '1895ed9870fdbcb332639befffd5a6ec', array[
 array[$o$  if v_det is null then raise exception 'this item is no longer waiting (someone may have decided it)'; end if;
$o$,
       $n$  if v_det is null then raise exception 'this item is no longer waiting (someone may have decided it)'; end if;
  -- CF-247 mandate 16:32 §8: the same decision sent again returns the first; a retry on an unchanged stop is refused (both audited, never taken)
  v_det := v_det || jsonb_build_object('_guard', security.layer4_decide_guard_v1(v_kind, v_ref, v_choice, v_pid));
  if v_det->'_guard' is not null and jsonb_typeof(v_det->'_guard') = 'object' then
    insert into pipeline.admin_control_events(area, action, target, detail, actor)
    values ('layer4', 'inbox_refused', v_kind || ':' || v_ref, jsonb_build_object('kind', v_kind, 'ref', v_ref, 'choice', v_choice, 'value', v_value, 'reason', v_reason, 'provider_id', v_pid,
            'result', v_det->'_guard'), auth.uid()) returning id into v_event;
    return security.layer4_action_ack_v1(v_kind, v_ref, jsonb_build_object('ok', false, 'kind', v_kind, 'choice', v_choice, 'ref', v_ref, 'event_id', v_event,
                                         'request', v_det->'_guard'->>'request', 'result', v_det->'_guard'));
  end if;
  v_det := v_det - '_guard';
$n$],
 array[$o$  insert into pipeline.admin_control_events(area, action, target, detail, actor)
  values ('layer4', 'inbox_decide', v_kind || ':' || v_ref, jsonb_build_object('kind', v_kind, 'ref', v_ref, 'choice', v_choice, 'value', v_value, 'reason', v_reason, 'provider_id', v_pid, 'result', v_r), auth.uid())$o$,
       $n$  -- CF-247 mandate 16:32 §8: whether the item is still waiting after the decision, so a decision that did not apply is never recorded as done
  if jsonb_typeof(v_r) = 'object' or v_r is null then
    v_r := coalesce(v_r, '{}'::jsonb) || jsonb_build_object('still_waiting', exists (select 1 from security.layer4_inbox_items_v2(null, v_kind, array[v_kind || ':' || v_ref], false)));
  end if;
  if coalesce(v_r->>'still_waiting', '') = 'false' then
    update pipeline.layer4_item_groups set state = 'closed', closed_at = now() where kind = v_kind and ref = v_ref and state = 'waiting';
  end if;
  insert into pipeline.admin_control_events(area, action, target, detail, actor)
  values ('layer4', 'inbox_decide', v_kind || ':' || v_ref, jsonb_build_object('kind', v_kind, 'ref', v_ref, 'choice', v_choice, 'value', v_value, 'reason', v_reason, 'provider_id', v_pid, 'result', v_r), auth.uid())$n$]],
 array[1, 1]);

-- the acknowledgement: a decision that left the item waiting is "Still incomplete"; an opened screen is named
select pg_temp.edit_once('security.layer4_ack_normalise_v1(text,text,boolean,jsonb,text,jsonb)', '50f4b7b6224c852bcecf4f054b3a81ae', 'e5f2fee175a931d3d886259f69c27bca', array[
 array[$o$         when x.r ? 'repeat' or x.d ? 'repeat' then 'already_requested'$o$,
       $n$         when x.r ? 'repeat' or x.d ? 'repeat' then 'already_requested'
         when coalesce(x.r->>'still_waiting', '') = 'true' and p_choice in ('approve', 'approve_except', 'reject', 'keep', 'use', 'enter', 'refuse', 'publish', 'not_international',
              'not_scholarship', 'duplicate', 'archive', 'archive_course', 'closed', 'merged', 'reviewed', 'report_fixed', 'report_not_changed', 'has_page', 'parent', 'no_page') then 'incomplete'
         when x.d ? 'navigated' then 'accepted'$n$],
 array[$o$    'reason', coalesce(p_request,$o$,
       $n$    'reason', coalesce(p_request, case when o.k = 'incomplete' and coalesce(x.r->>'still_waiting', '') = 'true' then 'sent, but the item is still waiting: the decision was not applied' end,$n$],
 array[$o$    'alternative', case when o.k in ('refused', 'deferred', 'already_requested', 'incomplete') then$o$,
       $n$    'alternative', case when o.k in ('refused', 'deferred', 'already_requested', 'incomplete') and p_kind <> 'aer_review' and x.d->>'alternative' is not null then x.d->>'alternative'
                        when o.k in ('refused', 'deferred', 'already_requested', 'incomplete') then$n$]],
 array[1, 1, 1]);
select pg_temp.edit_once('security.layer4_ack_headline_v1(text,jsonb,jsonb,timestamptz)', 'c715ccb353dcdd77cc6c8f88402595e6', '54654848fd9ed4d833e36ad3494dcf3a', array[
 array[$o$  select case
$o$,
       $n$  select case
    when p_d ? 'navigated' then 'Opened ' || case p_d->>'navigated' when 'course' then 'the course' when 'builder' then 'the adapter builder' else coalesce(p_d->>'navigated', 'another screen') end
                                || ' — ' || v_hm || ': the item closes when the work there is saved'
    when p_n->>'outcome' in ('refused', 'already_requested') and p_d ? 'repeat_of' and p_d->>'refused' = 'already tried on this stop' then 'Not tried again — the same stop, nothing changed'
    when p_n->>'outcome' = 'already_requested' and p_d->'existing' ? 'event' then 'Already sent — the first decision stands'
$n$]], array[1]);

-- 6 a choice that opens another screen is audited (§8) -----------------------------------------------------------------------------------------
create or replace function public.admin_layer4_navigate(p_args jsonb) returns jsonb
 language plpgsql security definer set search_path to '' as $function$
-- CF-247 mandate 16:32 §8: a Layer 4 choice that opens another screen (Open the course, the adapter, the builder, the central pages) records that it
-- was opened, by whom and when (pipeline.admin_control_events, action inbox_navigate). Nothing is decided; the item's lifecycle shows the visit
-- and, later, when the item closed.
declare v_kind text := p_args->>'kind'; v_ref text := p_args->>'ref'; v_choice text := p_args->>'choice'; v_c jsonb; v_pid uuid; v_ev bigint;
begin
  if auth.uid() is null then raise exception 'authentication required' using errcode = '42501'; end if;
  if security.current_role_rank() < 3 then raise exception 'Curator role or above required' using errcode = '42501'; end if;
  v_c := (select c from jsonb_array_elements(security.layer4_inbox_hooks_v1()->'kinds'->v_kind->'choices') c where c->>'key' = v_choice);
  if v_c is null or not (v_c ? 'link') then raise exception 'this choice does not open another screen'; end if;
  select g.provider_id into v_pid from pipeline.layer4_item_groups g where g.kind = v_kind and g.ref = v_ref;
  insert into pipeline.admin_control_events(area, action, target, detail, actor)
  values ('layer4', 'inbox_navigate', v_kind || ':' || v_ref, jsonb_build_object('kind', v_kind, 'ref', v_ref, 'choice', v_choice, 'provider_id', v_pid,
          'result', jsonb_build_object('navigated', v_c->>'link')), auth.uid()) returning id into v_ev;
  return jsonb_build_object('ok', true, 'event_id', v_ev);
end $function$;
revoke all on function public.admin_layer4_navigate(jsonb) from public, anon;
grant execute on function public.admin_layer4_navigate(jsonb) to authenticated;

-- 7 the Inbox's three choices (§7) ---------------------------------------------------------------------------------------------------------
create or replace function public.admin_layer4_groups(p_args jsonb default '{}'::jsonb) returns jsonb
 language plpgsql stable security definer set search_path to '' as $function$
-- CF-247 mandate 16:32 §7: Layer 4 › Inbox by what a person must do. summary: counts of C (Ready for my decision), D (Information needed from me),
-- B (Technical recovery) and A (settled by an existing rule: counts and rules only, no cards). items: one page of a group (optionally one
-- university or kind), oldest first, in the Inbox's own card shape. Curator and above.
declare v_lim int := least(greatest(coalesce((p_args->>'limit')::int, security.pipeline_num_v1('layer4.inbox_page_size', 25)::int), 1), 200);  -- fixed: page size bounds
        v_off int := greatest(coalesce((p_args->>'offset')::int, 0), 0); v_grp text := upper(coalesce(p_args->>'group', ''));
        v_prov uuid := nullif(p_args->>'provider_id', '')::uuid; v_kind text := nullif(p_args->>'kind', ''); v_kinds jsonb; v_t int := security.pipeline_num_v1('layer4.target_days', 7)::int;
begin
  if auth.uid() is null then raise exception 'authentication required' using errcode = '42501'; end if;
  if security.current_role_rank() < 3 then raise exception 'Curator role or above required' using errcode = '42501'; end if;
  if p_args->>'action' = 'flow' then return security.layer4_flow_report_v1(); end if;
  if coalesce(p_args->>'action', 'summary') = 'summary' then
    return security.layer4_group_counts_v1(v_prov) || jsonb_build_object('labels', jsonb_build_object('C', 'Ready for my decision', 'D', 'Information needed from me',
             'B', 'Technical recovery', 'A', 'Settled by existing rules'));
  end if;
  if v_grp not in ('A', 'B', 'C', 'D', 'I') then raise exception 'choose a group: C, D, B or I (Human input needed requests; A is counts only)'; end if;
  if v_grp = 'A' then raise exception 'group A is settled by existing rules and has no cards; see its rules in the summary'; end if;
  v_kinds := security.layer4_inbox_hooks_v1()->'kinds';
  -- the stored groups only (never classified here); a row whose input changed since it was grouped is listed under C until it is grouped again
  return (with g0 as (select x.kind, x.ref, x.provider_id, x.item_created_at created_at, x.cls, x.rule,
                             case when x.grp <> 'C' and ((rd.classified_at is not null and rd.classified_at > x.input_at) or (iv.updated_at is not null and iv.updated_at > x.input_at)) then 'C' else x.grp end grp,
                             (rd.classified_at is not null and rd.classified_at > x.input_at) or (iv.updated_at is not null and iv.updated_at > x.input_at) stale
                        from pipeline.layer4_item_groups x
                        left join pipeline.layer4_item_readiness rd on x.kind in ('course_link', 'aer_review', 'provider_description', 'no_page_first_run', 'conjoint_first_run')
                             and rd.item_id = case when x.ref ~ '^[0-9a-f-]{36}$' then x.ref::uuid end
                        left join pipeline.layer4_interventions iv on x.kind = 'intervention' and iv.id = case when x.ref ~ '^[0-9]+$' then x.ref::bigint end
                       where x.state = 'waiting' and (v_prov is null or x.provider_id = v_prov) and (v_kind is null or x.kind = v_kind)),
               -- I: the Human input needed requests (their own line); C, D, B: the waiting items, one disposition each
               g as (select * from g0 where case when v_grp = 'I' then g0.kind = 'intervention' else g0.kind <> 'intervention' and g0.grp = v_grp end),
               pg as (select * from g order by g.created_at, g.kind, g.ref limit v_lim offset v_off),
               b as (select i.kind, i.ref, i.provider_id, i.subject, i.why, i.suggestion, i.created_at, i.detail
                       from security.layer4_inbox_items_v2(null, null, array(select pg.kind || ':' || pg.ref from pg where pg.kind <> 'intervention'), true) i
                      where exists (select 1 from pg where pg.kind <> 'intervention')),
               j as (select pg.created_at, pg.kind, pg.ref, jsonb_build_object('kind', pg.kind, 'ref', pg.ref, 'provider_id', pg.provider_id,
                              'provider', (select coalesce(p.display_name, p.canonical_name) from catalogue.providers p where p.id = pg.provider_id),
                              'subject', coalesce(b.subject, (select x.subject from pipeline.layer4_interventions x where pg.kind = 'intervention' and x.id::text = pg.ref)),
                              'why', b.why, 'suggestion', b.suggestion, 'created_at', pg.created_at, 'late', pg.created_at < now() - make_interval(days => v_t),
                              'detail', coalesce(b.detail, '{}'::jsonb), 'o', (v_kinds->pg.kind->>'order')::int, 'hook', pg.kind = 'intervention',
                              'group', pg.grp, 'class', case when pg.stale then 'not_grouped_yet' else pg.cls end, 'rule', pg.rule) item
                       from pg left join b on b.kind = pg.kind and b.ref = pg.ref
                      -- a stored row whose item has just left the Inbox is not drawn (the next run marks it closed)
                      where pg.kind = 'intervention' or b.ref is not null)
    select jsonb_build_object('group', v_grp, 'total', (select count(*) from g), 'offset', v_off, 'limit', v_lim,
                              'items', coalesce((select jsonb_agg(j.item order by j.created_at, j.kind, j.ref) from j), '[]'::jsonb)));
end $function$;
revoke all on function public.admin_layer4_groups(jsonb) from public, anon;
grant execute on function public.admin_layer4_groups(jsonb) to authenticated;

-- 7b the flow report (direction 18:08 §5): what actually happened to Layer 4 work, kept apart; a move between queues is never an admission ------
create or replace function security.layer4_flow_report_v1() returns jsonb
 language sql stable security definer set search_path to '' as $function$
  -- over layer4.lifecycle_report_days, from the existing records only: genuine admissions and publication (pipeline.layer4_admission_checks, the
  -- post-decision check), decisions that did not apply, technical recovery (corrected reads that replaced a held read; Human input needed
  -- requests resumed and verified), reroutes (Decision 179: official-link items moved to Course page needed), duplicates and other platform
  -- supersessions (pipeline.layer4_supersessions, reversals left out). Each count is separate; none is added to another.
  with p as (select make_interval(days => security.pipeline_num_v1('layer4.lifecycle_report_days', 7)::int) d)
  select jsonb_build_object('days', security.pipeline_num_v1('layer4.lifecycle_report_days', 7),
    'decisions_applied', (select count(*) from pipeline.admin_control_events e, p where e.area = 'layer4' and e.action = 'inbox_decide' and e.created_at > now() - p.d
                            and coalesce(e.detail->'result'->>'still_waiting', 'false') <> 'true' and e.detail->'result' ? 'still_waiting'),
    'decisions_not_applied', (select count(*) from pipeline.admin_control_events e, p where e.area = 'layer4' and e.action = 'inbox_decide' and e.created_at > now() - p.d
                                and e.detail->'result'->>'still_waiting' = 'true'),
    'admitted', (select count(*) from pipeline.layer4_admission_checks a, p where a.decided_at > now() - p.d and a.admitted),
    'admitted_and_published', (select count(*) from pipeline.layer4_admission_checks a, p where a.decided_at > now() - p.d and a.admitted and a.published),
    'approved_not_admitted', (select count(*) from pipeline.layer4_admission_checks a, p where a.decided_at > now() - p.d and a.result = 'not_admitted'),
    'technical_recovery', jsonb_build_object(
       'corrected_reads_replaced', (select count(*) from pipeline.aer_read_supersessions s, p where s.state = 'superseded' and s.closed_at > now() - p.d),
       'corrected_reads_refused', (select count(*) from pipeline.aer_read_supersessions s, p where s.state = 'refused' and s.closed_at > now() - p.d),
       'human_input_resumed', (select count(*) from pipeline.layer4_interventions i, p where i.resumed_at > now() - p.d),
       'human_input_verified', (select count(*) from pipeline.layer4_interventions i, p where i.verified_at > now() - p.d)),
    'reroutes', jsonb_build_object('decision_179_to_course_page_needed',
       (select count(*) from pipeline.layer4_review_items r, p where r.status = 'superseded' and r.decided_at > now() - p.d and r.field_code = 'official_course_url'
           and exists (select 1 from pipeline.course_page_needed n where r.id = any (n.converted_items)))),
    'duplicates', (select count(*) from pipeline.layer4_supersessions x, p where x.reason = 'duplicate_pending' and x.reversed_at is null and x.at > now() - p.d),
    'supersessions', (select coalesce(jsonb_object_agg(reason, n), '{}'::jsonb) from (select x.reason, count(*) n from pipeline.layer4_supersessions x, p
                        where x.reason <> 'duplicate_pending' and x.reversed_at is null and x.at > now() - p.d group by 1) z),
    'note', 'Admissions are counted only from the post-decision check (pipeline.layer4_admission_checks); reroutes, duplicates and supersessions move work between queues and are never admissions')
$function$;
revoke all on function security.layer4_flow_report_v1() from public, anon, authenticated;

-- 8 component register --------------------------------------------------------------------------------------------------------------------
insert into pipeline.component_register(kind, name, layer, area, purpose, status, replaces, introduced_in) values
 ('function', 'security.layer4_groups_v1', 'Layer 4', 'Layer 4 review', 'Every waiting item in group A, B, C or D (mandate 16:32 §2)', 'active', '{}', '20261104590000'),
 ('function', 'security.layer4_group_counts_v1', 'Layer 4', 'Layer 4 review', 'Counts of the Inbox''s three choices and group A rules', 'active', '{}', '20261104590000'),
 ('function', 'security.layer4_card_evidence_v1', 'Layer 4', 'Layer 4 review', 'Evidence on provider and adapter cards; an earlier decision of the same question', 'active', '{}', '20261104590000'),
 ('function', 'security.layer4_card_group_v1', 'Layer 4', 'Layer 4 review', 'The group, person question and evidence of the cards on screen', 'active', '{}', '20261104590000'),
 ('function', 'security.layer4_decide_guard_v1', 'Layer 4', 'Layer 4 review', 'Same decision sent again; retries on an unchanged stop', 'active', '{}', '20261104590000'),
 ('function', 'security.layer4_cl_group_call_v1', 'Layer 4', 'Layer 4 review', 'The Course Link workstream''s routing, when shipped', 'active', '{}', '20261104590000'),
 ('function', 'public.admin_layer4_groups', 'Layer 4', 'Layer 4 review', 'Layer 4 › Inbox: Ready for my decision, Information needed from me, Technical recovery', 'active', '{}', '20261104590000'),
 ('table', 'pipeline.layer4_item_groups', 'Layer 4', 'Layer 4 review', 'Stored group, class, rule and next action of each Layer 4 item', 'active', '{}', '20261104590000'),
 ('function', 'security.layer4_groups_fill_v1', 'Layer 4', 'Layer 4 review', 'Job layer4-groups: groups new and changed items within a time budget', 'active', '{}', '20261104590000'),
 ('job', 'layer4-groups', 'Layer 4', 'Platform upkeep', 'Stores the operational group of new and changed Layer 4 items', 'active', '{}', '20261104590000'),
 ('function', 'security.layer4_flow_report_v1', 'Layer 4', 'Layer 4 review', 'Admissions, recovery, reroutes, duplicates and supersessions kept apart (direction 18:08 §5)', 'active', '{}', '20261104590000'),
 ('function', 'public.admin_layer4_navigate', 'Layer 4', 'Layer 4 review', 'Audit of a Layer 4 choice that opens another screen', 'active', '{}', '20261104590000')
on conflict do nothing;

-- 9 post-check -------------------------------------------------------------------------------------------------------------------------------
do $$
declare r record;
begin
  for r in select * from (values
      ('public.admin_layer4_inbox(text,jsonb)', '1895ed9870fdbcb332639befffd5a6ec'),
      ('security.layer4_lifecycle_one_v1(text,text,boolean)', 'e1e3c4a1744663d9793a896816b93f8d'),
      ('security.layer4_items_lifecycle_v1(jsonb)', '9abc7baa6fb19a660527559bac78df1a'),
      ('security.layer4_item_lifecycle_v1(text,text)', 'f54065d6b84004b3eb0f6e49be6b1779')) v(sig, m) loop
    if md5(pg_get_functiondef(r.sig::regprocedure)) <> r.m then raise exception 'post-check: % has md5 %', r.sig, md5(pg_get_functiondef(r.sig::regprocedure)); end if;
  end loop;
  if not exists (select 1 from pipeline.automation_catalogue where jobname = 'layer4-groups') then raise exception 'post-check: job layer4-groups is catalogued'; end if;
end $$;
