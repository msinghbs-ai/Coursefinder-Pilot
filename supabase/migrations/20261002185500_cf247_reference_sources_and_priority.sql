-- CF-247 (2 Oct 2026, 22:15 AEST). Platform Admin, 22:11: "Add this as a source as well: github.com/Hipo/university-
-- domains-list, univ.cc/world, xuanxiao.org/en/rankings. Do I get control to manually prioritise the uni or data
-- ingestion?"
-- 1. Sources (Decision 232: third-party lists are hints only; nothing from them is admitted):
--    - Hipo university-domains-list (MIT licence): institution names with their official web addresses, worldwide; read
--      from GitHub as a whole file, stored as evidence, used as website hints;
--    - univ.cc: a directory of university websites by country (no terms published; robots.txt respected); its links
--      are website hints;
--    - xuanxiao.org: its terms reserve text and data mining and forbid crawlers, scripts and bulk downloading
--      (sections 3-5), so it is recorded as a reference only and is NOT read by any job. Rankings stay with the
--      official QS and THE imports.
-- 2. Website hints are used only after our own website rule passes on the institution's home page (Australia: the
--    CRICOS provider code on the page; Canada: a .ca site naming the provider or printing its DLI number; New Zealand:
--    a .nz site naming the provider). A verified site is recorded through svc_coverage_site_record, as a searched site.
-- 3. Manual priority: the link matcher's queue now follows the priority list (Priority queue screen: a pinned course,
--    university, state or country first), as page reading already does.
insert into pipeline.sources(source_type, url, label, trust_rank, status, metadata)
select v.t, v.u, v.l, v.r, 'active', v.m::jsonb
  from (values
    ('dataset', 'https://github.com/Hipo/university-domains-list', 'Hipo university-domains-list (MIT) — institution websites, hints only', 80,
     '{"use":"website_hint","licence":"MIT","decision":"Decision 232","admitted":false}'),
    ('third_party_directory', 'https://univ.cc/world', 'univ.cc world universities directory — website hints only', 85,
     '{"use":"website_hint","terms":"none published; robots.txt respected","decision":"Decision 232","admitted":false}'),
    ('third_party_directory', 'https://xuanxiao.org/en/rankings', 'XuanXiao rankings archive — reference only, not read', 99,
     '{"use":"reference_only","read_by_jobs":false,"reason":"terms reserve text and data mining and forbid automated access (sections 3-5, https://xuanxiao.org/en/terms)","decision":"Decision 232"}')
  ) v(t, u, l, r, m)
 where not exists (select 1 from pipeline.sources s where s.url = v.u);

create or replace function security.institution_name_key(p text)
returns text language sql immutable as $f$
  select trim(regexp_replace(regexp_replace(lower(regexp_replace(coalesce(p, ''), '\s*\([^)]*\)', '', 'g')), '[^a-z0-9]+', ' ', 'g'), '^the ', ''))
$f$;

create table if not exists pipeline.reference_institutions (
  source text not null,
  country_code text not null,
  name text not null,
  state text,
  domains text[] not null default '{}',
  web_pages text[] not null default '{}',
  provider_id uuid,
  matched_by text,
  storage_path text,
  loaded_at timestamptz not null default now(),
  primary key (source, country_code, name)
);
alter table pipeline.reference_institutions enable row level security;
revoke all on pipeline.reference_institutions from public, anon, authenticated;

