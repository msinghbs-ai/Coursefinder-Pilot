-- CF-247 F-PDESC (Platform Admin decision 9 Nov 2026, "All-Provider Autonomous Description Delivery": partitioned AU/NZ/CA queues, fair rotation, throughput sized from the remaining providers and the
-- observed rate, bounded concurrency, and the machine admission route inside the reader). Follows 20261109020000 (the machine admission functions, settings and tables).
--
-- With pdesc.machine_admit_on = 0 (the default, and what this migration leaves) every edited function behaves exactly as before: each edit is behind that setting. With it at 1:
--   security.provider_description_selection_v1   the size limit is pdesc.queue_cap (60) instead of min(queue_per_run, pending_max, run_now.pilot_cap) = 10
--   security.provider_description_enqueue_v1     queues each country in pdesc.countries separately (selection called per country), sized by security.provider_description_throughput_v1:
--                                                remaining providers / runs in pdesc.target_hours, limited by what the observed rate can drain (pdesc.backlog_hours); a share per country
--   public.svc_provider_description_next         work in progress is bounded by pdesc.concurrency_max and by the AI spend still available (pdesc.read_cost_floor_usd), not by the Layer 4
--                                                waiting cap; the country read least recently is leased first (fair rotation); lease and 20-minute claim recovery are unchanged
--   public.svc_provider_description_record       a proposal that fails the machine rule is HELD with machine_declined_<rule> (no Layer 4 item); one that passes is created as a Layer 4 item and admitted
--                                                by security.provider_description_machine_admit_v1 under the system automation account (never the human decision path)
--   security.provider_description_fire_v1        runs the machine step (settle waiting items, tier 4) each run, does not stop for the Layer 4 waiting cap, and sends up to pdesc.dispatch_max
--                                                worker calls (sized from the due reads) instead of one; the hourly floor (pdesc.every_minutes), AI ceiling, Firecrawl ceiling and fire guards are unchanged
-- The AI ceiling (pdesc.ai_usd_max), the Firecrawl ceiling (pdesc.firecrawl_reads_max) and the waiting cap (pdesc.pending_max) are NOT changed. No schedule, job or setting value changes.
--
-- Live definitions this change edits (read 9 Nov 2026 ~20:30 UTC, project fxcwkweaxjtknorudmwp), md5 of pg_get_functiondef before -> after:
--   security.provider_description_selection_v1(jsonb) eaebe3d0a6c188f0b4f6b6c3fcf659ba -> b69951b8afaa51aed55850460079361d
--   security.provider_description_enqueue_v1() 0a1897bb7f56697a9f01d4ec3e8befc0 -> ee5403b713c9e8176c87ec10f7de047d
--   public.svc_provider_description_next(integer) 559407dc479753698b858231b2e7eb93 -> bcc2eb6edd8170a7e6a6a1f2090c4313
--   public.svc_provider_description_record(jsonb) d95f0bafc894b662468a309254544444 -> b933e48dc0e59f140ab7a52726adf1ca
--   security.provider_description_fire_v1() b334fbefe8a7fb2b8cfd2feda570a616 -> cf8dd14c6a2168c4fd68daff5d9a0076
-- (eaebe3d0... is the selection function after 20261109010000.)
-- Replaces: the single-batch, Layer 4 capacity-bound queue and dispatch of the provider-description reader when automatic admission is on (edited in place behind pdesc.machine_admit_on; the functions are not replaced)
-- Retires: nothing
-- Nothing is dropped or deleted.

do $g$
declare r record;
begin
  for r in select * from (values ('security.provider_description_selection_v1(jsonb)'), ('security.provider_description_enqueue_v1()'), ('public.svc_provider_description_next(integer)'),
                                 ('public.svc_provider_description_record(jsonb)'), ('security.provider_description_fire_v1()'), ('security.provider_description_machine_admit_v1(uuid)'),
                                 ('security.provider_description_machine_gate_v1(uuid,text,jsonb)'), ('security.provider_description_machine_step_v1()'), ('security.provider_description_throughput_v1()')) v(sig) loop
    if to_regprocedure(r.sig) is null then raise exception 'required % is missing (apply 20261109020000 first)', r.sig; end if;
  end loop;
end $g$;

