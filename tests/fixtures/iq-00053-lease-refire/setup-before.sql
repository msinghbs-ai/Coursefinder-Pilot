-- CF-247 IQ-00053: what the change reads and changes on the live system (8 Nov 2026), cut to the columns used: the worker request log and the HTTP answer
-- table (shapes as live), and the two pipeline settings (enrich.ai_calls_at_once 20 as set by the Platform Admin's load test on 23 Oct 2026).
create table if not exists pipeline.edge_request_log (slot int, request_id bigint, function_name text, mode text, created_at timestamptz default now());
create table if not exists net._http_response (id bigint primary key, status_code int, content text, timed_out boolean, error_msg text, created timestamptz default now());
insert into pipeline.platform_toolset_settings(toolset_key, key, label, help, kind, value, min_value, max_value, unit, sort, section, used_by, reason) values
 ('pipeline', 'enrich.ai_calls_at_once', 'AI calls at once', 'h', 'number', '20', 1, 40, 'calls', 1, 'Enrich fields', 'security.enrich_ai_fire_v1', 'OpenRouter load test step 3 (Platform Admin 19:27)'),
 ('pipeline', 'integration.hidden_error_window_minutes', 'Hidden error window', 'h', 'number', '120', 10, 1440, 'minutes', 2, 'Integration', 'security.integration_yield_checks_v1', 'fixture')
on conflict do nothing;