create or replace function public.svc_reference_institutions_load(p_source text, p_rows jsonb, p_storage_path text)
returns jsonb language plpgsql security definer set search_path to 'pg_catalog', 'catalogue', 'pipeline', 'security' as $f$
declare v_loaded int; v_matched int;
begin
  if current_user <> 'postgres' and coalesce(auth.role(), '') <> 'service_role' then raise exception 'service_role required'; end if;
  insert into pipeline.reference_institutions(source, country_code, name, state, domains, web_pages, storage_path)
  select distinct on (upper(r->>'alpha_two_code'), r->>'name') p_source, upper(r->>'alpha_two_code'), r->>'name', r->>'state-province',
         coalesce(array(select jsonb_array_elements_text(r->'domains')), '{}'), coalesce(array(select jsonb_array_elements_text(r->'web_pages')), '{}'), p_storage_path
    from jsonb_array_elements(p_rows) r
   where coalesce(r->>'name', '') <> '' and coalesce(r->>'alpha_two_code', '') ~ '^[A-Za-z]{2}$'
   order by upper(r->>'alpha_two_code'), r->>'name'
  on conflict (source, country_code, name) do update set state = excluded.state, domains = excluded.domains, web_pages = excluded.web_pages, storage_path = excluded.storage_path, loaded_at = now();
  get diagnostics v_loaded = row_count;
  with p as (select pr.id, k.iso_alpha2 cc, array[security.institution_name_key(coalesce(pr.display_name, pr.canonical_name)), security.institution_name_key(pr.canonical_name)] keys
               from catalogue.providers pr join ref.countries k on k.id = pr.country_id where pr.lifecycle_status = 'active'),
  m as (select r.source, r.country_code, r.name, (array_agg(p.id order by p.id))[1] pid, count(distinct p.id) n
          from pipeline.reference_institutions r join p on p.cc = r.country_code and security.institution_name_key(r.name) = any(p.keys)
         where r.source = p_source group by 1, 2, 3)
  update pipeline.reference_institutions r set provider_id = m.pid, matched_by = 'exact_name'
    from m where m.n = 1 and r.source = m.source and r.country_code = m.country_code and r.name = m.name and r.provider_id is distinct from m.pid;
  get diagnostics v_matched = row_count;
  return jsonb_build_object('loaded', v_loaded, 'matched', v_matched);
end $f$;
revoke all on function public.svc_reference_institutions_load(text, jsonb, text) from public, anon, authenticated;
grant execute on function public.svc_reference_institutions_load(text, jsonb, text) to service_role;

-- directory pages whose links are the institutions' own websites (univ.cc): link text = name, link = website hint
create or replace function public.svc_directory_anchor_hints(p_site text, p_country text, p_page_id bigint, p_page_url text, p_anchors jsonb)
returns jsonb language plpgsql security definer set search_path to 'pg_catalog', 'catalogue', 'pipeline', 'security' as $f$
declare v_n int;
begin
  if current_user <> 'postgres' and coalesce(auth.role(), '') <> 'service_role' then raise exception 'service_role required'; end if;
  insert into pipeline.directory_institutions(site, country_code, directory_id, name, profile_url, website_hint, first_seen_page)
  select distinct on (h) p_site, p_country, h, left(a->>'text', 200), p_page_url, a->>'href', p_page_id
    from jsonb_array_elements(coalesce(p_anchors, '[]'::jsonb)) a
    cross join lateral (select lower(regexp_replace(substring(a->>'href' from '^https?://([^/:?#]+)'), '^www\.', '')) h) x
   where p_country is not null and x.h is not null and length(coalesce(a->>'text', '')) >= 3
   order by h
  on conflict (site, country_code, directory_id) do update set name = excluded.name, website_hint = excluded.website_hint, updated_at = now();
  get diagnostics v_n = row_count;
  return jsonb_build_object('hints', v_n, 'match', security.directory_match_v1(p_site));
end $f$;
revoke all on function public.svc_directory_anchor_hints(text, text, bigint, text, jsonb) from public, anon, authenticated;
grant execute on function public.svc_directory_anchor_hints(text, text, bigint, text, jsonb) to service_role;

create table if not exists pipeline.site_hint_checks (
  provider_id uuid not null,
  url text not null,
  accepted boolean not null,
  basis text,
  evidence jsonb,
  checked_at timestamptz not null default now(),
  primary key (provider_id, url)
);
alter table pipeline.site_hint_checks enable row level security;
revoke all on pipeline.site_hint_checks from public, anon, authenticated;

-- providers with courses and no working website that have a website hint not yet checked
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
       and not exists (select 1 from pipeline.site_hint_checks c where c.provider_id = h.provider_id and c.url = h.url)
     group by 1 limit greatest(1, least(coalesce(p_limit, 20), 60)))
  select coalesce(jsonb_agg(jsonb_build_object('provider_id', t.provider_id, 'name', coalesce(pr.display_name, pr.canonical_name), 'country', security.coverage_country(t.provider_id),
           'cricos', (select i.identifier from catalogue.provider_identifiers i where i.provider_id = t.provider_id and i.scheme = 'cricos' limit 1),
           'dli', (select i.identifier from catalogue.provider_identifiers i where i.provider_id = t.provider_id and i.scheme = 'ircc_dli' limit 1),
           'urls', t.urls)), '[]'::jsonb)
    into v from todo t join catalogue.providers pr on pr.id = t.provider_id;
  return v;
