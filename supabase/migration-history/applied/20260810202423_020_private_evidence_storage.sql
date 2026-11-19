insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
values('evidence','evidence',false,52428800,array['application/pdf','text/html','text/plain','application/json','image/png','image/jpeg'])
on conflict(id) do update set public=false,file_size_limit=excluded.file_size_limit,allowed_mime_types=excluded.allowed_mime_types;

-- No anon/authenticated object policies are created intentionally. Evidence access is server-side only.
