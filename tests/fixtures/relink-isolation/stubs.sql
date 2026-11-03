-- CF-247 SS-021 course-relink university isolation (migration 20261104240000) on isolated fixtures: the live shapes
-- security.course_relink_provider_v1 reads, beyond ../work-continuity/stubs.sql (which run.sh loads first). Columns as live (read-only,
-- 3 Nov 2026 22:17-22:30 AEDT). The address helpers are stand-ins with the live names (they are called, not edited);
-- course_relink_slugs_v1 sleeps for a title containing "Slow" so one university outlasts its time, as live. Scratch PostgreSQL only.

-- the work-continuity fixture's stand-in for the university step is replaced by the live definition (live/course_relink_provider_v1.sql)
drop function security.course_relink_provider_v1(uuid, integer);
alter table pipeline.coverage_course_pages add column if not exists candidates jsonb;
create table pipeline.coverage_provider_urls(provider_id uuid, url text, title text, primary key (provider_id, url));
create table pipeline.provider_discovery_links(provider_id uuid, url text, anchor_text text, primary key (provider_id, url));
create table pipeline.course_page_blocks(course_id uuid, url text);
create table pipeline.page_rejections(course_id uuid, url text);
create function security.coverage_country(p uuid) returns text language sql stable as $f$ select 'AU' $f$;
create table fx.binds(course_id uuid, provider_id uuid, url text, basis text, at timestamptz default clock_timestamp());
create function security.course_link_bind_v1(p_course uuid, p_provider uuid, p_url text, p_basis text) returns void language sql as
  $f$ insert into fx.binds(course_id, provider_id, url, basis) values (p_course, p_provider, p_url, p_basis) $f$;
create function security.course_relink_url_norm_v1(p_url text) returns text language sql immutable as
  $f$ select nullif(regexp_replace(regexp_replace(lower(btrim(coalesce(p_url, ''))), '^[a-z]+://(www\.)?', ''), '/+$', ''), '') $f$;
create function security.course_relink_url_seg_v1(p_url text) returns text language sql immutable as
  $f$ select regexp_replace(coalesce(substring(lower(coalesce(p_url, '')) from '/([^/?#]+)/?(?:[?#].*)?$'), ''), '\.(html?|aspx?|php)$', '') $f$;
create table fx.slugs_calls(n bigint);
insert into fx.slugs_calls values (0);
create function security.course_relink_slugs_v1(p_title text) returns text[] language plpgsql volatile as $f$
begin
  update fx.slugs_calls set n = n + 1;
  if p_title like '%Slow%' then perform pg_sleep(1.5); end if;  -- the deliberately slow university
  return array[regexp_replace(regexp_replace(lower(coalesce(p_title, '')), '[^a-z0-9]+', '-', 'g'), '(^-|-$)', '', 'g')];
end $f$;
create function security.course_relink_year_url_v1(p_url text) returns text language sql stable as $f$ select null::text $f$;
create function security.course_relink_stored_untried_v1(p_course uuid) returns text[] language sql stable as $f$ select '{}'::text[] $f$;
insert into pipeline.platform_toolset_settings(toolset_key, key, label, kind, value, min_value, max_value, unit, used_by) values
 ('pipeline', 'relink.slug_variants_on', 'Course re-linking: title forms', 'number', to_jsonb(1), 0, 1, 'on (1) or off (0)', 'security.course_relink_provider_v1'),
 ('pipeline', 'relink.pattern_min_pages', 'Course re-linking: pages that make an address form', 'number', to_jsonb(10), 1, 100, 'pages', 'security.course_relink_provider_v1')
on conflict do nothing;
