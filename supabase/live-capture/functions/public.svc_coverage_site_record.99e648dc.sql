CREATE OR REPLACE FUNCTION public.svc_coverage_site_record(p_provider_id uuid, p_website text, p_evidence jsonb)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'pipeline'
AS $function$
declare v_dom text;
begin
  if current_user<>'postgres' and coalesce(auth.role(),'')<>'service_role' then raise exception 'service_role required'; end if;
  -- v2.15.232 (Fix 3): a course finder address entered by hand is kept; the search result is stored as evidence only
  if exists (select 1 from pipeline.manual_locks l where l.entity='provider' and l.entity_id=p_provider_id and l.field='course_finder')
     or exists (select 1 from pipeline.coverage_provider_discovery d where d.provider_id=p_provider_id and d.site_source='manual') then
    update pipeline.coverage_provider_discovery set site_searched_at=now(), leased_until=null, site_evidence=p_evidence, updated_at=now() where provider_id=p_provider_id;
    return;
  end if;
  update pipeline.coverage_provider_discovery set site_searched_at=now(), leased_until=null, site_evidence=p_evidence,
         website=coalesce(nullif(p_website,''),website), site_source=case when nullif(p_website,'') is not null then coalesce('search_verified_'||nullif(p_evidence->>'basis',''),'search_verified_cricos_code') else site_source end,
         status=case when nullif(p_website,'') is not null then 'pending' else status end, attempts=case when nullif(p_website,'') is not null then 0 else attempts end,
         updated_at=now()
   where provider_id=p_provider_id;
  -- Decision 220: a Canadian site gets the generic recipe for its own .ca domain, and its active courses with no
  -- candidate page are queued for the course-page search by title.
  if nullif(p_website,'') is not null and security.coverage_country(p_provider_id) = 'CA' then
    v_dom := lower(regexp_replace(substring(btrim(p_website) from '^(?:https?://)?([^/:?#]+)'), '^www\.', ''));
    if v_dom ~ '^[a-z0-9.-]+\.ca$' then
      insert into pipeline.course_link_recipes(provider_id, search_domain, patterns, active, notes, updated_at)
      select p_provider_id, v_dom,
             jsonb_build_array(jsonb_build_object(
               're', '(?i)^https?://([a-z0-9-]+\.)*' || regexp_replace(v_dom, '\.', '\\.', 'g')
                     || '/(?!.*\.(pdf|docx?|xlsx?|pptx?|jpe?g|png|gif|svg|zip)$)(?!(.*/)?(news|events?|blog|staff|people|media|search|tags?|category)(/|$)).+$',
               'rep', '\&')),
             true, 'Generic recipe: any page on the provider''s own site; used only when the reader proves the page is the course''s (CA, Decision 220, 2 Oct 2026)', now()
       where not exists (select 1 from pipeline.course_link_recipes x where x.provider_id = p_provider_id);
      insert into pipeline.course_link_search(course_id, provider_id, stage, state, queued_at)
      select c.id, c.provider_id, 'title', 'queued', now()
        from catalogue.courses c
       where c.provider_id = p_provider_id and c.lifecycle_status = 'active'
         and exists (select 1 from pipeline.course_link_recipes x where x.provider_id = p_provider_id and x.active)
         and not exists (select 1 from pipeline.coverage_course_pages g where g.course_id = c.id)
      on conflict (course_id) do nothing;
    end if;
  end if;
end $function$