create or replace function pg_temp.edit_all(p_sig text, p_before text, p_after text, p_olds text[], p_news text[]) returns text language plpgsql as $f$
declare v_def text := pg_get_functiondef(p_sig::regprocedure); v_c int; i int;
begin
  if md5(v_def) = p_after then return p_sig || ': already applied'; end if;
  if md5(v_def) <> p_before then raise exception 'live % differs from the definition this change edits (md5 %)', p_sig, md5(v_def); end if;
  -- fixed: line endings are normalised, so the edit applies the same however the text arrives
  v_def := replace(v_def, chr(13), '');
  for i in 1 .. array_length(p_olds, 1) loop
    v_c := (length(v_def) - length(replace(v_def, p_olds[i], ''))) / length(p_olds[i]);
    if v_c <> 1 then raise exception '%: edit % must apply exactly once (found %)', p_sig, i, v_c; end if;
    v_def := replace(v_def, p_olds[i], p_news[i]);
  end loop;
  execute v_def;
  if md5(pg_get_functiondef(p_sig::regprocedure)) <> p_after then
    raise exception '% after the edit has md5 %, expected %', p_sig, md5(pg_get_functiondef(p_sig::regprocedure)), p_after;
  end if;
  return p_sig || ': applied';
end $f$;


-- ------------------------------------------------------------------------------------------------------------------ selection: the size limit in automatic mode
select pg_temp.edit_all('security.provider_description_selection_v1(jsonb)', 'eaebe3d0a6c188f0b4f6b6c3fcf659ba', 'b69951b8afaa51aed55850460079361d',
array[
$old$ v_max int := least(security.pipeline_num_v1('pdesc.queue_per_run',10),security.pipeline_num_v1('pdesc.pending_max',10),security.pipeline_num_v1('run_now.pilot_cap',20))::int;
$old$],
array[
$new$ v_max int := case when security.pipeline_num_v1('pdesc.machine_admit_on',0)>=1 then security.pipeline_num_v1('pdesc.queue_cap',60)::int else least(security.pipeline_num_v1('pdesc.queue_per_run',10),security.pipeline_num_v1('pdesc.pending_max',10),security.pipeline_num_v1('run_now.pilot_cap',20))::int end;
$new$]);

-- ------------------------------------------------------------------------------------------------------------------ enqueue: one partition a country in automatic mode
select pg_temp.edit_all('security.provider_description_enqueue_v1()', '0a1897bb7f56697a9f01d4ec3e8befc0', 'ee5403b713c9e8176c87ec10f7de047d',
array[
$old$ declare v_n int;
begin
 if security.pipeline_num_v1('pdesc.enabled',0)<1 then return 0; end if;
 insert into pipeline.provider_description_reads(provider_id)
$old$,
$old$ get diagnostics v_n=row_count; return v_n;
end $function$
$old$],
array[
$new$ declare v_n int; v_k int; v_t jsonb; v_cc text; v_share int;
begin
 if security.pipeline_num_v1('pdesc.enabled',0)<1 then return 0; end if;
 if security.pipeline_num_v1('pdesc.machine_admit_on',0)>=1 then
  -- automatic mode: each country is its own bounded queue, sized from the providers still to do and the observed rate
  v_n:=0; v_t:=security.provider_description_throughput_v1();
  for v_cc,v_share in select e.key,e.value::int from jsonb_each_text(coalesce(v_t->'share','{}'::jsonb)) e order by e.key loop
   insert into pipeline.provider_description_reads(provider_id)
   select (x->>'provider_id')::uuid from jsonb_array_elements(security.provider_description_selection_v1(jsonb_build_object('filter','all','size',v_share,'country',v_cc,
    'mode',case when security.pipeline_num_v1('pdesc.acquire_direct',0)>=1 then 'approved' else 'stored' end))->'providers') x
   where (x->>'eligible')::boolean on conflict do nothing;
   get diagnostics v_k=row_count; v_n:=v_n+v_k;
  end loop;
  return v_n;
 end if;
 insert into pipeline.provider_description_reads(provider_id)
$new$,
$new$ get diagnostics v_n=row_count; return v_n;
end $function$
$new$]);

