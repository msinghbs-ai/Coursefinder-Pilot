-- CF-247 AER: reads the AI provider refused are read again at the next run, not after the 30-day retry (Platform Admin 13 Nov 2026 07:54: "Credit updated at
-- openrouter. How does stalled jobs get requeued").
-- Evidence: from 12 Nov 2026 22:17 to 13 Nov 07:17 AEDT OpenRouter refused every call with HTTP 403 "Key limit exceeded (weekly limit)". 839 course-page reads
--   were recorded as failed and, under aer.schedule_retry_days (30), would not be read again until 12 Dec; 289 v2 trial reads spent their tries (aer.v2_shadow_tries).
--   The reads and the trial were paused at 07:40 (aer.schedule_daily_max 0, aer.v2_shadow_on 0, control event). The Platform Admin raised the key limit at 07:54.
-- Guards: G2 (the refusal pattern is a setting), G3 (no consumer API object), Decision 260; nothing deleted: the failed records stay as they are.
-- What:
--   1. Setting aer.retry_now_error_pattern: a failed read whose recorded reason matches it was refused by the AI provider (not read), so it does not wait
--      for the retry interval and does not count as a try.
--   2. security.aer_schedule_courses_v1 (md5-guarded): such a failed read does not hold its course back; the course is chosen again at the next run.
--   3. security.aer_v2_shadow_candidates_v1 (md5-guarded): such a result does not count towards aer.v2_shadow_tries.
--   4. Restored: aer.schedule_daily_max 0 -> 5000, aer.v2_shadow_on 0 -> 1 (the 07:40 pause); batch.aer_schedule_courses 100 -> 200 (the 839 are read again in
--      about five hourly runs; 22:05 "Fasten it up").
-- Live definitions this change edits (md5 of pg_get_functiondef, read 13 Nov 2026 08:00 AEDT): security.aer_schedule_courses_v1 c208bcd0c7695018bba0b63d9d797f4a;
--   security.aer_v2_shadow_candidates_v1 454a9271ddc5b436e56ca6056bbee5a8.
-- Replaces: nothing. Retires: nothing.

insert into pipeline.platform_toolset_settings(toolset_key, key, label, help, kind, value, unit, sort, section, used_by, reason) values
 ('pipeline', 'aer.retry_now_error_pattern', 'Entry requirements: AI refusals read again at once',
  'A read that failed with a recorded reason matching this pattern (case-insensitive) was refused by the AI provider, not read: it is read again at the next run and does not count as a try. Empty: no exception.',
  'text', to_jsonb('Key limit exceeded|Insufficient credits|requires more credits|HTTP 402'::text), 'pattern', 1147, 'Entry requirements',
  'security.aer_schedule_courses_v1, security.aer_v2_shadow_candidates_v1',
  'Platform Admin 13 Nov 2026 07:54: stalled reads requeued after the OpenRouter key limit (12 Nov 22:17 to 13 Nov 07:17)')
on conflict (toolset_key, key) do nothing;

create or replace function pg_temp.edit_n(p_sig text, p_md5 text, p_edits text[][], p_times int[]) returns void language plpgsql as $f$
declare v_def text := pg_get_functiondef(p_sig::regprocedure); i int; v_c int;
begin
  if md5(v_def) <> p_md5 then raise exception 'live % differs from the definition this change edits (md5 %)', p_sig, md5(v_def); end if;
  for i in 1 .. array_length(p_edits, 1) loop
    v_c := (length(v_def) - length(replace(v_def, p_edits[i][1], ''))) / length(p_edits[i][1]);
    if v_c <> p_times[i] then raise exception '%: edit % must apply exactly % times (found %)', p_sig, i, p_times[i], v_c; end if;
    v_def := replace(v_def, p_edits[i][1], p_edits[i][2]);
  end loop;
  execute v_def;
end $f$;

select pg_temp.edit_n('security.aer_schedule_courses_v1(integer,boolean)', 'c208bcd0c7695018bba0b63d9d797f4a', array[
  array[$o$security.pipeline_num_v1('aer.schedule_per_provider', 5) per),$o$,
        $n$security.pipeline_num_v1('aer.schedule_per_provider', 5) per,
                    coalesce(security.toolset_setting('pipeline', 'aer.retry_now_error_pattern') #>> '{}', '') refused),$n$],
  array[$o$(f.state in ('queued', 'waiting', 'ai', 'leased', 'review') or f.updated_at > now() - s.retry))$o$,
        $n$(f.state in ('queued', 'waiting', 'ai', 'leased', 'review')
                                  -- 13 Nov 2026: a read the AI provider refused (aer.retry_now_error_pattern) was not read, so it does not wait for the retry interval
                                  or (f.updated_at > now() - s.retry and not (f.state = 'failed' and s.refused <> '' and coalesce(f.reason, '') ~* s.refused))))$n$]
], array[1, 1]);

select pg_temp.edit_n('security.aer_v2_shadow_candidates_v1(text,integer)', '454a9271ddc5b436e56ca6056bbee5a8', array[
  array[$o$security.pipeline_num_v1('aer.v2_shadow_tries', 2) tries)$o$,
        $n$security.pipeline_num_v1('aer.v2_shadow_tries', 2) tries,
                            coalesce(security.toolset_setting('pipeline', 'aer.retry_now_error_pattern') #>> '{}', '') refused)$n$],
  array[$o$or count(*) >= cfg.tries$o$,
        $n$or count(*) filter (where r.error is null or cfg.refused = '' or r.error !~* cfg.refused) >= cfg.tries$n$]
], array[1, 1]);

do $r$
declare v_reason text := 'Platform Admin 13 Nov 2026 07:54: OpenRouter key limit raised; the 07:40 pause is lifted and refused reads are read again';
        r record; v_n int; v_done jsonb := '[]'::jsonb;
begin
  for r in select * from (values ('aer.schedule_daily_max', 0::numeric, 5000::numeric), ('aer.v2_shadow_on', 0, 1), ('batch.aer_schedule_courses', 100, 200)) v(key, from_v, to_v) loop
    update pipeline.platform_toolset_settings s set value = to_jsonb(r.to_v), reason = v_reason, updated_at = now()
     where s.toolset_key = 'pipeline' and s.key = r.key and (s.value #>> '{}')::numeric = r.from_v;
    get diagnostics v_n = row_count;
    v_done := v_done || jsonb_build_array(jsonb_build_object('key', r.key, 'from', r.from_v, 'to', r.to_v, 'applied', v_n = 1));
  end loop;
  insert into pipeline.admin_control_events(area, action, target, detail, actor)
  values ('toolsets', 'setting_change', 'AER course reads and v2 trial resumed', jsonb_build_object('reason', v_reason, 'settings', v_done), null);
end $r$;
