-- CF-247 Layer 4 › Inbox performance: bounded first reads, server-side paging per university and kind, lazy detail, kind hooks
-- (Platform Admin approval 4 Nov 2026 06:53 §1 and §6, admin docs/platform/ui-audit/2026-11-04-ss020-follow-up-approval-0653.md; AER usability
-- decision 06:58 §2 to §4, 2026-11-04-layer4-aer-usability-recovery-decision-0658.md; contract 2026-11-04-layer4-inbox-paging-contract.md).
-- Why (live, read-only, 4 Nov 2026 06:56-06:58 AEDT):
--   * every read of the screen (summary, universities, items) and every decision built all 4,995 waiting items with their detail
--     (5.4 MB of detail) into a temporary table: 0.4-1.8 s each when the database is quiet; admin_layer4_inbox averaged 742 ms and reached
--     7.7 s over 9,158 calls (the 8 s screen time-out cancels the rest). Opening the screen runs three of them at once.
--   * each AER card reads public.layer4_aer_review_read as soon as it is drawn (55,135 calls, 240 ms average, up to 7.2 s), up to 200 cards a
--     page; one university has 303 AER items. A page of 200 items is what makes the screen about 22,000 px long.
-- What:
--   1 security.layer4_inbox_items_v2(provider, kind, keys, detail): the item list with the university, kind and item filters applied inside
--     each source before anything is built, and the detail built only when asked. security.layer4_inbox_items_v1() keeps its output and
--     now reads it (one definition of what waits for a person).
--   2 security.layer4_inbox_counts_v1(target_days): counts by kind and university without building any detail.
--   3 public.admin_layer4_inbox: summary and universities read counts only; items reads one page (keys first, detail for that page only),
--     in the same order and with the same cursor as before (UR-04); new action detail reads the stored-copy facts and a kind hook's detail
--     for the items on screen; decide finds its one item by key. Choices, labels, ranks, reasons, audit rows and effects are unchanged.
--   4 Kind hooks (pipeline.layer4_inbox_kind_hooks): a new kind (mode kind) supplies counts, a page, lazy detail and its decision; an
--     extension (mode extend) adds choices and detail to a built-in kind (AER recovery, decision 06:58 §1). Functions are found with
--     to_regprocedure in schema security; a missing or failing hook is skipped, never breaking the Inbox.
--   5 Settings: items and universities a page, detail reads at once, hooks on or off.
-- Edited live functions (md5-guarded, before -> after):
--   security.layer4_inbox_items_v1()              4fc05d14f4ba49335ff90496a20f582d -> 2fa8b921d19f05dbd147f6833c71b784
--   public.admin_layer4_inbox(text,jsonb)         1fb975482d29c7c9f1ecdf3cdb011a10 -> 29705b99108e7a0b4d68fea398565d36
-- Replaces: security.layer4_inbox_items_v1 (same name and output; it reads security.layer4_inbox_items_v2), public.admin_layer4_inbox (same
--   name and actions; summary, universities, items and decide no longer build every item)
-- Retires: nothing (the temporary table _l4 of every screen read is no longer made; there is no other object to retire)
-- Nothing is dropped or deleted. No consumer API object changes (G3). No job, no Firecrawl or AI spend.

create or replace function pg_temp.replace_once(p_sig text, p_before text, p_after text, p_def text) returns text language plpgsql as $f$
declare v_now text := md5(pg_get_functiondef(p_sig::regprocedure));
begin
  if v_now = p_after then return p_sig || ': already applied'; end if;
  if v_now <> p_before then raise exception 'live % differs from the definition this change replaces (md5 %)', p_sig, v_now; end if;
  execute p_def;
  if md5(pg_get_functiondef(p_sig::regprocedure)) <> p_after then
    raise exception '% after the change has md5 %, expected %', p_sig, md5(pg_get_functiondef(p_sig::regprocedure)), p_after;
  end if;
  return p_sig || ': applied';
end $f$;

-- 1 settings (G2; Settings › Pipeline settings, section Layer 4) ---------------------------------------------------------------------------
insert into pipeline.platform_toolset_settings(toolset_key, key, label, help, kind, value, min_value, max_value, unit, sort, section, used_by, reason) values
 ('pipeline', 'layer4.inbox_page_size', 'Layer 4 Inbox: items a page',
  'How many items Layer 4 › Inbox shows on one page of a university or a kind. Next and Previous move through the rest, oldest first.',
  'number', to_jsonb(25), 5, 200, 'items', 330, 'Layer 4', 'public.admin_layer4_inbox (summary paging); src/Layer4Inbox.jsx',
  'Platform Admin 4 Nov 2026 06:53 §1: bounded first reads; a page of 200 made the screen about 22,000 px long'),
 ('pipeline', 'layer4.inbox_universities_page_size', 'Layer 4 Inbox: universities a page',
  'How many universities the university list shows on one page.',
  'number', to_jsonb(25), 10, 100, 'universities', 331, 'Layer 4', 'public.admin_layer4_inbox (summary paging); src/Layer4Inbox.jsx',
  'Platform Admin 4 Nov 2026 06:53 §1 (page length)'),
 ('pipeline', 'layer4.inbox_detail_parallel', 'Layer 4 Inbox: detail reads at once',
  'An AER card reads its rows, and a card with a kind hook reads its detail, only when it is on screen; at most this many such reads run at the same time.',
  'number', to_jsonb(3), 1, 10, 'reads', 332, 'Layer 4', 'public.admin_layer4_inbox (summary paging); src/Layer4Inbox.jsx',
  'Platform Admin 4 Nov 2026 06:53 §1: lazy loading of expensive evidence and detail'),
 ('pipeline', 'layer4.inbox_hooks_on', 'Layer 4 Inbox: kinds and recovery choices from other workstreams',
  'On (1): kinds and choices registered in pipeline.layer4_inbox_kind_hooks show in the Inbox once their functions exist (human input needed; AER recovery). Off (0): the built-in kinds only.',
  'number', to_jsonb(1), 0, 1, 'on (1) or off (0)', 333, 'Layer 4', 'security.layer4_inbox_hooks_v1',
  'Platform Admin 4 Nov 2026 06:53 §1 (interventions use this Inbox) and 06:58 §1 (recovery actions); nothing shows until the functions are released')
on conflict do nothing;

-- 2 the hook register -----------------------------------------------------------------------------------------------------------------------
create table if not exists pipeline.layer4_inbox_kind_hooks (
  kind text not null,
  mode text not null default 'kind' check (mode in ('kind', 'extend')),
  kind_fn text, counts_fn text, page_fn text, detail_fn text, decide_fn text,
  enabled boolean not null default true,
  owner text, note text,
  created_at timestamptz not null default now(),
  primary key (kind, mode));
