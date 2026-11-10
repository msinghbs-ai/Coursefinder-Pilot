-- HELD (not a migration): forward recovery for 20261110210000 (provider-description sentence-subset recovery). Run only if the Platform Admin decides to take the change back.
-- It puts back, byte for byte, the text of security.provider_description_machine_admit_v1 (body md5 dedf28930cc7a12ad31570dec0d2f334), security.data_delivery_pdesc_v1 (body md5 15b2f9882e77d7fcf0a8a4be2b6df18f) and security.provider_description_fill_status_v1 (body md5 4a37300325d9da37ba26c92a0eda8279) before that migration, each guarded by the md5 of what is live now:
-- it stops, and changes nothing, if a live body is neither its earlier text nor the one the migration wrote (86d2596a13efe885b597771e70542efd, 575bded841d3ceca0afc9bdf13bf4d82 and e0fea4e1e736f97b5a7172ecb981501a). Readings already recovered, ledger rows, Layer 4 items, decisions and descriptions are never touched.
-- security.provider_description_subset_v1 is left in place (nothing calls it once the admission is restored); it is dropped by a paste file only on the Platform Admin's say. After it a reading that the text rule declines for some of its sentences is declined as a whole again. The migration applies again after it.
do $g$
declare v_a text; v_d text; v_f text;
begin
  select md5(p.prosrc) into v_a from pg_proc p where p.oid = to_regprocedure('security.provider_description_machine_admit_v1(uuid)');
  select md5(p.prosrc) into v_d from pg_proc p where p.oid = to_regprocedure('security.data_delivery_pdesc_v1()');
  select md5(p.prosrc) into v_f from pg_proc p where p.oid = to_regprocedure('security.provider_description_fill_status_v1(uuid[],boolean,uuid)');
  if v_a is null or v_d is null or v_f is null then raise exception 'the provider-description admission, its Data Delivery stream or the Fill fields status read is missing'; end if;
  if v_a not in ('dedf28930cc7a12ad31570dec0d2f334', '86d2596a13efe885b597771e70542efd') then raise exception 'live security.provider_description_machine_admit_v1 differs from both texts this recovery knows (body md5 %)', v_a; end if;
  if v_d not in ('15b2f9882e77d7fcf0a8a4be2b6df18f', '575bded841d3ceca0afc9bdf13bf4d82') then raise exception 'live security.data_delivery_pdesc_v1 differs from both texts this recovery knows (body md5 %)', v_d; end if;
  if v_f not in ('4a37300325d9da37ba26c92a0eda8279', 'e0fea4e1e736f97b5a7172ecb981501a') then raise exception 'live security.provider_description_fill_status_v1 differs from both texts this recovery knows (body md5 %)', v_f; end if;
end $g$;

