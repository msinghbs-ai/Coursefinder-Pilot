-- CF-247 F-PDESC delivery (Platform Admin operating model v1.5, 10 Nov 2026): an AI reservation that was never settled no longer consumes the provider-description AI budget for ever.
--
-- Production fact (project fxcwkweaxjtknorudmwp, SELECT only, 10 Nov 2026): the scheduled provider reader (worker v0.60.0) posts ALL results of one invocation to public.svc_provider_description_record in ONE call at the end.
--   That call failed twice with HTTP 500 "svc_provider_description_record: canceling statement due to statement timeout" (the API role has an 8 s statement time-out; 2026-11-09 23:06 UTC and 2026-11-10 01:16 UTC, pipeline.edge_request_log
--   joined to net._http_response). A failed call is one rolled-back transaction: the ai_calls, the cost_usd (so no ledger row) and the settle of the reservation of EVERY item of that invocation are lost together. The reservations themselves were
--   committed earlier (svc_provider_description_reserve_v1 sets reserved_usd before the paid call) and stay. Live state: 73 reads held with rule existing_cost_reservation_uncertain (reserved_usd US$0.521 in all, ai_calls 0, cost_usd 0, no ledger row,
--   no lease) and 6 reads in state reading with a live lease (US$0.042). The real ledger spend of the lane is US$0.0982 over 119 calls (about US$0.0008 a call). The reserve function and the lease add every reservation to the spend when they test the
--   ceiling, so the stuck reservations alone used the budget: with the ceiling at US$0.30 every call was refused, and a read that holds a reservation is refused for ever (existing_cost_reservation_uncertain), and the fire only returns such a read to the
--   queue when reserved_usd = 0, which nothing did. Whether each lost invocation made its AI call cannot be known from the database (the process ended between the reserve and the record), so a reservation is SETTLED, never released on the
--   assumption that no call was made.
-- Why one record call ran past 8 s (measured read only, 10 Nov 2026): the duplicate test in security.provider_description_validate_v1 computes the word-overlap similarity of the new text against EVERY provider description (1,082 of them) and every
--   proposed read, a word split, sort and distinct for each row: 5.7 s for one proposal (EXPLAIN ANALYZE of the same expression), and it grows with every description admitted. It runs once for each item that passes the sentence rules, so three items
--   (batch.provider_description) are past 8 s and even one item is near it. Everything else in the record loop is indexed lookups.
--
-- What this changes (no new setting, table, column, job or consumer object; the record function and the lease are NOT edited):
--   1 security.provider_description_settle_abandoned_v1() NEW (security definer, search path empty, service role or postgres only). An abandoned reservation is a read with reserved_usd > 0 that is not being worked on now: its state is not reading,
--     or it is reading and its lease has run out (or has none). A read in state reading with a live lease is a call in flight and is never touched. For each abandoned reservation, set-based and at most pdesc.queue_cap reads a run (oldest first,
--     rows already locked by a record call are skipped and taken on the next run): the call is ASSUMED to have been made (the conservative side) and its cost is the dearer of pdesc.read_cost_floor_usd and the observed cost of a read (sum of cost_usd
--     over count of reads with ai_calls > 0, the expression svc_provider_description_next uses), never more than the reservation and never zero: cost_usd rises by that amount (the existing trigger ai_spend_capture writes the ledger row for the
--     increase, which is the settlement), ai_calls rises by one (so the observed average stays cost per call), reserved_usd becomes 0, and checks.reservation_settlement says what was done (basis abandoned_reservation_assumed_called, settled_usd,
--     reserved_usd, floor_usd, observed_average_usd, ai_calls_before, state_before, at). A read that was reading with an expired lease becomes held with rule existing_cost_reservation_uncertain, so the requeue that the fire already makes (state held,
--     that rule, reserved_usd = 0) returns it to the queue and gives its try back. A read in any other state keeps its state, rule and reason: only its reservation is settled. It is idempotent (a settled read has reserved_usd = 0) and takes the lock
--     the reservation takes (advisory 'cf247 provider description spend'), so a settlement and a new reservation never see each other half done.
--   2 security.provider_description_fire_v1(): calls it right before the requeue statement (not for a Run Now cohort, which adds no work outside its fixed cohort). The held reads of the backlog are therefore settled and returned to the queue by the
--     next fire after release, 60 a run (pdesc.queue_cap); no data-fixing script.
--   3 security.provider_description_validate_v1(uuid,text,timestamptz,jsonb): the duplicate test keeps its result and loses its cost. A description whose word overlap with the new text is at least pdesc.duplicate_share needs at least that share of the
--     NEW text's distinct words (three or more letters, as pdesc_words_v1 reads them) to occur in it, so a row is first tested with a plain substring count of those words in the lower-cased description (about 0.1 ms) and the exact similarity runs
--     only for the rows that pass. The count can only be larger than the true overlap (a word in the description is always a substring of it), and it is compared with duplicate_share minus 0.0001, which covers the rounding of the similarity to four
--     decimals, so no row the exact test would have matched is skipped. The matched row, the rule duplicate_other_provider and the reason are the same; an optimisation fence (offset 0) keeps the cheap count in front of the exact similarity. Measured
--     read only on live (10 Nov 2026): 93 ms against 5,719 ms for a typical proposal text. Every other line of the validator is unchanged.
--   4 The used_by line of pdesc.queue_cap and pdesc.read_cost_floor_usd names the new function (text only, no value changes).
--   Worker v0.61.0 (supabase/functions/coverage-sweep) posts the results of an invocation ONE ITEM AT A TIME with one retry, so one slow item can no longer discard the others; deploy it with this migration. The settlement above covers the rest (a
--   record that fails twice, or a worker that ends, leaves a reservation that the next fire settles).
-- Not changed: the reserve function and its ceiling tests, the lease, the record, pdesc.ai_usd_max, the daily guard, timeouts of the database or of any role, the machine word policy, the identity proof, the quote proof, rejection memory, the queue, any read, ledger row or setting value.
-- Live definitions this change edits (pg_proc.prosrc md5, read 10 Nov 2026), before -> after:
--   security.provider_description_fire_v1() 21662da5fc9c4e15facbaef47b63a50f -> e518081dfb0882f93c264813b6ce3788
--   security.provider_description_validate_v1(uuid,text,timestamptz,jsonb) 7347f51b70a0c4a6cdd01a117080aad5 -> 91a7c9b7757cace6006af37df2bdc40a
--   security.provider_description_settle_abandoned_v1() (new) -> 6d27f04c5555ecdb7f8c4efb26abdcfb
-- Each edit is guarded: the migration stops, and nothing is applied, if a live body is neither the one it replaces nor the one it writes; applying it twice changes nothing. The text before is kept in supabase/held/pdesc_reservation_settlement_forward_recovery.sql.
-- Depends on 20261109110000 (the fire as it leaves it) and 20261110120000 (the validator as it leaves it). Consumer API (G3): not touched (internal provider-description functions). No operational value is written into code (G2): the floor, the
--   observed cost, the batch bound (pdesc.queue_cap) and the duplicate share are read from pipeline settings; the only constants are technical (the lock key, the rounding slack of the similarity) and are marked `-- fixed:`. No job is added (G1): the
--   settlement runs inside the existing provider-description fire.
-- Replaces: security.provider_description_fire_v1 (it never settled an abandoned reservation) and security.provider_description_validate_v1 (its duplicate test computed the similarity against every description); the earlier text is kept in supabase/held/pdesc_reservation_settlement_forward_recovery.sql
-- Retires: nothing
-- Nothing is dropped, deleted or renamed by this migration; no existing read, ledger row or setting value is changed by it (the settlement runs later, inside the fire).

