-- CF-247 AER, RMIT row-limit recovery step 1 (Platform Admin directive 8 Nov 2026, item 1: "Approve engineering the permitted maximum for
-- entry.max_rows_per_course from 10 to 19, with the global operational value remaining 6.").
-- Guards: Platform Admin directive 8 Nov 2026 item 1, G2 (a range is setting metadata, the global value stays 6), G3 (no consumer API object is touched),
--   Decision 260 (housekeeping), Layer 4 admission authority kept (no read is approved or admitted by this change).
-- Why: RMIT University's waiting reads need 7 to 19 rows a course (measured 8 Nov 2026 in pipeline.aer_replay_checks: 16 need 7, 8 need 8, 10 need 9, 15 need 10,
--   6 need 11, 12 need 12, 7 need 13, 4 need 14, 3 need 16, 1 need 17, 1 need 19) while the range maximum was 10, so security.course_entry_max_rows_v1 ignored any
--   RMIT value above 10 and those reads stayed held. This migration only widens the allowed range. It sets no provider value: the RMIT-only override in
--   entry.max_rows_by_provider is a separate Admin settings action (the largest RMIT need is 19, the smallest limit that recovers every RMIT read), made after this is deployed.
-- Nothing else changes: the global value (6), every other provider, the E13 completeness checks and the D-R2 checks are untouched; a read that needs more rows than the
--   university's limit is still held, never cut.
-- Rollback: set max_value back to 10 (only while no provider value above 10 is set); the audit event keeps the values before.
-- Replaces: nothing
-- Retires: nothing

do $apply$
declare
  v_pa constant uuid := '63ba56cb-48d4-4169-98c2-7c4d1f72925b';
  v_before jsonb; v_n int;
begin
  select to_jsonb(s) - 'help' into v_before from pipeline.platform_toolset_settings s where s.toolset_key = 'pipeline' and s.key = 'entry.max_rows_per_course';
  if v_before is null then raise exception 'entry.max_rows_per_course not found; nothing changed'; end if;
  if (v_before->>'max_value')::numeric = 19 then return; end if;          -- already applied
  if (v_before->>'max_value')::numeric <> 10 or (v_before->'value') <> to_jsonb(6) then
    raise exception 'entry.max_rows_per_course is not (value 6, maximum 10): %; nothing changed', v_before;
  end if;
  update pipeline.platform_toolset_settings
     set max_value = 19, updated_by = v_pa, updated_at = now(),
         reason = 'CF-247 AER (Platform Admin directive 8 Nov 2026, item 1): the permitted maximum is 19 so RMIT can be given a provider limit that fits its longest requirement tables (up to 19 rows); the global value stays 6'
   where toolset_key = 'pipeline' and key = 'entry.max_rows_per_course' and max_value = 10 and value = to_jsonb(6);
  get diagnostics v_n = row_count;
  if v_n <> 1 then raise exception 'updated %, expected 1', v_n; end if;
  insert into pipeline.admin_control_events(area, action, target, detail, actor)
  values ('toolsets', 'setting', 'pipeline/entry.max_rows_per_course',
          jsonb_build_object('governance', 'Platform Admin directive 8 Nov 2026 item 1', 'change', 'range maximum 10 -> 19; value stays 6', 'before', v_before, 'migration', '20261108010000',
                             'reason', 'RMIT reads need 7 to 19 rows; the provider override is a separate Admin settings action'), v_pa);
end $apply$;