CREATE OR REPLACE FUNCTION security.provider_description_machine_admit_v1(p_item_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $body$
declare i pipeline.layer4_review_items%rowtype; v_read pipeline.provider_description_reads%rowtype; v_tier text; v_text text; v_gate jsonb; v_check jsonb; v_prof jsonb; v_now text; v_pub jsonb; v_shown text; v_key text;
        v_sys uuid := 'c0ffee00-0000-4000-8000-000000000150'; -- fixed: the system automation account that records Decision 263 rule decisions
        v_rule constant text := 'pdesc-machine-v1'; v_ref text := 'CF-247 F-PDESC; Platform Admin decision 9 Nov 2026 (source-verified machine admission, tiers 1 to 4)'; v_dec uuid; v_facts jsonb := '[]'::jsonb; v_codes jsonb := '[]'::jsonb;
        v_url text; v_hash text; v_reason text; v_decline text; v_basic jsonb; v_upg boolean := false;
begin
  if security.pipeline_num_v1('pdesc.machine_admit_on', 0) < 1 then return jsonb_build_object('ok', false, 'rule', 'machine_admission_off'); end if;
  select * into i from pipeline.layer4_review_items where id = p_item_id for update;
  if i.id is null or i.entity_type <> 'provider' or i.field_code <> 'provider_description' or i.status <> 'pending' then return jsonb_build_object('ok', false, 'rule', 'not_a_waiting_provider_description'); end if;
  select * into v_read from pipeline.provider_description_reads r where r.review_item_id = i.id and r.state = 'proposed' for update;
  v_text := nullif(btrim(i.proposed_value->>'description'), '');
  v_tier := coalesce(nullif(v_read.checks->>'tier', ''), v_read.read_via, i.proposed_value->>'tier');
  v_decline := null;
  -- upgrade of a register-fact profile (pdesc.registry_upgrade_on): the item's before text is the profile the provider holds now and the proposal comes from a source tier
  v_basic := security.provider_description_basic_profile_v1(i.entity_id);
  v_upg := v_basic is not null and v_tier in ('stored', 'direct', 'firecrawl') and btrim(coalesce(i.before_value->>'description', '')) = btrim(v_basic->>'text');
  if v_read.id is null then v_decline := 'no_proposed_read';
  elsif v_tier not in ('stored', 'direct', 'firecrawl', 'registry_factual') then v_decline := 'unknown_tier';
  end if;
  if v_decline is null then
    if v_tier = 'registry_factual' then
      -- rebuilt from the verified record now: the text, the register evidence and the facts must be exactly what was proposed
      v_prof := security.provider_description_registry_profile_v1(i.entity_id);
      if not coalesce((v_prof->>'ok')::boolean, false) then v_decline := 'profile_' || coalesce(v_prof->>'rule', 'not_ok');
      elsif v_prof->>'text' is distinct from v_text or (v_prof->>'evidence_id')::uuid is distinct from i.evidence_id then v_decline := 'profile_changed_since_proposed';
      elsif not exists (select 1 from catalogue.provider_registrations rr where rr.id = (v_prof->>'registration_id')::uuid and rr.provider_id = i.entity_id and rr.status = 'active' and rr.evidence_id = i.evidence_id) then v_decline := 'register_listing_changed';
      end if;
      v_facts := coalesce(v_prof->'facts', '[]'::jsonb); v_codes := coalesce(v_prof->'codes', '[]'::jsonb); v_url := v_prof->>'source_url'; v_hash := v_prof->>'source_hash';
    else
      -- the same lineage, identity and quote checks the human path makes, proved again now
      if v_read.evidence_id is distinct from i.evidence_id or not exists (select 1 from pipeline.evidence_artifacts a join pipeline.sources s on s.id = a.source_id
           where a.id = i.evidence_id and s.provider_id = i.entity_id and a.source_url = v_read.source_url and coalesce(a.content_hash, a.id::text) = v_read.content_hash) then v_decline := 'evidence_lineage_changed';
      elsif not (security.provider_description_identity_v1(i.entity_id, v_read.source_url)->>'ok')::boolean then v_decline := 'identity_' || coalesce(security.provider_description_identity_v1(i.entity_id, v_read.source_url)->>'rule', 'not_clear');
      elsif v_read.checks->'identity_snapshot' is not null and v_read.checks->'identity_snapshot' is distinct from security.provider_description_identity_snapshot_v1(i.entity_id) then v_decline := 'identity_changed_since_read';
      elsif v_read.checks->'identity_snapshot' is null and not exists (select 1 from catalogue.providers p cross join lateral jsonb_array_elements(coalesce(i.proposed_value->'sentences', '[]'::jsonb)) sentence
           where p.id = i.entity_id and exists (select 1 from unnest(array[p.canonical_name, p.display_name]) nm where nullif(btrim(nm), '') is not null
             and position(regexp_replace(lower(nm), '[^a-z0-9]+', '', 'g') in regexp_replace(lower(sentence->>'quote'), '[^a-z0-9]+', '', 'g')) > 0)) then v_decline := 'legacy_proposal_name_not_in_quote';
      else
        v_check := security.provider_description_validate_v1(i.entity_id, v_read.source_url, v_read.source_captured_at, jsonb_build_object('about_page', true, 'sentences', i.proposed_value->'sentences'));
        if v_check->>'outcome' not in ('propose', 'verified') or v_check->>'text' is distinct from v_text then v_decline := 'validation_' || coalesce(v_check->>'rule', 'changed'); end if;
      end if;
      v_url := v_read.source_url; v_hash := v_read.content_hash;
      v_facts := coalesce((select jsonb_agg(jsonb_build_object('sentence', s->>'text', 'quote', s->>'quote', 'source_url', v_read.source_url, 'source_hash', v_read.content_hash, 'evidence_id', v_read.evidence_id,
                    'captured_at', v_read.source_captured_at, 'model', v_read.model, 'prompt_version', v_read.prompt_version, 'worker', v_read.worker)) from jsonb_array_elements(coalesce(i.proposed_value->'sentences', '[]'::jsonb)) s), '[]'::jsonb);
    end if;
  end if;
  if v_decline is null then
    v_gate := security.provider_description_machine_gate_v1(i.entity_id, v_text, jsonb_build_object('tier', v_tier, 'codes', v_codes, 'sentences', case when v_tier = 'registry_factual' then '[]'::jsonb else coalesce(i.proposed_value->'sentences', '[]'::jsonb) end));
    if not (v_gate->>'ok')::boolean then v_decline := v_gate->>'rule'; v_reason := v_gate->>'reason'; end if;
  end if;
  if v_decline is null and v_upg and (jsonb_array_length(coalesce(i.proposed_value->'sentences', '[]'::jsonb)) < security.pipeline_num_v1('pdesc.min_sentences', 2) or v_text = btrim(v_basic->>'text')) then v_decline := 'upgrade_too_short_or_unchanged'; end if;
  if v_decline is null and not v_upg and i.before_value->>'description' is not null and nullif(btrim(i.before_value->>'description'), '') is not null then v_decline := 'before_value_not_empty'; end if;
  if v_decline is null then
    select nullif(btrim(p.description), '') into v_now from catalogue.providers p where p.id = i.entity_id for update;
    if v_now is not null and not (v_upg and v_now = btrim(v_basic->>'text')) then v_decline := 'description_already_held'; end if;
  end if;
  if v_decline is not null then
    v_reason := coalesce(v_reason, 'The automatic rule did not admit this description (' || v_decline || '); a person decides in Layer 4.');
    insert into pipeline.provider_description_machine_admissions (provider_id, review_item_id, read_id, tier, rule, outcome, reason, evidence_id, source_url, source_hash, facts, actor)
    values (i.entity_id, i.id, v_read.id, case when v_tier in ('stored', 'direct', 'firecrawl', 'registry_factual') then v_tier else 'stored' end, v_rule, 'declined', v_reason, i.evidence_id, v_read.source_url, v_read.content_hash, v_facts, v_sys)
    on conflict (review_item_id) where outcome = 'declined' do update set reason = excluded.reason, tier = excluded.tier, facts = excluded.facts, created_at = now();
    update pipeline.layer4_review_items set escalation_reason = left('Machine rule ' || v_rule || ' did not admit this: ' || v_decline || '. ' || regexp_replace(coalesce(escalation_reason, ''), '^Machine rule [^.]*\. ', ''), 1000) -- fixed: the item's reason column shows its first 1000 characters
     where id = i.id and coalesce(escalation_reason, '') not like 'Machine rule ' || v_rule || ' did not admit this: ' || v_decline || '.%';
    return jsonb_build_object('ok', false, 'rule', v_decline, 'reason', v_reason);
  end if;
  -- write the one description, settle the item as a machine decision, record everything
  update catalogue.providers set description = v_text, updated_at = now() where id = i.entity_id;
  -- proved on the row: a guard that put the old text back must stop the admission, not leave an audit that says it was published
  if (select nullif(btrim(p.description), '') from catalogue.providers p where p.id = i.entity_id) is distinct from v_text then raise exception 'description_not_written: the catalogue kept the earlier text'; end if;
  update pipeline.layer4_review_items set status = 'approved', decided_at = now() where id = i.id and status = 'pending';
  v_reason := format('Auto (%s, tier %s): %s. Not a person''s decision.', v_rule, v_tier,
                     case when v_tier = 'registry_factual' then 'built only from the verified register listing, provider record and active catalogue courses; every sentence tied to its facts'
                          else 'official page ' || coalesce(v_url, '') || ' (hash ' || left(coalesce(v_hash, ''), 12) || '); identity, evidence lineage and every sentence''s quote proved again at admission' end); -- fixed: a short hash prefix is shown for reading, the full hash is stored
  insert into pipeline.layer4_decisions (review_item_id, action, actor_id, reason, before_value, proposed_value, final_value, evidence_id, layer2_state, layer3_state, change_control_ref)
  values (i.id, 'approve', v_sys, v_reason, i.before_value, i.proposed_value, i.proposed_value, i.evidence_id,
          coalesce(i.layer2_state, '{}'::jsonb) || jsonb_build_object('machine_rule', v_rule, 'tier', v_tier, 'actor_kind', 'machine'), coalesce(i.layer3_state, '{}'::jsonb), v_ref) returning id into v_dec;
  insert into pipeline.admin_control_events (area, action, target, detail, actor)
  values ('layer4', 'inbox_decide', i.id::text, jsonb_build_object('kind', 'provider_description', 'ref', i.id::text, 'choice', 'approve', 'reason', v_reason, 'provider_id', i.entity_id, 'auto', true,
          'machine_rule', v_rule, 'tier', v_tier, 'decision_id', v_dec, 'field_code', i.field_code), v_sys);
  select p.stable_key into v_key from catalogue.providers p where p.id = i.entity_id;
  begin v_pub := public.website_v2_provider(v_key); v_shown := v_pub->'item'->>'description'; exception when others then v_shown := null; end;
  update pipeline.provider_description_reads set state = 'admitted', last_verified_at = now(), published_at = case when v_shown = v_text then now() end, updated_at = now(),
         checks = coalesce(checks, '{}'::jsonb) || jsonb_build_object('machine_rule', v_rule, 'tier', v_tier, 'actor_kind', 'machine') where id = v_read.id;
  update pipeline.provider_description_reads set state = 'superseded', updated_at = now() where provider_id = i.entity_id and state = 'admitted' and id <> v_read.id;
  insert into pipeline.search_refresh_signals (entity_type, entity_id, review_decision_id, reason, change_control_ref)
  values ('provider', i.entity_id, v_dec, 'Accepted machine-rule Layer 4 canonical change: ' || v_reason, v_ref);
  if v_upg then
    -- the profile admission is closed, never deleted: its text stays as the earlier version (one live admission a provider)
    update pipeline.provider_description_machine_admissions set withdrawn_at = now(), withdrawn_by = v_sys,
           withdrawn_reason = 'Upgraded to a source-verified description from ' || coalesce(v_url, 'the official page') || '; the register-fact profile is kept in this row.'
     where id = (v_basic->>'admission_id')::uuid and outcome = 'admitted' and withdrawn_at is null;
  end if;
  insert into pipeline.provider_description_machine_admissions (provider_id, review_item_id, read_id, tier, rule, outcome, reason, before_description, after_description, evidence_id, source_url, source_hash, facts, checks, actor)
  values (i.entity_id, i.id, v_read.id, v_tier, v_rule, 'admitted', v_reason || case when v_upg then ' Upgrade of the register-fact profile, which is kept as the earlier version.' else '' end, case when v_upg then v_basic->>'text' end, v_text, i.evidence_id, v_url, v_hash, v_facts,
          jsonb_build_object('decision_id', v_dec, 'published', v_shown = v_text, 'validation', coalesce(v_check->'checks', v_prof->'facts'),
          'neutral_words', to_jsonb(security.pdesc_machine_neutral_supported_v1(v_text, case when v_tier = 'registry_factual' then '[]'::jsonb else coalesce(i.proposed_value->'sentences', '[]'::jsonb) end))), v_sys);
  if v_upg then
    update pipeline.provider_description_machine_admissions set checks = checks || jsonb_build_object('upgrade', jsonb_build_object('from_tier', 'registry_factual', 'prior_admission_id', v_basic->'admission_id', 'prior_read_id', v_basic->'read_id',
           'source_url', v_url, 'source_hash', v_hash, 'evidence_id', i.evidence_id, 'sentences', jsonb_array_length(coalesce(i.proposed_value->'sentences', '[]'::jsonb))))
     where review_item_id = i.id and outcome = 'admitted';
  end if;
  return jsonb_build_object('ok', true, 'provider_id', i.entity_id, 'tier', v_tier, 'rule', v_rule, 'decision_id', v_dec, 'description_chars', length(v_text), 'published', v_shown = v_text);
end $body$;

CREATE OR REPLACE FUNCTION security.data_delivery_pdesc_v1()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $body$
-- data-delivery-pdesc-v1
declare v_top int := security.pipeline_num_v1('data_delivery.reasons_shown', 3)::int; -- derived: the existing Data Delivery setting, how many exact reasons a stream lists
        v_cap numeric := security.pipeline_num_v1('pdesc.ai_usd_max', 1); -- the ceiling the reserve function tests (same setting, same default)
        v_daily numeric := (security.toolset_setting('openrouter', 'guard_provider_description') #>> '{}')::numeric; -- the daily guard the reserve function also tests; null = the setting is not held, shown as Not measured
        v_on boolean := security.pipeline_num_v1('pdesc.registry_upgrade_on', 0) >= 1;
begin
  return (
  with led as (select coalesce(sum(l.cost_usd), 0) usd, coalesce(sum(l.calls), 0) calls,
                      coalesce(sum(l.cost_usd) filter (where l.at >= date_trunc('day', now() at time zone 'UTC') at time zone 'UTC'), 0) today -- fixed: the UTC day the reserve function's daily guard uses
                 from pipeline.ai_spend_ledger l where l.lane = 'provider_description' and l.source <> 'opening'),
       res as (select coalesce(sum(r.reserved_usd), 0) usd, count(*) n from pipeline.provider_description_reads r where r.reserved_usd > 0),
       stl as (select count(*) n, coalesce(sum((r.checks->'reservation_settlement'->>'settled_usd')::numeric), 0) usd from pipeline.provider_description_reads r where r.checks ? 'reservation_settlement'),
       live as (select a.provider_id, a.tier, a.read_id, a.created_at from pipeline.provider_description_machine_admissions a where a.outcome = 'admitted' and a.withdrawn_at is null),
       closed as (select distinct a.provider_id from pipeline.provider_description_machine_admissions a where a.outcome = 'admitted' and a.withdrawn_at is not null and a.tier = 'registry_factual'),
       up as (select l.provider_id from live l join closed c on c.provider_id = l.provider_id where l.tier <> 'registry_factual'),
       ai as (select r.provider_id from pipeline.provider_description_reads r join live l on l.read_id = r.id and l.provider_id = r.provider_id and l.tier <> 'registry_factual' where r.state = 'admitted' and r.rule = 'missing'),
       uq as (select count(*) n from pipeline.provider_description_reads r where r.state = 'queued' and security.provider_description_basic_profile_v1(r.provider_id) is not null),
       uh as (select coalesce(nullif(btrim(r.rule), ''), 'no rule recorded') rule, r.reason, r.updated_at
                from pipeline.provider_description_reads r join live l on l.provider_id = r.provider_id and l.tier = 'registry_factual'
               where r.state = 'held' and r.created_at > l.created_at),
       uht as (select h.rule, count(*) n, (array_agg(h.reason order by h.updated_at desc))[1] example from uh h group by 1 order by 2 desc, 1 limit v_top)
  select jsonb_build_object(
    'known', true, 'counted_at', now(), 'unit', 'providers',
    'ai', jsonb_build_object(
        'ceiling_usd', v_cap, 'spent_usd', (select usd from led), 'calls', (select calls from led),
        'reserved_usd', (select usd from res), 'reserved_reads', (select n from res),
        'remaining_usd', greatest(0, v_cap - (select usd from led) - (select usd from res)),
        'today_usd', (select today from led), 'daily_guard_usd', v_daily,
        'daily_remaining_usd', case when v_daily is null then null else greatest(0, v_daily - (select today from led) - (select usd from res)) end,
        'settled_estimated_reads', (select n from stl), 'settled_estimated_usd', (select usd from stl)),
    'admitted', jsonb_build_object(
        'ai_first_description', (select count(*) from ai where ai.provider_id not in (select provider_id from up)),
        'ai_upgrade', (select count(*) from ai where ai.provider_id in (select provider_id from up)),
        'registry_fact', (select count(*) from live where tier = 'registry_factual'),
        'by_person', (select count(*) from pipeline.layer4_review_items i where i.entity_type = 'provider' and i.field_code = 'provider_description' and i.status in ('approved', 'edited_approved')
                        and not exists (select 1 from pipeline.provider_description_machine_admissions m where m.review_item_id = i.id and m.outcome = 'admitted')),
        'withdrawn', (select count(*) from pipeline.provider_description_machine_admissions a where a.outcome = 'admitted' and a.withdrawn_at is not null and not exists (select 1 from live l where l.provider_id = a.provider_id))),
    'upgrade', jsonb_build_object(
        'lane_on', v_on, 'admitted', (select count(*) from up), 'basic_profiles_held', (select count(*) from live where tier = 'registry_factual'),
        'queued_reads', (select n from uq), 'held_reads', (select count(*) from uh),
        'top_hold_rules', coalesce((select jsonb_agg(jsonb_build_object('rule', t.rule, 'n', t.n, 'example', t.example) order by t.n desc, t.rule) from uht t), '[]'::jsonb))));
exception when others then
  -- a count that cannot be made is shown as such, never as 0, and does not stop the rest of Data Delivery
  return jsonb_build_object('known', false, 'reason', 'The provider AI and upgrade counts could not be read: ' || sqlerrm);
end
$body$;

create or replace function security.provider_description_fill_status_v1(p_ids uuid[], p_feeds boolean, p_actor uuid) returns jsonb
language plpgsql stable security definer set search_path to ''
as $body$
begin
  return (
    with q as (select * from security.provider_description_quality_v1(p_ids, p_feeds)),
    lr as (
      select distinct on (r.provider_id) r.provider_id, r.id read_id, r.state, r.rule, r.reason, r.tries, r.updated_at, r.next_try_at, r.review_item_id, r.evidence_id, r.source_url, r.read_via
        from pipeline.provider_description_reads r where r.provider_id = any(p_ids) order by r.provider_id, r.created_at desc, r.id desc
    ), lt as (
      select distinct on (m.provider_id) m.provider_id, c.id cohort_id, c.state cohort_state, c.run_id, c.created_at, c.reason, (c.requested_by = p_actor) mine, c.selection->>'fill_mode' fill_mode,
             j.state run_state, j.outcome run_outcome, j.finished_at run_finished_at
        from pipeline.provider_description_cohort_members m
        join pipeline.provider_description_cohorts c on c.id = m.cohort_id
        left join pipeline.admin_jobs j on j.id = c.run_id
       where m.provider_id = any(p_ids) order by m.provider_id, c.created_at desc, c.id desc
    )
    select jsonb_build_object('as_at', now(), 'feeds', p_feeds, 'providers', coalesce(jsonb_agg(jsonb_build_object(
      'provider_id', p.id, 'name', coalesce(p.display_name, p.canonical_name), 'stable_key', p.stable_key, 'country', k.iso_alpha2::text, 'type', pt.code,
      'lifecycle_status', p.lifecycle_status, 'publication_status', p.publication_status,
      'description_present', q.description_filled, 'current_description', p.description, 'quality_class', q.quality_class,
      'source_tier', q.source_tier, 'admission_state', q.admission_state, 'admitted_at', q.admitted_at, 'admitted_by', q.admitted_by, 'evidence_id', coalesce(q.evidence_id, lr.evidence_id), 'source_url', coalesce(q.source_url, lr.source_url),
      'reader', jsonb_build_object('read_id', lr.read_id, 'state', lr.state, 'rule', lr.rule, 'reason', lr.reason, 'tries', lr.tries, 'updated_at', lr.updated_at, 'read_via', lr.read_via),
      'hold_reason', coalesce(q.hold_reason, case when lr.state in ('held', 'rejected', 'dead_letter') then coalesce(nullif(lr.reason, ''), lr.rule) end), 'next_retry_at', coalesce(q.next_retry_at, case when lr.state in ('queued', 'held') then lr.next_try_at end),
      'last_read_ok_at', q.last_read_ok_at, 'l4_status', q.l4_status, 'review_item_id', lr.review_item_id,
      'website_state', q.website_state, 'zoho_state', q.zoho_state, 'website_publication', q.website_publication, 'zoho_publication', q.zoho_publication, 'readback_at', q.readback_at,
      'missing_fields', to_jsonb(q.missing_fields),
      'locked', exists (select 1 from pipeline.manual_locks l where l.entity = 'provider' and l.entity_id = p.id and l.field in ('description', 'p_description', 'all')),
      'latest_task', case when lt.cohort_id is null then null else jsonb_build_object('cohort_id', lt.cohort_id, 'state', lt.cohort_state, 'run_id', lt.run_id, 'created_at', lt.created_at, 'reason', lt.reason,
        'requested_by_me', lt.mine, 'fill_mode', lt.fill_mode, 'run_state', lt.run_state, 'run_outcome', lt.run_outcome, 'run_finished_at', lt.run_finished_at) end
    ) order by coalesce(p.display_name, p.canonical_name)), '[]'::jsonb))
    from q join catalogue.providers p on p.id = q.provider_id join ref.countries k on k.id = p.country_id left join ref.provider_types pt on pt.id = p.provider_type_id
    left join lr on lr.provider_id = p.id left join lt on lt.provider_id = p.id
  );
end
$body$;