do $g$
declare r record;
begin
  for r in select * from (values ('security.provider_description_fire_v1()'), ('security.provider_description_validate_v1(uuid,text,timestamptz,jsonb)'), ('public.svc_provider_description_record(jsonb)'),
                                 ('public.svc_provider_description_reserve_v1(uuid,text,numeric,text)'), ('security.pdesc_similarity_v1(text,text)'), ('security.pdesc_words_v1(text)'), ('security.pipeline_num_v1(text,numeric)')) v(sig) loop
    if to_regprocedure(r.sig) is null then raise exception 'required % is missing', r.sig; end if;
  end loop;
  -- the settlement is the cost increase that this trigger turns into a ledger row
  if not exists (select 1 from pg_trigger t where t.tgrelid = 'pipeline.provider_description_reads'::regclass and t.tgname = 'ai_spend_capture' and t.tgenabled <> 'D' and not t.tgisinternal) then
    raise exception 'required trigger ai_spend_capture on pipeline.provider_description_reads is missing or disabled';
  end if;
  if to_regclass('pipeline.ai_spend_ledger') is null then raise exception 'required table pipeline.ai_spend_ledger is missing'; end if;
end $g$;

create or replace function pg_temp.edit_all(p_sig text, p_before text, p_after text, p_olds text[], p_news text[]) returns text language plpgsql as $f$
declare v_def text := pg_get_functiondef(p_sig::regprocedure); v_src text := (select p.prosrc from pg_proc p where p.oid = p_sig::regprocedure); v_c int; i int;
begin
  -- fixed: the guard is the md5 of the function body (pg_proc.prosrc), the same text on PostgreSQL 16 and 17
  if md5(v_src) = p_after then return p_sig || ': already applied'; end if;
  if md5(v_src) <> p_before then raise exception 'live % differs from the definition this change edits (body md5 %)', p_sig, md5(v_src); end if;
  -- fixed: line endings are normalised, so the edit applies the same however the text arrives
  v_def := replace(v_def, chr(13), '');
  for i in 1 .. array_length(p_olds, 1) loop
    v_c := (length(v_def) - length(replace(v_def, p_olds[i], ''))) / length(p_olds[i]);
    if v_c <> 1 then raise exception '%: edit % must apply exactly once (found %)', p_sig, i, v_c; end if;
    v_def := replace(v_def, p_olds[i], p_news[i]);
  end loop;
  execute v_def;
  v_src := (select p.prosrc from pg_proc p where p.oid = p_sig::regprocedure);
  if md5(v_src) <> p_after then raise exception '% after the edit has body md5 %, expected %', p_sig, md5(v_src), p_after; end if;
  return p_sig || ': applied';
