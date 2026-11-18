CREATE OR REPLACE FUNCTION security.cdesc_subset_recover_v1()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare r record; v_stamp text := security.course_description_machine_policy_stamp_v1(); v_cap int := security.pipeline_num_v1('enrich.course_text_items_per_day', 500)::int; -- derived: never more in a run than the platform reads in a day (as the replay)
        v_days int := security.pipeline_num_v1('gaps.recheck_days', 60)::int; v_t0 timestamptz := clock_timestamp(); v_dl timestamptz; v_dl_a timestamptz; v_tb boolean := false; v_prov jsonb; v_plan jsonb; v_sub jsonb; v_val jsonb; v_res text; v_why text; v_msg text; v_adm jsonb; v_slots jsonb := '{}'::jsonb; v_n int;
        v_looked int := 0; v_rec_a int := 0; v_rec_b int := 0; v_by jsonb := '{}'::jsonb; v_no jsonb := '{}'::jsonb; v_full int := 0; v_item uuid;
begin
  if security.pipeline_num_v1('enrich.course_description_machine_on', 0) < 1 then return jsonb_build_object('on', false); end if;
  -- fixed: the whole subset step ends 45 s after it began or 60 s after the job began, whichever comes first (13 Nov 2026: the job now runs every two minutes and a recovered reading is admitted inside this step, so the step has the larger share; the settle after it still stops 85 s into the job, inside the 120 s statement time-out)
  v_dl := least(v_t0 + make_interval(secs => 45), statement_timestamp() + make_interval(secs => 60));
  -- fixed: part (a) may use 60 % of that time box, so part (b) is never starved behind it (what part (a) leaves is part (b)'s)
  v_dl_a := v_t0 + (v_dl - v_t0) * 0.6;
  -- (a) a reading held by the reader's own check: the latest reading of an active course that has no description
  for r in select e.id, e.course_id, e.value, e.quote, c.provider_id, btrim(split_part(e.reason, ':', 2)) cause
             from pipeline.field_enrich_items e join catalogue.courses c on c.id = e.course_id
            where e.field = 'description' and e.state = 'skipped' and e.reason ~ '^held: (sentence_count|length|unsupported_claim|quote_not_on_page|unsupported_sentence|unsupported_marketing|incomplete_sentence|copied_sentence|generic_phrase):'
              and jsonb_typeof(e.value->'sentences') = 'array' and c.lifecycle_status = 'active' and nullif(btrim(c.description), '') is null
              and e.updated_at > now() - make_interval(days => v_days)
              and e.id = (select max(x.id) from pipeline.field_enrich_items x where x.course_id = e.course_id and x.field = 'description')
              and coalesce(e.value->'subset_attempt'->>'stamp', '') <> v_stamp
            order by e.id limit v_cap loop
    if clock_timestamp() > v_dl_a then v_tb := true; exit; end if;
    v_looked := v_looked + 1; v_why := null; v_sub := null;
    -- the provider's places (enrich.course_description_pending_max): a provider whose places are all taken is left for a later run (nothing is written, so it is not marked)
    if not v_slots ? r.provider_id::text then v_slots := v_slots || jsonb_build_object(r.provider_id::text, security.cdesc_provider_slots_v1(r.provider_id)); end if;
    if (v_slots->>r.provider_id::text)::int <= 0 then v_full := v_full + 1; continue; end if;
    if security.course_description_trusted_v1(r.provider_id) then continue; end if; -- a provider whose first descriptions a person approved is written by the existing trusted route, not by the machine rule
    begin
      v_prov := security.cdesc_reading_provenance_v1(r.id, r.value);
      if nullif(v_prov->>'model', '') is null or nullif(v_prov->>'prompt', '') is null then v_why := 'reader_unrecorded';
      else
        v_plan := security.cdesc_subset_plan_v1(r.course_id, r.provider_id, r.value);
        if not coalesce((v_plan->>'ok')::boolean, false) then v_why := coalesce(v_plan->>'rule', 'plan_failed');
        else
          v_sub := (v_plan->'subset') || jsonb_build_object('cause', r.cause, 'stamp', v_stamp, 'at', now());
          begin
            v_val := (r.value - 'subset_attempt' - 'check') || jsonb_build_object('sentences', v_plan->'sentences', 'subset_of_reading', v_sub);
            v_res := security.enrich_course_text_record_v1(r.id, jsonb_build_object('value', v_val, 'quote', r.quote, 'model', v_prov->>'model', 'prompt_version', v_prov->>'prompt', 'worker', v_prov->>'worker'));
            if v_res is distinct from 'review' then raise exception 'cdesc_subset:record_%', coalesce(v_res, 'nothing'); end if;
            -- recording the waiting item runs the machine rule on it (the trigger of the reading); the subset stands only if that admitted it
            if not exists (select 1 from catalogue.courses c where c.id = r.course_id and c.description = v_plan->>'text') then
              select a.reason_code into v_why from pipeline.course_description_machine_admissions a
               where a.review_item_id = (select (f.value->>'review_item_id')::uuid from pipeline.field_enrich_items f where f.id = r.id) and a.outcome = 'declined' order by a.id desc limit 1;
              raise exception 'cdesc_subset:machine_%', coalesce(v_why, 'not_admitted');
            end if;
            v_rec_a := v_rec_a + 1; v_by := jsonb_set(v_by, array[r.cause], to_jsonb(coalesce((v_by->>r.cause)::int, 0) + 1)); v_why := 'recovered';
          exception when others then
            get stacked diagnostics v_msg = message_text;
            v_why := case when v_msg like 'cdesc_subset:%' then substr(v_msg, length('cdesc_subset:') + 1) else 'error' end; -- the sub-transaction is rolled back: nothing of the attempt stays
          end;
        end if;
      end if;
    exception when others then v_why := 'error';
    end;
    if v_why is distinct from 'recovered' then
      v_no := jsonb_set(v_no, array[v_why], to_jsonb(coalesce((v_no->>v_why)::int, 0) + 1));
      update pipeline.field_enrich_items set value = value || jsonb_build_object('subset_attempt', jsonb_build_object('stamp', v_stamp, 'result', v_why, 'at', now())) where id = r.id and state = 'skipped'; -- noted for this policy stamp; updated_at stays, so the queue's own timing is not moved
    end if;
  end loop;
  -- (b) a waiting first description that the machine declined for its wording (or a check that changed): the item and its reading are rewritten to the subset, and the machine rule decides
  for r in select i.id item_id, i.entity_id course_id, c.provider_id, f.id rid, f.value, d.reason_code cause, i.proposed_value
             from pipeline.layer4_review_items i
             join catalogue.courses c on c.id = i.entity_id and c.lifecycle_status = 'active' and nullif(btrim(c.description), '') is null
             join pipeline.course_description_machine_admissions d on d.review_item_id = i.id and d.outcome = 'declined' and d.withdrawn_at is null and not d.transient and d.policy_stamp = v_stamp
                  and (d.reason_code like 'policy\_%' or d.reason_code like 'check\_%') and d.reason_code not in ('check_duplicate_other_course', 'check_not_stated')
             join pipeline.field_enrich_items f on f.id = case when coalesce(i.proposed_value->>'item_id', '') ~ '^\d+$' then (i.proposed_value->>'item_id')::bigint end and f.state = 'review' and f.course_id = i.entity_id
            where i.entity_type = 'course' and i.field_code = 'course_description_first_read' and i.status = 'pending' and jsonb_typeof(f.value->'sentences') = 'array'
              and coalesce(f.value->'subset_attempt'->>'stamp', '') <> v_stamp
            order by i.created_at, i.id limit v_cap loop
    if clock_timestamp() > v_dl then v_tb := true; exit; end if;
    v_looked := v_looked + 1; v_why := null;
    begin
      v_plan := security.cdesc_subset_plan_v1(r.course_id, r.provider_id, r.value);
      if not coalesce((v_plan->>'ok')::boolean, false) then v_why := coalesce(v_plan->>'rule', 'plan_failed');
      else
        v_sub := (v_plan->'subset') || jsonb_build_object('cause', r.cause, 'stamp', v_stamp, 'at', now());
        begin
          update pipeline.field_enrich_items set value = (value - 'subset_attempt') || jsonb_build_object('sentences', v_plan->'sentences', 'text', v_plan->>'text', 'check', v_plan->'check', 'subset_of_reading', v_sub) where id = r.rid and state = 'review';
          update pipeline.layer4_review_items set proposed_value = proposed_value || jsonb_build_object('description', v_plan->>'text', 'checks', v_plan->'check'->'checks',
                   'sentences', (select jsonb_agg(jsonb_build_object('text', x->>'text', 'quote', x->>'quote') order by o) from jsonb_array_elements(v_plan->'sentences') with ordinality e(x, o)),
                   'subset_of_reading', (v_sub - 'original') || jsonb_build_object('original_proposal', jsonb_build_object('description', r.proposed_value->>'description', 'sentences', r.proposed_value->'sentences')))
           where id = r.item_id and status = 'pending';
          v_adm := security.course_description_machine_admit_v1(r.item_id, 'subset_of_reading');
          if not coalesce((v_adm->>'ok')::boolean, false) then raise exception 'cdesc_subset:machine_%', coalesce(v_adm->>'rule', 'not_admitted'); end if;
          v_rec_b := v_rec_b + 1; v_by := jsonb_set(v_by, array[r.cause], to_jsonb(coalesce((v_by->>r.cause)::int, 0) + 1)); v_why := 'recovered';
        exception when others then
          get stacked diagnostics v_msg = message_text;
          v_why := case when v_msg like 'cdesc_subset:%' then substr(v_msg, length('cdesc_subset:') + 1) else 'error' end; -- rolled back: the item and its reading are as they were
        end;
      end if;
    exception when others then v_why := 'error';
    end;
    if v_why is distinct from 'recovered' then
      v_no := jsonb_set(v_no, array[v_why], to_jsonb(coalesce((v_no->>v_why)::int, 0) + 1));
      update pipeline.field_enrich_items set value = value || jsonb_build_object('subset_attempt', jsonb_build_object('stamp', v_stamp, 'result', v_why, 'at', now())) where id = r.rid and state = 'review';
    end if;
  end loop;
  return jsonb_build_object('on', true, 'looked_at', v_looked, 'recovered_held_readings', v_rec_a, 'recovered_waiting_items', v_rec_b, 'recovered_by_cause', v_by, 'not_recovered_by_reason', v_no, 'provider_places_full', v_full, 'time_box_reached', v_tb);
end $function$
