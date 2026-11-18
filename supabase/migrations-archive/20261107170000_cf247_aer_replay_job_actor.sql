-- CF-247 AER technical holds, fix 1: the replay could not write its job record (found on the first live run of aer-replay, 7 Nov 2026 12:33 UTC).
-- Guards: Platform Admin mandate 7 Nov 2026 21:57 (recover technically held items automatically), G1/G2 (no new job or setting), G3 (no consumer API object touched),
--   Decision 260 (housekeeping), Layer 4 admission authority kept (nothing is approved or admitted).
-- Live fault: security.aer_replay_apply_v1 inserted pipeline.admin_jobs with requested_by null; live the column is NOT NULL with no default, so every replacement failed
--   (SQLSTATE 23502). The step caught the error and recorded nothing, so the run reported "succeeded" with 2 recoverable reads and 0 replaced. The test fixture allowed a null there.
-- Now: the job is requested by the platform's system identity (security.system_actor_id(), the identity the other scheduled jobs use); if that identity is missing the
--   read is left alone with the reason; the reason a read was not applied is kept in pipeline.aer_replay_checks.outcome instead of being lost. The fixture mirrors the live constraint.
-- Replaces: security.aer_replay_apply_v1 and security.aer_replay_v1 (same names and results; the job record carries the system identity)
-- Retires: nothing

create or replace function security.aer_replay_apply_v1(p_item uuid, p_plan jsonb default null) returns jsonb
language plpgsql security definer set search_path to '' as $function$
-- CF-247 AER technical holds: records the request (history), runs the plan through security.enrich_entry_record_v1 (all E13 and D-R2 checks, row limit
-- included), and returns the outcome. The waiting item becomes superseded only when the replacement is complete; a person still decides the new item.
declare p jsonb := coalesce(p_plan, security.aer_replay_plan_v1(p_item)); r pipeline.layer4_review_items; v_job uuid; v_enrich bigint; v_sup uuid; v_res text; v_new uuid; v_state text;
begin
  if not coalesce((p->>'ok')::boolean, false) then return jsonb_build_object('item', p_item, 'applied', false, 'why', p->>'why'); end if;
  -- live: pipeline.admin_jobs.requested_by is not null; the job is the platform's own, so it is requested by the system identity (the same one the other scheduled jobs use)
  if security.system_actor_id() is null then return jsonb_build_object('item', p_item, 'applied', false, 'why', 'no system identity (security.system_actor_id) to request the replay job'); end if;
  select * into r from pipeline.layer4_review_items where id = p_item for update;
  insert into pipeline.admin_jobs(kind, lane, state, title, args, progress, requested_by, reason, scope)
  values ('enrich_fields', 'enrich', 'done', left('Entry requirements · replay of the stored read of item ' || p_item, 200),
          jsonb_build_object('replay', true, 'entry_read', true, 'ai', false, 'scraper', false, 'provider_ids', jsonb_build_array(p->>'provider_id'), 'course_ids', jsonb_build_array(p->>'course_id'),
                             'fields', jsonb_build_array('entry_requirements')),
          jsonb_build_object('done', 1, 'total', 1), security.system_actor_id(), 'Replay of stored read for Layer 4 item ' || p_item || ' (no AI read): ' || (p->>'source'), '1 course')
  returning id into v_job;
  insert into pipeline.field_enrich_items(job_id, provider_id, course_id, field, state, reason)
  values (v_job, (p->>'provider_id')::uuid, (p->>'course_id')::uuid, 'entry_requirements', 'skipped', 'replay of a stored read: no AI')
  returning id into v_enrich;
  insert into pipeline.aer_read_supersessions(old_item_id, course_id, source_url, old_evidence_id, enrich_item_id, job_id, requested_by, reason)
  values (p_item, r.entity_id, r.proposed_value->>'url', r.evidence_id, v_enrich, v_job, null,
          left('Replay of the stored read (no AI): ' || (p->>'source') || '; ' || jsonb_array_length(p->'rows') || ' requirement(s)', 500))
  returning id into v_sup;
  v_res := security.enrich_entry_record_v1(v_enrich, jsonb_build_object('model', 'stored-read-replay', 'worker', 'aer_replay', 'prompt_version', 'none',
             'value', jsonb_build_object('rows', p->'rows', 'dropped', p->'dropped', 'coverage', jsonb_build_object('basis', 'stored read replay', 'complete', true))));
  select s.state, s.new_item_id into v_state, v_new from pipeline.aer_read_supersessions s where s.id = v_sup;
  return jsonb_build_object('item', p_item, 'applied', v_state = 'superseded', 'result', v_res, 'request', v_sup, 'state', v_state, 'new_item', v_new, 'rows', jsonb_array_length(p->'rows'),
                            'why', case when v_state <> 'superseded' then (select s.outcome from pipeline.aer_read_supersessions s where s.id = v_sup) end);
