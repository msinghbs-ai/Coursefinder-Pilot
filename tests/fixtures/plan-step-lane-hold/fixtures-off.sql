-- With tasks.lane_hold_on set off (0; it ships on), the edited definitions behave exactly as before.
update pipeline.platform_toolset_settings set value = '0' where toolset_key = 'pipeline' and key = 'tasks.lane_hold_on';
select fx.ok(security.pipeline_num_v1('tasks.lane_hold_on', -1) = 0, 'off: tasks.lane_hold_on set 0');
\ir fixtures-before.sql
