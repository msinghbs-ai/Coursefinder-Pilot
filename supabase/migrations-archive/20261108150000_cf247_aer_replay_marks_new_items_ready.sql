-- CF-247 AER (lane aer2): a read the replay job recreates is assessed for review-readiness in the same run (Platform Admin directive 8 Nov 2026:
-- "Run readiness assessment for newly replayed RMIT items"; complete technical recovery and review-ready progression).
--
-- Finding (live read 8 Nov 2026 03:10 UTC, project fxcwkweaxjtknorudmwp): job aer-replay (:33) recreates a waiting course read from the stored read and
-- the new item is a new row with no readiness row. Its first completeness gate waited for the next run of job layer4-readiness (:22, :52), which gates
-- 20 never-gated entry items a run, oldest first. Of the 18 items the replay has created since 7 Nov, all 18 were classified later: median 619 minutes,
-- longest 799 minutes after the item was created (pipeline.aer_read_supersessions joined to pipeline.layer4_item_readiness.classified_at). Until then the
-- Inbox settlement calls an item with no gate "recoverable", not ready to decide.
-- Change: security.aer_replay_v1 collects the new item of each replacement it applies and, at the end of a real run (never the preview), calls
--   security.layer4_readiness_items_v1(new items) (released with 20261108040000 for exactly this: it classifies the listed waiting items as the readiness run
--   does, honours layer4.readiness_on and layer4.gate_batch, and records only). The call is inside its own exception block: a failure there is returned
--   under "readiness" and never undoes or fails the replay. Nothing is decided, approved, admitted or published; no new setting, job or number.
-- Called, not edited: security.layer4_readiness_items_v1(uuid[]) (live md5 f211fd1135deef955eaf179b1ac1665c; its presence is checked, 8 Nov 2026).
-- Not changed: security.aer_replay_plan_v1, security.aer_replay_apply_v1, security.aer_matrix_rank_repair_v1 (it repairs rows in runs that already exist, so
--   the item's gate is rechecked by the readiness run's own recheck interval), the replay's switches and caps (aer.replay_on, aer.replay_scan, batch.aer_replay,
--   aer.replay_per_provider, aer.replay_daily_max).
-- Consumer API: untouched (no public.website_v2_*, website_edge_*, zoho_edge_*, api.* object is read or changed).
--
-- Live definition this change edits (read 8 Nov 2026, md5 of pg_get_functiondef), then the md5 after:
--   security.aer_replay_v1(boolean) eccd0e821b5cffa733af3adc0162c0ea -> a58d95dbb079674e315b62b4c65542bf
-- Replaces: security.aer_replay_v1 (edited in place; same name and signature)
-- Retires: nothing
-- Nothing is dropped or deleted. No Layer 4 item is changed; no setting or flag is changed.

-- 0 the definition this change calls exists ---------------------------------------------------------------------------------------------------
do $g$
begin
  if to_regprocedure('security.layer4_readiness_items_v1(uuid[])') is null then
    raise exception 'security.layer4_readiness_items_v1(uuid[]) is missing: apply 20261108040000 first; nothing changed';
  end if;
end $g$;

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

-- 1 the replay collects the new items and has them assessed -------------------------------------------------------------------------------------
select pg_temp.edit_once('security.aer_replay_v1(boolean)', 'eccd0e821b5cffa733af3adc0162c0ea', 'a58d95dbb079674e315b62b4c65542bf',
  array[
    -- the items this run creates, and the readiness result
    ['v_key text; v_mx jsonb;',
     'v_key text; v_mx jsonb; v_new uuid[] := ''{}''; v_rd jsonb;'],
    -- each applied replacement names its new item
    ['        v_done := v_done + 1; v_byp := jsonb_set(',
     E'        if a->>''new_item'' is not null then v_new := v_new || (a->>''new_item'')::uuid; end if;  -- 8 Nov 2026 (lane aer2): the new item is assessed for readiness below\n        v_done := v_done + 1; v_byp := jsonb_set('],
    -- at the end of a real run, the new items are assessed now instead of at the next layer4-readiness run
    ['  return jsonb_build_object(''preview'', p_preview, ''judged'', v_judged,',
     E'  -- 8 Nov 2026 (lane aer2): the items this run created are classified now (security.layer4_readiness_items_v1, the readiness run''s own steps); a failure here is reported, never undoes the replay\n  if not p_preview and cardinality(v_new) > 0 then\n    begin v_rd := security.layer4_readiness_items_v1(v_new);\n    exception when others then v_rd := jsonb_build_object(''error'', left(sqlerrm, 200));\n    end;\n  end if;\n  return jsonb_build_object(''preview'', p_preview, ''judged'', v_judged,'],
    ['''matrix_rank_repair'', v_mx);',
     '''matrix_rank_repair'', v_mx, ''readiness'', v_rd);']
  ], array[1, 1, 1, 1]);

do $v$
begin
  if position('security.layer4_readiness_items_v1(v_new)' in pg_get_functiondef('security.aer_replay_v1(boolean)'::regprocedure)) = 0 then
    raise exception 'security.aer_replay_v1 does not call the readiness assessment after this change';
  end if;
end $v$;
