-- CF-247 scholarship hand-off to Layer 4 (IQ-00264; Platform Admin direction 4 Nov 2026 10:00 §1, §2; admin
-- docs/platform/2026-11-04-autonomous-admission-throughput-direction-1000.md). Lands after 20261104390000 (scholarship coverage), 20261104430000
-- (classification fix) and 20261104450000 (human-assisted recovery).
--
-- Why (live, read-only, 4 Nov 2026 11:07-11:14 AEDT):
--   * IQ-00264 ("132 eligible, nothing created for 6 h") measures pending scholarship AI reviews (Layer 4 › AI could not decide) against reviews
--     admitted in the window. Those 132 are already in the Inbox (kind held_scholarship) and people decide them (22 refused in the window; last
--     admit 30 Oct). The hand-off gap is upstream: classified cases that are one decision from publication reach no one.
--   * 144 classified cases were "admitted not published" with no review item, intervention or recovery work (20 admission-eligible providers):
--     - 113 active scholarships are unpublished for one reason only, "no stated award value" (security.scholarship_publishability_for_v1). The
--       page states the value in words ("equivalent to the RTP stipend rate"; tiers without amounts; 109 are text_only), so no automatic reader
--       can ever pass the numeric check, and nothing asks a person. They stay unpublished for ever.
--     - 24 were already decided by a person (held by admin: "Refused in Layer 4 ...", "Prize or award, not a scholarship") yet counted as
--       unresolved, so the lane reported decided work as eligible.
--     - the reason shown was "unpublished": the publishing checks that failed were not recorded on the case.
--   * the scholarship coverage lane (sch_coverage) holds 139 open interventions against har.open_max_per_lane 150 (international eligibility),
--     so any new class in that lane would be starved.
-- What:
--   1 security.scholarship_coverage_items_v1 (md5-guarded edit): an unpublished scholarship carries the publishing checks it fails (evidence.missing,
--     reason "publishing checks: ..."); one a person refused (held by admin with a Layer 4 or Platform Admin refusal) or whose value a person
--     confirmed is not stated (intervention not_published) is "rejected correctly": an explicit, evidence-backed disposition, never re-asked.
--   2 A new intervention lane, sch_value (its own handler and its own open limit), class sch_value_missing: an admitted scholarship whose only
--     failing check is "no stated award value", of an admission-eligible provider, whose page has been read (the automated attempt), with no
--     person's lock on its value and no Layer 4 decision already waiting, becomes one deduplicated "Human input needed" item in the Inbox
--     (security.har_sch_value_generate_v1, job layer4-interventions, switch har.generate_sch_value_on). Each raise runs in its own block: one
--     failing provider never stops the others.
--   3 The reviewer enters the amount or percentage with the page's sentence (enter_value or correct_value), or confirms with the official page
--     that no award value is stated (confirm_not_published: the case is then rejected correctly). A valid value is applied as the reviewer's own
--     locked edit through the existing Curator route public.admin_scholarship_edit (manual lock and manual edit log, the reviewer's identity),
--     while sch_cov.value_apply_on is 1. Nothing automatic sets a value.
--   4 The next stage runs unattended: scholarship-auto-publish (hourly, already on) publishes it when every check passes; the tick verifies
--     publication and consumer read-back (api.website_v2_scholarship_item, read only) and records published_at, or returns the item to the
--     reviewer with the checks that still fail.
-- Activation:
--   ON (they raise review work and record dispositions; they spend nothing): the classification change; har.generate_sch_value_on.
--   ON, flagged for the Integration Controller: sch_cov.value_apply_on. It applies a value only when a person with the Layer 4 rank enters it
--     with the page's sentence, through the existing Curator edit route (already authorised for people): it is a person's admission decision,
--     not automation. Set it to 0 to keep supplied values as proposals only.
--   Nothing spends Firecrawl or AI. No manual enqueue; no switch of another workstream is changed (har.open_max_per_lane is unchanged).
-- md5 (before = live, read 4 Nov 2026 11:12 AEDT; after = local replay on PostgreSQL 16, tests/fixtures/sch-l4-handoff/run.sh):
--   security.scholarship_coverage_items_v1(uuid[])   d3dfacf0e70fd33162eab7a57aca72e4 -> 5605660603d40b3917001c37807a09bb
-- Called, not edited (live md5, 11:12): security.layer4_intervention_raise_v1(jsonb) 8fcabf1137cf126158c260759ac9f9aa,
--   security.layer4_intervention_resolve_v1(bigint,text,jsonb) 1385d22605acc549b545beb4f6a7d312, security.layer4_interventions_tick_v1()
--   da2aaf0fd207edf4c36a55a8e2172424, security.scholarship_publishability_for_v1(uuid[]) d8123efd7e6e0d36fb6ebe9c8d38fdf7,
--   public.admin_scholarship_edit(uuid,text,jsonb) 0147553263d5a1b8795a0b31ebf11019 (live only: no checked-in migration holds it; recorded as a
--   governance gap), security.har_quote_ok_v1(text) 036a0df333451181b044ffc606e91b69.
-- Replaces: security.scholarship_coverage_items_v1 (same name; md5-guarded edit)
-- Retires: nothing
-- Consumer API: untouched (G3); it is only read. Nothing is dropped or deleted. Nothing is read, spent, admitted or published by this migration.

do $guard$
declare r record;
begin
  if to_regclass('pipeline.layer4_interventions') is null or to_regclass('pipeline.scholarship_coverage_items') is null then
    raise exception 'the scholarship hand-off needs human-assisted recovery (20261104450000) and scholarship coverage (20261104390000) first';
  end if;
  for r in select * from (values ('security.layer4_intervention_raise_v1(jsonb)', '8fcabf1137cf126158c260759ac9f9aa'),
                                 ('security.layer4_intervention_resolve_v1(bigint,text,jsonb)', '1385d22605acc549b545beb4f6a7d312'),
                                 ('security.layer4_interventions_tick_v1()', 'da2aaf0fd207edf4c36a55a8e2172424'),
                                 ('security.scholarship_publishability_for_v1(uuid[])', 'd8123efd7e6e0d36fb6ebe9c8d38fdf7'),
                                 ('public.admin_scholarship_edit(uuid,text,jsonb)', '0147553263d5a1b8795a0b31ebf11019'),
                                 ('security.har_quote_ok_v1(text)', '036a0df333451181b044ffc606e91b69')) v(sig, m) loop
    if to_regprocedure(r.sig) is null then raise exception 'this change calls %, which does not exist', r.sig; end if;
    if md5(pg_get_functiondef(r.sig::regprocedure)) <> r.m then
      raise exception 'live % differs from the definition this change was written against (md5 %)', r.sig, md5(pg_get_functiondef(r.sig::regprocedure));
    end if;
  end loop;
  if to_regprocedure('api.website_v2_scholarship_item(uuid)') is null then raise exception 'the consumer read-back api.website_v2_scholarship_item is missing'; end if;
end $guard$;

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

-- 1 settings (G2) --------------------------------------------------------------------------------------------------------------------------------
insert into pipeline.platform_toolset_settings(toolset_key, key, label, help, kind, value, min_value, max_value, unit, sort, section, used_by, reason) values
 ('pipeline', 'har.generate_sch_value_on', 'Human-assisted recovery: ask for missing scholarship award values',
  'On (1): an admitted scholarship whose only failing publishing check is "no stated award value" (its page states the value in words) becomes one "Human input needed" item, for providers the admission rule accepts. Off (0): none.',
  'number', to_jsonb(1), 0, 1, 'on (1) or off (0)', 1503, 'Human-assisted recovery', 'security.har_sch_value_generate_v1 (job layer4-interventions)',
  'Direction 4 Nov 2026 10:00 §2 (IQ-00264): eligible cases create the appropriate review work; ships on (it asks people, spends nothing)'),
 ('pipeline', 'sch_cov.value_apply_on', 'Scholarships: apply an award value a Layer 4 reviewer enters',
  'On (1): a value entered in Layer 4 with the page''s sentence is applied as that reviewer''s own locked edit (the Curator edit route), and publishing follows at the next hourly run when every check passes. Off (0): the value is kept as a proposal only.',
  'number', to_jsonb(1), 0, 1, 'on (1) or off (0)', 1413, 'Scholarship coverage recovery', 'security.har_sch_value_resume_v1',
  'Direction 4 Nov 2026 10:00 §1 "humans remain responsible for decisions that require human admission authority"; each application is a person''s decision')
on conflict (toolset_key, key) do nothing;

-- 2 the class and its time bounds (the human-assisted recovery contract) ---------------------------------------------------------------------------
insert into pipeline.layer4_intervention_classes(code, lane, workstream, title, required_input, recommended_action, unblocks, allowed_actions, interpretative, recheck_condition, sort) values
 ('sch_value_missing', 'sch_value', 'Scholarships', 'An admitted scholarship cannot be published: its award value is stated only in words',
  'The award value as a number (an amount in the provider''s currency, or a percentage of tuition) with the sentence from the official page that states it; or confirm, with the official page, that the page states no award value.',
  'enter_value',
  'The value is applied as your own locked edit of the scholarship (it is never changed by automation) and the hourly publishing run publishes it when every other check passes; publication and the website read-back are then verified.',
  '{"enter_value": 4, "correct_value": 4, "confirm_not_published": 5, "reject_evidence": 4, "return_technical": 4}', true,
  'the scholarship is published, or its only failing check is no longer the award value', 75)
on conflict (code) do nothing;

insert into pipeline.platform_toolset_settings(toolset_key, key, label, help, kind, value, min_value, max_value, unit, sort, section, used_by, reason)
select 'pipeline', 'har.' || c.code || '.' || t.k, c.title || ': ' || t.label, t.help, t.kind, t.v, t.lo, t.hi, t.unit, 1520 + c.sort + t.o, 'Human-assisted recovery',
       t.used_by, 'Direction 4 Nov 2026 10:00 §2 (IQ-00264): time-bound resolution of the class, as every class (decision 06:30 §6)'
  from pipeline.layer4_intervention_classes c
 cross join (values
   (1, 'max_attempts', 'automated attempts before a person is asked', 'The platform''s own reads this class needs before it raises an intervention (the scholarship''s page read by the scholarship reader).', 'number', to_jsonb(1), 0::numeric, 20::numeric, 'attempts', 'security.layer4_intervention_raise_v1'),
   (2, 'escalate_after_hours', 'escalate when unanswered for', 'An intervention still waiting for a person this long is escalated once, as one integration issue per class.', 'number', to_jsonb(72), 1, 2160, 'hours', 'security.layer4_interventions_tick_v1'),
   (3, 'recheck_hours', 'recheck the failure every', 'While it waits, the platform checks this often whether the value has been found or the scholarship published without a person.', 'number', to_jsonb(24), 1, 720, 'hours', 'security.layer4_interventions_tick_v1'),
   (4, 'deadline_hours', 'recovery deadline', 'The case should be recovered within this long of the intervention being raised; later, it is reported as overdue.', 'number', to_jsonb(168), 1, 4320, 'hours', 'security.layer4_interventions_tick_v1; security.layer4_intervention_report_v1'),
   (5, 'assigned_to', 'assigned responsibility', 'Who is responsible for answering this class of intervention (shown on the card and in the report).', 'text', to_jsonb('Layer 4 reviewer (Pipeline Operator or above)'::text), null, null, null, 'security.layer4_intervention_raise_v1')
 ) t(o, k, label, help, kind, v, lo, hi, unit, used_by)
 where c.code = 'sch_value_missing'
on conflict (toolset_key, key) do nothing;

-- 3 the classification: failing checks on the case; decided cases resolved (md5-guarded) -------------------------------------------------------------
select pg_temp.edit_once('security.scholarship_coverage_items_v1(uuid[])', 'd3dfacf0e70fd33162eab7a57aca72e4', '5605660603d40b3917001c37807a09bb', array[
  array[$o$  sh as (
    select s.provider_id, 'sch:' || s.id item_key,$o$,
        $n$  -- CF-247 IQ-00264 (4 Nov 2026): the publishing checks each unpublished scholarship fails
  sp as (select x.* from security.scholarship_publishability_for_v1(array(select s.id from scholarship.scholarships s join pv on pv.id = s.provider_id
                                                                          where s.lifecycle_status = 'active' and s.publication_status <> 'published')) x),
  sh as (
    select s.provider_id, 'sch:' || s.id item_key,$n$],
  array[$o$                  or exists (select 1 from pipeline.layer4_review_items r where r.entity_type = 'scholarship' and r.entity_id = s.id and r.status = 'pending') then 'awaiting_layer4'
                else 'admitted_not_published' end state,$o$,
        $n$                  or exists (select 1 from pipeline.layer4_review_items r where r.entity_type = 'scholarship' and r.entity_id = s.id and r.status = 'pending') then 'awaiting_layer4'
                -- CF-247 IQ-00264: a person's refusal, or a person's confirmation that the page states no award value, is a decision, never re-asked
                when exists (select 1 from pipeline.scholarship_publication_holds h where h.scholarship_id = s.id and h.released_at is null and h.held_by = 'admin'
                               and (h.reason ~* '^Refused in Layer 4' or h.reason ~* '^Prize or award, not a scholarship'))
                  or exists (select 1 from pipeline.layer4_interventions v where v.lane = 'sch_value' and v.entity = s.provider_id::text || '|sch:' || s.id::text
                               and v.missing_fact = 'sch_value_missing' and v.status = 'not_published') then 'rejected_correctly'
                else 'admitted_not_published' end state,$n$],
  array[$o$                when s.publication_status <> 'published' then coalesce((select h.reason from pipeline.scholarship_publication_holds h where h.scholarship_id = s.id and h.released_at is null limit 1),
                                                                        s.publication_status) end reason,$o$,
        $n$                when s.publication_status <> 'published' then coalesce((select h.reason from pipeline.scholarship_publication_holds h where h.scholarship_id = s.id and h.released_at is null limit 1),
                                                                        (select 'a person confirmed the page states no award value' from pipeline.layer4_interventions v
                                                                          where v.lane = 'sch_value' and v.entity = s.provider_id::text || '|sch:' || s.id::text and v.status = 'not_published' limit 1),
                                                                        (select 'publishing checks: ' || array_to_string(x.missing, '; ') from sp x where x.scholarship_id = s.id and cardinality(x.missing) > 0),
                                                                        s.publication_status) end reason,$n$],
  array[$o$           jsonb_build_object('scholarship_id', s.id, 'name', s.name, 'publication_status', s.publication_status, 'audience', s.audience, 'page', s.source_url) evidence,$o$,
        $n$           jsonb_build_object('scholarship_id', s.id, 'name', s.name, 'publication_status', s.publication_status, 'audience', s.audience, 'page', s.source_url,
                              'missing', (select to_jsonb(x.missing) from sp x where x.scholarship_id = s.id),
                              'held_by', (select h.held_by from pipeline.scholarship_publication_holds h where h.scholarship_id = s.id and h.released_at is null limit 1)) evidence,$n$]
], array[1, 1, 1, 1]);

-- 4 the lane sch_value: generate, validate, resume, verify, recheck ------------------------------------------------------------------------------------
create or replace function security.har_sch_value_generate_v1(p_limit int) returns jsonb
language plpgsql security definer set search_path to '' as $function$
-- CF-247 IQ-00264 (direction 4 Nov 2026 10:00 §2): an admitted scholarship whose only failing publishing check is "no stated award value"
-- (classified admitted_not_published by scholarship-coverage-classify), of an admission-eligible provider, becomes one intervention, once its page
-- has been read (the automated attempt). Not asked: a value a person locked (people win), a scholarship with a Layer 4 decision already waiting,
-- a case already open, or one closed with the same evidence. Fair: oldest first, at most har.generate_per_provider_max per provider and p_limit
-- in all. Each raise runs in its own block, so one failing provider never stops the others.
declare r record; v_res jsonb; v_n int := 0; v_rep int := 0; v_skip int := 0; v_err int := 0; v_last text;
        v_per int := security.pipeline_num_v1('har.generate_per_provider_max', 2)::int;
begin
  for r in
    with cand as (
      select x.provider_id, x.item_key, x.reason, x.first_seen, (x.evidence->>'scholarship_id')::uuid sid, x.provider_id::text || '|' || x.item_key entity
        from pipeline.scholarship_coverage_items x
       where x.present and x.state = 'admitted_not_published' and x.evidence->'missing' = '["no stated award value"]'::jsonb
         and coalesce(security.scholarship_admission_provider_ok_v1(x.provider_id), false)),
    c2 as (
      select c.*, s.name, s.source_url, s.award_value_text, sp.read_status, sp.read_at, sp.evidence_id,
             c.sid::text || '|' || coalesce(s.award_value_text, '') sig
        from cand c join scholarship.scholarships s on s.id = c.sid
        left join pipeline.scholarship_pages sp on sp.scholarship_id = c.sid
       where s.lifecycle_status = 'active' and s.publication_status <> 'published'
         -- the automated attempt first: a page the reader has not read yet waits for the reader and takes no slot
         and sp.read_status = 'read'
         and not exists (select 1 from pipeline.manual_locks k where k.entity = 'scholarship' and k.entity_id = s.id and k.field in ('award_amount', 'award_percentage', 'award_value_type'))
         and not exists (select 1 from pipeline.scholarship_ai_reviews rv where rv.scholarship_id = s.id and rv.status = 'pending')
         and not exists (select 1 from pipeline.layer4_review_items l where l.entity_type = 'scholarship' and l.entity_id = s.id and l.status = 'pending')),
    ranked as (
      select c2.*, row_number() over (partition by c2.provider_id order by c2.first_seen, c2.item_key) pn from c2
       where not exists (select 1 from pipeline.layer4_interventions i where i.lane = 'sch_value' and i.entity = c2.entity and i.missing_fact = 'sch_value_missing'
                           and (i.status in ('ai_pending', 'awaiting_input', 'resuming') or i.closed_fingerprint = md5('sch_value_missing|' || c2.sig))))
    select rk.*, coalesce(p.display_name, p.short_name, p.canonical_name) pname from ranked rk join catalogue.providers p on p.id = rk.provider_id
     where rk.pn <= v_per order by rk.first_seen, rk.provider_id, rk.item_key limit greatest(coalesce(p_limit, 0), 0)
  loop
    begin
      v_res := security.layer4_intervention_raise_v1(jsonb_build_object('class', 'sch_value_missing', 'entity', r.entity, 'provider_id', r.provider_id, 'field', 'award_value',
                 'subject', r.pname || ': ' || coalesce(r.name, 'scholarship'),
                 'attempts', case when r.read_status = 'read' then 1 else 0 end, 'signature', r.sig,
                 'issue', jsonb_build_object('summary', 'Admitted, but not published: the award value is stated only in words',
                                             'attempted', jsonb_build_array('scholarship page read (' || coalesce(r.read_status, 'not read') || coalesce(', ' || to_char(r.read_at, 'DD Mon YYYY'), '') || ')',
                                                                            'publishing checks: no stated award value'),
                                             'why_stopped', 'the page gives no amount or percentage the publishing check can use',
                                             'impact', 'the scholarship is in the catalogue but never reaches the website or Zoho'),
                 'evidence', jsonb_build_object('official_links', to_jsonb(array_remove(array[r.source_url], null)),
                                                'stored_copies', case when r.evidence_id is not null then jsonb_build_array(r.evidence_id) else '[]'::jsonb end,
                                                'quotes', case when nullif(btrim(coalesce(r.award_value_text, '')), '') is not null then jsonb_build_array(r.award_value_text) else '[]'::jsonb end,
                                                'attempts', jsonb_build_array(jsonb_build_object('reason', r.reason)), 'conflicts', '[]'::jsonb),
                 'suggested', case when nullif(btrim(coalesce(r.award_value_text, '')), '') is not null
                                   then jsonb_build_object('value_text', r.award_value_text, 'from', 'the value as the page words it (held on the record; not a number)') end,
                 'resume_target', jsonb_build_object('operation', 'apply the value as the reviewer''s edit; scholarship-auto-publish publishes',
                                                     'work_item', jsonb_build_object('lane', 'sch_value', 'entity', r.entity, 'kind', 'value'))));
      if coalesce((v_res->>'raised')::boolean, false) then v_n := v_n + 1; elsif coalesce((v_res->>'repeat')::boolean, false) then v_rep := v_rep + 1; else v_skip := v_skip + 1; end if;
    exception when others then
      v_err := v_err + 1; v_last := left(r.entity || ': ' || sqlerrm, 300);
    end;
  end loop;
  return jsonb_build_object('raised_or_changed', v_n, 'repeats', v_rep, 'not_raised', v_skip, 'errors', v_err, 'error_last', v_last);
end $function$;
revoke all on function security.har_sch_value_generate_v1(integer) from public, anon, authenticated;

create or replace function security.har_sch_value_validate_v1(p_id bigint, p_action text, p_payload jsonb) returns jsonb
language plpgsql stable security definer set search_path to '' as $function$
-- CF-247 IQ-00264: an amount (greater than 0) or a percentage (above 0, at most 100), with the sentence from the official page; the scholarship
-- must still be active, unpublished and without a person's lock on its value
declare i pipeline.layer4_interventions; v_sid uuid; j jsonb; v_val text := btrim(coalesce(p_payload->>'value', '')); v_kind text; v_num numeric; v_quote text;
begin
  select * into i from pipeline.layer4_interventions where id = p_id;
  if p_action not in ('enter_value', 'correct_value') then
    return jsonb_build_object('valid', false, 'request', 'This action is not used for award values; enter the value or confirm that the page states none.');
  end if;
  v_sid := substring(i.entity from '\|sch:([0-9a-f-]{36})$')::uuid;
  if not exists (select 1 from scholarship.scholarships s where s.id = v_sid and s.lifecycle_status = 'active' and s.publication_status <> 'published') then
    return jsonb_build_object('valid', false, 'request', 'The scholarship is no longer waiting for publication; nothing to enter.');
  end if;
  if exists (select 1 from pipeline.manual_locks k where k.entity = 'scholarship' and k.entity_id = v_sid and k.field in ('award_amount', 'award_percentage', 'award_value_type')) then
    return jsonb_build_object('valid', false, 'request', 'A person has already set this value on the scholarship record; change it there.');
  end if;
  begin j := v_val::jsonb; exception when others then j := null; end;
  if j is null or jsonb_typeof(j) <> 'object' then
    j := case when v_val ~ '^[0-9]+(\.[0-9]+)?\s*%$' then jsonb_build_object('percentage', regexp_replace(v_val, '\s*%$', ''))
              when replace(replace(v_val, ',', ''), '$', '') ~ '^[0-9]+(\.[0-9]+)?$' then jsonb_build_object('amount', replace(replace(v_val, ',', ''), '$', ''))
              else '{}'::jsonb end;
  end if;
  v_kind := case when j ? 'percentage' then 'percentage' when j ? 'amount' then 'fixed_amount' end;
  if v_kind is null or coalesce(j->>'percentage', j->>'amount') !~ '^[0-9]+(\.[0-9]+)?$' then
    return jsonb_build_object('valid', false, 'request', 'Enter the value as an amount (for example 5000) or a percentage (for example 25%), with the sentence from the official page.');
  end if;
  v_num := coalesce(j->>'percentage', j->>'amount')::numeric;
  if v_num <= 0 or (v_kind = 'percentage' and v_num > 100) then
    return jsonb_build_object('valid', false, 'request', 'An amount must be above 0; a percentage must be above 0 and at most 100.');
  end if;
  v_quote := coalesce(j->>'quote', p_payload->>'quote');
  if not security.har_quote_ok_v1(v_quote) then
    return jsonb_build_object('valid', false, 'request', 'Add the sentence from the official page that states the value (a quotation, so it can be checked).');
  end if;
  return jsonb_build_object('valid', true, 'normalised', jsonb_build_object('field', 'award_value', 'kind', v_kind, 'value', v_num, 'quote', v_quote,
                                                                              'scholarship_id', v_sid, 'url', i.evidence->'official_links'->>0));
end $function$;
revoke all on function security.har_sch_value_validate_v1(bigint, text, jsonb) from public, anon, authenticated;

create or replace function security.har_sch_value_resume_v1(p_id bigint, p_action text, p_norm jsonb) returns jsonb
language plpgsql security definer set search_path to '' as $function$
-- CF-247 IQ-00264: the reviewer's value is applied as the reviewer's own locked edit through the existing Curator route (public.admin_scholarship_edit:
-- role check, manual lock, manual edit log, the reviewer's identity) while sch_cov.value_apply_on is 1; publishing follows at the next hourly
-- scholarship-auto-publish run. A refusal by the edit route keeps the input and says why; nothing automatic sets a value.
declare i pipeline.layer4_interventions; v_sid uuid := nullif(p_norm->>'scholarship_id', '')::uuid; v jsonb;
begin
  select * into i from pipeline.layer4_interventions where id = p_id;
  if security.pipeline_num_v1('sch_cov.value_apply_on', 1) < 1 then
    return jsonb_build_object('scheduled', false, 'held', 'sch_cov.value_apply_on is 0: the value is kept as a proposal (pipeline.layer4_intervention_values)');
  end if;
  begin
    v := public.admin_scholarship_edit(v_sid, 'set_core', jsonb_build_object('field', case p_norm->>'kind' when 'percentage' then 'award_percentage' else 'award_amount' end,
                                                                             'value', p_norm->>'value',
                                                                             'reason', left('Layer 4 › Human input needed (intervention ' || p_id || '): ' || coalesce(p_norm->>'quote', ''), 500)));
  exception when others then
    return jsonb_build_object('scheduled', false, 'held', left('the scholarship edit refused the value: ' || sqlerrm, 300));
  end;
  return jsonb_build_object('scheduled', true, 'operation', 'the value is your locked edit of the scholarship; the hourly publishing run publishes it when every check passes',
                            'scholarship_id', v_sid, 'value_label', v->>'value_label');
end $function$;
revoke all on function security.har_sch_value_resume_v1(bigint, text, jsonb) from public, anon, authenticated;

create or replace function security.har_sch_value_verify_v1(p_id bigint) returns jsonb
language plpgsql stable security definer set search_path to '' as $function$
-- CF-247 IQ-00264: succeeded when the scholarship is published and the consumer API returns it (published and consumer-verified); failed, back to
-- the reviewer with the checks, when the value is applied and the scholarship still fails another check; pending while the hourly run is due
declare i pipeline.layer4_interventions; v_sid uuid; s record; v_missing text[];
begin
  select * into i from pipeline.layer4_interventions where id = p_id;
  v_sid := substring(i.entity from '\|sch:([0-9a-f-]{36})$')::uuid;
  select x.publication_status, x.lifecycle_status into s from scholarship.scholarships x where x.id = v_sid;
  if not found or s.lifecycle_status <> 'active' then return jsonb_build_object('state', 'failed', 'request', 'The scholarship is no longer active.'); end if;
  if s.publication_status = 'published' then
    if api.website_v2_scholarship_item(v_sid) is not null then
      return jsonb_build_object('state', 'succeeded', 'outcome', 'published_consumer_verified', 'admitted', true, 'published', true);
    end if;
    return jsonb_build_object('state', 'pending', 'evidence', 'published; the website read-back does not return it yet');
  end if;
  select x.missing into v_missing from security.scholarship_publishability_for_v1(array[v_sid]) x;
  if coalesce(cardinality(v_missing), 0) > 0 and not ('no stated award value' = any (v_missing)) then
    return jsonb_build_object('state', 'failed', 'request', 'The value is applied, but publishing is still held by: ' || array_to_string(v_missing, '; ') || '.');
  end if;
  return jsonb_build_object('state', 'pending', 'evidence', coalesce('still failing: ' || array_to_string(v_missing, '; '), 'waiting for the hourly publishing run'));
end $function$;
revoke all on function security.har_sch_value_verify_v1(bigint) from public, anon, authenticated;

create or replace function security.har_sch_value_recheck_v1(p_id bigint) returns jsonb
language sql stable security definer set search_path to '' as $function$
  -- CF-247 IQ-00264: cleared without a person when the case is no longer an admitted scholarship held only by its award value
  select jsonb_build_object('cleared', not exists (select 1 from pipeline.scholarship_coverage_items x
            where x.provider_id = i.provider_id and x.item_key = split_part(i.entity, '|', 2) and x.present
              and x.state = 'admitted_not_published' and x.evidence->'missing' = '["no stated award value"]'::jsonb))
    from pipeline.layer4_interventions i where i.id = p_id
$function$;
revoke all on function security.har_sch_value_recheck_v1(bigint) from public, anon, authenticated;

insert into pipeline.layer4_intervention_handlers(lane, title, validate_fn, resume_fn, verify_fn, recheck_fn, generate_fn, generate_switch, description) values
 ('sch_value', 'Scholarships: award value for publication', 'security.har_sch_value_validate_v1(bigint,text,jsonb)', 'security.har_sch_value_resume_v1(bigint,text,jsonb)',
  'security.har_sch_value_verify_v1(bigint)', 'security.har_sch_value_recheck_v1(bigint)', 'security.har_sch_value_generate_v1(integer)', 'har.generate_sch_value_on',
  'An award value entered with its official sentence is applied as the reviewer''s locked edit; scholarship-auto-publish publishes; publication and the website read-back are verified.')
on conflict (lane) do nothing;

-- 5 root cause and remedy (workstream A's contract) -------------------------------------------------------------------------------------------------
select security.ops_root_cause_register_v1('sch_value_in_words_unrouted', jsonb_build_object('class', 'rule',
  'title', 'Admitted scholarships whose value is stated in words reach no one',
  'description', 'An admitted scholarship whose only failing publishing check is "no stated award value" (the page states the value in words, e.g. the RTP stipend rate) had no review item, intervention or recovery (113 of 144 admitted-not-published cases, 4 Nov 2026); decided refusals were counted as eligible work (IQ-00264).',
  'detect', jsonb_build_object('fn', 'security.scholarship_coverage_items_v1(uuid[])', 'state', 'admitted_not_published', 'missing', '["no stated award value"]')));
select security.ops_remedy_register_v1('sch_value_intervention', jsonb_build_object('authority', 'release', 'treats', jsonb_build_array('sch_value_in_words_unrouted'),
  'title', 'Ask a Layer 4 reviewer for the value (lane sch_value); apply it as the reviewer''s edit; publish and verify (release 20261104480000)',
  'notes', 'Switches har.generate_sch_value_on and sch_cov.value_apply_on; nothing automatic sets a value.'));

-- 6 register (housekeeping): no new job (job layer4-interventions runs the lane), no new table -------------------------------------------------------
-- 7 post-check --------------------------------------------------------------------------------------------------------------------------------------
do $$
begin
  if md5(pg_get_functiondef('security.scholarship_coverage_items_v1(uuid[])'::regprocedure)) <> '5605660603d40b3917001c37807a09bb' then
    raise exception 'post-check: scholarship_coverage_items_v1';
  end if;
  if not exists (select 1 from pipeline.layer4_intervention_handlers where lane = 'sch_value' and generate_switch = 'har.generate_sch_value_on') then
    raise exception 'post-check: the sch_value handler';
  end if;
  if (select count(*) from pipeline.platform_toolset_settings where key like 'har.sch_value_missing.%') <> 5 then raise exception 'post-check: class settings'; end if;
end $$;
