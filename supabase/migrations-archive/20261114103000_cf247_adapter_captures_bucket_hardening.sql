-- CF-247 storage housekeeping beside the pre-AI admission gate (Decision 278 bundle; ingestion validation report, storage findings).
-- 1. The adapter-captures bucket (private; full-page screenshots the adapter builder keeps for a draft, worker coverage-sweep mode adapter_capture)
--    had no MIME list and no size cap (live 14 Nov 2026: allowed_mime_types null, file_size_limit null). It now takes only images, up to 10 MiB:
--      allowed_mime_types = image/png, image/webp, image/jpeg; file_size_limit = 10485760 bytes.
--    Measured before this change (live 14 Nov 2026): 4,637 objects, 7.5 GB, every one image/png; the largest 10,460,119 bytes (under 10 MiB, over a
--    decimal 10 MB, so the cap is 10 MiB); 22 objects between 8 MB and 10 MB. Nothing stored is outside the new rule (guarded below). The limit applies
--    to new uploads only: the worker already names the type it uploads (the screenshot's own content-type, else image/png) and a refused upload keeps
--    the draft without its screenshot (shotPath = null), as for any failed upload today.
-- 2. A read-only audit of the evidence bucket's non-evidence prefixes, security.storage_prefix_audit_v1(): objects in evidence that are not page
--    copies registered in pipeline.evidence_artifacts. Measured 14 Nov 2026:
--      layer2/<CC>/firecrawl/search/  14,798 objects,  6.6 MB, Firecrawl search results (worker mode central/search runs), last written 2 Nov 2026,
--                                     referenced from pipeline.firecrawl_run_items.result->>'search_path';
--      layer2/<CC>/adapters/           4,039 objects, 287 MB, the pages the adapter builder captured, referenced from
--                                     pipeline.uni_adapter_drafts.captures[].html_path (screenshots: captures[].screenshot_path in adapter-captures);
--      layer2/<CC>/companion/            627 objects,  17 MB, course companion pages, referenced from pipeline.course_companion_pages.storage_path;
--    none of them is registered in pipeline.evidence_artifacts. The audit counts, per prefix, what its owner still references and what nothing
--    references; it moves and removes nothing (removal goes to the Platform Admin as a paste file, after hygiene.retire_after_days).
-- G1: no job.  G2: the bucket limit is Supabase Storage's own setting, enforced by Storage on upload, not a value the platform reads.  G3: no consumer
-- API object is read or changed.  Nothing is dropped or deleted.
-- Replaces: nothing (the bucket's open limits become a MIME list and a size cap).
-- Retires: nothing.

set local lock_timeout = '3s';

do $g$
begin
  if not exists (select 1 from storage.buckets where id = 'adapter-captures') then raise exception 'pre-check: bucket adapter-captures not found'; end if;
  -- nothing already stored may fall outside the new rule
  if exists (select 1 from storage.objects o where o.bucket_id = 'adapter-captures'
              and (coalesce(o.metadata->>'mimetype', '') not in ('image/png', 'image/webp', 'image/jpeg') or coalesce((o.metadata->>'size')::bigint, 0) > 10485760)) then
    raise exception 'pre-check: adapter-captures holds an object outside the new rule; measure it before restricting the bucket';
  end if;
end $g$;

update storage.buckets
   set allowed_mime_types = array['image/png', 'image/webp', 'image/jpeg'],
       file_size_limit = 10485760  -- fixed: Supabase Storage bucket cap (10 MiB), enforced by Storage itself on upload
 where id = 'adapter-captures';

create or replace function security.storage_prefix_audit_v1() returns table (
  bucket text, prefix text, owner text, objects bigint, bytes bigint, first_at timestamptz, last_at timestamptz, written_7d bigint,
  registered_evidence bigint, referenced bigint, unreferenced bigint)
language sql stable security definer set search_path = '' as $function$
  -- CF-247 storage housekeeping, read-only: the non-evidence prefixes of the evidence bucket and the adapter-captures bucket, what their owner still
  -- references and what nothing references. It moves and removes nothing.
  with o as (
    select x.bucket_id, x.name, coalesce((x.metadata->>'size')::bigint, 0) sz, x.created_at,
           case when x.bucket_id = 'adapter-captures' then 'adapter-captures/<provider>/<draft>/'
                when x.name ~ '^layer2/[A-Z]{2}/firecrawl/' then 'layer2/<CC>/firecrawl/'
                when x.name ~ '^layer2/[A-Z]{2}/adapters/' then 'layer2/<CC>/adapters/'
                when x.name ~ '^layer2/[A-Z]{2}/companion/' then 'layer2/<CC>/companion/' end fam
      from storage.objects x
     where x.bucket_id = 'adapter-captures' or (x.bucket_id = 'evidence' and x.name ~ '^layer2/[A-Z]{2}/(firecrawl|adapters|companion)/')),
  cap as (select c->>'html_path' html_path, c->>'screenshot_path' shot_path
            from pipeline.uni_adapter_drafts d, jsonb_array_elements(case when jsonb_typeof(d.captures) = 'array' then d.captures else '[]'::jsonb end) c),
  refs as (
    select 'layer2/<CC>/companion/' fam, p.storage_path path from pipeline.course_companion_pages p where p.storage_path is not null
    union select 'layer2/<CC>/adapters/', cap.html_path from cap where cap.html_path is not null
    union select 'adapter-captures/<provider>/<draft>/', cap.shot_path from cap where cap.shot_path is not null
    union select 'layer2/<CC>/firecrawl/', r.result->>'search_path' from pipeline.firecrawl_run_items r where r.result ? 'search_path')
  select o.bucket_id, o.fam,
         case o.fam when 'layer2/<CC>/firecrawl/' then 'Firecrawl search results: pipeline.firecrawl_run_items.result->>search_path'
                    when 'layer2/<CC>/adapters/' then 'adapter builder pages: pipeline.uni_adapter_drafts.captures[].html_path'
                    when 'layer2/<CC>/companion/' then 'course companion pages: pipeline.course_companion_pages.storage_path'
                    else 'adapter builder screenshots: pipeline.uni_adapter_drafts.captures[].screenshot_path' end,
         count(*), sum(o.sz)::bigint, min(o.created_at), max(o.created_at), count(*) filter (where o.created_at > now() - interval '7 days'),  -- fixed: report window
         count(*) filter (where exists (select 1 from pipeline.evidence_artifacts e where e.storage_path = o.name)),
         count(*) filter (where exists (select 1 from refs where refs.fam = o.fam and refs.path = o.name)),
         count(*) filter (where not exists (select 1 from refs where refs.fam = o.fam and refs.path = o.name))
    from o group by o.bucket_id, o.fam order by o.bucket_id, o.fam
$function$;
revoke all on function security.storage_prefix_audit_v1() from public, anon, authenticated;
grant execute on function security.storage_prefix_audit_v1() to service_role;

do $c$
begin
  if not exists (select 1 from storage.buckets where id = 'adapter-captures' and file_size_limit = 10485760
                  and allowed_mime_types @> array['image/png', 'image/webp', 'image/jpeg'] and cardinality(allowed_mime_types) = 3) then
    raise exception 'post-check: adapter-captures takes images only, up to 10 MiB';
  end if;
end $c$;