-- ------------------------------------------------------------------------------------------------------------------ lease: work in progress bounded by concurrency and spend, fair rotation
select pg_temp.edit_all('public.svc_provider_description_next(integer)', '559407dc479753698b858231b2e7eb93', 'bcc2eb6edd8170a7e6a6a1f2090c4313',
array[
$old$declare v jsonb; v_model text; v_pending int; v_spent numeric; v_fc_used int;
$old$,
$old$  select (select count(*) from pipeline.layer4_review_items i where i.field_code='provider_description' and i.status='pending')
$old$,
$old$  if v_pending >= security.pipeline_num_v1('pdesc.pending_max', 10) then return jsonb_build_object('idle', true, 'reason', 'review_full', 'items', '[]'::jsonb); end if;
$old$,
$old$  if v_spent >= security.pipeline_num_v1('pdesc.ai_usd_max', 1) then return jsonb_build_object('idle', true, 'reason', 'ai_ceiling', 'spent_usd', v_spent, 'items', '[]'::jsonb); end if;
$old$,
$old$                 order by r.next_try_at, r.created_at
                 limit greatest(1, least(coalesce(p_limit, 3),security.pipeline_num_v1('batch.provider_description',3)::int,(security.pipeline_num_v1('pdesc.pending_max', 10) - v_pending)::int))
$old$],
array[
$new$declare v jsonb; v_model text; v_pending int; v_spent numeric; v_fc_used int; v_mach boolean := security.pipeline_num_v1('pdesc.machine_admit_on', 0) >= 1; v_cap numeric; v_afford numeric;
$new$,
$new$  v_cap := case when v_mach then security.pipeline_num_v1('pdesc.concurrency_max', 12) else security.pipeline_num_v1('pdesc.pending_max', 10) end;
  select (case when v_mach then 0 else (select count(*) from pipeline.layer4_review_items i where i.field_code='provider_description' and i.status='pending') end)
$new$,
$new$  if v_pending >= v_cap then return jsonb_build_object('idle', true, 'reason', 'review_full', 'items', '[]'::jsonb); end if;
$new$,
$new$  if v_spent >= security.pipeline_num_v1('pdesc.ai_usd_max', 1) then return jsonb_build_object('idle', true, 'reason', 'ai_ceiling', 'spent_usd', v_spent, 'items', '[]'::jsonb); end if;
  if v_mach then
    -- automatic mode: no more reads in progress than the AI spend still available covers, at the dearer of the set cost and the observed cost of a read
    v_afford := floor((security.pipeline_num_v1('pdesc.ai_usd_max', 1) - v_spent - coalesce((select sum(x.reserved_usd) from pipeline.provider_description_reads x where x.state = 'reading'), 0))
                      / greatest(security.pipeline_num_v1('pdesc.read_cost_floor_usd', 0.003), coalesce((select sum(x.cost_usd) / nullif(count(*) filter (where x.ai_calls > 0), 0) from pipeline.provider_description_reads x), 0)))
                - (select count(*) from pipeline.provider_description_reads x where x.state = 'reading' and x.leased_until >= now());
    if v_afford < 1 then return jsonb_build_object('idle', true, 'reason', 'ai_spend_committed', 'spent_usd', v_spent, 'items', '[]'::jsonb); end if;
  end if;
$new$,
$new$                 order by case when v_mach then (select count(*) from pipeline.provider_description_reads o join catalogue.providers po on po.id = o.provider_id join catalogue.providers pr on pr.id = r.provider_id
                                                      where po.country_id = pr.country_id and o.state in ('reading', 'proposed', 'admitted', 'held')
                                                        and o.updated_at > now() - make_interval(hours => security.pipeline_num_v1('pdesc.rate_window_hours', 3)::int)) else 0 end, r.next_try_at, r.created_at
                 limit greatest(1, least(coalesce(p_limit, 3),security.pipeline_num_v1('batch.provider_description',3)::int,(v_cap - v_pending)::int,coalesce(v_afford, 1000000)::int))
$new$]);

