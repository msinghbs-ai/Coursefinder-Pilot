-- Guards: F-INT.01/SRC-01 (9 Nov 2026): security.policy_auto_approve_v1 exactly as production holds it (md5 189d5c4349f604653f20c8fc854d1cd1, read 9 Nov 2026), so the md5-guarded edit of migration 20261109060000 is tested against the real definition.
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
             left join pipeline.enrich_focus_providers f on f.provider_id = x.provider_id
            where x.status = 'proposed' and x.kind in ('english_policy', 'intake_calendar')
              -- CF-247 6 Nov 2026 (English requirements, decision D2): a faculty or course-group reading is never approved automatically; a person approves it and binds its groups
              and (x.kind <> 'english_policy' or jsonb_array_length(case when jsonb_typeof(x.proposal->'groups') = 'array' then x.proposal->'groups' else '[]'::jsonb end) = 0)
              and (x.parser like 'ai:%'
                   -- CF-247 decision 5 Nov 2026 §2: a deterministic dated calendar reading, only when the Platform Admin switches it on
                   or (x.kind = 'intake_calendar' and x.parser = 'provider-policy-calendar-dates-v2' and security.pipeline_num_v1('central.auto_approve_calendar_dates', 0) = 1
                       and security.calendar_scope_v1(x.proposal, x.url, x.parser) = 'main_teaching'))
              -- 23 Oct 2026 (Platform Admin 12:40): English rules for every university, not only the focus list
              and (coalesce(f.in_focus, false)
                   or (x.kind = 'english_policy' and coalesce((select (s.value #>> '{}')::boolean from pipeline.platform_toolset_settings s where s.toolset_key = 'pipeline' and s.key = 'central.auto_approve_english_all'), false)))
            order by f.rank nulls last, x.created_at loop
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
     where provider_id = r.provider_id and kind = r.kind and status = 'proposed' and id <> r.id
       and (r.kind <> 'intake_calendar' or fact_source_id is not distinct from r.fact_source_id)
       and jsonb_array_length(case when jsonb_typeof(proposal->'groups') = 'array' then proposal->'groups' else '[]'::jsonb end) = 0;  -- CF-247 6 Nov 2026: an automatic approval never closes a course-group reading a person has yet to decide (5 Nov 2026: one calendar document never closes another's)
    v_ok := v_ok + 1;
  end loop;
  return jsonb_build_object('approved', v_ok, 'refused', v_refused);
end $function$;
