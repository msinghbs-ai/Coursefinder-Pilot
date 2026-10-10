-- CF-247 (Platform Admin, 1 Oct 2026 16:01 AEST: scale admitted data for production handover; Firecrawl, Supabase and
-- OpenRouter subscriptions raised). Course-link search (security.course_link_search_tick_v1) finds a course's own page
-- with a Firecrawl search on the provider's site ("<CRICOS code>" site:<domain>, then "<title>" site:<domain>). It ran
-- only for the 10 universities with a hand-written recipe and has finished them (1,400 pages found). 920 more Australian
-- providers with a website and CRICOS-coded courses have no recipe, so about 10,000 of their courses (no page found, or a
-- page that did not show the course's CRICOS code) were never searched.
-- This adds a generic recipe for each of them: any page on the provider's own site is a candidate, except files and
-- news, event, staff and search pages. The safeguard is unchanged: a candidate page is only used once the reader finds
-- the course's CRICOS code printed on it; otherwise the next candidate is tried, then the title search, then the course
-- is marked as not found. Generic recipes are marked in notes and can be switched off per provider (active = false).
-- Websites holding more than one address (6) are left out. The monthly search allowance rises from 15,000 to 50,000
-- Firecrawl credits, inside the 100,000-credit plan guard (svc_coverage_firecrawl stops all use at 2,000 remaining).
-- The courses are then queued for search. Hand-written recipes are not changed.

insert into pipeline.course_link_recipes(provider_id, search_domain, patterns, active, notes, updated_at)
select d.id, d.dom,
       jsonb_build_array(jsonb_build_object(
         're', '(?i)^https?://([a-z0-9-]+\.)*' || regexp_replace(d.dom, '([.-])', '\\\1', 'g')
               || '/(?!.*\.(pdf|docx?|xlsx?|pptx?|jpe?g|png|gif|svg|zip)$)(?!(.*/)?(news|events?|blog|staff|people|media|search|tags?|category)(/|$)).+$',
         'rep', '\&')),
       true, 'Generic recipe: any page on the provider''s own site; used only when the page shows the course''s CRICOS code (auto, 1 Oct 2026, CF-247)', now()
  from (select p.id, lower(regexp_replace(regexp_replace(btrim(p.website), '^(https?://)+', '', 'i'), '^www\.|[/:?#].*$', '', 'g')) dom
          from catalogue.providers p join ref.countries k on k.id = p.country_id
         where k.iso_alpha2 = 'AU' and nullif(btrim(p.website), '') is not null
           and exists (select 1 from catalogue.courses c where c.provider_id = p.id and c.lifecycle_status = 'active' and c.course_code ~ '^[0-9]{6}[0-9A-Z]$')) d
 where d.dom ~ '^[a-z0-9.-]+\.[a-z]{2,}$'
on conflict (provider_id) do nothing;

update pipeline.course_link_search_settings set monthly_credit_cap = 50000, updated_at = now() where id = 1;

select security.course_link_search_enqueue_v1(null);
