-- CF-247 F-PDESC Data Delivery (Platform Admin order, 10 Nov 2026 12:07): show the provider-description lane's AI cost and remaining allowance, who admitted what, and the Basic -> Enriched outcome in the EXISTING Data Delivery
-- panel (the stream "Provider descriptions"). The panel showed providers covered, the queue, the holds by cause, the rate and the last run; it did not show what the lane has spent, what is left to spend, how many descriptions the AI wrote
-- from an official page, or how the upgrade of a register-fact (Basic) profile to a source-verified (Enriched) description is going.
--   security.data_delivery_pdesc_v1() (read only, Admin only) NEW: counted live and exactly when the page is read, from the lane's own tables (no estimate, no forecast, no new table, setting, job or dashboard). It is called by the existing
--   security.data_delivery_v1 for the stream 'pdesc' only, as ONE new key 'provider_ai' (the response is additive: every existing key is unchanged; the screen treats a missing key as Not measured). Same pattern as 'stages' for the course stream.
--   AI cost: spent = sum(cost_usd) of pipeline.ai_spend_ledger where lane = 'provider_description' and source <> 'opening'; ceiling = pdesc.ai_usd_max (the same setting and default the reserve function tests); reserved = sum(reserved_usd) of the reads
--     that hold a reservation; remaining allowance = the ceiling less spent less reserved, never below 0. The reserve function also tests a DAILY guard (toolset openrouter, guard_provider_description) against today's spend (UTC day) plus the
--     reservations, so the day's spend, that guard and the day's remaining allowance are shown too (a guard that is not held is null: Not measured). The reads whose reservation the database settled as an estimate (checks.reservation_settlement, migration
--     20261110140000) are counted with their summed settled amount and labelled estimated on the screen: they were never measured by the provider.
--   Admitted, labelled Machine rule or Person as the course stages are: by the AI from an official page = reads in state admitted with rule missing joined (read_id) to a live (not withdrawn) machine admission whose tier is not registry_factual,
--     split into first descriptions (the provider never held a register-fact profile) and upgrades (it did); by the registry-fact route = live machine admissions of tier registry_factual; by a person = Layer 4 provider descriptions approved or
--     edited_approved with no admitted machine admission on the item; withdrawn = admitted machine admissions withdrawn where the provider has no live admission now (an upgrade closes the profile admission and replaces it, which is not a withdrawal).
--   Basic -> Enriched: upgraded = providers with a closed registry_factual admission and a live admission of another tier; Basic profiles still held = live registry_factual admissions; queued upgrade reads = queued reads of providers for which
--     security.provider_description_basic_profile_v1(provider) is not null (the test the upgrade lane and its selection use; null when the lane switch pdesc.registry_upgrade_on is off, and the screen says so); held upgrade reads = held reads of
--     providers that hold a live registry_factual admission and that were created AFTER that admission (a read made before it is the history that led to the profile, not an upgrade read: counting them would add about 970 reads that were never an
--     upgrade attempt); the top holds by rule are listed with the latest exact reason, as many as the existing setting data_delivery.reasons_shown (no new setting).
--   A count that cannot be made returns known false with the error: the rest of Data Delivery is not affected.
--   Cost (live, 10 Nov 2026, EXPLAIN ANALYZE of the same statement, read only): 161 ms execution, 14 ms planning. It reads 1,100 admissions, 2,614 reads, the 187 ledger rows of the lane (a scan of the 29,918-row ledger) and 1,090 Layer 4 items; no
--     function runs per row except security.provider_description_basic_profile_v1 on the queued reads (247 now). The statement time-out is 8 s.
-- Live definition this change edits (pg_proc.prosrc md5, read 10 Nov 2026, project fxcwkweaxjtknorudmwp), before -> after:
--   security.data_delivery_v1() b67bd181c58546076da48e7b5f00a2a4 -> 849453412a8b9a448118e7b87362752a
--   security.data_delivery_pdesc_v1() (new) -> 15b2f9882e77d7fcf0a8a4be2b6df18f
-- The edit is guarded: the migration stops, and nothing is applied, if the live body is neither the one it replaces nor the one it writes; applying it twice changes nothing. The text before is kept in supabase/held/dd_provider_ai_allowance_forward_recovery.sql.
-- Depends on 20261110100000 (the 'stages' key as it leaves it) and 20261110140000 (the settlement the screen counts). Consumer API (G3): not touched; the Website and Zoho objects, the feed tables and every api.* function are not read or changed.
-- No operational value is written into code (G2): the ceiling, the daily guard, the number of reasons and the upgrade switch are read from settings; the only constants are technical and marked `-- fixed:`. No job is added (G1): it runs inside the existing
--   Data Delivery read. No setting, ledger row, read or admission is written; no setting value changes.
-- Replaces: security.data_delivery_v1 is edited in place (md5-guarded, one new key 'provider_ai'); the earlier text is kept in supabase/held/dd_provider_ai_allowance_forward_recovery.sql; otherwise nothing
-- Retires: nothing
-- Nothing is dropped, deleted or renamed by this migration.

