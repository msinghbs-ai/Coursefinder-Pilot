-- CF-247 (23 Oct 2026). Platform Admin 19:27: "Lets test openrouter where it goes bottleneck, and make that settings configurable in ui
-- as well." The AI reader (Enrich fields) ran at most enrich.ai_calls_at_once (1 to 6) worker calls, each reading 3 pages at once
-- (fixed in the worker), so at most 18 requests reached OpenRouter together; nothing recorded rate limits or answer times.
-- 1 Settings (Settings › Pipeline settings, each with its range): enrich.ai_calls_at_once now 1 to 40; new enrich.ai_pages_at_once
--   (pages one AI reader call reads at once, 1 to 12, 3 as before); fees.concurrency now 1 to 16. Values are unchanged here; the load
--   test raises them step by step.
-- 2 security.enrich_ai_fire_v1 sends enrich.ai_pages_at_once to the worker (v0.43.0).
-- 3 Worker v0.43.0 returns, with each call, how its OpenRouter requests went (answered, rate-limited 429, server error, other, timed
--   out, answer times); public.admin_jobs_pulse sums the last 15 minutes for the Task manager (openrouter).
-- Replaces: nothing (security.enrich_ai_fire_v1 and public.admin_jobs_pulse edited in place, md5-guarded)
-- Retires: nothing

create or replace function pg_temp.edit_once(p_sig text, p_md5 text, p_edits text[][]) returns void language plpgsql as $f$
declare v_def text := pg_get_functiondef(p_sig::regprocedure); i int;
begin
  if md5(v_def) <> p_md5 then raise exception 'live % differs from the definition this change edits (md5 %)', p_sig, md5(v_def); end if;
  for i in 1 .. array_length(p_edits, 1) loop
    if (length(v_def) - length(replace(v_def, p_edits[i][1], ''))) / length(p_edits[i][1]) <> 1 then raise exception '%: edit % must apply exactly once', p_sig, i; end if;
    v_def := replace(v_def, p_edits[i][1], p_edits[i][2]);
  end loop;
  execute v_def;
end $f$;

-- 1 settings ---------------------------------------------------------------------------------------------------------------------------
update pipeline.platform_toolset_settings set max_value = '40', reason = 'Platform Admin 23 Oct 2026 19:27: test where OpenRouter becomes the bottleneck', updated_at = now(),
       help = 'AI reader (Enrich fields) worker calls running at the same time. Each call reads Enrich fields: AI pages at once pages together, so requests reaching OpenRouter at once = this × that. Watch the OpenRouter line on Scheduled jobs › Task manager: lower this when calls are rate-limited (429) or answers slow down.'
 where toolset_key = 'pipeline' and key = 'enrich.ai_calls_at_once';
insert into pipeline.platform_toolset_settings(toolset_key, key, label, help, kind, value, min_value, max_value, unit, sort, section, used_by, reason)
values ('pipeline', 'enrich.ai_pages_at_once', 'Enrich fields: AI pages at once',
        'Course pages one AI reader call reads with OpenRouter at the same time (it was 3, fixed in the worker). Requests reaching OpenRouter at once = this × Enrich fields: AI calls at once.',
        'number', '3'::jsonb, '1', '12', 'pages', 102, 'Job sizes', 'job admin-jobs (Enrich fields), worker coverage-sweep enrich_ai',
        'Platform Admin 23 Oct 2026 19:27: make that settings configurable in ui')
on conflict (toolset_key, key) do nothing;
update pipeline.platform_toolset_settings set max_value = '16', reason = 'Platform Admin 23 Oct 2026 19:27: test where OpenRouter becomes the bottleneck', updated_at = now()
 where toolset_key = 'pipeline' and key = 'fees.concurrency';
