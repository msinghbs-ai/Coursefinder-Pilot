CREATE OR REPLACE FUNCTION public.admin_settings_register_read()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_rank int := security.current_role_rank();
begin
  if auth.uid() is null or coalesce(v_rank, 0) < 3 then raise exception 'assigned StudySearch role required' using errcode = '42501'; end if;
  return jsonb_build_object('can_manage', v_rank >= 6,
    'sections', (select coalesce(jsonb_agg(jsonb_build_object('section', z.section, 'settings', z.settings) order by z.first_sort), '[]'::jsonb)
                   from (select s.section, min(s.sort) first_sort,
                                jsonb_agg(jsonb_build_object('key', s.key, 'label', s.label, 'help', s.help, 'kind', s.kind, 'value', s.value, 'min', s.min_value, 'max', s.max_value,
                                          'unit', s.unit, 'used_by', s.used_by, 'reason', s.reason, 'updated_at', s.updated_at,
                                          'control_class', s.control_class,
                                          'replaced_by', (select r.replaced_by from pipeline.component_register r where r.name = s.toolset_key || '.' || s.key and r.status = 'retiring' limit 1)) order by s.sort, s.key) settings
                           from pipeline.platform_toolset_settings s where s.toolset_key = 'pipeline' group by s.section) z),
    'check', (select coalesce(jsonb_agg(jsonb_build_object('job', c.jobname, 'detail', c.detail)), '[]'::jsonb) from security.controls_check_v1() c),
    'jobs', (select count(*) from cron.job where active));
end $function$