-- ------------------------------------------------------------------------------------------------------------------ record: the machine rule decides a proposal when automatic admission is on
select pg_temp.edit_all('public.svc_provider_description_record(jsonb)', 'd95f0bafc894b662468a309254544444', 'b933e48dc0e59f140ab7a52726adf1ca',
array[
$old$v_max int := security.pipeline_num_v1('pdesc.tries', 3)::int; v_err text;
$old$,
$old$    if v_chk->>'outcome'='propose' and (select count(*) from pipeline.layer4_review_items i where i.field_code='provider_description' and i.status='pending')>=security.pipeline_num_v1('pdesc.pending_max',10) then
$old$,
$old$      v_out := 'proposed';
    elsif v_chk->>'outcome' = 'verified' then
$old$],
array[
$new$v_max int := security.pipeline_num_v1('pdesc.tries', 3)::int; v_err text; v_m jsonb;
$new$,
$new$    if v_chk->>'outcome'='propose' and security.pipeline_num_v1('pdesc.machine_admit_on',0)>=1 then
      -- machine rule pdesc-machine-v1: a proposal that fails it is held with the exact reason (no Layer 4 item); a person can still decide a waiting item
      v_m:=security.provider_description_machine_gate_v1(r.provider_id,v_chk->>'text',jsonb_build_object('tier',r.read_via));
      if not (v_m->>'ok')::boolean then
        update pipeline.provider_description_reads set state='held',leased_until=null,proposal=jsonb_build_object('description',v_chk->>'text','sentences',x->'answer'->'sentences'),checks=v_chk->'checks',rule='machine_declined_'||(v_m->>'rule'),reason=left(v_m->>'reason',400),last_verified_at=now(),updated_at=now() where id=r.id;
        v_tally:=v_tally||jsonb_build_object('machine_declined',coalesce((v_tally->>'machine_declined')::int,0)+1); continue;
      end if;
    end if;
    if v_chk->>'outcome'='propose' and security.pipeline_num_v1('pdesc.machine_admit_on',0)<1 and (select count(*) from pipeline.layer4_review_items i where i.field_code='provider_description' and i.status='pending')>=security.pipeline_num_v1('pdesc.pending_max',10) then
$new$,
$new$      v_out := 'proposed';
      if security.pipeline_num_v1('pdesc.machine_admit_on',0)>=1 then
        -- admitted here under the machine rule, or left waiting for a person with the reason on the item; a failure never undoes the proposal
        begin
          v_m:=security.provider_description_machine_admit_v1(v_item);
          if (v_m->>'ok')::boolean then v_out:='admitted'; end if;
        exception when others then null;
        end;
      end if;
    elsif v_chk->>'outcome' = 'verified' then
$new$]);

-- ------------------------------------------------------------------------------------------------------------------ fire: machine step, no Layer 4 stop, several worker calls
select pg_temp.edit_all('security.provider_description_fire_v1()', 'b334fbefe8a7fb2b8cfd2feda570a616', 'cf8dd14c6a2168c4fd68daff5d9a0076',
array[
$old$declare v_q int := 0; v_due int; v_open int; v_last timestamptz; v_pending int; v_dead int; v_cohort uuid; v_resumed int;
$old$,
$old$  v_q := security.provider_description_enqueue_v1();
  else v_q:=0; v_resumed:=0; end if;
$old$,
$old$  if v_pending >= security.pipeline_num_v1('pdesc.pending_max', 10) then return jsonb_build_object('queued', v_q, 'review', 'full', 'pending', v_pending); end if;
$old$,
$old$    perform pipeline.svc_pilot_submit_nonce('coverage-sweep', jsonb_build_object('mode', 'provider_description', 'limit', security.pipeline_num_v1('batch.provider_description', 3)::int,'cohort_id',v_cohort));
    return jsonb_build_object('queued', v_q, 'due', v_due, 'sent', 1, 'dead_letter', v_dead);
$old$],
array[
$new$declare v_q int := 0; v_due int; v_open int; v_last timestamptz; v_pending int; v_dead int; v_cohort uuid; v_resumed int; v_sent int; v_i int;
$new$,
$new$  v_q := security.provider_description_enqueue_v1();
  if security.pipeline_num_v1('pdesc.machine_admit_on',0)>=1 then perform security.provider_description_machine_step_v1(); end if;
  else v_q:=0; v_resumed:=0; end if;
$new$,
$new$  if v_pending >= security.pipeline_num_v1('pdesc.pending_max', 10) and security.pipeline_num_v1('pdesc.machine_admit_on',0)<1 then return jsonb_build_object('queued', v_q, 'review', 'full', 'pending', v_pending); end if;
$new$,
$new$    -- automatic mode: as many worker calls as the due reads need, up to pdesc.dispatch_max (each lease is bounded by the concurrency and spend limits); otherwise one call, as before
    v_sent := case when security.pipeline_num_v1('pdesc.machine_admit_on',0)>=1 and v_cohort is null then least(security.pipeline_num_v1('pdesc.dispatch_max',3)::int, greatest(1, ceil(v_due::numeric / greatest(1, security.pipeline_num_v1('batch.provider_description', 3)))::int)) else 1 end;
    for v_i in 1 .. v_sent loop
      perform pipeline.svc_pilot_submit_nonce('coverage-sweep', jsonb_build_object('mode', 'provider_description', 'limit', security.pipeline_num_v1('batch.provider_description', 3)::int,'cohort_id',v_cohort));
    end loop;
    return jsonb_build_object('queued', v_q, 'due', v_due, 'sent', v_sent, 'dead_letter', v_dead);
$new$]);
