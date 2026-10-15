CREATE OR REPLACE FUNCTION security.policy_auto_approve_v1()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare r record; v_sum jsonb; v_ag int; v_df int; v_ok int := 0; v_refused int := 0;
        v_max numeric := security.pipeline_num_v1('central.max_disagree_pct', 50);
        v_min int := security.pipeline_num_v1('central.min_compare', 10)::int;
        v_note text := 'Automatic: AI reading of the central page, every value quoted on the page (Platform Admin 15 Oct 2026: "Central pages, per course group", "Auto-approve checked AI proposals")';
begin
  if not coalesce((select (s.value #>> '{}')::boolean from pipeline.platform_toolset_settings s where s.toolset_key = 'pipeline' and s.key = 'central.auto_approve'), false) then
    return jsonb_build_object('off', true);
  end if;
  for r in select x.* from pipeline.provider_policy_proposals x
             join pipeline.enrich_focus_providers f on f.provider_id = x.provider_id and f.in_focus
            where x.status = 'proposed' and x.parser like 'ai:%' and x.kind in ('english_policy', 'intake_calendar')
            order by f.rank, x.created_at loop
    if r.kind = 'english_policy' then
      v_sum := security.provider_policy_refresh_one_v1(r.id);
      v_ag := coalesce((v_sum->>'agrees')::int, 0); v_df := coalesce((v_sum->>'differs')::int, 0);
      if v_ag + v_df >= v_min and 100.0 * v_df / (v_ag + v_df) > v_max then
        insert into pipeline.enrichment_flags(entity, entity_key, provider_id, field, reason_code, reason, source)
        values ('policy', r.id::text, r.provider_id, 'english', 'policy_disagrees',
                format('Not approved automatically: %s course pages agree and %s disagree with this default; a person decides (%s)', v_ag, v_df, r.url), 'policy-auto-approve')
        on conflict (entity, entity_key, field, reason_code) do update set reason = excluded.reason, flagged_at = now(), cleared_at = null;
        v_refused := v_refused + 1;
        continue;
      end if;
    end if;
    update pipeline.provider_policy_proposals set status = 'approved', decided_by = null, decided_at = now(), decision_note = v_note, updated_at = now() where id = r.id;
    insert into pipeline.admin_control_events(area, action, target, detail, actor)
    values ('policies', 'approve', r.kind || ': ' || r.url, jsonb_build_object('decision', 'Platform Admin 15 Oct 2026: automatic approval of checked AI readings', 'proposal_id', r.id, 'provider_id', r.provider_id), null);
    update pipeline.provider_policy_proposals
       set status = 'superseded', decided_at = now(), updated_at = now(), decision_note = 'Closed: another document for this university was approved (' || r.url || ')'
     where provider_id = r.provider_id and kind = r.kind and status = 'proposed' and id <> r.id;
    v_ok := v_ok + 1;
  end loop;
  return jsonb_build_object('approved', v_ok, 'refused', v_refused);
end $function$