end $f$;
revoke all on function public.svc_site_hint_next(int) from public, anon, authenticated;
grant execute on function public.svc_site_hint_next(int) to service_role;

create or replace function public.svc_site_hint_record(p_provider_id uuid, p_url text, p_accepted boolean, p_basis text, p_evidence jsonb)
returns text language plpgsql security definer set search_path to 'pg_catalog', 'pipeline', 'public' as $f$
begin
  if current_user <> 'postgres' and coalesce(auth.role(), '') <> 'service_role' then raise exception 'service_role required'; end if;
  insert into pipeline.site_hint_checks(provider_id, url, accepted, basis, evidence) values (p_provider_id, p_url, p_accepted, p_basis, p_evidence)
  on conflict (provider_id, url) do update set accepted = excluded.accepted, basis = excluded.basis, evidence = excluded.evidence, checked_at = now();
  if not p_accepted then return 'rejected'; end if;
  insert into pipeline.coverage_provider_discovery(provider_id, status, attempts, updated_at) values (p_provider_id, 'no_website', 0, now())
  on conflict (provider_id) do nothing;
  perform public.svc_coverage_site_record(p_provider_id, p_url, coalesce(p_evidence, '{}'::jsonb) || jsonb_build_object('basis', 'hint_' || coalesce(p_basis, 'verified')));
  return 'accepted';
end $f$;
revoke all on function public.svc_site_hint_record(uuid, text, boolean, text, jsonb) from public, anon, authenticated;
grant execute on function public.svc_site_hint_record(uuid, text, boolean, text, jsonb) to service_role;

-- 3. the link matcher's queue follows the priority list (pinned course first, then university rank, then oldest)
do $p$
begin
  if (select md5(prosrc) from pg_proc where oid = 'public.svc_coverage_ai_match_next(int)'::regprocedure) <> 'f55e52fe09e4e0eec93e7c4e2a32bc0f' then
    raise exception 'svc_coverage_ai_match_next changed since it was read';
  end if;
end $p$;
create or replace function public.svc_coverage_ai_match_next(p_limit int)
returns jsonb language plpgsql security definer set search_path to 'pg_catalog', 'catalogue', 'pipeline', 'security' as $f$
declare v jsonb;
begin
  if current_user <> 'postgres' and coalesce(auth.role(), '') <> 'service_role' then raise exception 'service_role required'; end if;
  with pick as (
    select q.id from pipeline.coverage_ai_match q
      left join pipeline.course_priority cp on cp.course_id = q.course_id
      left join pipeline.provider_priority pp on pp.provider_id = q.provider_id
     where q.state = 'ready' or (q.state = 'leased' and q.leased_until < now())
     order by (q.state = 'leased'), coalesce(cp.sort, 1000000), coalesce(pp.rank, 100000), q.id
     limit greatest(1, least(coalesce(p_limit, 20), 80)) for update of q skip locked),
  upd as (update pipeline.coverage_ai_match q set state = 'leased', leased_until = now() + interval '10 minutes' from pick where q.id = pick.id returning q.*)
  select coalesce(jsonb_agg(jsonb_build_object('id', u.id, 'course_id', u.course_id, 'provider_id', u.provider_id, 'title', co.canonical_title,
           'code', case when co.course_code ~ '^[0-9a-f]{8}-' then null else co.course_code end,
           'level', (select sl.name from ref.study_levels sl where sl.id = co.study_level_id),
           'provider', coalesce(pr.display_name, pr.canonical_name), 'country', security.coverage_country(u.provider_id),
           'candidates', u.candidates)), '[]'::jsonb)
    into v from upd u join catalogue.courses co on co.id = u.course_id join catalogue.providers pr on pr.id = u.provider_id;
  return v;
end $f$;
revoke all on function public.svc_coverage_ai_match_next(int) from public, anon, authenticated;
grant execute on function public.svc_coverage_ai_match_next(int) to service_role;
