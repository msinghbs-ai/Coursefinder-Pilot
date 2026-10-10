update storage.buckets
set allowed_mime_types = case
  when allowed_mime_types is null then array['application/vnd.openxmlformats-officedocument.spreadsheetml.sheet']::text[]
  when not ('application/vnd.openxmlformats-officedocument.spreadsheetml.sheet' = any(allowed_mime_types))
    then array_append(allowed_mime_types,'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet')
  else allowed_mime_types
end
where id='evidence';