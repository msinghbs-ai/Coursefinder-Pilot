CREATE OR REPLACE FUNCTION security.cdesc_recheck_held_v1()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare r record; v_stamp text := security.course_description_machine_policy_stamp_v1(); v_cap int := security.pipeline_num_v1('enrich.course_text_items_per_day', 500)::int; -- derived: never more in a run than the platform reads in a day
        v_days int := security.pipeline_num_v1('gaps.recheck_days', 60)::int; v_t0 timestamptz := clock_timestamp(); v_prov jsonb; v_chk jsonb; v_res text; v_looked int := 0; v_noprov int := 0; v_replayed int := 0; v_to_l4 int := 0; v_promoted int := 0; v_p uuid;
begin
  if security.pipeline_num_v1('enrich.course_description_machine_on', 0) < 1 then return jsonb_build_object('on', false); end if;
  -- (a) a reading held by a check is looked at again once for each policy stamp: where the live text check now passes and the reader is provable, the one record function takes it as the reader would have
  for r in select e.id, e.course_id, e.value, e.quote from pipeline.field_enrich_items e
            where e.field = 'description' and e.state = 'skipped' and e.reason like 'held: %' and e.course_id is not null and jsonb_typeof(e.value->'sentences') = 'array'
              and e.value->>'recheck_stamp' is distinct from v_stamp and e.updated_at > now() - make_interval(days => v_days)
            order by e.id limit v_cap loop
    exit when clock_timestamp() - v_t0 > make_interval(secs => 20); -- fixed: stays well inside the 120 s statement time-out of the job, with the settle and the follow-up that come after
    v_looked := v_looked + 1;
    begin
      v_prov := security.cdesc_reading_provenance_v1(r.id, r.value);
      v_chk := security.course_description_check_v1(r.course_id, r.value);
      if nullif(v_prov->>'model', '') is null or nullif(v_prov->>'prompt', '') is null then
        v_noprov := v_noprov + 1;
        update pipeline.field_enrich_items set value = value || jsonb_build_object('recheck_stamp', v_stamp) where id = r.id; -- noted; updated_at stays, so the queue's own timing is not moved
      elsif not coalesce((v_chk->>'ok')::boolean, false) then
        update pipeline.field_enrich_items set value = value || jsonb_build_object('recheck_stamp', v_stamp) where id = r.id;
      else
        v_res := security.enrich_course_text_record_v1(r.id, jsonb_build_object('value', r.value || jsonb_build_object('recheck_stamp', v_stamp), 'quote', r.quote,
                                                            'model', v_prov->>'model', 'prompt_version', v_prov->>'prompt', 'worker', v_prov->>'worker'));
        v_replayed := v_replayed + 1; if v_res = 'review' then v_to_l4 := v_to_l4 + 1; end if;
      end if;
    exception when others then null; -- one reading never stops the rest; it is looked at again on the next stamp
    end;
  end loop;
  -- (b) held first-admission readings take the places that are free (declined descriptions no longer fill them)
  for v_p in select distinct e.provider_id from pipeline.field_enrich_items e
              where e.field = 'description' and e.state = 'skipped' and e.reason like 'held\_first\_admission:%' and e.provider_id is not null order by 1 loop
    exit when clock_timestamp() - v_t0 > make_interval(secs => 25); -- fixed: with (a) it stays inside the time box above
    begin v_promoted := v_promoted + security.course_description_promote_held_v1(v_p); exception when others then null; end;
  end loop;
  return jsonb_build_object('on', true, 'looked_at', v_looked, 'no_provable_reader', v_noprov, 'replayed', v_replayed, 'to_layer4', v_to_l4, 'promoted_into_free_places', v_promoted);
end $function$
