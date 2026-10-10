-- CF-247 (2 Oct 2026). Platform Admin, 21:18: "Extract all uni for Canada and nz from hotcourse as starting point if
-- required using firecrawl, save as evidence as off-line website in our evidence bucket." Decision (plan section 7):
-- third-party directories give hints and counts only; nothing from them is admitted.
-- coverage-sweep mode directory_capture stores each captured page (gzipped, evidence bucket thirdparty/<site>/<CC>/)
-- here with its links and plain text. Institutions found on the pages are kept in pipeline.directory_institutions with
-- the directory's own id, name, profile page and (when the profile shows it) the outbound website link and course count,
-- matched to our providers by exact normalised name within the country. A website hint is used only after our own
-- website rule passes on the institution's home page.
create table if not exists pipeline.directory_pages (
  id bigint generated always as identity primary key,
  site text not null,
  country_code text,
  url text not null,
  final_url text,
  http_status int,
  storage_path text,
  sha256 text,
  title text,
  links jsonb not null default '[]'::jsonb,
  page_text text,
  captured_at timestamptz not null default now()
);
create index if not exists directory_pages_site on pipeline.directory_pages(site, country_code, captured_at desc);
alter table pipeline.directory_pages enable row level security;
revoke all on pipeline.directory_pages from public, anon, authenticated;

create table if not exists pipeline.directory_institutions (
  site text not null,
  country_code text not null,
  directory_id text not null,
  name text,
  profile_url text not null,
  website_hint text,
  course_count_hint int,
  provider_id uuid,
  matched_by text,
  first_seen_page bigint,
  updated_at timestamptz not null default now(),
  primary key (site, country_code, directory_id)
);
alter table pipeline.directory_institutions enable row level security;
revoke all on pipeline.directory_institutions from public, anon, authenticated;

create or replace function public.svc_directory_page_record(p_site text, p_country text, p_url text, p_final_url text, p_http int, p_storage_path text,
  p_sha256 text, p_title text, p_links jsonb, p_text text)
returns bigint language plpgsql security definer set search_path to 'pg_catalog', 'pipeline' as $f$
declare v_id bigint;
begin
  if current_user <> 'postgres' and coalesce(auth.role(), '') <> 'service_role' then raise exception 'service_role required'; end if;
  insert into pipeline.directory_pages(site, country_code, url, final_url, http_status, storage_path, sha256, title, links, page_text)
  values (p_site, p_country, p_url, p_final_url, p_http, p_storage_path, p_sha256, left(p_title, 300), coalesce(p_links, '[]'::jsonb), left(p_text, 20000))
  returning id into v_id;
  -- Hotcourses institution profile links: /study/<country>/school-college-university/<slug>/<id>/international.html
  if p_site = 'hotcourses' then
    insert into pipeline.directory_institutions(site, country_code, directory_id, name, profile_url, first_seen_page)
    select distinct on (x.m[2]) 'hotcourses', p_country, x.m[2], initcap(replace(x.m[1], '-', ' ')), split_part(l, '#', 1), v_id
      from jsonb_array_elements_text(coalesce(p_links, '[]'::jsonb)) l
      cross join lateral (select regexp_match(l, '/study/[a-z-]+/school-college-university/([a-z0-9-]+)/([0-9]+)/international\.html') m) x
     where p_country is not null and x.m is not null
     order by x.m[2]
    on conflict (site, country_code, directory_id) do nothing;
  end if;
  return v_id;
end $f$;
revoke all on function public.svc_directory_page_record(text, text, text, text, int, text, text, text, jsonb, text) from public, anon, authenticated;
grant execute on function public.svc_directory_page_record(text, text, text, text, int, text, text, text, jsonb, text) to service_role;
