-- CF-247 F-PDESC delivery (Platform Admin operating model v1.5, 10 Nov 2026): the Basic -> Enriched upgrade lane of the scheduled reader is no longer starved by the queue of providers that have no description.
--
-- Production fact (project fxcwkweaxjtknorudmwp, SELECT only, 10 Nov 2026): security.provider_description_enqueue_v1 runs the upgrade lane (pdesc.registry_upgrade_on = 1, selection argument upgrade = true) only when the count of ALL queued reads is below
--   pdesc.queue_cap (60). The lane for providers with no description is sized by security.provider_description_throughput_v1 to its queue_target (about 178: 1,415 providers still to do, ETA 16 h) and keeps the whole queue above 60 for as long as any provider lacks a
--   description (203 queued now, 5 of them reads of providers that hold a register-fact profile). The upgrade lane therefore never queued anything, and a Basic -> Enriched upgrade was only possible by hand (Provider Fill Fields). Not a fault of the selection:
--   provider_description_selection_v1 with upgrade = true does not read the queue size at all (read the live body; its only bounds are the size asked for, pdesc.queue_cap as the largest size, pdesc.scan_max and pdesc.scan_factor for the slice). Measured by calling it
--   read only with the lane's arguments (10 Nov 2026): 60 providers eligible of the 60 asked for; of the 150 looked at, 2 were not eligible (unchanged_unsuitable_evidence: a hold on the same page).
--
-- What this changes (one function body; no new setting, table, column, job or consumer object):
--   security.provider_description_enqueue_v1(): the upgrade lane is gated on its OWN queue. The queued reads of providers that hold a register-fact profile (security.provider_description_basic_profile_v1(provider) is not null, the same test the selection uses; a live
--     registry_factual admission, not withdrawn, whose text is still the provider's text) are counted, and the lane runs while that count is below least(pdesc.queue_per_run, pdesc.queue_cap). It asks the selection for the difference, so the upgrade reads that wait
--     never exceed that bound and a run adds at most pdesc.queue_per_run (as before). The reads of providers with no description no longer switch the lane off. Every other bound is kept: pdesc.registry_upgrade_on and pdesc.machine_admit_on, the AI ceiling (pdesc.ai_usd_max)
--     and concurrency (pdesc.concurrency_max) in the lease, pdesc.tries, rejection memory, the recheck period, the scan marks (the providers looked at go to the back of the rotation), and the machine word policy at admission.
-- Live definition this change edits (pg_proc.prosrc md5, read 10 Nov 2026), before -> after:
--   security.provider_description_enqueue_v1() e97170e51cb27dee62db0cef3e07bb43 -> 6506620f2895f0b977e40261f4ff6afd
-- The edit is guarded: the migration stops, and nothing is applied, if the live body is neither the one it replaces nor the one it writes; applying it twice changes nothing. The text before is kept in supabase/held/pdesc_upgrade_lane_gate_forward_recovery.sql.
-- Depends on 20261110040000 (the upgrade lane as it leaves it). Consumer API (G3): not touched (an internal provider-description function). No operational value is written into code (G2): both bounds are read from pipeline settings. No job is added (G1).
-- Replaces: security.provider_description_enqueue_v1 (its upgrade lane waited for the whole queue to be short); the earlier text is kept in supabase/held/pdesc_upgrade_lane_gate_forward_recovery.sql
-- Retires: nothing
-- Nothing is dropped, deleted or renamed by this migration; no read, setting value or description is changed by it.

do $g$
declare r record;
begin
  for r in select * from (values ('security.provider_description_enqueue_v1()'), ('security.provider_description_selection_v1(jsonb)'), ('security.provider_description_basic_profile_v1(uuid)'), ('security.pipeline_num_v1(text,numeric)')) v(sig) loop
    if to_regprocedure(r.sig) is null then raise exception 'required % is missing', r.sig; end if;
  end loop;
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

select pg_temp.edit_all('security.provider_description_enqueue_v1()', 'e97170e51cb27dee62db0cef3e07bb43', '6506620f2895f0b977e40261f4ff6afd',
  array[$o1$ declare v_n int; v_k int; v_t jsonb; v_cc text; v_share int; v_sel jsonb;$o1$,
        $o2$  -- the upgrade lane is bounded by existing settings: pdesc.queue_per_run a run, and none while pdesc.queue_cap or more reads already wait (the providers with no description come first)
  if security.pipeline_num_v1('pdesc.registry_upgrade_on',0)>=1 and (select count(*) from pipeline.provider_description_reads q where q.state='queued')<security.pipeline_num_v1('pdesc.queue_cap',60) then$o2$,
        $o3$'size',least(security.pipeline_num_v1('pdesc.queue_per_run',10),security.pipeline_num_v1('pdesc.queue_cap',60))::int,'prefilter',true,'upgrade',true,$o3$],
  array[$n1$ declare v_n int; v_k int; v_t jsonb; v_cc text; v_share int; v_sel jsonb; v_up int;$n1$,
        $n2$  -- the upgrade lane has its OWN bound: the queued reads of providers that hold a register-fact profile are counted against the lower of pdesc.queue_per_run and pdesc.queue_cap, and the lane tops them up to that bound each run, however many reads of providers with no description wait (they used to switch the lane off, so an upgrade was never queued)
  v_up:=case when security.pipeline_num_v1('pdesc.registry_upgrade_on',0)>=1 then (select count(*) from pipeline.provider_description_reads q where q.state='queued' and security.provider_description_basic_profile_v1(q.provider_id) is not null) end;
  if v_up is not null and v_up<least(security.pipeline_num_v1('pdesc.queue_per_run',10),security.pipeline_num_v1('pdesc.queue_cap',60)) then$n2$,
        $n3$'size',least(security.pipeline_num_v1('pdesc.queue_per_run',10),security.pipeline_num_v1('pdesc.queue_cap',60))::int-v_up,'prefilter',true,'upgrade',true,$n3$]);
