update storage.buckets
set allowed_mime_types = array(select distinct x from unnest(coalesce(allowed_mime_types,'{}'::text[]) || array['application/zip']) x)
where id='evidence';
