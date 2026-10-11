CREATE OR REPLACE FUNCTION security.provider_website_adopt_v1(p_provider_id uuid, p_url text)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_url text := btrim(coalesce(p_url, '')); v_dom text;
begin
  if v_url !~* '^https?://[^\s/]+\.[^\s]+$' or security.third_party_host_v1(v_url) then return false; end if;
  if exists (select 1 from pipeline.manual_locks l where l.entity = 'provider' and l.entity_id = p_provider_id and l.field = 'website') then return false; end if;
  update catalogue.providers set website = v_url, updated_at = now() where id = p_provider_id and nullif(btrim(website), '') is null;
  if not found then return false; end if;
  v_dom := lower(regexp_replace(substring(v_url from '^(?:https?://)?([^/:?#]+)'), '^www\.', ''));
  if v_dom ~ '^[a-z0-9.-]+\.[a-z]{2,}$' then
    insert into pipeline.course_link_recipes(provider_id, search_domain, patterns, active, notes, updated_at)
    select p_provider_id, v_dom,
           jsonb_build_array(jsonb_build_object(
             're', '(?i)^https?://([a-z0-9-]+\.)*' || regexp_replace(v_dom, '\.', '\\.', 'g')
                   || '/(?!.*\.(pdf|docx?|xlsx?|pptx?|jpe?g|png|gif|svg|zip)$)(?!(.*/)?(news|events?|blog|staff|people|media|search|tags?|category)(/|$)).+$',
             'rep', '\&')),
           true, 'Generic recipe: any page on the provider''s own site, from a website found and verified by search; used only when the reader proves the page is the course''s (CF-247, 11 Oct 2026)', now()
     where not exists (select 1 from pipeline.course_link_recipes x where x.provider_id = p_provider_id);
    insert into pipeline.course_link_search(course_id, provider_id, stage, state, queued_at)
    select c.id, c.provider_id, case when c.course_code ~ '^[0-9]{6}[0-9A-Z]$' then 'cricos' else 'title' end, 'queued', now()
      from catalogue.courses c
     where c.provider_id = p_provider_id and c.lifecycle_status = 'active'
       and exists (select 1 from pipeline.course_link_recipes x where x.provider_id = p_provider_id and x.active)
       and not exists (select 1 from pipeline.coverage_course_pages g where g.course_id = c.id)
    on conflict (course_id) do nothing;
  end if;
  insert into pipeline.provider_central_search(provider_id, state, requested_at) values (p_provider_id, 'queued', now())
  on conflict (provider_id) do update set state = 'queued', requested_at = now(), leased_until = null, updated_at = now() where pipeline.provider_central_search.state <> 'leased';
  return true;
end $function$
