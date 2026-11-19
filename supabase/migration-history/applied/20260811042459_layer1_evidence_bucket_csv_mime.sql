update storage.buckets
set allowed_mime_types = array[
  'application/pdf',
  'text/html',
  'text/plain',
  'text/csv',
  'application/json',
  'image/png',
  'image/jpeg'
]::text[]
where id = 'evidence';