end $f$;

-- 1 the settlement of abandoned reservations (new; applying again writes the same text)
create or replace function security.provider_description_settle_abandoned_v1() returns integer
language plpgsql security definer set search_path to ''
as $settle$
-- provider-description-reservation-settlement-v1
declare v_floor numeric := security.pipeline_num_v1('pdesc.read_cost_floor_usd', 0.003); v_avg numeric; v_est numeric;
        v_bound int := greatest(1, security.pipeline_num_v1('pdesc.queue_cap', 60)::int); v_n int := 0;
begin
  if current_user <> 'postgres' and coalesce(auth.role(), '') <> 'service_role' then raise exception 'service_role required' using errcode = '42501'; end if;
  perform pg_advisory_xact_lock(hashtext('cf247 provider description spend')); -- fixed: the lock the reservation takes, so a settlement and a new reservation never see each other half done
  -- the observed cost of a read, the same expression the lease uses (svc_provider_description_next): cost over the reads that made a call
  select coalesce(sum(x.cost_usd) / nullif(count(*) filter (where x.ai_calls > 0), 0), 0) into v_avg from pipeline.provider_description_reads x;
  v_est := greatest(v_floor, v_avg);
  with a as (
    -- abandoned: a reservation that nothing is working on (not reading, or reading with a lease that has run out); a live lease is a call in flight
    select r.id from pipeline.provider_description_reads r
     where r.reserved_usd > 0 and (r.state <> 'reading' or r.leased_until is null or r.leased_until < now())
     order by r.updated_at, r.id limit v_bound for update skip locked),
  u as (
    update pipeline.provider_description_reads r
       set cost_usd = r.cost_usd + least(r.reserved_usd, v_est), -- the trigger ai_spend_capture writes the ledger row for this increase
           ai_calls = r.ai_calls + 1,
           reserved_usd = 0,
           checks = coalesce(r.checks, '{}'::jsonb) || jsonb_build_object('reservation_settlement', jsonb_build_object('basis', 'abandoned_reservation_assumed_called', 'settled_usd', least(r.reserved_usd, v_est),
                      'reserved_usd', r.reserved_usd, 'floor_usd', v_floor, 'observed_average_usd', round(v_avg, 6), 'ai_calls_before', r.ai_calls, 'state_before', r.state, 'at', now())),
           state = case when r.state = 'reading' then 'held' else r.state end,
           rule = case when r.state = 'reading' then 'existing_cost_reservation_uncertain' else r.rule end,
           reason = case when r.state = 'reading' then 'A paid read was leased and its result never recorded; its AI cost was settled at the dearer of the set floor and the observed cost of a read, and the read is offered again.' else r.reason end,
           leased_until = case when r.state = 'reading' then null else r.leased_until end,
           updated_at = now()
      from a where r.id = a.id
    returning 1)
  select count(*) into v_n from u;
  return v_n;
