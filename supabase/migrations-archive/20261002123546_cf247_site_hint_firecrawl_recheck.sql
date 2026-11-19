-- CF-247 (2 Oct 2026, 22:45 AEST). Platform Admin: "For any reference website if direct access is not useful use firecrawl."
-- Worker v0.10.2 reads a hinted home page through Firecrawl (rendered, robots.txt respected) when the direct read is
-- refused or does not prove the site; the same rule decides (CRICOS provider code in Australia; national domain plus
-- name or DLI number in Canada and New Zealand). Hints rejected by the earlier workers (v0.10.0, v0.10.1), which had no
-- Firecrawl read, are offered once more. Patch behind an md5 guard.
do $g$
begin
  if (select md5(prosrc) from pg_proc where proname = 'svc_site_hint_next') is distinct from 'f743c419942bf42f9980042873b0335f' then
    raise exception 'svc_site_hint_next changed; not replacing';
  end if;
end $g$;

create or replace function public.svc_site_hint_next(p_limit int)
returns jsonb language plpgsql security definer set search_path to 'pg_catalog', 'catalogue', 'pipeline', 'security' as $f$
declare v jsonb;
begin
  if current_user <> 'postgres' and coalesce(auth.role(), '') <> 'service_role' then raise exception 'service_role required'; end if;
  with hints as (
    select r.provider_id, u url, 'hipo' via from pipeline.reference_institutions r, unnest(r.web_pages) u where r.provider_id is not null
    union select d.provider_id, d.website_hint, d.site from pipeline.directory_institutions d where d.provider_id is not null and d.website_hint is not null),
  todo as (
    select h.provider_id, jsonb_agg(distinct jsonb_build_object('url', h.url, 'via', h.via)) urls
      from hints h
      left join pipeline.coverage_provider_discovery d on d.provider_id = h.provider_id
     where (d.provider_id is null or d.status in ('no_website', 'failed') or d.website is null)
       and exists (select 1 from catalogue.courses co where co.provider_id = h.provider_id and co.lifecycle_status = 'active')
       and not exists (select 1 from pipeline.site_hint_checks c where c.provider_id = h.provider_id and c.url = h.url
                         and (c.accepted or coalesce(c.evidence->>'worker', '') not in ('coverage-sweep-worker-v0.10.0', 'coverage-sweep-worker-v0.10.1')))
     group by 1 limit greatest(1, least(coalesce(p_limit, 20), 60)))
  select coalesce(jsonb_agg(jsonb_build_object('provider_id', t.provider_id, 'name', coalesce(pr.display_name, pr.canonical_name), 'country', security.coverage_country(t.provider_id),
           'cricos', (select i.identifier from catalogue.provider_identifiers i where i.provider_id = t.provider_id and i.scheme = 'cricos' limit 1),
           'dli', (select i.identifier from catalogue.provider_identifiers i where i.provider_id = t.provider_id and i.scheme = 'ircc_dli' limit 1),
           'urls', t.urls)), '[]'::jsonb)
    into v from todo t join catalogue.providers pr on pr.id = t.provider_id;
  return v;
end $f$;
