-- CF-247 Layer 1 register: courses (AU) and providers (NZ) per background batch are settings (S2-Build, CRICOS 11 Nov 2026 edition apply).
-- Cause: CRICOS re-run 802d8928 got past the facts phase with 20 records per call, then layer1-au-depth returned HTTP 504: a batch of 500
-- courses, written into layer1-operations-control, now needs more calls than fit in one edge function request. The batch size per country is
-- now setting layer1.batch_courses_au (100) and layer1.batch_providers_nz (20, unchanged), read by layer1-operations-control v1.x through
-- public.svc_layer1_register_settings_v1 (layer1.* settings).
-- Replaces: the fixed batch sizes (500 AU courses, 20 NZ providers) in layer1-operations-control batchPlan (G2).
-- Retires: nothing.

insert into pipeline.platform_toolset_settings(toolset_key, key, label, help, kind, value, min_value, max_value, unit, sort, reason, section, used_by) values
 ('pipeline', 'layer1.batch_courses_au', 'Layer 1 register: Australian courses per background batch',
  'How many CRICOS courses one background batch of the Layer 1 run takes. Each batch must finish within one edge function request; lower it if a run stops with HTTP 504.',
  'number', to_jsonb(100), 20, 500, 'courses', 1202, 'CRICOS re-run 802d8928 (17 Nov 2026 19:18): a 500-course batch exceeded the edge request time limit', 'Layer 1 register',
  'layer1-operations-control (batchPlan, AU) and layer1-au-depth'),
 ('pipeline', 'layer1.batch_providers_nz', 'Layer 1 register: New Zealand providers per background batch',
  'How many NZQA providers one background batch of the Layer 1 run takes.',
  'number', to_jsonb(20), 5, 100, 'providers', 1203, 'Moved from code with the AU batch size (17 Nov 2026); value unchanged', 'Layer 1 register',
  'layer1-operations-control (batchPlan, NZ) and layer1-nz-live')
on conflict (toolset_key, key) do nothing;

do $$
begin
  if not ((select public.svc_layer1_register_settings_v1()) ?& array['layer1.batch_courses_au', 'layer1.batch_providers_nz', 'layer1.register_apply_chunk']) then
    raise exception 'post-check: layer1 batch settings';
  end if;
end $$;
