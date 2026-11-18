-- CF-247 v2.15.240 (S3): scholarship coverage check (Platform Admin, 11 Oct 2026: "how do I make sure the scholarships published on the
-- platform are complete and correct ... present the mechanism in UI"; "all operational and configuration for scholarship should be
-- available in UI with full control, like Providers Adapters; keep it simple and modern").
-- Each provider is measured against its own scholarship listing page (Curtin's "International scholarships" lists 7):
--  1. pipeline.scholarship_listing_pages: a provider's listing pages (found automatically, suggested, or entered by a person); read
--     weekly by the worker (mode scholarship_listing), which keeps the scholarships the page names, each with its link.
--  2. Each listed scholarship is matched to our records (by its page address, else by its name without edition words).
--  3. pipeline.scholarship_coverage_checks: a Platform Admin signs a provider off; when the listing page changes it shows "Changed".
--  4. pipeline.scholarship_watch: providers checked first (the Platform Admin's list of 27, 11 Oct 2026).
--  5. admin_scholarship_coverage_read / _provider / _write: the Scholarships > Coverage screen.
--  6. Jobs and settings are registered with the scholarship layers, so they are switched and tuned on screen.
--  7. admin_archive_restore_bulk: bulk restore on Providers > Archived.
-- Nothing is dropped or deleted.

do $guard$
begin
  if to_regclass('pipeline.scholarship_listing_pages') is not null then raise exception 'pipeline.scholarship_listing_pages already exists'; end if;
  if to_regprocedure('security.scholarship_series_key_v1(text)') is null then raise exception 'needs v2.15.239 (security.scholarship_series_key_v1)'; end if;
end $guard$;

create table pipeline.scholarship_listing_pages (
  id bigint generated always as identity primary key,
  provider_id uuid not null references catalogue.providers(id),
  url text not null,
  url_norm text not null,
  source text not null check (source in ('auto', 'suggested', 'manual')),
  active boolean not null default true,
  status text not null default 'waiting' check (status in ('waiting', 'read', 'failed', 'suggested')),
  http_status integer,
  read_at timestamptz,
  next_read_at timestamptz default now(),
  items jsonb not null default '[]'::jsonb,
  item_hash text,
  error text,
  added_by uuid,
  added_at timestamptz not null default now(),
  unique (provider_id, url_norm)
);
alter table pipeline.scholarship_listing_pages enable row level security;
revoke all on pipeline.scholarship_listing_pages from public, anon, authenticated;

create table pipeline.scholarship_coverage_checks (
  provider_id uuid primary key references catalogue.providers(id),
  checked_by uuid,
  checked_at timestamptz not null default now(),
  item_hash text,
  note text
);
alter table pipeline.scholarship_coverage_checks enable row level security;
revoke all on pipeline.scholarship_coverage_checks from public, anon, authenticated;

create table pipeline.scholarship_watch (
  provider_id uuid primary key references catalogue.providers(id),
  active boolean not null default true,
  added_by uuid,
  added_at timestamptz not null default now(),
  note text
);
alter table pipeline.scholarship_watch enable row level security;
revoke all on pipeline.scholarship_watch from public, anon, authenticated;

-- Listing pages found automatically: an "international-scholarships" section that our scholarship pages sit under (or that was
-- found itself). A page that three or more of a provider's admitted scholarships sit under is suggested, for a person to confirm.
insert into pipeline.scholarship_listing_pages(provider_id, url, url_norm, source, active, status, next_read_at)
select provider_id, pre, security.scholarship_url_norm(pre), how, how = 'auto', case when how = 'auto' then 'waiting' else 'suggested' end, case when how = 'auto' then now() end
  from (select distinct on (provider_id, security.scholarship_url_norm(pre)) provider_id, pre, how from (
          select provider_id, substring(url from '^(https?://[^?#]*?/international[-_]scholarships)(?:[/?#]|$)') pre, 'auto' how, 1 n from pipeline.scholarship_page_candidates
          union all
          select provider_id, pre, 'suggested', count(*) from (select provider_id, regexp_replace(split_part(coalesce(final_url, url), '?', 1), '/[^/]+/?$', '') pre
                                                               from pipeline.scholarship_page_candidates where admit_status = 'admitted' and coalesce(final_url, url) !~ '\?') q
           group by 1, 2 having count(*) >= 3) z
         where pre is not null and pre ~* 'scholarship'
         order by provider_id, security.scholarship_url_norm(pre), (how = 'auto') desc) y
on conflict (provider_id, url_norm) do nothing;

-- The Platform Admin's list of 27 providers (11 Oct 2026), by CRICOS code
insert into pipeline.scholarship_watch(provider_id, note)
select distinct r.provider_id, 'Platform Admin list, 11 Oct 2026' from catalogue.provider_registrations r
 where lower(r.registration_scheme) = 'cricos' and upper(r.registration_code) in ('00301J','03567C','00586B','00300K','00117J','00213J','00017B','00212K','00115M','00111D','02475D','00124K','01545C','03245K','03389E','01241G','00003G','00109J','00098G','00002J','00099F','00917K','00004G','02426B','01328A','02664K','01259J')
on conflict (provider_id) do nothing;

-- Worker: listing pages due to be read
create or replace function public.svc_scholarship_listing_next(p_limit integer)
 returns jsonb
 language plpgsql
 security definer
 set search_path to ''
as $function$
declare v jsonb;
begin
  if current_user <> 'postgres' and coalesce(auth.role(), '') <> 'service_role' then raise exception 'service_role required'; end if;
  with pick as (
    select l.id from pipeline.scholarship_listing_pages l
     where l.active and l.source <> 'suggested' and coalesce(l.next_read_at, now()) <= now()
       and not exists (select 1 from security.provider_hidden_v1 h where h.provider_id = l.provider_id)
     order by l.next_read_at nulls first, l.id limit greatest(1, least(coalesce(p_limit, 6), 20)) for update skip locked),
  upd as (update pipeline.scholarship_listing_pages l set next_read_at = now() + interval '15 minutes' from pick where l.id = pick.id returning l.id, l.provider_id, l.url)
  select coalesce(jsonb_agg(jsonb_build_object('id', u.id, 'provider_id', u.provider_id, 'url', u.url,
           'hosts', (select to_jsonb(coalesce(d.allowed_hosts, '{}') || array[regexp_replace(lower(substring(coalesce(d.site_origin, d.website, '') from '^https?://([^/:?#]+)')), '^www\.', '')])
                       from pipeline.scholarship_discovery_providers d where d.provider_id = u.provider_id))), '[]'::jsonb) into v from upd u;
  return v;
end $function$;
revoke all on function public.svc_scholarship_listing_next(integer) from public, anon, authenticated;
grant execute on function public.svc_scholarship_listing_next(integer) to service_role;

-- Worker: what a listing page names
create or replace function public.svc_scholarship_listing_record(p_id bigint, p_status text, p_http_status integer, p_items jsonb, p_error text)
 returns jsonb
 language plpgsql
 security definer
 set search_path to ''
as $function$
declare v_items jsonb := case when jsonb_typeof(p_items) = 'array' then p_items else '[]'::jsonb end; v_hash text;
begin
  if current_user <> 'postgres' and coalesce(auth.role(), '') <> 'service_role' then raise exception 'service_role required'; end if;
  select md5(coalesce(string_agg(lower(btrim(e->>'name')), '|' order by lower(btrim(e->>'name'))), '')) into v_hash from jsonb_array_elements(v_items) e;
  update pipeline.scholarship_listing_pages
     set status = case when p_status = 'read' then 'read' else 'failed' end, http_status = p_http_status, read_at = now(), error = left(p_error, 300),
         items = case when p_status = 'read' then v_items else items end, item_hash = case when p_status = 'read' then v_hash else item_hash end,
         next_read_at = case when p_status = 'read' then now() + interval '7 days' else now() + interval '1 day' end
   where id = p_id;
  return jsonb_build_object('ok', true, 'items', jsonb_array_length(v_items));
end $function$;
revoke all on function public.svc_scholarship_listing_record(bigint, text, integer, jsonb, text) from public, anon, authenticated;
grant execute on function public.svc_scholarship_listing_record(bigint, text, integer, jsonb, text) to service_role;

-- Each listed scholarship matched to a record: by its page address, else by its name without edition words. Among several records,
-- the one that is published or can be published comes first.
create or replace function security.scholarship_listing_match_v1(p_provider_id uuid)
 returns table(listing_id bigint, item_name text, item_url text, scholarship_id uuid, matched_by text)
 language sql
 stable security definer
 set search_path to ''
as $function$
  with items as (
    select distinct on (lower(btrim(e->>'name'))) l.id listing_id, btrim(e->>'name') item_name, nullif(btrim(e->>'url'), '') item_url
      from pipeline.scholarship_listing_pages l, jsonb_array_elements(l.items) e
     where l.provider_id = p_provider_id and l.active and l.source <> 'suggested' and coalesce(btrim(e->>'name'), '') <> ''
     order by lower(btrim(e->>'name')), l.id),
  recs as (
    select s.id, s.name, s.publication_status, security.scholarship_series_key_v1(s.name) k,
           array_remove(array[security.scholarship_url_norm(s.source_url)]
             || array(select security.scholarship_url_norm(i.identifier_value) from scholarship.identifiers i where i.scholarship_id = s.id and i.scheme = 'first_party_detail_url')
             || array(select security.scholarship_url_norm(coalesce(sp.final_url, sp.url)) from pipeline.scholarship_pages sp where sp.scholarship_id = s.id)
             || array(select security.scholarship_url_norm(sp.url) from pipeline.scholarship_pages sp where sp.scholarship_id = s.id), null) urls
      from scholarship.scholarships s where s.provider_id = p_provider_id and s.lifecycle_status = 'active')
  select it.listing_id, it.item_name, it.item_url, m.id, m.how
    from items it
    left join lateral (
      select r.id, case when it.item_url is not null and security.scholarship_url_norm(it.item_url) = any(r.urls) then 'page' else 'name' end how
        from recs r
       where (it.item_url is not null and security.scholarship_url_norm(it.item_url) = any(r.urls))
          or r.k = security.scholarship_series_key_v1(it.item_name)
       order by (it.item_url is not null and security.scholarship_url_norm(it.item_url) = any(r.urls)) desc, (r.publication_status = 'published') desc, r.id
       limit 1) m on true
$function$;
revoke all on function security.scholarship_listing_match_v1(uuid) from public, anon, authenticated;

-- One provider's coverage row
create or replace function security.scholarship_coverage_row_v1(p_provider_id uuid)
 returns jsonb
 language sql
 stable security definer
 set search_path to ''
as $function$
  with m as (select * from security.scholarship_listing_match_v1(p_provider_id)),
  recs as (select s.id, s.publication_status, s.source_url from scholarship.scholarships s where s.provider_id = p_provider_id and s.lifecycle_status = 'active'),
  lp as (select * from pipeline.scholarship_listing_pages l where l.provider_id = p_provider_id and l.active),
  chk as (select c.* from pipeline.scholarship_coverage_checks c where c.provider_id = p_provider_id),
  h as (select md5(coalesce(string_agg(lower(item_name), '|' order by lower(item_name)), '')) v from m)
  select jsonb_build_object(
    'provider_id', p.id, 'name', coalesce(p.display_name, p.canonical_name), 'country', (select k.iso_alpha2 from ref.countries k where k.id = p.country_id),
    'watch', exists (select 1 from pipeline.scholarship_watch w where w.provider_id = p.id and w.active),
    'listing_pages', (select count(*) from lp where lp.source <> 'suggested'),
    'suggested_pages', (select count(*) from lp where lp.source = 'suggested'),
    'listing_read_at', (select max(lp.read_at) from lp where lp.source <> 'suggested'),
    'listed', (select count(*) from m),
    'found', (select count(*) from m where m.scholarship_id is not null),
    'published', (select count(*) from m join recs r on r.id = m.scholarship_id where r.publication_status = 'published'),
    'missing', (select count(*) from m where m.scholarship_id is null),
    'records', (select count(*) from recs),
    'records_published', (select count(*) from recs where publication_status = 'published'),
    'extra', (select count(*) from recs r where not exists (select 1 from m where m.scholarship_id = r.id)),
    'study_australia', (select count(*) from recs r where security.reference_url_has_use(coalesce(r.source_url, ''), 'scholarship_placeholder')),
    'checked_at', (select checked_at from chk), 'checked_by', (select u.email from chk join auth.users u on u.id = chk.checked_by),
    'state', case when not exists (select 1 from lp where lp.source <> 'suggested') then 'no_listing'
                  when not exists (select 1 from lp where lp.status = 'read') then 'waiting'
                  when not exists (select 1 from chk) then 'to_check'
                  when (select item_hash from chk) is distinct from (select v from h) then 'changed'
                  else 'checked' end)
  from catalogue.providers p where p.id = p_provider_id
$function$;
revoke all on function security.scholarship_coverage_row_v1(uuid) from public, anon, authenticated;

-- The screen: one row per provider (watch list, or every provider with scholarships or a listing page)
create or replace function public.admin_scholarship_coverage_read(p_scope text default 'watch', p_query text default null, p_limit integer default 100, p_offset integer default 0)
 returns jsonb
 language plpgsql
 stable security definer
 set search_path to ''
as $function$
declare v_rank int := security.current_role_rank(); v_q text := nullif(btrim(coalesce(p_query, '')), ''); v_rows jsonb; v_total int;
begin
  if auth.uid() is null or v_rank < 3 then raise exception 'Curator role or above required' using errcode = '42501'; end if;
  with ids as (
    select p.id, coalesce(p.display_name, p.canonical_name) n from catalogue.providers p
     where p.lifecycle_status = 'active'
       and (case when coalesce(p_scope, 'watch') = 'watch' then exists (select 1 from pipeline.scholarship_watch w where w.provider_id = p.id and w.active)
                 else exists (select 1 from scholarship.scholarships s where s.provider_id = p.id and s.lifecycle_status = 'active')
                   or exists (select 1 from pipeline.scholarship_listing_pages l where l.provider_id = p.id and l.active)
                   or exists (select 1 from pipeline.scholarship_watch w where w.provider_id = p.id and w.active) end)
       and (v_q is null or p.canonical_name ilike '%' || v_q || '%' or p.display_name ilike '%' || v_q || '%'))
  select (select count(*) from ids), coalesce(jsonb_agg(security.scholarship_coverage_row_v1(x.id) order by x.n), '[]'::jsonb)
    into v_total, v_rows from (select * from ids order by n limit greatest(1, least(coalesce(p_limit, 100), 300)) offset greatest(0, coalesce(p_offset, 0))) x;
  return jsonb_build_object('scope', coalesce(p_scope, 'watch'), 'total', v_total, 'rows', v_rows, 'can_manage', v_rank >= 6, 'can_watch', v_rank >= 5,
    'auto_publish', jsonb_build_object('on', security.scholarship_setting('auto_publish', 0) >= 1,
      'recent', (select coalesce(jsonb_agg(jsonb_build_object('id', s.id, 'name', s.name, 'provider', coalesce(p.display_name, p.canonical_name), 'at', b.created_at,
                    'status', s.publication_status, 'value', s.award_value_text, 'courses', (select count(*) from scholarship.course_mappings cm where cm.scholarship_id = s.id and cm.mapping_state = 'mapped'))
                    order by b.created_at desc, s.name), '[]'::jsonb)
                   from pipeline.scholarship_publication_batches b cross join lateral unnest(b.scholarship_ids) sid
                   join scholarship.scholarships s on s.id = sid join catalogue.providers p on p.id = s.provider_id
                  where b.kind = 'publish' and b.approval_ref like 'auto-publish%' and b.created_at > now() - interval '3 days')),
    'totals', jsonb_build_object(
      'watch', (select count(*) from pipeline.scholarship_watch w where w.active),
      'with_listing', (select count(distinct l.provider_id) from pipeline.scholarship_listing_pages l where l.active and l.source <> 'suggested'),
      'suggested', (select count(distinct l.provider_id) from pipeline.scholarship_listing_pages l where l.source = 'suggested' and not exists (select 1 from pipeline.scholarship_listing_pages a where a.provider_id = l.provider_id and a.active and a.source <> 'suggested')),
      'checked', (select count(*) from pipeline.scholarship_coverage_checks),
      'active', (select count(*) from scholarship.scholarships where lifecycle_status = 'active'),
      'published', (select count(*) from scholarship.scholarships where lifecycle_status = 'active' and publication_status = 'published')));
end $function$;
revoke all on function public.admin_scholarship_coverage_read(text, text, integer, integer) from public, anon;
grant execute on function public.admin_scholarship_coverage_read(text, text, integer, integer) to authenticated;

-- One provider: each listed scholarship beside our record, then our other records
create or replace function public.admin_scholarship_coverage_provider(p_provider_id uuid)
 returns jsonb
 language plpgsql
 stable security definer
 set search_path to ''
as $function$
declare v_rank int := security.current_role_rank();
begin
  if auth.uid() is null or v_rank < 3 then raise exception 'Curator role or above required' using errcode = '42501'; end if;
  return (with m as (select * from security.scholarship_listing_match_v1(p_provider_id)),
  pub as (select * from security.scholarship_publishability_v1() x where x.scholarship_id in (select s.id from scholarship.scholarships s where s.provider_id = p_provider_id)),
  rec as (
    select s.id, jsonb_build_object('id', s.id, 'name', s.name, 'status', s.publication_status, 'audience', s.audience, 'source_url', s.source_url,
      'value_type', s.award_value_type, 'percentage', s.award_percentage, 'amount', s.award_amount, 'currency', s.award_currency_code, 'value_text', s.award_value_text,
      'value_is_maximum', s.award_value_is_maximum, 'closes', s.application_close_date,
      'study_australia', security.reference_url_has_use(coalesce(s.source_url, ''), 'scholarship_placeholder'),
      'courses', (select count(*) from scholarship.course_mappings cm where cm.scholarship_id = s.id and cm.mapping_state = 'mapped'),
      'levels', (select coalesce(jsonb_agg(distinct sl.name), '[]'::jsonb) from scholarship.course_mappings cm join catalogue.courses c on c.id = cm.course_id
                   join ref.study_levels sl on sl.id = c.study_level_id where cm.scholarship_id = s.id and cm.mapping_state = 'mapped'),
      'all_courses', exists (select 1 from pipeline.scholarship_pages sp where sp.scholarship_id = s.id and sp.apply_result->'changes' ? 'course_links_all'),
      'publishable', coalesce((select x.publishable from pub x where x.scholarship_id = s.id), false),
      'reasons', coalesce((select to_jsonb(x.missing) from pub x where x.scholarship_id = s.id), '[]'::jsonb),
      'held', exists (select 1 from pipeline.scholarship_publication_holds h where h.scholarship_id = s.id and h.released_at is null)) j
      from scholarship.scholarships s where s.provider_id = p_provider_id and s.lifecycle_status = 'active')
  select jsonb_build_object(
    'row', security.scholarship_coverage_row_v1(p_provider_id),
    'listing_pages', (select coalesce(jsonb_agg(jsonb_build_object('id', l.id, 'url', l.url, 'source', l.source, 'status', l.status, 'read_at', l.read_at, 'items', jsonb_array_length(l.items), 'error', l.error) order by (l.source = 'suggested'), l.id), '[]'::jsonb)
                        from pipeline.scholarship_listing_pages l where l.provider_id = p_provider_id and l.active),
    'listed', (select coalesce(jsonb_agg(jsonb_build_object('name', m.item_name, 'url', m.item_url, 'matched_by', m.matched_by, 'record', r.j) order by (m.scholarship_id is null) desc, m.item_name), '[]'::jsonb)
                 from m left join rec r on r.id = m.scholarship_id),
    'extra', (select coalesce(jsonb_agg(r.j order by (r.j->>'status') = 'published' desc, r.j->>'name'), '[]'::jsonb) from rec r where not exists (select 1 from m where m.scholarship_id = r.id)),
    'can_manage', v_rank >= 6));
end $function$;
revoke all on function public.admin_scholarship_coverage_provider(uuid) from public, anon;
grant execute on function public.admin_scholarship_coverage_provider(uuid) to authenticated;

-- Actions. Listing pages, sign-off, read now and publishing: Platform Admin. The watch list: PIM Operator and above. No reason asked;
-- every action is logged in admin_control_events.
create or replace function public.admin_scholarship_coverage_write(p_action text, p_args jsonb default '{}'::jsonb)
 returns jsonb
 language plpgsql
 security definer
 set search_path to ''
as $function$
declare v_rank int := security.current_role_rank(); v_pid uuid := nullif(p_args->>'provider_id', '')::uuid; v_sid uuid := nullif(p_args->>'scholarship_id', '')::uuid;
        v_url text := btrim(coalesce(p_args->>'url', '')); v_id bigint := nullif(p_args->>'id', '')::bigint; v_res jsonb; v_hash text;
begin
  if auth.uid() is null or v_rank < 5 then raise exception 'PIM Operator role or above required' using errcode = '42501'; end if;
  if p_action not in ('watch', 'unwatch') and v_rank < 6 then raise exception 'Platform Admin role required' using errcode = '42501'; end if;
  if p_action = 'add_listing' then
    if v_url !~* '^https?://[^\s/]+\.[^\s]+$' then raise exception 'enter a full web address starting with https://'; end if;
    if not security.url_on_provider_sites(v_url, v_pid) then raise exception 'this page is not on the provider''s own website'; end if;
    insert into pipeline.scholarship_listing_pages(provider_id, url, url_norm, source, active, status, next_read_at, added_by)
    values (v_pid, v_url, security.scholarship_url_norm(v_url), 'manual', true, 'waiting', now(), auth.uid())
    on conflict (provider_id, url_norm) do update set active = true, source = case when pipeline.scholarship_listing_pages.source = 'suggested' then 'manual' else pipeline.scholarship_listing_pages.source end,
       status = case when pipeline.scholarship_listing_pages.status = 'suggested' then 'waiting' else pipeline.scholarship_listing_pages.status end, next_read_at = now(), added_by = auth.uid();
  elsif p_action = 'use_suggested' then
    update pipeline.scholarship_listing_pages set source = 'manual', status = 'waiting', active = true, next_read_at = now(), added_by = auth.uid() where id = v_id and source = 'suggested';
    select provider_id into v_pid from pipeline.scholarship_listing_pages where id = v_id;
  elsif p_action = 'remove_listing' then
    update pipeline.scholarship_listing_pages set active = false where id = v_id returning provider_id into v_pid;
  elsif p_action = 'read_now' then
    update pipeline.scholarship_listing_pages set next_read_at = now() where provider_id = v_pid and active and source <> 'suggested';
    update pipeline.scholarship_pages sp set next_read_at = now() from scholarship.scholarships s where s.id = sp.scholarship_id and s.provider_id = v_pid and s.lifecycle_status = 'active';
  elsif p_action = 'sign_off' then
    select md5(coalesce(string_agg(lower(item_name), '|' order by lower(item_name)), '')) into v_hash from security.scholarship_listing_match_v1(v_pid);
    insert into pipeline.scholarship_coverage_checks(provider_id, checked_by, checked_at, item_hash, note) values (v_pid, auth.uid(), now(), v_hash, left(p_args->>'note', 300))
    on conflict (provider_id) do update set checked_by = auth.uid(), checked_at = now(), item_hash = excluded.item_hash, note = excluded.note;
  elsif p_action = 'watch' then
    insert into pipeline.scholarship_watch(provider_id, added_by) values (v_pid, auth.uid()) on conflict (provider_id) do update set active = true, added_by = auth.uid(), added_at = now();
  elsif p_action = 'unwatch' then
    update pipeline.scholarship_watch set active = false where provider_id = v_pid;
  elsif p_action = 'publish' then
    select provider_id into v_pid from scholarship.scholarships where id = v_sid;
    if not coalesce((select x.publishable from security.scholarship_publishability_v1() x where x.scholarship_id = v_sid), false) then
      raise exception 'this scholarship does not pass every check yet; see its reasons'; end if;
    update scholarship.scholarships set publication_status = 'published', updated_at = now() where id = v_sid and publication_status <> 'published';
    insert into pipeline.scholarship_publication_batches(kind, approval_ref, scholarship_ids) values ('publish', 'coverage check: published by hand', array[v_sid]);
  elsif p_action = 'hold' then
    -- withdraws it if published, and keeps it from automatic publishing until released
    select provider_id into v_pid from scholarship.scholarships where id = v_sid;
    insert into pipeline.scholarship_publication_holds(scholarship_id, reason, held_by) values (v_sid, coalesce(nullif(btrim(p_args->>'reason'), ''), 'Held on the coverage check'), 'admin')
    on conflict (scholarship_id) do update set reason = excluded.reason, held_by = 'admin', held_at = now(), released_at = null, release_note = null;
    update scholarship.scholarships set publication_status = 'withdrawn', updated_at = now() where id = v_sid and publication_status = 'published';
  elsif p_action = 'release' then
    select provider_id into v_pid from scholarship.scholarships where id = v_sid;
    update pipeline.scholarship_publication_holds set released_at = now(), release_note = 'released on the coverage check' where scholarship_id = v_sid and released_at is null;
  elsif p_action = 'confirm_international' then
    select provider_id into v_pid from scholarship.scholarships where id = v_sid;
    insert into scholarship.criteria(scholarship_id, criterion_type, operator, value_codes, value_json, human_text, is_mandatory, machine_evaluable, status, confidence)
    values (v_sid, 'student_type', 'in', array['international'], jsonb_build_object('by', 'person', 'actor', auth.uid(), 'basis', 'listed on the provider''s international scholarships page'),
            left(coalesce(nullif(btrim(p_args->>'note'), ''), 'Listed on the provider''s international scholarships page'), 300), true, true, 'active', 1);
    update scholarship.scholarships set audience = case when audience ~* 'domestic' then 'international_and_domestic' else 'international' end, updated_at = now() where id = v_sid and coalesce(audience, '') !~* 'international';
  else
    raise exception 'unknown action %', p_action;
  end if;
  insert into pipeline.admin_control_events(area, action, target, detail, actor) values ('scholarship_coverage', p_action, coalesce(v_sid::text, v_pid::text, v_id::text), p_args, auth.uid());
  if v_pid is null then return jsonb_build_object('ok', true); end if;
  return public.admin_scholarship_coverage_provider(v_pid);
end $function$;
revoke all on function public.admin_scholarship_coverage_write(text, jsonb) from public, anon;
grant execute on function public.admin_scholarship_coverage_write(text, jsonb) to authenticated;

-- Jobs and settings, on the scholarship layer screens
insert into pipeline.scholarship_layer_settings(key, layer, label, help, value, min_value, max_value, unit, updated_at, reason)
values ('listing_limit', 2, 'Listing pages read per run', 'How many providers'' scholarship listing pages are read each time (every 15 minutes). Each is read again weekly.', 6, 1, 20, 'pages', now(), 'CF-247 v2.15.240 coverage check')
on conflict (key) do nothing;
insert into pipeline.scholarship_jobs(jobname, layer, label, what, setting_keys, sort) values
  ('scholarship-listing', 2, 'Read listing pages', 'Reads each provider''s scholarship listing page and keeps the scholarships it names, for the coverage check.', array['listing_limit'], 25),
  ('scholarship-auto-publish', 4, 'Publish automatically', 'Publishes the scholarships that pass every check, every hour, as a batch named auto-publish.', array['auto_publish'], 15)
on conflict (jobname) do nothing;
select cron.schedule('scholarship-listing', '7-59/15 * * * *', $$select pipeline.svc_pilot_submit_nonce('coverage-sweep', jsonb_build_object('mode','scholarship_listing','limit',security.scholarship_setting('listing_limit',6)::int))$$);

-- 7. Bulk restore on Providers > Archived (Platform Admin feature request, 11 Oct 2026). PIM Operator and above, as single restore.
--    Providers go through the restore workflow one by one; courses through the same course restore as the course panel (only
--    when their provider is active). At most 200 a call.
create or replace function public.admin_archive_restore_bulk(p_section text, p_ids uuid[])
 returns jsonb
 language plpgsql
 security definer
 set search_path to ''
as $function$
declare v_id uuid; n_ok int := 0; n_skip int := 0; v_res jsonb;
begin
  if auth.uid() is null or security.current_role_rank() < 5 then raise exception 'PIM Operator role or above required' using errcode = '42501'; end if;
  if coalesce(cardinality(p_ids), 0) = 0 then raise exception 'choose at least one record'; end if;
  if cardinality(p_ids) > 200 then raise exception 'at most 200 at a time'; end if;
  foreach v_id in array p_ids loop
    if p_section = 'providers' then
      v_res := security.provider_restore_v1(v_id, 'Restored by hand (bulk)', auth.uid(), true);
      if v_res->>'status' = 'restored' then n_ok := n_ok + 1; else n_skip := n_skip + 1; end if;
    elsif p_section = 'courses' then
      if exists (select 1 from catalogue.courses c join catalogue.providers p on p.id = c.provider_id
                  where c.id = v_id and c.lifecycle_status is distinct from 'active' and p.lifecycle_status = 'active') then
        perform public.admin_course_edit(v_id, 'restore', jsonb_build_object('reason', 'Restored by hand (bulk)'));
        n_ok := n_ok + 1;
      else n_skip := n_skip + 1; end if;
    else raise exception 'unknown section %', p_section; end if;
  end loop;
  return jsonb_build_object('restored', n_ok, 'skipped', n_skip);
end $function$;
revoke all on function public.admin_archive_restore_bulk(text, uuid[]) from public, anon;
grant execute on function public.admin_archive_restore_bulk(text, uuid[]) to authenticated;

do $post$
begin
  if (select count(*) from pipeline.scholarship_watch) < 25 or not exists (select 1 from pipeline.scholarship_listing_pages where source = 'auto')
     or not exists (select 1 from cron.job where jobname = 'scholarship-listing' and active)
     or (select count(*) from pipeline.scholarship_jobs where jobname in ('scholarship-listing', 'scholarship-auto-publish')) <> 2 then
    raise exception 'CF-247 v2.15.240 post-check: coverage objects not as intended';
  end if;
end $post$;
