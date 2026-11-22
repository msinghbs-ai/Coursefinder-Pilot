CREATE OR REPLACE FUNCTION security.controls_check_v1()
 RETURNS TABLE(jobname text, detail text)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  select j.jobname::text, left(j.command, 240)
    from cron.job j
   where j.active
     and (regexp_replace(regexp_replace(j.command, '(pipeline_num_v1|scholarship_setting|fc_setting_num_v1)\(''[^'']+'',\s*\d+(\.\d+)?\)', 'S', 'g'), '''[^'']*''', 'T', 'g')
            ~ '(\(|,)\s*\d+(\.\d+)?\s*(\)|,)'
          or j.command ~ '"\w+"\s*:\s*\d')
   order by 1
$function$
