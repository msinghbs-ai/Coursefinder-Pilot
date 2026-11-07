-- Guards: Platform Admin mandate 7 Nov 2026 21:57 (a row-limit cut is not eligible for a corrected read until the university's row limit fits it).
-- Runs on the AER selector database (live rule b194475a loaded), BEFORE and AFTER 20261107130100.
\set ON_ERROR_STOP 1
set client_min_messages = notice;
create function pg_temp.ok(p boolean, p_what text) returns void language plpgsql as $f$
begin if p is distinct from true then raise exception 'FAIL: %', p_what; end if; end $f$;
create function pg_temp.cls(p uuid) returns text language sql as $f$ select security.aer_recovery_rule_v1(p)->>'class' $f$;
-- a live-shaped cut read: 6 rows kept, 4 cut (10 seen), RMIT-like university, cut under limit 6 (limit not recorded, as on pre-E13 items)
create temp table pick as select i.id, c.provider_id from pipeline.layer4_review_items i join pipeline.layer4_item_readiness x on x.item_id = i.id join catalogue.courses c on c.id = i.entity_id
  where i.status = 'pending' and i.field_code = 'course_entry_first_read' and security.aer_e13_class_v1(x.gate) = 'row_limit' and security.aer_route_v1(i.field_code, x.gate)->>'route' = 'row_limit' order by i.id limit 1;
update pipeline.layer4_review_items set proposed_value = proposed_value || '{"rows": 6}'::jsonb where id = (select id from pick);
update pipeline.layer4_item_readiness set gate = jsonb_set(gate, '{rows_cut}', '4') where item_id = (select id from pick);
-- the defect: a setting touched after the read (values unchanged) makes it eligible
insert into pipeline.platform_toolset_settings(toolset_key, key, label, kind, value, min_value, max_value, unit) values ('pipeline', 'entry.max_rows_per_course', 'rows', 'number', '6', 1, 10, 'rows')
  on conflict (toolset_key, key) do update set min_value = 1, max_value = 10;
update pipeline.platform_toolset_settings set updated_at = now() where key = 'entry.max_rows_by_provider';
do $t$ declare v_id uuid := (select id from pick); begin
  if current_setting('aerth.phase') = 'before' then
    perform pg_temp.ok(pg_temp.cls(v_id) = 'changed_conditions' and (security.aer_recovery_rule_v1(v_id)->>'eligible')::boolean, 'BEFORE: an untouched-value setting touch makes a 10-row read eligible at limit 6');
    raise notice 'PASS before: the live rule calls a cut read eligible although its limit is unchanged';
  else
    perform pg_temp.ok(pg_temp.cls(v_id) = 'row_limit' and not (security.aer_recovery_rule_v1(v_id)->>'eligible')::boolean, 'AFTER: still a row-limit hold at limit 6');
    perform pg_temp.ok((security.aer_recovery_rule_v1(v_id)->>'rows_needed')::int = 10 and security.aer_recovery_rule_v1(v_id)->>'authority' like 'a row limit of at least 10%', 'the authority line names the 10 rows needed');
    -- a limit that is higher but still short of 12 does not make it eligible
    update pipeline.platform_toolset_settings set value = to_jsonb(array[(select provider_id::text from pick) || '=9']) where key = 'entry.max_rows_by_provider';
    perform pg_temp.ok(pg_temp.cls(v_id) = 'row_limit', 'a limit of 9 is short of 10: still a row-limit hold');
    update pipeline.platform_toolset_settings set value = to_jsonb(array[(select provider_id::text from pick) || '=10']) where key = 'entry.max_rows_by_provider';
    perform pg_temp.ok(pg_temp.cls(v_id) = 'changed_conditions' and (security.aer_recovery_rule_v1(v_id)->>'eligible')::boolean, 'a limit of 10 fits the read: eligible by itself');
    -- live: entry.max_rows_per_course has range 1 to 10, and a university value outside the range is ignored (security.course_entry_max_rows_v1)
    update pipeline.platform_toolset_settings set value = to_jsonb(array[(select provider_id::text from pick) || '=12']) where key = 'entry.max_rows_by_provider';
    perform pg_temp.ok(security.course_entry_max_rows_v1((select provider_id from pick)) = 6, 'a university limit above the setting range (10) is ignored: the range must be raised first');
    update pipeline.platform_toolset_settings set value = '[]'::jsonb where key = 'entry.max_rows_by_provider';
    perform pg_temp.ok(pg_temp.cls(v_id) = 'row_limit', 'the limit removed: a row-limit hold again');
    raise notice 'PASS after: a cut read is eligible only when the row limit fits it';
  end if;
end $t$;