insert into pipeline.admin_control_events(area, action, target, detail, actor) values
 ('toolsets', 'setting', 'pipeline.enrich.ai_calls_at_once', jsonb_build_object('range_before', '1 to 6', 'range_after', '1 to 40', 'reason', 'Platform Admin 23 Oct 2026 19:27 (migration 20261023022000)'), '63ba56cb-48d4-4169-98c2-7c4d1f72925b'),
 ('toolsets', 'setting', 'pipeline.enrich.ai_pages_at_once', jsonb_build_object('added', true, 'value', 3, 'range', '1 to 12', 'reason', 'Platform Admin 23 Oct 2026 19:27 (migration 20261023022000)'), '63ba56cb-48d4-4169-98c2-7c4d1f72925b'),
 ('toolsets', 'setting', 'pipeline.fees.concurrency', jsonb_build_object('range_before', '1 to 8', 'range_after', '1 to 16', 'reason', 'Platform Admin 23 Oct 2026 19:27 (migration 20261023022000)'), '63ba56cb-48d4-4169-98c2-7c4d1f72925b');

-- 2 the worker is told how many pages to read at once ----------------------------------------------------------------------------------
select pg_temp.edit_once('security.enrich_ai_fire_v1()', 'bea52a45b124e3e9d9b3fd17cb92620a', array[
  array[$o$jsonb_build_object('mode', 'enrich_ai', 'limit', security.pipeline_num_v1('enrich.ai_items_per_call', 30)::int)$o$,
        $n$jsonb_build_object('mode', 'enrich_ai', 'limit', security.pipeline_num_v1('enrich.ai_items_per_call', 30)::int,
                                                                       'concurrency', security.pipeline_num_v1('enrich.ai_pages_at_once', 3)::int)$n$]]);

-- 3 OpenRouter in the Task manager pulse -----------------------------------------------------------------------------------------------
create or replace function security.jsonb_or_null_v1(p text) returns jsonb language plpgsql immutable set search_path to '' as $f$
begin return p::jsonb; exception when others then return null; end $f$;
revoke execute on function security.jsonb_or_null_v1(text) from public, anon, authenticated;

select pg_temp.edit_once('public.admin_jobs_pulse()', 'ce231f5687d6ecf2b5370f3c86716ca0', array[
  array[$o$    'jobs', coalesce((select jsonb_object_agg(o.id,$o$,
        $n$    -- 23 Oct 2026: how the AI readers' OpenRouter requests went in the last 15 minutes (worker v0.43.0 returns them with each call)
    'openrouter', (select jsonb_build_object('worker_calls', count(*), 'worker_open', count(*) filter (where r.id is null),
                          'worker_failed', count(*) filter (where r.id is not null and r.status_code is distinct from 200),
                          'calls', coalesce(sum((z.x->>'calls')::int), 0), 'ok', coalesce(sum((z.x->>'ok')::int), 0),
                          'http429', coalesce(sum((z.x->>'http429')::int), 0), 'http5xx', coalesce(sum((z.x->>'http5xx')::int), 0),
                          'timeout', coalesce(sum((z.x->>'timeout')::int), 0), 'other', coalesce(sum((z.x->>'other')::int), 0),
                          'ms_p50', (percentile_cont(0.5) within group (order by (z.x->>'ms_p50')::numeric))::int,
                          'ms_p95', max((z.x->>'ms_p95')::int))
                     from pipeline.edge_request_log l left join net._http_response r on r.id = l.request_id
                     cross join lateral (select security.jsonb_or_null_v1(r.content)->'openrouter' x) z
                    where l.function_name = 'coverage-sweep' and l.mode in ('enrich_ai', 'fee_ai') and l.created_at > now() - interval '15 minutes'),
    'jobs', coalesce((select jsonb_object_agg(o.id,$n$]]);

insert into pipeline.component_register(kind, name, layer, purpose, status, replaces, introduced_in) values
 ('function', 'security.jsonb_or_null_v1', 'Operations', 'Reads a worker answer as JSON, or nothing when it is not JSON', 'active', '{}', '20261023022000')
on conflict (kind, name) do nothing;

select 'AI reader limits are settings; OpenRouter results in the Task manager pulse' ok;