comment on table pipeline.layer4_inbox_kind_hooks is 'CF-247 Layer 4 Inbox kind hooks (Platform Admin 4 Nov 2026 06:53 §1, 06:58 §1; admin docs/platform/ui-audit/2026-11-04-layer4-inbox-paging-contract.md). One row per kind that plugs into Layer 4 › Inbox without another heavy query. mode kind: a new kind with its own counts (counts_fn), pages (page_fn), lazy detail (detail_fn) and decision (decide_fn, which audits itself). mode extend: choices (kind_fn), detail and decisions added to a built-in kind, such as AER recovery. Each function is a full signature in schema security, found with to_regprocedure by security.layer4_inbox_hooks_v1; a row whose functions do not exist yet changes nothing. Switch layer4.inbox_hooks_on. Never read by the consumer API.';
revoke all on pipeline.layer4_inbox_kind_hooks from public, anon, authenticated;
alter table pipeline.layer4_inbox_kind_hooks enable row level security;
insert into pipeline.layer4_inbox_kind_hooks(kind, mode, kind_fn, counts_fn, page_fn, detail_fn, decide_fn, owner, note) values
 ('intervention', 'kind', 'security.layer4_intervention_kind_v1()', 'security.layer4_intervention_inbox_counts_v1()', 'security.layer4_intervention_inbox_page_v1(jsonb)',
  'security.layer4_intervention_inbox_detail_v1(text)', 'security.layer4_intervention_inbox_decide_v1(text,text,text,text)', 'human-assisted recovery (cf247-human-assisted-recovery)',
  'Human input needed (Platform Admin 06:30 human-assisted recovery; 06:53 §1)'),
 ('aer_review', 'extend', 'security.layer4_aer_recovery_kind_v1()', null, null, 'security.layer4_aer_recovery_detail_v1(text)',
  'security.layer4_aer_recovery_decide_v1(text,text,text,text)', 'human-assisted recovery (cf247-human-assisted-recovery)',
  'AER recovery choices on E13-held reads (Platform Admin 06:58 §1, §3); Approve all and Approve except stay held by E13')
on conflict do nothing;

-- 3 the item list, filtered at the source ---------------------------------------------------------------------------------------------------
create or replace function security.layer4_inbox_items_v2(p_provider_id uuid default null, p_kind text default null, p_keys text[] default null, p_detail boolean default true)
 returns table(kind text, ref text, provider_id uuid, subject text, why text, suggestion text, created_at timestamp with time zone, detail jsonb)
 language sql stable security definer set search_path to ''
