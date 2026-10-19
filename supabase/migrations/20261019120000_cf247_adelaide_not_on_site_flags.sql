-- CF-247 (19 Oct 2026). Platform Admin 22:47, choice "Check CRICOS, keep with soft flag (Recommended)" for the 8 Adelaide University
-- courses whose re-find found no page on the new adelaide.edu.au site (7 found only unit pages; the Catholic Education certificate was
-- offered only the general Graduate Certificate in Education page, which the reader refused). CRICOS lists all 8 as active (checked 19 Oct
-- 2026), so they stay active with their old page and a soft not_on_provider_site flag for a person, as for Melbourne, Wollongong and
-- Torrens (Decision 265). If CRICOS drops a course, Layer 1 archives it as usual.
-- Replaces: nothing
-- Retires: nothing
-- Nothing dropped or deleted. Consumer API not touched (Decision 266).

insert into pipeline.enrichment_flags(entity, entity_key, provider_id, field, reason_code, reason, source, kind, state, raised_by_kind)
select 'course', c.id::text, c.provider_id, 'official_url', 'not_on_provider_site',
       format('CRICOS still lists %s (%s) as active, but the new Adelaide University site has no page for it (the re-find of 19 Oct 2026 found only unit pages or a different course). It keeps its old page; check whether it is still offered under this name.',
              c.canonical_title, c.course_code),
       'cf247-adelaide-refind', 'soft', 'raised', 'auto'
  from catalogue.courses c
 where c.id in ('538dd7f6-ba9e-4938-81c4-db6469599e38', 'a1ade33c-83ec-4b52-b64a-e01194f1eb86', '87c14dfa-9704-42bf-9303-ea28de35bd94',
                '4c678db2-ddfa-4c22-9a52-ba041b3c46e8', '0a7ed62b-4785-42cf-9540-066b233fc379', '6790cbbc-fe92-477a-9f92-0973e0f6c00e',
                '2c64a078-a7ed-4384-85dc-9a26ece93f7f', 'f44734c6-21c4-4540-81af-0ef323434432')
   and c.lifecycle_status = 'active'
   and exists (select 1 from catalogue.course_registrations r where r.course_id = c.id and r.scheme = 'cricos' and r.status = 'active')
on conflict (entity, entity_key, field, reason_code) do nothing;