end $function$;

create or replace function security.aer_replay_v1(p_preview boolean default false) returns jsonb
language plpgsql security definer set search_path to '' as $function$
-- CF-247 AER technical holds: judges a bounded scan of waiting course reads that are not complete and not on a shared page, and replaces the ones that
-- can be recovered from stored records. aer.replay_on = 0 stops it; the preview writes nothing and ignores the switch.
declare r record; p jsonb; a jsonb; v_scan int := security.pipeline_num_v1('aer.replay_scan', 60)::int; v_batch int := security.pipeline_num_v1('batch.aer_replay', 10)::int;
        v_per int := security.pipeline_num_v1('aer.replay_per_provider', 5)::int; v_left int := security.pipeline_num_v1('aer.replay_daily_max', 100)::int
                     - (select count(*) from pipeline.aer_read_supersessions s where s.reason like 'Replay of the stored read%' and s.requested_at > now() - interval '1 day');  -- fixed: the daily cap is counted over the last 24 hours
        v_done int := 0; v_judged int := 0; v_can int := 0; v_wait int := 0; v_out jsonb := '[]'::jsonb; v_byp jsonb := '{}'::jsonb; v_key text; v_mx jsonb;
begin
  if not p_preview and security.pipeline_num_v1('aer.replay_on', 1) < 1 then return jsonb_build_object('held', 'aer.replay_on is 0'); end if;
  begin v_mx := security.aer_matrix_rank_repair_v1(p_preview);
  exception when others then v_mx := jsonb_build_object('error', left(sqlerrm, 200));
  end;
  for r in select i.id, c.provider_id from pipeline.layer4_review_items i
             join pipeline.layer4_item_readiness x on x.item_id = i.id
             join catalogue.courses c on c.id = i.entity_id
             left join pipeline.aer_replay_checks k on k.item_id = i.id
            where i.status = 'pending' and i.field_code = 'course_entry_first_read' and x.gate is not null and not coalesce((x.gate->>'complete')::boolean, false)
              and jsonb_array_length(coalesce(x.gate->'shared_page', '[]'::jsonb)) = 0
              and (jsonb_array_length(coalesce(x.gate->'drops_uncovered', '[]'::jsonb)) > 0 or coalesce((x.gate->>'rows_cut')::int, 0) > 0)
            order by k.checked_at nulls first, i.created_at, i.id limit v_scan loop
    p := security.aer_replay_plan_v1(r.id); v_judged := v_judged + 1; v_key := p->>'condition_key';
    if coalesce((p->>'ok')::boolean, false) then
      v_can := v_can + 1;
      if not p_preview and v_done < v_batch and v_left > v_done and coalesce((v_byp->>(r.provider_id::text))::int, 0) < v_per then
        begin
          a := security.aer_replay_apply_v1(r.id, p);
        exception when others then a := jsonb_build_object('item', r.id, 'applied', false, 'why', left(sqlerrm, 200));
        end;
        v_done := v_done + 1; v_byp := jsonb_set(v_byp, array[r.provider_id::text], to_jsonb(coalesce((v_byp->>(r.provider_id::text))::int, 0) + 1));
        v_out := v_out || jsonb_build_array(a);
      else v_wait := v_wait + 1; end if;
    end if;
    if not p_preview then
      insert into pipeline.aer_replay_checks(item_id, condition_key, checked_at, ok, why, rows_needed, row_limit, outcome)
      values (r.id, coalesce(v_key, '-'), now(), coalesce((p->>'ok')::boolean, false), left(p->>'why', 500), (p->>'rows_needed')::int, (p->>'row_limit')::int,
              case when jsonb_array_length(v_out) > 0 and v_out->-1->>'item' = r.id::text then left(coalesce(v_out->-1->>'result', 'not applied: ' || (v_out->-1->>'why')), 200) end)
      on conflict (item_id) do update set condition_key = excluded.condition_key, checked_at = excluded.checked_at, ok = excluded.ok, why = excluded.why,
             rows_needed = excluded.rows_needed, row_limit = excluded.row_limit, outcome = excluded.outcome;
    elsif coalesce((p->>'ok')::boolean, false) then
      v_out := v_out || jsonb_build_array(jsonb_build_object('item', r.id, 'would_replace', true, 'rows', p->'rows_needed'));
    end if;
  end loop;
  return jsonb_build_object('preview', p_preview, 'judged', v_judged, 'can_be_recovered', v_can, 'replaced', case when p_preview then 0 else v_done end, 'waiting_for_room', v_wait, 'results', v_out, 'matrix_rank_repair', v_mx);
end $function$;