as $function$
  -- CF-247 Layer 4 Inbox performance (4 Nov 2026): every item that needs a person, one row each, as security.layer4_inbox_items_v1 had them.
  -- A university (p_provider_id), a kind (p_kind) or items ('kind:ref' in p_keys) are chosen inside each source before anything is built;
  -- p_detail false leaves the detail out (counts and keys only).
  with ob as (select distinct on (o.provider_id) o.* from pipeline.provider_onboarding o order by o.provider_id, o.created_at desc),
  cricos_only as (select b.provider_id from pipeline.adapter_builds b where b.wave = 'cricos-only'),
  held_pages as (select f.provider_id from pipeline.enrichment_flags f where f.entity = 'provider' and f.state = 'raised' and f.reason_code = 'course_pages_not_found')
  -- course links and other review items
  -- hotfix 26 Oct 2026: a first run for a university (no page published, conjoint rule) carries its university and its own kind
  select z.k, r.id::text, z.pid,
         coalesce(nullif(c.display_title, ''), c.canonical_title, s.name,
                  case when r.entity_type = 'provider' and r.field_code = 'no_page_first_run' then 'No page published: first run'
                       when r.entity_type = 'provider' and r.field_code = 'conjoint_rule_first_run' then 'Conjoint or double degrees: first run' end,
                  case r.field_code when 'entry_matrix_first_run' then 'Entry requirements: first read of the provider table'
                                       when 'entry_matrix_change' then 'Entry requirements: the provider table changed'
                                       when 'provider_description' then 'University description from the official page' end,
                  r.field_code),
         -- mandate 3 Nov 2026 20:47 §5: a CRICOS code is named only for Australian providers
         case when coalesce(kc.iso_alpha2, 'AU') <> 'AU' and r.escalation_reason ilike '%CRICOS%'
              then replace(replace(r.escalation_reason, 'this course''s CRICOS code', 'this course''s code'), 'CRICOS code', 'course code')
              else coalesce(nullif(r.escalation_reason, ''), 'Needs a decision') end, null::text, r.created_at,
         case when p_detail then
         jsonb_build_object('field_code', r.field_code, 'course_id', c.id, 'course_code', c.course_code, 'before', r.before_value, 'proposed', r.proposed_value,
                            'code_label', case when coalesce(kc.iso_alpha2, 'AU') = 'AU' then 'CRICOS' else 'Course code' end,
                            -- UR-05 (1 Nov 2026): the stored copy behind the item, when it was captured, and whether a newer copy of the same page exists
                            'evidence_id', r.evidence_id, 'captured_at', ev.captured_at, 'source_url', ev.source_url,
                            'newer_copy', ev.id is not null and exists (select 1 from pipeline.evidence_artifacts n where lower(n.source_url) = lower(ev.source_url) and n.captured_at > ev.captured_at)) end
    from pipeline.layer4_review_items r
    left join catalogue.courses c on r.entity_type = 'course' and c.id = r.entity_id
    left join scholarship.scholarships s on r.entity_type = 'scholarship' and s.id = r.entity_id
    cross join lateral (select case when r.entity_type = 'provider' and r.field_code = 'no_page_first_run' then 'no_page_first_run'
              when r.entity_type = 'provider' and r.field_code = 'conjoint_rule_first_run' then 'conjoint_first_run'
              when r.field_code = any (security.aer_review_kinds_v1()) then 'aer_review'  -- CF-247 A1-A3 (30 Oct 2026): the AER review path
              when r.entity_type = 'provider' and r.field_code = 'provider_description' then 'provider_description'  -- CF-247 P1 (2 Nov 2026): university descriptions
              when r.entity_type = 'course' and r.field_code = 'course_description_first_read' then 'provider_description'  -- CF-247 Workstream C (3 Nov 2026): course descriptions, the same review (approve as read or reject)
              else 'course_link' end::text k,
              coalesce(c.provider_id, s.provider_id, case when r.entity_type = 'provider' then r.entity_id end) pid) z
    left join pipeline.evidence_artifacts ev on p_detail and ev.id = r.evidence_id
    left join catalogue.providers pv on pv.id = coalesce(c.provider_id, s.provider_id)
    left join ref.countries kc on kc.id = pv.country_id
   where r.status = 'pending'
     and (p_provider_id is null or z.pid = p_provider_id) and (p_kind is null or z.k = p_kind) and (p_keys is null or z.k || ':' || r.id::text = any (p_keys))
  union all
  -- held scholarship pages, with the AI re-check
  select 'held_scholarship', r.id::text, r.provider_id,
         coalesce((select e.answer->>'name' from pipeline.scholarship_ai_extractions e where e.id = r.extraction_ids[array_upper(r.extraction_ids, 1)]), r.url),
         r.reason, r.recheck->>'why', r.created_at,
         case when p_detail then
         jsonb_build_object('url', r.url, 'recommendation', r.recheck->>'recommendation', 'audience_quote', r.recheck->>'audience_quote', 'value_quote', r.recheck->>'value_quote',
                            'extraction_id', (select e.id from pipeline.scholarship_ai_extractions e where e.id = any (r.extraction_ids) and coalesce((e.answer->>'is_scholarship')::boolean, false) order by e.id desc limit 1)) end
    from pipeline.scholarship_ai_reviews r where r.status = 'pending'
     and (p_kind is null or p_kind = 'held_scholarship') and (p_provider_id is null or r.provider_id = p_provider_id)
     and (p_keys is null or 'held_scholarship:' || r.id::text = any (p_keys))
  union all
  -- universities whose onboarding stopped and needs a person
  select z.k, ob.id::text, ob.provider_id, null, coalesce(ob.note, ob.stop_reason), null, ob.updated_at,
         case when p_detail then jsonb_build_object('stop_reason', ob.stop_reason, 'onboarding_id', ob.id) end
    from ob
    cross join lateral (select case ob.stop_reason when 'no_website' then 'website_needed' when 'too_few_pages' then 'too_few_pages' when 'nothing_ready' then 'nothing_ready'
              when 'approve_central' then 'central_to_approve' else 'onboarding_failed' end k) z
   where ob.status = 'stopped' and ob.stop_reason in ('no_website', 'too_few_pages', 'nothing_ready', 'approve_central', 'proposal_failed', 'capture_failed')
     and ob.provider_id not in (select provider_id from cricos_only)
     and not (ob.stop_reason = 'too_few_pages' and ob.provider_id in (select provider_id from held_pages))
     and (p_kind is null or z.k = p_kind) and (p_provider_id is null or ob.provider_id = p_provider_id) and (p_keys is null or z.k || ':' || ob.id::text = any (p_keys))
  union all
  -- provider holds a person lifts
  select z.k, f.id::text, f.provider_id, null, f.reason, null, f.flagged_at, case when p_detail then jsonb_build_object('flag_id', f.id, 'evidence', f.evidence) end
    from pipeline.enrichment_flags f
    cross join lateral (select case f.reason_code when 'course_pages_not_found' then 'pages_not_found' when 'site_unreachable' then 'site_down' else 'fee_check' end k) z
   where f.entity = 'provider' and f.state = 'raised'
     and (f.reason_code in ('course_pages_not_found', 'adapter_fee_fails_check')
          or (f.reason_code = 'site_unreachable' and f.flagged_at < now() - make_interval(days => security.pipeline_num_v1('layer4.site_down_days', 30)::int)))
     and (p_kind is null or z.k = p_kind) and (p_provider_id is null or f.provider_id = p_provider_id) and (p_keys is null or z.k || ':' || f.id::text = any (p_keys))
  union all
  -- course holds a person decides
  select z.k, f.id::text, coalesce(f.provider_id, c.provider_id), coalesce(nullif(c.display_title, ''), c.canonical_title), f.reason, null, f.flagged_at,
         case when p_detail then
         jsonb_build_object('flag_id', f.id, 'course_id', c.id, 'course_code', c.course_code,
                            -- mandate 3 Nov 2026 20:47 §5: the stored copy of the course's bound page, so a fee or course hold shows its evidence
                            'evidence_id', g.evidence_id, 'captured_at', gev.captured_at, 'source_url', gev.source_url) end
    from pipeline.enrichment_flags f left join catalogue.courses c on c.id::text = f.entity_key
    cross join lateral (select case f.reason_code when 'not_offered' then 'not_offered' when 'not_on_provider_site' then 'not_on_site' else 'fee_check' end k) z
    left join pipeline.coverage_course_pages g on p_detail and g.course_id = c.id
    left join pipeline.evidence_artifacts gev on gev.id = g.evidence_id
   where f.entity = 'course' and f.state = 'raised' and f.reason_code in ('not_offered', 'not_on_provider_site', 'fee_crosscheck')
     and (p_kind is null or z.k = p_kind) and (p_provider_id is null or coalesce(f.provider_id, c.provider_id) = p_provider_id)
     and (p_keys is null or z.k || ':' || f.id::text = any (p_keys))
  union all
  -- Decision 179 (Platform Admin 3 Nov 2026 20:29): courses that need a correct page, while open and still without an official page
  select 'course_page_needed', n.course_id::text, n.provider_id, coalesce(nullif(c.display_title, ''), c.canonical_title),
         'No page of this course has been verified. ' || n.refused || ' page' || case when n.refused = 1 then ' was' else 's were' end || ' found and refused, the last: '
           || coalesce(n.last_refused_reason, 'not proved to be this course''s page'),
         null, n.created_at,
         case when p_detail then
         jsonb_build_object('course_id', c.id, 'course_code', c.course_code, 'code_label', case when coalesce(kc.iso_alpha2, 'AU') = 'AU' then 'CRICOS' else 'Course code' end,
                            'proposed', jsonb_build_object('course_url', n.last_refused_url), 'refused', n.refused, 'lane', n.last_refused_lane, 'converted_items', to_jsonb(n.converted_items),
                            'searches_requested', n.searches_requested, 'evidence_id', n.last_refused_evidence, 'captured_at', nev.captured_at, 'source_url', nev.source_url) end
    from pipeline.course_page_needed n join catalogue.courses c on c.id = n.course_id
    left join catalogue.providers pv on pv.id = n.provider_id left join ref.countries kc on kc.id = pv.country_id
    left join pipeline.evidence_artifacts nev on p_detail and nev.id = n.last_refused_evidence
   where n.state = 'open' and c.lifecycle_status = 'active'
     and not exists (select 1 from catalogue.course_links l where l.course_id = n.course_id and l.link_type = 'official_course' and l.status = 'active')
     and (p_kind is null or p_kind = 'course_page_needed') and (p_provider_id is null or n.provider_id = p_provider_id)
     and (p_keys is null or 'course_page_needed:' || n.course_id::text = any (p_keys))
  union all
  -- counsellor reports from Zoho
  select 'counsellor_report', d.id::text, z.pid, coalesce(d.detail->>'label', d.field_code), coalesce(d.detail->>'note', 'Reported by a counsellor'), null, d.created_at,
         case when p_detail then d.detail end
    from pipeline.data_flags d
    cross join lateral (select coalesce((select c.provider_id from catalogue.courses c where d.entity_type = 'course' and c.id = d.entity_id), case when d.entity_type = 'provider' then d.entity_id end) pid) z
   where d.flag_code = 'reported' and d.status = 'open'
     and (p_kind is null or p_kind = 'counsellor_report') and (p_provider_id is null or z.pid = p_provider_id) and (p_keys is null or 'counsellor_report:' || d.id::text = any (p_keys))
  union all
  -- CF-247 20 Oct 2026: providers whose every registered course left the register (from the retired Review queue)
  select 'provider_departure', d.id::text, d.provider_id, coalesce(p.display_name, p.canonical_name),
         'Every registered course left the register (' || d.courses_retired || ' course' || case when d.courses_retired = 1 then '' else 's' end || '). Closed, merged into another provider, or still operating?',
         null, d.created_at, case when p_detail then jsonb_build_object('departure_id', d.id, 'courses_retired', d.courses_retired, 'note', d.note) end
    from pipeline.layer1_provider_departures d left join catalogue.providers p on p.id = d.provider_id where d.status = 'needs_review'
     and (p_kind is null or p_kind = 'provider_departure') and (p_provider_id is null or d.provider_id = p_provider_id)
     and (p_keys is null or 'provider_departure:' || d.id::text = any (p_keys))
