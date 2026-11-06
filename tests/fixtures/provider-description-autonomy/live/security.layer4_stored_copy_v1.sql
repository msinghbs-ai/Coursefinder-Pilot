CREATE OR REPLACE FUNCTION security.layer4_stored_copy_v1(p_url text)
 RETURNS uuid
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
-- The newest stored copy of an address however it is written (http or https, with or without www., a trailing slash or a fragment).
  select e.id from pipeline.evidence_artifacts e
   where lower(e.source_url) = any (array(select s || h || security.layer4_url_key_v1(p_url) || t
                                           from unnest(array['https://', 'http://']) s, unnest(array['', 'www.']) h, unnest(array['', '/']) t))
     and security.layer4_url_key_v1(p_url) is not null
   order by e.captured_at desc nulls last, e.created_at desc limit 1
$function$

