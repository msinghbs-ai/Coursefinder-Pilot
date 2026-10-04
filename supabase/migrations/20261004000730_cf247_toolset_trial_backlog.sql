-- CF-247 Decision 252: the backlog each trial purpose samples from (also used for the projection). Robots-disallowed pages are never included.
create or replace function security.toolset_trial_backlog(p_purpose text, p_country text) returns table (subject_key text, course_id uuid, provider_id uuid, input jsonb)
language sql stable security definer set search_path = '' as $f$
  select 'course:' || c.id, c.id, p.id,
         jsonb_build_object('course', coalesce(c.display_title, c.canonical_title), 'code', c.course_code, 'provider', coalesce(p.display_name, p.canonical_name),
                            'domain', regexp_replace(lower(substring(p.website from '^(?:https?://)?([^/?#]+)')), '^www\.', ''), 'country', k.name,
                            'earlier_candidate', pg.url, 'earlier_status', pg.status)
  from catalogue.courses c join catalogue.providers p on p.id = c.provider_id join ref.countries k on k.id = p.country_id
  left join pipeline.coverage_course_pages pg on pg.course_id = c.id
  where p_purpose = 'find_course_page' and k.iso_alpha2 = p_country and c.lifecycle_status = 'active'
    and p.website is not null and pg.status is distinct from 'bound'
  union all
  select 'provider:' || p.id, null, p.id,
         jsonb_build_object('provider', coalesce(p.display_name, p.canonical_name), 'city', coalesce(p.primary_city, ''), 'country', k.name)
  from catalogue.providers p join ref.countries k on k.id = p.country_id
  where p_purpose = 'find_provider_site' and k.iso_alpha2 = p_country and p.website is null
    and exists (select 1 from catalogue.courses c where c.provider_id = p.id and c.lifecycle_status = 'active')
  union all
  select 'page:' || pg.course_id, pg.course_id, pg.provider_id,
         jsonb_build_object('url', pg.url, 'course', coalesce(c.display_title, c.canonical_title), 'code', c.course_code, 'provider', coalesce(p.display_name, p.canonical_name),
                            'earlier_read', pg.read_status, 'earlier_http', pg.http_status)
  from pipeline.coverage_course_pages pg join catalogue.courses c on c.id = pg.course_id join catalogue.providers p on p.id = pg.provider_id join ref.countries k on k.id = p.country_id
  where p_purpose = 'render_page' and k.iso_alpha2 = p_country and c.lifecycle_status = 'active'
    and pg.read_status in ('needs_render', 'blocked') and pg.url is not null
$f$;
revoke all on function security.toolset_trial_backlog(text, text) from public, anon, authenticated;