end $settle$;

comment on function security.provider_description_settle_abandoned_v1() is 'CF-247 F-PDESC: settles AI reservations that nothing is working on (reserved_usd > 0 and the read is not reading, or its lease has run out) at the dearer of pdesc.read_cost_floor_usd and the observed cost of a read, never above the reservation: cost_usd rises (ai_spend_capture writes the ledger row), ai_calls rises by one, reserved_usd becomes 0, checks.reservation_settlement records it, and an expired reading read becomes held existing_cost_reservation_uncertain so the fire requeues it. At most pdesc.queue_cap reads a run; called by security.provider_description_fire_v1; idempotent.';
revoke all on function security.provider_description_settle_abandoned_v1() from public, anon, authenticated;

-- 2 the fire settles before it requeues; 3 the duplicate test counts shared words before it computes the similarity
select pg_temp.edit_all('security.provider_description_fire_v1()', '21662da5fc9c4e15facbaef47b63a50f', 'e518081dfb0882f93c264813b6ce3788',
  array[$old$  perform security.provider_description_publication_check_v1();
  update pipeline.provider_description_reads set state='queued',tries=greatest(0,tries-1)$old$],
  array[$new$  perform security.provider_description_publication_check_v1();
  perform security.provider_description_settle_abandoned_v1(); -- reservations that nothing is working on are settled first (an abandoned paid call is counted, never assumed free); a settled read with the held rule below goes back to the queue
  update pipeline.provider_description_reads set state='queued',tries=greatest(0,tries-1)$new$]);

select pg_temp.edit_all('security.provider_description_validate_v1(uuid,text,timestamptz,jsonb)', '7347f51b70a0c4a6cdd01a117080aad5', '91a7c9b7757cace6006af37df2bdc40a',
  array[$old$    select p.id provider_id, security.pdesc_similarity_v1(v_text, p.description) sim from catalogue.providers p
     where p.id <> p_provider and nullif(btrim(p.description), '') is not null
    union all$old$],
  array[$new$    select f.id provider_id, security.pdesc_similarity_v1(v_text, f.description) sim from (
      -- the cheap count first (a word of the description is always a substring of it, so the count is never below the true overlap; 0.0001 covers the four-decimal rounding of the similarity): a row that cannot reach duplicate_share is not worked out
      select p.id, p.description from catalogue.providers p cross join (select security.pdesc_words_v1(v_text) wa offset 0) w
       where p.id <> p_provider and nullif(btrim(p.description), '') is not null
         and (select count(*) from unnest(w.wa) x where position(x in lower(p.description)) > 0) >= (v_dup - 0.0001) * cardinality(w.wa) -- fixed: rounding slack of pdesc_similarity_v1 (four decimals)
       offset 0) f -- offset 0: optimisation fence, so the count runs before the similarity
    union all$new$]);

-- 4 text only: the settings that the new function reads name it
update pipeline.platform_toolset_settings
   set used_by = used_by || '; security.provider_description_settle_abandoned_v1 (batch bound)', updated_at = now()
 where toolset_key = 'pipeline' and key = 'pdesc.queue_cap' and coalesce(used_by, '') not like '%provider_description_settle_abandoned_v1%';
update pipeline.platform_toolset_settings
   set used_by = used_by || '; security.provider_description_settle_abandoned_v1 (cost of an abandoned reservation)', updated_at = now()
 where toolset_key = 'pipeline' and key = 'pdesc.read_cost_floor_usd' and coalesce(used_by, '') not like '%provider_description_settle_abandoned_v1%';

-- the new function is the text this change recorded
do $c$
begin
  if (select md5(p.prosrc) from pg_proc p where p.oid = 'security.provider_description_settle_abandoned_v1()'::regprocedure) <> '6d27f04c5555ecdb7f8c4efb26abdcfb' then
    raise exception 'security.provider_description_settle_abandoned_v1 does not have the recorded body md5';
  end if;
end $c$;