$function$;
revoke all on function security.layer4_inbox_items_v2(uuid, text, text[], boolean) from public, anon, authenticated;

-- the old list keeps its name and output, read from the one definition above
select pg_temp.replace_once('security.layer4_inbox_items_v1()', '4fc05d14f4ba49335ff90496a20f582d', '2fa8b921d19f05dbd147f6833c71b784', $def$
CREATE OR REPLACE FUNCTION security.layer4_inbox_items_v1()
 RETURNS TABLE(kind text, ref text, provider_id uuid, subject text, why text, suggestion text, created_at timestamp with time zone, detail jsonb)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  -- CF-247 Layer 4 Inbox performance (4 Nov 2026): every item that needs a person, one row each, from security.layer4_inbox_items_v2
  select * from security.layer4_inbox_items_v2(null, null, null, true)
$function$
$def$);

-- 4 counts without building items -----------------------------------------------------------------------------------------------------------
create or replace function security.layer4_inbox_counts_v1(p_target_days int)
 returns table(kind text, provider_id uuid, n bigint, oldest timestamptz, late bigint)
 language sql stable security definer set search_path to ''
as $function$
  -- CF-247 Layer 4 Inbox performance (4 Nov 2026): waiting items by kind and university, and how many are older than the target, with no detail built
  select i.kind, i.provider_id, count(*), min(i.created_at), count(*) filter (where i.created_at < now() - make_interval(days => p_target_days))
    from security.layer4_inbox_items_v2(null, null, null, false) i group by 1, 2
$function$;
revoke all on function security.layer4_inbox_counts_v1(int) from public, anon, authenticated;

-- 5 kind hooks ------------------------------------------------------------------------------------------------------------------------------
create or replace function security.layer4_inbox_hook_fn_v1(p_sig text) returns text
 language sql stable security definer set search_path to ''
as $function$
  -- a hook function by its full signature, only in schema security; null when it does not exist (yet)
  select p.oid::regproc::text from pg_catalog.pg_proc p join pg_catalog.pg_namespace n on n.oid = p.pronamespace
   where p.oid = pg_catalog.to_regprocedure(p_sig) and n.nspname = 'security'
$function$;
revoke all on function security.layer4_inbox_hook_fn_v1(text) from public, anon, authenticated;

create or replace function security.layer4_inbox_hooks_v1() returns jsonb
 language plpgsql security definer set search_path to ''
as $function$
-- CF-247 Layer 4 Inbox kind hooks (4 Nov 2026; contract admin docs/platform/ui-audit/2026-11-04-layer4-inbox-paging-contract.md): the kinds and
-- choices of the Inbox, the built-in ones (security.layer4_inbox_kinds_v1) with the registered hooks whose functions exist. A hook that is
-- missing, collides with a built-in kind or fails is left out and named, so the Inbox always loads.
declare v_kinds jsonb := security.layer4_inbox_kinds_v1(); v_builtin jsonb := security.layer4_inbox_kinds_v1(); h record; v_fn jsonb; v_id text; v_k jsonb; v_ch jsonb;
        v_hooks jsonb := '[]'; v_missing jsonb := '[]'; v_failed jsonb := '[]'; v_need text[];
begin
  if security.pipeline_num_v1('layer4.inbox_hooks_on', 1) <> 1 then
    return jsonb_build_object('kinds', v_kinds, 'hooks', v_hooks, 'missing', v_missing, 'failed', v_failed, 'on', false);
  end if;
  for h in select * from pipeline.layer4_inbox_kind_hooks x where x.enabled order by x.mode desc, x.kind loop
    v_id := h.kind || ':' || h.mode;
    v_fn := jsonb_build_object('kind_fn', security.layer4_inbox_hook_fn_v1(h.kind_fn), 'counts_fn', security.layer4_inbox_hook_fn_v1(h.counts_fn),
              'page_fn', security.layer4_inbox_hook_fn_v1(h.page_fn), 'detail_fn', security.layer4_inbox_hook_fn_v1(h.detail_fn), 'decide_fn', security.layer4_inbox_hook_fn_v1(h.decide_fn));
    if (h.mode = 'kind') = (v_builtin ? h.kind) then
      v_failed := v_failed || jsonb_build_array(jsonb_build_object('id', v_id, 'error', case when h.mode = 'kind' then 'a built-in kind has this key' else 'no built-in kind has this key' end));
      continue;
    end if;
    v_need := case when h.mode = 'kind' then array['kind_fn', 'counts_fn', 'page_fn', 'decide_fn'] else array['kind_fn', 'decide_fn'] end;
    if exists (select 1 from unnest(v_need) x where v_fn->>x is null) then
      v_missing := v_missing || jsonb_build_array(jsonb_build_object('id', v_id, 'missing', to_jsonb(array(select x from unnest(v_need) x where v_fn->>x is null))));
      continue;
    end if;
    begin
      execute format('select %s()', v_fn->>'kind_fn') into v_k;
    exception when others then
      v_failed := v_failed || jsonb_build_array(jsonb_build_object('id', v_id, 'error', sqlerrm)); continue;
    end;
    v_ch := (select coalesce(jsonb_agg(c || jsonb_build_object('hook', v_id) order by o), '[]'::jsonb)
               from jsonb_array_elements(case when jsonb_typeof(v_k->'choices') = 'array' then v_k->'choices' else '[]'::jsonb end) with ordinality x(c, o)
              where c ? 'key' and c ? 'label'
                and (h.mode = 'kind' or not exists (select 1 from jsonb_array_elements(v_builtin->h.kind->'choices') b where b->>'key' = c->>'key')));
    if h.mode = 'kind' then
      v_kinds := v_kinds || jsonb_build_object(h.kind, jsonb_build_object('label', coalesce(v_k->>'label', h.kind), 'order', coalesce((v_k->>'order')::int, 99),
                   'choices', v_ch, 'hook', v_id, 'detail', v_fn->>'detail_fn' is not null));
    else
      v_kinds := jsonb_set(v_kinds, array[h.kind], (v_kinds->h.kind) || jsonb_build_object('choices', (v_kinds->h.kind->'choices') || v_ch, 'extension', v_id,
                   'detail', v_fn->>'detail_fn' is not null));
    end if;
    v_hooks := v_hooks || jsonb_build_array(jsonb_build_object('id', v_id, 'kind', h.kind, 'mode', h.mode,
                 'order', coalesce((v_kinds->h.kind->>'order')::int, 99)) || v_fn);
  end loop;
  return jsonb_build_object('kinds', v_kinds, 'hooks', v_hooks, 'missing', v_missing, 'failed', v_failed, 'on', true);
end $function$;
revoke all on function security.layer4_inbox_hooks_v1() from public, anon, authenticated;

create or replace function security.layer4_inbox_hook_counts_v1(p_hooks jsonb, p_kind text) returns jsonb
 language plpgsql security definer set search_path to ''
