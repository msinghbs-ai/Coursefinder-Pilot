-- CF-089: align Parse.bot provider metadata with official Parse API quickstart.
update pipeline.layer2_acquisition_providers
set base_url='https://api.parse.bot',
    auth_scheme='header',
    auth_field_name='X-API-Key',
    request_template=jsonb_build_object(
      'integration_mode','generated_api',
      'dispatch_path','/dispatch',
      'task_status_path','/dispatch/tasks/{task_id}',
      'execution_path','/scraper/{scraper_id}/{endpoint_name}',
      'response_adapter','parsebot_generated_api',
      'configuration_required',true,
      'route_qualification_required',true,
      'docs_reference','https://docs.parse.bot/quickstart'
    ),
    change_control_ref='CF-CHG-20260903-089',
    updated_at=now()
where provider_key='parsebot';