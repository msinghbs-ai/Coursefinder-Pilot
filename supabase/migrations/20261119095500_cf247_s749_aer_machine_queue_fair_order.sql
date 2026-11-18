-- CF-247 S749 AER course machine queue: the least recently checked item comes first within its group (session S2-BOOST-AER; Platform Admin 1-day handover directive
-- 19 Nov 2026 06:49 AEDT item 1; follows S748, migration 20261119080500).
-- Guards: AER course machine admission (rule aer-machine-v1), Decision 276 (pacing only: no reader, threshold, rule, validator or audit-sample change), G3 (CREATE OR REPLACE of one
--   security function; 75 functions and 48 relations post-checked), Decision 260 (housekeeping).
-- Replaces: security.aer_machine_run_v1 (same name and signature; md5-guarded edit of its order, exactly once)
-- Retires: nothing
--
-- Live evidence (project fxcwkweaxjtknorudmwp, read only, 19 Nov 2026 08:10 to 08:27 AEDT). After S748 the queue moves: the 07:54 run recorded the last check of 114 items, the 08:24 run
-- reached 80 more (75 audit samples, 5 declined). A run checks about 80 to 115 items inside its 45-second limit, about 1,100 in the 6-hour gap. The run takes gate-complete items first,
-- then never-checked ones, then the oldest by creation, so an item becomes eligible again after 6 hours and, being older, goes back in front of items not yet reached: when the
-- gate-complete group (about 970 audit samples and the 89 reads recorded would-admit among them) is larger than one 6-hour cycle can check, the tail of the group can starve again.
-- What this changes: within the same groups (gate-complete first, never checked next), the least recently checked comes first (s.updated_at nulls first), then the oldest by creation.
-- Not changed: which items are eligible, the batch (batch.aer_machine), the 45-second limit, the daily cap, the 6-hour gap, the rule, its thresholds, the validators, the audit sample.
-- Before -> after (pg_get_functiondef md5):
--   security.aer_machine_run_v1()   da1f53c6970cb5eef2c1826208b2bb0a -> fc9261cb02a7274a85cbd29238b68afe

do $g$
begin
  if to_regprocedure('security.aer_machine_run_v1()') is null then raise exception 'needs security.aer_machine_run_v1'; end if;
end $g$;

do $rn$
declare v_sig constant text := 'security.aer_machine_run_v1()'; v_before constant text := 'da1f53c6970cb5eef2c1826208b2bb0a';
        v_def text := pg_get_functiondef('security.aer_machine_run_v1()'::regprocedure); v_old text; v_new text; v_c int;
begin
  if v_def like '%S749 (19 Nov 2026)%' then raise notice '%: already applied', v_sig; return; end if;
  if md5(v_def) <> v_before then raise exception '% differs from the definition this change edits (md5 %)', v_sig, md5(v_def); end if;
  v_old := $o0$            order by coalesce((k.gate->>'complete')::boolean, false) desc, (s.id is null) desc, i.created_at$o0$;
  v_new := $n0$            -- S749 (19 Nov 2026): within each group the least recently checked comes first, so every item is checked once a cycle and a refreshed item waits behind the rest
            order by coalesce((k.gate->>'complete')::boolean, false) desc, (s.id is null) desc, s.updated_at nulls first, i.created_at$n0$;
  v_c := (length(v_def) - length(replace(v_def, v_old, ''))) / length(v_old);
  if v_c <> 1 then raise exception '%: the edit must apply exactly once (found %)', v_sig, v_c; end if;
  execute replace(v_def, v_old, v_new);
  raise notice '%: applied, md5 now %', v_sig, md5(pg_get_functiondef('security.aer_machine_run_v1()'::regprocedure));
end $rn$;

insert into pipeline.admin_control_events(area, action, target, detail)
select 'aer', 'machine_queue_order', 'security.aer_machine_run_v1',
       jsonb_build_object('change', 'within its group the least recently checked item comes first, so every item is checked once a cycle',
                          'authority', 'Platform Admin 19 Nov 2026 06:49 (S2-BOOST-AER item 1)', 'migration', '20261119095500')
 where not exists (select 1 from pipeline.admin_control_events e where e.area = 'aer' and e.action = 'machine_queue_order' and e.detail->>'migration' = '20261119095500');

do $p$
begin
  if pg_catalog.pg_get_functiondef('security.aer_machine_run_v1()'::regprocedure) not like '%S749 (19 Nov 2026)%' then raise exception 'post-check: S749 edit missing'; end if;
  if security.pipeline_num_v1('aer.machine_min_confidence', -1) <> 0.8 or security.pipeline_num_v1('aer.machine_min_quote_chars', -1) <> 8 then
    raise exception 'post-check: AER v1 thresholds must stay unchanged (Decision 276)';
  end if;
  if md5(pg_catalog.pg_get_functiondef('security.aer_machine_validate_v1()'::regprocedure)) <> '945077fe5dc291cc0893976f8fe65aef' then
    raise exception 'post-check: the course validator must stay the definition aer-validation-renew.yml pins';
  end if;
  if (select count(*) from security.consumer_api_functions_v1()) <> 75 or (select count(*) from security.consumer_api_relations_v1()) <> 48 then
    raise exception 'post-check: G3 must stay 75 functions and 48 relations';
  end if;
end $p$;