as $function$
-- the counts of each registered kind (mode kind); a failing hook is named and left out
declare h jsonb; v jsonb; v_out jsonb := '[]'; v_failed jsonb := '[]';
begin
  for h in select x from jsonb_array_elements(coalesce(p_hooks->'hooks', '[]'::jsonb)) x where x->>'mode' = 'kind' and (p_kind is null or x->>'kind' = p_kind) loop
    begin
      execute format('select %s()', h->>'counts_fn') into v;
      v_out := v_out || jsonb_build_array(jsonb_build_object('kind', h->>'kind', 'order', h->'order', 'n', coalesce((v->>'n')::bigint, 0), 'oldest', v->'oldest',
                 'late', coalesce((v->>'late')::bigint, 0), 'by_provider', case when jsonb_typeof(v->'by_provider') = 'array' then v->'by_provider' else '[]'::jsonb end));
    exception when others then
      v_failed := v_failed || jsonb_build_array(jsonb_build_object('id', h->>'id', 'error', sqlerrm));
    end;
  end loop;
  return jsonb_build_object('items', v_out, 'failed', v_failed);
end $function$;
revoke all on function security.layer4_inbox_hook_counts_v1(jsonb, text) from public, anon, authenticated;

create or replace function security.layer4_inbox_hook_call_v1(p_fn text, p_arg jsonb, p_ref text) returns jsonb
 language plpgsql security definer set search_path to ''
as $function$
-- one page (p_arg) or one item's detail (p_ref) from a hook; an error comes back as {error}, never breaking the Inbox
declare v jsonb;
begin
  if p_fn is null then return null; end if;
  begin
    if p_ref is null then execute format('select %s($1)', p_fn) into v using p_arg;
    else execute format('select %s($1)', p_fn) into v using p_ref; end if;
  exception when others then
    return jsonb_build_object('error', sqlerrm);
  end;
  return v;
end $function$;
revoke all on function security.layer4_inbox_hook_call_v1(text, jsonb, text) from public, anon, authenticated;

