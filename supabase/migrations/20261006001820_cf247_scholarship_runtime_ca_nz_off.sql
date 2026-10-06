insert into pipeline.scholarship_runtime_settings (country_code, enabled, detail_batch_limit, auto_dispatch, catalogue_refresh_hours, detail_refresh_hours, metadata)
values
  ('CA', false, 25, false, 168, 168, '{"route_mode":"managed","change_control_ref":"CF-247","international_only":true,"publication_authorised":false}'::jsonb),
  ('NZ', false, 25, false, 168, 168, '{"route_mode":"managed","change_control_ref":"CF-247","international_only":true,"publication_authorised":false}'::jsonb)
on conflict (country_code) do nothing;
