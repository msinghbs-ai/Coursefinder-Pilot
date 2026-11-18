CREATE OR REPLACE FUNCTION security.course_description_machine_policy_stamp_v1()
 RETURNS text
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  -- a fingerprint of every setting the rule reads, so a declined item is looked at again when (and only when) the policy changes
  select md5('cdesc-machine-v2|' || coalesce(string_agg(s.key || '=' || s.value::text, '|' order by s.key), ''))
    from pipeline.platform_toolset_settings s
   where s.toolset_key = 'pipeline' and (s.key like 'enrich.course_description\_%' escape '\' and s.key <> 'enrich.course_description_machine_on'
         or s.key in ('pdesc.claim_words', 'pdesc.superlatives', 'pdesc.evidence_claim_words', 'pdesc.machine_refused_words', 'pdesc.machine_refused_words_fr', 'pdesc.machine_neutral_words',
                      'pdesc.machine_numbers_allowed', 'pdesc.founded_year_min', 'pdesc.support_min_share', 'pdesc.duplicate_share', 'gaps.recheck_days'))
$function$