do $g$
declare r record;
begin
  for r in select * from (values ('security.data_delivery_v1()'), ('security.pipeline_num_v1(text,numeric)'), ('security.toolset_setting(text,text)'), ('security.provider_description_basic_profile_v1(uuid)')) v(sig) loop
    if to_regprocedure(r.sig) is null then raise exception 'required % is missing', r.sig; end if;
  end loop;
  if to_regclass('pipeline.ai_spend_ledger') is null or to_regclass('pipeline.provider_description_reads') is null or to_regclass('pipeline.provider_description_machine_admissions') is null or to_regclass('pipeline.layer4_review_items') is null then
    raise exception 'a table this change reads is missing';
  end if;
end $g$;

-- ----------------------------------------------------------------------------------------------------------------------------------------- the provider AI and upgrade counts (read only; applying again writes the same text)
create or replace function security.data_delivery_pdesc_v1() returns jsonb
language plpgsql stable security definer set search_path to ''
as $pdesc$
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
$pdesc$;

comment on function security.data_delivery_pdesc_v1() is 'CF-247 F-PDESC Data Delivery (Platform Admin 10 Nov 2026): the provider-description lane''s AI spend, reservations, remaining allowance (ceiling pdesc.ai_usd_max and the daily guard), estimated settlements, descriptions admitted by the AI from an official page (first descriptions and upgrades), by the registry-fact route and by a person, and the Basic to Enriched upgrade (upgraded, queued upgrade reads, held upgrade reads by rule), counted live and read only. Called by security.data_delivery_v1 for the stream pdesc as the key provider_ai.';
revoke all on function security.data_delivery_pdesc_v1() from public, anon, authenticated;

-- ----------------------------------------------------------------------------------------------------------------------------------------- the md5-guarded edit
do $m$
declare r record; v_def text; v_src text; v_c int; k int; v_sig regprocedure;
begin
  for r in select * from (values
    ('security.data_delivery_v1()', 'b67bd181c58546076da48e7b5f00a2a4', '849453412a8b9a448118e7b87362752a',
     array[$o$      'stages', case when s.stream = 'cdesc' then security.data_delivery_cdesc_stages_v1() end,$o$],
     array[$n$      'stages', case when s.stream = 'cdesc' then security.data_delivery_cdesc_stages_v1() end,
      'provider_ai', case when s.stream = 'pdesc' then security.data_delivery_pdesc_v1() end,$n$])
  ) v(sig, md5_before, md5_after, olds, news) loop
    v_sig := to_regprocedure(r.sig);
    v_src := (select p.prosrc from pg_proc p where p.oid = v_sig);
    -- fixed: the guard is the md5 of the live function body (pg_proc.prosrc), the same text on PostgreSQL 16 and 17
    if md5(v_src) = r.md5_after then continue; end if; -- already applied
    if md5(v_src) <> r.md5_before then raise exception 'live % differs from the definition this change edits (body md5 %)', r.sig, md5(v_src); end if;
    v_def := replace(pg_get_functiondef(v_sig), chr(13), '');
    for k in 1 .. array_length(r.olds, 1) loop
      v_c := (length(v_def) - length(replace(v_def, r.olds[k], ''))) / length(r.olds[k]);
      if v_c <> 1 then raise exception '%: edit % must apply exactly once (found %)', r.sig, k, v_c; end if;
      v_def := replace(v_def, r.olds[k], r.news[k]);
    end loop;
    execute v_def;
    v_src := (select p.prosrc from pg_proc p where p.oid = v_sig);
    if md5(v_src) <> r.md5_after then raise exception '% after the edit has body md5 %, expected %', r.sig, md5(v_src), r.md5_after; end if;
  end loop;
end $m$;

-- ----------------------------------------------------------------------------------------------------------------------------------------- register, post-check
insert into pipeline.component_register(kind, name, layer, purpose, status, replaces, introduced_in) values
 ('function', 'security.data_delivery_pdesc_v1', 'Platform', 'F-PDESC: the provider-description AI spend, remaining allowance, admissions by route and Basic to Enriched upgrade counts for Data Delivery (read only, live)', 'active', '{}', '20261110150000')
on conflict do nothing;

do $post$ begin
  if md5((select p.prosrc from pg_proc p where p.oid = 'security.data_delivery_pdesc_v1()'::regprocedure)) <> '15b2f9882e77d7fcf0a8a4be2b6df18f' then raise exception 'post-check: security.data_delivery_pdesc_v1 does not have the recorded body md5'; end if;
  if position('data_delivery_pdesc_v1' in (select p.prosrc from pg_proc p where p.oid = 'security.data_delivery_v1()'::regprocedure)) = 0 then raise exception 'post-check: Data Delivery does not call the provider AI counts'; end if;
  if position('data_delivery_cdesc_stages_v1' in (select p.prosrc from pg_proc p where p.oid = 'security.data_delivery_v1()'::regprocedure)) = 0 then raise exception 'post-check: the course stages call was lost'; end if;
end $post$;