-- 6 the screen's read and decision ----------------------------------------------------------------------------------------------------------
select pg_temp.replace_once('public.admin_layer4_inbox(text,jsonb)', '1fb975482d29c7c9f1ecdf3cdb011a10', '29705b99108e7a0b4d68fea398565d36', $def$
CREATE OR REPLACE FUNCTION public.admin_layer4_inbox(p_action text, p_args jsonb DEFAULT '{}'::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_rank int; v_hooks jsonb; v_kinds jsonb; v_kind text; v_ref text; v_choice text; v_reason text; v_value text; v_pid uuid;
        v_target int := security.pipeline_num_v1('layer4.target_days', 7)::int; v_actor text; v_lim int; v_off int; v_q text; v_r jsonb; v_c jsonb; v_det jsonb; v_out jsonb; v_ids uuid[]; v_event bigint;
        -- CF-247 Layer 4 Inbox performance (4 Nov 2026): counts, pages, lazy detail and kind hooks
        v_hc jsonb; v_prov uuid; v_fkind text; v_bkind text; v_has boolean; v_ao int; v_aat timestamptz; v_ak text; v_ar text; v_h jsonb; v_hp jsonb; v_hargs jsonb;
        v_total bigint := 0; v_before bigint := 0; v_hitems jsonb := '[]'; v_keys text[]; v_fn text; v_np bigint; v_ho int;
begin
  if auth.uid() is null then raise exception 'authentication required' using errcode = '42501'; end if;
  v_rank := security.current_role_rank();
  v_actor := coalesce((select u.email from auth.users u where u.id = auth.uid()), auth.uid()::text);
  if v_rank < 3 then raise exception 'Curator role or above required' using errcode = '42501'; end if;
  v_lim := least(greatest(coalesce((p_args->>'limit')::int, 50), 1), 200); v_off := greatest(coalesce((p_args->>'offset')::int, 0), 0);  -- fixed: page size bounds
  v_q := nullif(btrim(p_args->>'q'), '');
  v_hooks := security.layer4_inbox_hooks_v1(); v_kinds := v_hooks->'kinds';
  v_fkind := nullif(p_args->>'kind', '');
  -- a built-in kind is read from the item list; a registered kind from its hooks
  v_bkind := case when v_fkind is null or security.layer4_inbox_kinds_v1() ? v_fkind then v_fkind else '-' end;

  if p_action = 'summary' then
    -- counts only: no item is built (Platform Admin 4 Nov 2026 06:53 §1, bounded first queries)
    v_hc := security.layer4_inbox_hook_counts_v1(v_hooks, null);
    return (with b as (select * from security.layer4_inbox_counts_v1(v_target)),
                 h as (select x->>'kind' kind, (x->>'n')::bigint n, (x->>'oldest')::timestamptz oldest, (x->>'late')::bigint late, x->'by_provider' bp from jsonb_array_elements(v_hc->'items') x),
                 k as (select kind, sum(n)::bigint n, min(oldest) oldest, sum(late)::bigint late from b group by 1 union all select kind, n, oldest, late from h where n > 0)
      select jsonb_build_object('kinds', v_kinds, 'target_days', v_target, 'rank', v_rank,
        'by_kind', (select coalesce(jsonb_object_agg(k.kind, jsonb_build_object('n', k.n, 'oldest', k.oldest, 'late', k.late)), '{}'::jsonb) from k),
        'total', (select coalesce(sum(n), 0) from k),
        'universities', (select count(distinct p) from (select provider_id p from b where provider_id is not null
                                                        union select (y->>'provider_id')::uuid from h, jsonb_array_elements(h.bp) y where y->>'provider_id' is not null) u),
        'late', (select coalesce(sum(late), 0) from k),
        'paging', jsonb_build_object('items', security.pipeline_num_v1('layer4.inbox_page_size', 25)::int,
                                     'universities', security.pipeline_num_v1('layer4.inbox_universities_page_size', 25)::int,
                                     'detail_parallel', security.pipeline_num_v1('layer4.inbox_detail_parallel', 3)::int),
        'hooks_missing', v_hooks->'missing', 'hooks_failed', (v_hooks->'failed') || (v_hc->'failed')));

  elsif p_action = 'universities' then
    -- counts by university; names and course counts for the universities of this page only
    v_hc := case when v_bkind = '-' or v_fkind is null then security.layer4_inbox_hook_counts_v1(v_hooks, v_fkind) else '{"items": []}'::jsonb end;
    return (with c as (select b.kind, b.provider_id, b.n, b.oldest from security.layer4_inbox_counts_v1(v_target) b where v_bkind is distinct from '-' and (v_fkind is null or b.kind = v_fkind)
                       union all
                       select x->>'kind', (y->>'provider_id')::uuid, (y->>'n')::bigint, (y->>'oldest')::timestamptz
                         from jsonb_array_elements(v_hc->'items') x, jsonb_array_elements(x->'by_provider') y where coalesce((y->>'n')::bigint, 0) > 0),
                 g as (select c.provider_id, sum(c.n)::bigint n, min(c.oldest) oldest, min((v_kinds->c.kind->>'order')::int) first_order, jsonb_object_agg(c.kind, c.n) by_kind
                         from c group by 1),
                 u as (select g.*, coalesce(p.display_name, p.canonical_name, 'Platform') name, k.iso_alpha2::text country,
                              (select count(*) from catalogue.courses cc where cc.provider_id = g.provider_id and cc.lifecycle_status = 'active') courses
                         from g left join catalogue.providers p on p.id = g.provider_id left join ref.countries k on k.id = p.country_id
                        where (nullif(p_args->>'country', '') is null or k.iso_alpha2 = p_args->>'country')
                          and (v_q is null or coalesce(p.display_name, p.canonical_name, '') ilike '%' || v_q || '%'))
      select jsonb_build_object('total', (select count(*) from u), 'limit', v_lim, 'offset', v_off,
        'items', coalesce((select jsonb_agg(jsonb_build_object('provider_id', z.provider_id, 'name', z.name, 'country', z.country, 'courses', z.courses, 'n', z.n, 'oldest', z.oldest,
                     'late', z.oldest < now() - make_interval(days => v_target), 'by_kind', z.by_kind)
                   order by z.first_order, z.courses desc nulls last, z.name)
            from (select * from u order by first_order, courses desc nulls last, name limit v_lim offset v_off) z), '[]'::jsonb)));

  elsif p_action = 'items' then
    if not (p_args ? 'provider_id' or p_args ? 'kind') then return jsonb_build_object('total', 0, 'items', '[]'::jsonb, 'before', 0, 'more', false); end if;
    v_prov := nullif(p_args->>'provider_id', '')::uuid;
    -- UR-04 (1 Nov 2026): a stable position (kind order, kind, created, ref) so every item is reached once, oldest first; kinds have their own order
    v_has := p_args ? 'after_ref';
    if v_has then v_ao := (p_args->>'after_o')::int; v_aat := (p_args->>'after_at')::timestamptz; v_ak := p_args->>'after_kind'; v_ar := p_args->>'after_ref'; end if;
    -- the built-in kinds: keys first (no detail), then the detail of this page's items only
    if v_bkind is distinct from '-' then
      with k as (select e.key kind, (e.value->>'order')::int o from jsonb_each(v_kinds) e),
           x as (select i.kind, i.ref, i.created_at, k.o, count(*) over () t,
                        count(*) filter (where v_has and (k.o, i.kind, i.created_at, i.ref) <= (v_ao, v_ak, v_aat, v_ar)) over () b
                   from security.layer4_inbox_items_v2(v_prov, v_bkind, null, false) i join k on k.kind = i.kind),
           pg as (select * from x where not v_has or (x.o, x.kind, x.created_at, x.ref) > (v_ao, v_ak, v_aat, v_ar) order by o, kind, created_at, ref limit v_lim + 1)
      select coalesce((select max(t) from x), 0), coalesce((select max(b) from x), 0), array(select pg.kind || ':' || pg.ref from pg) into v_total, v_before, v_keys;
    end if;
    -- registered kinds: their own pages and counts, merged in the same order
    for v_h in select x from jsonb_array_elements(v_hooks->'hooks') x where x->>'mode' = 'kind' and (v_fkind is null or x->>'kind' = v_fkind) loop
      v_ho := (v_h->>'order')::int;
      if v_hc is null then v_hc := security.layer4_inbox_hook_counts_v1(v_hooks, v_fkind); end if;
      v_np := coalesce((select case when v_prov is null then (x->>'n')::bigint
                                     else (select sum((y->>'n')::bigint) from jsonb_array_elements(x->'by_provider') y where (y->>'provider_id')::uuid = v_prov) end
                          from jsonb_array_elements(v_hc->'items') x where x->>'kind' = v_h->>'kind'), 0);
      v_total := v_total + v_np;
      if v_has and (v_ho, v_h->>'kind') < (v_ao, v_ak) then v_before := v_before + v_np; continue; end if;
      v_hargs := jsonb_strip_nulls(jsonb_build_object('provider_id', v_prov, 'limit', v_lim + 1));
      if v_has and (v_ho, v_h->>'kind') = (v_ao, v_ak) then v_hargs := v_hargs || jsonb_build_object('after_at', v_aat, 'after_ref', v_ar); end if;
      v_hp := security.layer4_inbox_hook_call_v1(v_h->>'page_fn', v_hargs, null);
      if v_hp ? 'error' or jsonb_typeof(v_hp->'items') is distinct from 'array' then continue; end if;
      if v_has and (v_ho, v_h->>'kind') = (v_ao, v_ak) then v_before := v_before + coalesce((v_hp->>'before')::bigint, 0); end if;
      v_hitems := v_hitems || coalesce((select jsonb_agg(i || jsonb_build_object('kind', v_h->>'kind', 'o', v_ho, '_s', lpad(n::text, 10, '0'),
                                                 'late', coalesce((i->>'late')::boolean, (i->>'created_at')::timestamptz < now() - make_interval(days => v_target)),
                                                 'detail', coalesce(i->'detail', '{}'::jsonb)) order by n)
                                          from jsonb_array_elements(v_hp->'items') with ordinality y(i, n) where i ? 'ref'), '[]'::jsonb);
    end loop;
    return (with b as (select i.kind, i.ref, i.provider_id, coalesce(p.display_name, p.canonical_name) provider, i.subject, i.why, i.suggestion, i.created_at, i.detail,
                              (v_kinds->i.kind->>'order')::int o
                         from security.layer4_inbox_items_v2(v_prov, v_bkind, v_keys, true) i left join catalogue.providers p on p.id = i.provider_id
                        where coalesce(array_length(v_keys, 1), 0) > 0),
                 m as (select b.o, b.kind, b.created_at, b.ref s, jsonb_build_object('kind', b.kind, 'ref', b.ref, 'provider_id', b.provider_id, 'provider', b.provider, 'subject', b.subject,
                              'why', b.why, 'suggestion', b.suggestion, 'created_at', b.created_at, 'late', b.created_at < now() - make_interval(days => v_target), 'detail', b.detail, 'o', b.o) j from b
                       union all
                       select (h->>'o')::int, h->>'kind', (h->>'created_at')::timestamptz, h->>'_s', (h - '_s') || jsonb_build_object('hook', true) from jsonb_array_elements(v_hitems) h),
                 pg as (select * from m order by o, kind, created_at, s limit v_lim)
      select jsonb_build_object('total', v_total, 'before', v_before, 'more', (select count(*) from m) > v_lim,
                                'items', coalesce((select jsonb_agg(pg.j order by pg.o, pg.kind, pg.created_at, pg.s) from pg), '[]'::jsonb)));

  elsif p_action = 'detail' then
    -- lazy detail of the items on screen (at most one page): the stored-copy facts of a built-in item and a hook's detail (kind or extension)
    return (with a as (select x->>'kind' kind, x->>'ref' ref from jsonb_array_elements(case when jsonb_typeof(p_args->'items') = 'array' then p_args->'items' else '[]'::jsonb end) x
                        where x ? 'kind' and x ? 'ref' limit v_lim),
                 b as (select i.kind, i.ref, i.detail from security.layer4_inbox_items_v2(null, null, array(select a.kind || ':' || a.ref from a where security.layer4_inbox_kinds_v1() ? a.kind), true) i
                        where exists (select 1 from a where security.layer4_inbox_kinds_v1() ? a.kind))
      select jsonb_build_object('items', coalesce(jsonb_agg(jsonb_build_object('kind', a.kind, 'ref', a.ref, 'detail', b.detail,
               'hook_detail', security.layer4_inbox_hook_call_v1((select h->>'detail_fn' from jsonb_array_elements(v_hooks->'hooks') h where h->>'kind' = a.kind limit 1), null, a.ref))), '[]'::jsonb))
        from a left join b on b.kind = a.kind and b.ref = a.ref);
  end if;

  -- CF-247 20 Oct 2026: the decisions taken here, newest first (replaces the old Review queue history)
  if p_action = 'decided' then
    return jsonb_build_object('items', coalesce((select jsonb_agg(jsonb_build_object('at', e.created_at, 'kind', e.detail->>'kind', 'choice', e.detail->>'choice', 'value', e.detail->>'value',
             'reason', e.detail->>'reason', 'provider_id', e.detail->>'provider_id',
             'provider', (select coalesce(p.display_name, p.canonical_name) from catalogue.providers p where p.id::text = e.detail->>'provider_id'),
             'by', (select u.email from auth.users u where u.id::text = e.actor::text)) order by e.id desc)
           from (select * from pipeline.admin_control_events x where x.area = 'layer4' and x.action = 'inbox_decide' order by x.id desc limit v_lim offset v_off) e), '[]'::jsonb));
  end if;
  if p_action <> 'decide' then raise exception 'unknown action %', p_action; end if;
  v_kind := p_args->>'kind'; v_ref := p_args->>'ref'; v_choice := p_args->>'choice'; v_value := nullif(btrim(p_args->>'value'), '');
  v_c := (select c from jsonb_array_elements(v_kinds->v_kind->'choices') c where c->>'key' = v_choice);
  if v_c is null then raise exception 'unknown choice % for %', v_choice, v_kind; end if;
  if v_c ? 'link' then raise exception 'this choice opens another screen'; end if;
  if v_rank < coalesce((v_c->>'rank')::int, 4) then raise exception 'your role cannot make this choice' using errcode = '42501'; end if;  -- fixed: university and value choices need Pipeline Operator or above unless the choice names a higher rank
  -- a registered kind or recovery choice is decided by its own function, which checks the item, enforces its rules and writes its own audit row
  if v_c ? 'hook' then
    v_fn := (select h->>'decide_fn' from jsonb_array_elements(v_hooks->'hooks') h where h->>'id' = v_c->>'hook');
    if v_fn is null then raise exception 'this choice is not available yet'; end if;
    execute format('select %s($1, $2, $3, $4)', v_fn) into v_r using v_ref, v_choice, v_value, coalesce(nullif(btrim(p_args->>'reason'), ''), v_c->>'reason', '');
    return jsonb_build_object('ok', coalesce((v_r->>'ok')::boolean, false), 'kind', v_kind, 'choice', v_choice, 'returns', coalesce(v_r->>'returns', v_c->>'returns'),
                              'result', v_r->'result', 'ref', v_ref, 'event_id', v_r->'event_id', 'request', v_r->'request', 'outcome', v_r->'outcome', 'hook', v_c->>'hook');
  end if;
  v_reason := coalesce(nullif(btrim(p_args->>'reason'), ''), v_c->>'reason', '');
  if length(v_reason) < 4 then raise exception 'give a reason (kept with the decision)'; end if;
  if v_c->>'input' = 'url' and (v_value is null or v_value !~* '^https?://[^\s/]+\.[^\s]+$') then raise exception 'enter the full web address (https://…)'; end if;
  select i.provider_id, i.detail into v_pid, v_det from security.layer4_inbox_items_v2(null, v_kind, array[v_kind || ':' || v_ref], true) i;
  if v_det is null then raise exception 'this item is no longer waiting (someone may have decided it)'; end if;

  -- SS-016 fee check (1 Nov 2026): an address on a fee-check item was taken as a plain Approve and admitted the proposed fee (46 decisions
  -- on 30 Oct). A fee check is admitted or not; a different course page is set on the course record.
  if v_kind = 'course_link' and v_det->>'field_code' = 'provider_current_tuition_validation' and v_choice = 'enter' then
    raise exception 'this is a fee check: admit the proposed fee or do not admit it. A different course page is set on the course record';
  end if;

  -- 24 Oct 2026 (hotfix D1): a course-link row that holds a fee (identity re-verification quarantine, fee floor) is not a link decision
  if v_kind = 'course_link' and v_det->>'field_code' = 'provider_current_tuition' and v_choice in ('use', 'enter') then
    if v_choice = 'use' then raise exception 'this item holds a fee, not a new page: enter the course page''s address, or keep the page we hold'; end if;
    v_r := security.layer4_fee_item_rebind_v1(v_ref::uuid, v_value, v_reason);
  elsif v_kind in ('no_page_first_run', 'conjoint_first_run') then
    -- hotfix 26 Oct 2026: a university's first run (no page published / conjoint rule); applied by security.no_page_review_apply_v1
    if v_choice = 'has_page' then
      begin
        v_ids := array(select jsonb_array_elements_text(v_value::jsonb)::uuid);
      exception when others then raise exception 'tick the sample courses that have their own page';
      end;
      if coalesce(array_length(v_ids, 1), 0) = 0 then raise exception 'tick the sample courses that have their own page'; end if;
      if exists (select 1 from unnest(v_ids) x(id) where not exists (select 1 from pipeline.course_no_page n where n.review_item_id = v_ref::uuid and n.course_id = x.id)) then
        raise exception 'a ticked course is not in this sample';
      end if;
    end if;
    v_r := public.layer4_review_decide(v_ref::uuid,
             case v_choice when 'approve' then 'approve' when 'reject' then 'reject' else 'edit_and_approve' end, v_reason,
             case v_choice when 'has_page' then jsonb_build_object('has_page_course_ids', to_jsonb(v_ids))
                           when 'parent' then jsonb_build_object('parent_url', v_value) end);
  elsif v_kind = 'aer_review' then
    -- CF-247 A1-A3 (Platform Admin 30 Oct 2026 06:53): one AER item at a time; Approve except sends the ticked rows to leave out
    if v_choice = 'approve_except' then
      begin
        v_ids := array(select jsonb_array_elements_text(v_value::jsonb)::uuid);
      exception when others then raise exception 'tick the rows to leave out';
      end;
      if coalesce(array_length(v_ids, 1), 0) = 0 then raise exception 'tick the rows to leave out'; end if;
    end if;
    v_r := public.layer4_review_decide(v_ref::uuid, case v_choice when 'approve' then 'approve' when 'reject' then 'reject' else 'edit_and_approve' end, v_reason,
             case when v_choice = 'approve_except' then jsonb_build_object('mode', 'approve_except', 'exclude_row_ids', to_jsonb(v_ids)) end);
  elsif v_kind = 'provider_description' then
    -- CF-247 P1 (Platform Admin 2 Nov 2026 10:28): a university description is approved as read or rejected, never edited
    v_r := public.layer4_review_decide(v_ref::uuid, case v_choice when 'approve' then 'approve' else 'reject' end, v_reason, null);
  elsif v_kind = 'course_link' and v_choice = 'refuse' then
    -- mandate 3 Nov 2026 20:47 §5: refuse the proposed page without claiming a held page
    v_r := security.layer4_course_link_refuse_v1(v_ref::uuid, v_reason);
  elsif v_kind = 'course_page_needed' then
    -- Decision 179 (Platform Admin 3 Nov 2026 20:29): add the page, search again, or record that no page exists
    v_r := security.course_page_needed_decide_v1(v_ref::uuid, v_choice, v_value, v_reason);
  elsif v_kind = 'held_scholarship' and v_choice = 'duplicate' then
    -- handover 3 Nov 2026 Priority 2 item 8: close a held scholarship as a duplicate of a published one (the reviewer names it)
    v_r := security.scholarship_duplicate_close_v1(v_ref::bigint, v_value, v_reason);
  elsif v_kind = 'course_link' then
    v_r := public.layer4_review_decide(v_ref::uuid, case v_choice when 'keep' then 'reject' when 'use' then 'approve' else 'edit_and_approve' end, v_reason,
                                       case when v_choice = 'enter' then to_jsonb(v_value) end);
  elsif v_kind = 'held_scholarship' then
    v_r := public.admin_scholarship_ai('review_decide', jsonb_build_object('review_id', v_ref::bigint, 'decision', case when v_choice = 'publish' then 'admit' else 'refuse' end,
                                                                         'extraction_id', v_det->'extraction_id', 'reason', v_reason));
  elsif v_kind = 'provider_departure' then  -- CF-247 20 Oct 2026: from the retired Review queue (Provider departures); Platform Admin
    if v_choice = 'merged' then
      select array_agg(p.id) into v_ids from catalogue.providers p
       where p.lifecycle_status = 'active' and p.id <> v_pid and p.country_id = (select q.country_id from catalogue.providers q where q.id = v_pid)
         and (lower(coalesce(p.display_name, p.canonical_name)) = lower(v_value)
              or p.id in (select r.provider_id from catalogue.provider_registrations r where upper(r.registration_code) = upper(v_value)));
      if coalesce(array_length(v_ids, 1), 0) <> 1 then raise exception 'enter the successor''s exact name or its CRICOS or NZQA code (% found)', coalesce(array_length(v_ids, 1), 0); end if;
    end if;
    v_r := public.layer4_provider_departure_decide(v_ref::bigint, v_choice, case when v_choice = 'merged' then v_ids[1] end, v_reason);
  elsif v_kind = 'counsellor_report' then  -- CF-247 20 Oct 2026: closed here (Coverage › Counsellor reports retired); Zoho reads the outcome back
    v_r := public.admin_counsellor_reports('close', jsonb_build_object('ids', jsonb_build_array(v_ref), 'outcome', case v_choice when 'report_fixed' then 'fixed' else 'not_changed' end, 'reason', v_reason));
  elsif v_choice = 'website' then
    v_r := public.admin_provider_website_set(v_pid, v_value);
    if v_kind in ('pages_not_found', 'site_down') then
      v_r := v_r || jsonb_build_object('released', security.flag_release_v1((v_det->>'flag_id')::bigint, v_actor, 'person', 'Layer 4: website changed to ' || v_value || '. ' || v_reason, jsonb_build_object('user_id', auth.uid()), false));
    end if;
  elsif v_choice in ('release', 'keep') then
    v_r := security.flag_release_v1((v_det->>'flag_id')::bigint, v_actor, 'person', 'Layer 4: ' || v_reason, jsonb_build_object('user_id', auth.uid()), false);
  elsif v_choice = 'wait' then
    update pipeline.enrichment_flags set flagged_at = now() where id = (v_det->>'flag_id')::bigint;  -- asked again after the waiting period
    v_r := jsonb_build_object('waiting', true);
  elsif v_choice = 'cricos_only' then
    v_r := public.admin_adapter_build('set_wave', jsonb_build_object('wave', 'cricos-only', 'provider_ids', jsonb_build_array(v_pid)));
  elsif v_choice = 'rebuild' then
    v_r := public.admin_adapter_build('build', jsonb_build_object('provider_ids', jsonb_build_array(v_pid), 'reason', 'Layer 4: ' || v_reason));
  elsif v_choice = 'retry' then
    v_r := public.admin_provider_onboarding('retry', jsonb_build_object('ids', jsonb_build_array((v_det->>'onboarding_id')::uuid), 'reason', 'Layer 4: ' || v_reason));
  elsif v_choice = 'archive' then
    v_r := public.admin_provider_archive(v_pid, 'Layer 4: ' || v_reason, false);
  elsif v_choice = 'archive_course' then
    v_r := public.admin_course_edit((v_det->>'course_id')::uuid, 'archive', jsonb_build_object('reason', 'Layer 4: ' || v_reason));
    perform security.flag_release_v1((v_det->>'flag_id')::bigint, v_actor, 'person', 'Layer 4: course archived. ' || v_reason, jsonb_build_object('user_id', auth.uid()), false);
  else
    raise exception 'choice % is not handled', v_choice;
  end if;
  insert into pipeline.admin_control_events(area, action, target, detail, actor)
  values ('layer4', 'inbox_decide', v_kind || ':' || v_ref, jsonb_build_object('kind', v_kind, 'ref', v_ref, 'choice', v_choice, 'value', v_value, 'reason', v_reason, 'provider_id', v_pid, 'result', v_r), auth.uid())
  returning id into v_event;
  -- UR-06 (1 Nov 2026): the reply names the audit event and what the decision actually did, read back from its destination
  return jsonb_build_object('ok', true, 'kind', v_kind, 'choice', v_choice, 'returns', v_c->>'returns', 'result', v_r, 'ref', v_ref, 'event_id', v_event,
                            'outcome', security.layer4_decision_outcome_v1(v_kind, v_choice, v_r));
end $function$
$def$);

-- 7 component register ----------------------------------------------------------------------------------------------------------------------
insert into pipeline.component_register(kind, name, layer, purpose, status, replaces, introduced_in) values
 ('table', 'pipeline.layer4_inbox_kind_hooks', 'Layer 4', 'Kinds and recovery choices that plug into Layer 4 › Inbox (counts, pages, lazy detail, decisions)', 'active', '{}', '20261104410000'),
 ('function', 'security.layer4_inbox_items_v2', 'Layer 4', 'Items that need a person, filtered by university, kind or item at the source; detail on request', 'active', '{}', '20261104410000'),
 ('function', 'security.layer4_inbox_counts_v1', 'Layer 4', 'Layer 4 Inbox counts by kind and university without building items', 'active', '{}', '20261104410000'),
 ('function', 'security.layer4_inbox_hooks_v1', 'Layer 4', 'Layer 4 Inbox kinds with registered hooks', 'active', '{}', '20261104410000'),
 ('function', 'security.layer4_inbox_hook_counts_v1', 'Layer 4', 'Counts of registered Layer 4 kinds', 'active', '{}', '20261104410000'),
 ('function', 'security.layer4_inbox_hook_call_v1', 'Layer 4', 'A registered kind''s page or detail, errors contained', 'active', '{}', '20261104410000'),
 ('function', 'security.layer4_inbox_hook_fn_v1', 'Layer 4', 'Find a hook function in schema security', 'active', '{}', '20261104410000')
on conflict do nothing;
