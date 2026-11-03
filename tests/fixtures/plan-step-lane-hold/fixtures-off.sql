-- With tasks.lane_hold_on off (as shipped), the edited definitions behave exactly as before.
select fx.ok(security.pipeline_num_v1('tasks.lane_hold_on', -1) = 0, 'off: tasks.lane_hold_on ships 0');
\ir fixtures-before.sql
