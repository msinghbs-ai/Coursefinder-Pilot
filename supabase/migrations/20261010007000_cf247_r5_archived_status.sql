-- CF-247 v2.15.238 (R5): Platform Admin bug list of 10 Oct 2026 — Features 5, 6 and 7. Decision: "New 'archived' status".
--  1. pipeline.provider_archives: one row per archive (who, when, why, from where) with what the clean-up switched off.
--  2. The clean-up workflow: archive sets the provider to 'archived' and unpublished (hidden with its courses, campuses and
--     scholarships; background work already paused since v2.15.237), switches off its adapter and course link search, and closes its
--     waiting Layer 4 reviews as superseded. Restore puts back exactly what was switched off. A checklist (preview) is shown first.
--  3. Layer 1: a provider whose registered courses have all left the register is archived automatically, and restored automatically
--     when one comes back. The departure still waits in Layer 4 › Provider departures to record a closure or a merger. The 10
--     departures already waiting are archived now.
--  4. Archived review screen data (admin_archive_read): archived providers, courses that are not active and why, departures waiting.
--  5. A course archived or restored by hand rebuilds search (gap A); a course that is not active is never served by a consumer API.
-- md5-checked before and after. Nothing is dropped or deleted.
do $guard$
declare v_expected jsonb := jsonb_build_object('public.admin_provider_edit(uuid,text,jsonb)', '88d604e0b4dcb6a012550d2384a63bdb', 'public.admin_provider_edit_read(uuid)', '3306e12173001cad55424308c605ee2c', 'security.layer4_provider_departure_decide_v1(bigint,text,uuid,text)', 'd319a992fc122798005b616fc7a243d2', 'public.admin_course_edit(uuid,text,jsonb)', 'a8acab9d6f56a5ccca9dafa435318f05');
  v_sig text;
begin
  for v_sig in select jsonb_object_keys(v_expected) loop
    if md5(replace(pg_get_functiondef(v_sig::regprocedure), E'\r', '')) <> v_expected->>v_sig then
      raise exception 'live % differs from the definition this change replaces', v_sig;
    end if;
  end loop;
end $guard$;
do $guard_view$
begin
  if md5(pg_get_viewdef('security.layer4_search_blocked_courses'::regclass)) <> 'e9d755ed1213a79f39276ae9ec093be1' then
    raise exception 'live security.layer4_search_blocked_courses differs from the definition this change replaces';
  end if;
  if to_regclass('pipeline.provider_archives') is not null then raise exception 'pipeline.provider_archives already exists'; end if;
end $guard_view$;

-- 1. Archive records: one row per archive, closed when the provider is restored. What the clean-up switched off is kept, so a restore
--    switches back on exactly that.
create table if not exists pipeline.provider_archives (
  id bigint generated always as identity primary key,
  provider_id uuid not null references catalogue.providers(id),
  source text not null check (source in ('layer1_departure', 'manual', 'departure_review')),
  reason text not null,
  previous_lifecycle text,
  previous_publication text,
  cascade jsonb not null default '{}'::jsonb,
  archived_by uuid,
  archived_at timestamptz not null default now(),
  restored_by uuid,
  restored_at timestamptz,
  restore_note text
);
create unique index if not exists provider_archives_open_idx on pipeline.provider_archives(provider_id) where restored_at is null;
alter table pipeline.provider_archives enable row level security;
revoke all on pipeline.provider_archives from public, anon, authenticated;

-- 2. What archiving a provider does (the checklist shown before a Platform Admin or PIM Operator confirms).
create or replace function security.provider_archive_preview_v1(p_provider_id uuid)
 returns jsonb
 language sql
 stable security definer
 set search_path to ''
as $function$
  select jsonb_build_object(
    'provider_id', p.id, 'name', coalesce(p.display_name, p.canonical_name), 'lifecycle_status', p.lifecycle_status, 'publication_status', p.publication_status,
    'items', jsonb_build_array(
      jsonb_build_object('key', 'hidden', 'count', null, 'effect', 'Unpublished and hidden from Wix, Zoho, the website and search, with its courses, campuses and scholarships. Records are kept.'),
      jsonb_build_object('key', 'courses', 'count', (select count(*) from catalogue.courses c where c.provider_id = p.id and c.lifecycle_status = 'active'), 'effect', 'Active courses: hidden with the provider; each course keeps its own status, so restoring brings them back as they were.'),
      jsonb_build_object('key', 'campuses', 'count', (select count(*) from catalogue.campuses x where x.provider_id = p.id), 'effect', 'Campuses: hidden with the provider.'),
      jsonb_build_object('key', 'scholarships', 'count', (select count(*) from scholarship.scholarships s where s.provider_id = p.id and s.lifecycle_status = 'active'), 'effect', 'Scholarships: hidden with the provider.'),
      jsonb_build_object('key', 'adapter', 'count', (select count(*) from pipeline.uni_adapters a where a.provider_id = p.id and a.enabled), 'effect', 'Adapter: switched off; switched back on at restore.'),
      jsonb_build_object('key', 'link_recipe', 'count', (select count(*) from pipeline.course_link_recipes r where r.provider_id = p.id and r.active), 'effect', 'Course link search: switched off; switched back on at restore.'),
      jsonb_build_object('key', 'reviews', 'count', (select count(*) from pipeline.layer4_review_items x where x.status = 'pending'
                           and ((x.entity_type = 'provider' and x.entity_id = p.id) or (x.entity_type = 'course' and x.entity_id in (select c.id from catalogue.courses c where c.provider_id = p.id)))),
                         'effect', 'Layer 4 reviews waiting: closed as superseded; reopened at restore.'),
      jsonb_build_object('key', 'background', 'count', null, 'effect', 'Background work (page finding and reading, AI matching, link search, provider facts, scholarships, contact reads) stops picking it up.')))
    from catalogue.providers p where p.id = p_provider_id
$function$;
revoke all on function security.provider_archive_preview_v1(uuid) from public, anon, authenticated;

-- 3. Archive: status 'archived', unpublished, adapter and course link search switched off, waiting Layer 4 reviews superseded, logged,
--    search rebuilt. A status locked by hand is kept when the archive comes from automation (Layer 1).
create or replace function security.provider_archive_apply_v1(p_provider_id uuid, p_source text, p_reason text, p_actor uuid, p_manual boolean)
 returns jsonb
 language plpgsql
 security definer
 set search_path to ''
as $function$
declare v_life text; v_pub text; v_now text; v_ad int; v_lr int; v_rv jsonb; v_id bigint;
begin
  select p.lifecycle_status, p.publication_status into v_life, v_pub from catalogue.providers p where p.id = p_provider_id for update;
  if not found then raise exception 'provider not found'; end if;
  if v_life = 'archived' then return jsonb_build_object('status', 'already_archived', 'provider_id', p_provider_id); end if;
  if p_manual then perform set_config('cf.manual_edit', 'on', true); end if;
  update catalogue.providers set lifecycle_status = 'archived', publication_status = 'unpublished', updated_at = now() where id = p_provider_id;
  select p.lifecycle_status into v_now from catalogue.providers p where p.id = p_provider_id;
  if v_now <> 'archived' then return jsonb_build_object('status', 'kept_by_hand', 'provider_id', p_provider_id); end if;
  with a as (update pipeline.uni_adapters set enabled = false, updated_at = now() where provider_id = p_provider_id and enabled returning 1) select count(*) into v_ad from a;
  with r as (update pipeline.course_link_recipes set active = false, updated_at = now() where provider_id = p_provider_id and active returning 1) select count(*) into v_lr from r;
  with i as (update pipeline.layer4_review_items x set status = 'superseded', decided_at = now()
              where x.status = 'pending' and ((x.entity_type = 'provider' and x.entity_id = p_provider_id)
                    or (x.entity_type = 'course' and x.entity_id in (select c.id from catalogue.courses c where c.provider_id = p_provider_id)))
             returning x.id)
  select coalesce(jsonb_agg(i.id), '[]'::jsonb) into v_rv from i;
  insert into pipeline.provider_archives(provider_id, source, reason, previous_lifecycle, previous_publication, cascade, archived_by)
  values (p_provider_id, p_source, left(btrim(coalesce(nullif(p_reason, ''), 'Archived')), 500), v_life, v_pub,
          jsonb_build_object('adapter_switched_off', v_ad > 0, 'link_recipe_switched_off', v_lr > 0, 'reviews_superseded', v_rv), p_actor)
  returning id into v_id;
  insert into pipeline.manual_edit_log(entity, entity_id, field, action, before, after, reason, actor)
  values ('provider', p_provider_id, 'lifecycle_status', 'archive', to_jsonb(v_life), to_jsonb('archived'::text), left(p_source || ': ' || coalesce(p_reason, ''), 500), p_actor);
  insert into search.refresh_requests(requested_by) values (format('provider %s archived (%s)', left(p_provider_id::text, 8), p_source));
  return jsonb_build_object('status', 'archived', 'provider_id', p_provider_id, 'archive_id', v_id, 'adapter_switched_off', v_ad > 0,
                            'link_recipe_switched_off', v_lr > 0, 'reviews_superseded', jsonb_array_length(v_rv));
end $function$;
revoke all on function security.provider_archive_apply_v1(uuid, text, text, uuid, boolean) from public, anon, authenticated;

-- 4. Restore: back to active with its earlier publication, and what the archive switched off is switched back on.
create or replace function security.provider_restore_v1(p_provider_id uuid, p_note text, p_actor uuid, p_manual boolean)
 returns jsonb
 language plpgsql
 security definer
 set search_path to ''
as $function$
declare v_life text; v_id bigint; v_prev_pub text; v_cascade jsonb; v_now text; v_rv int := 0;
begin
  select p.lifecycle_status into v_life from catalogue.providers p where p.id = p_provider_id for update;
  if not found then raise exception 'provider not found'; end if;
  if v_life = 'active' then return jsonb_build_object('status', 'already_active', 'provider_id', p_provider_id); end if;
  select a.id, a.previous_publication, a.cascade into v_id, v_prev_pub, v_cascade from pipeline.provider_archives a
   where a.provider_id = p_provider_id and a.restored_at is null for update;
  if p_manual then perform set_config('cf.manual_edit', 'on', true); end if;
  update catalogue.providers set lifecycle_status = 'active', publication_status = coalesce(v_prev_pub, 'published'), updated_at = now() where id = p_provider_id;
  select p.lifecycle_status into v_now from catalogue.providers p where p.id = p_provider_id;
  if v_now <> 'active' then return jsonb_build_object('status', 'kept_by_hand', 'provider_id', p_provider_id); end if;
  if v_id is not null then
    if coalesce((v_cascade->>'adapter_switched_off')::boolean, false) then update pipeline.uni_adapters set enabled = true, updated_at = now() where provider_id = p_provider_id; end if;
    if coalesce((v_cascade->>'link_recipe_switched_off')::boolean, false) then update pipeline.course_link_recipes set active = true, updated_at = now() where provider_id = p_provider_id; end if;
    with i as (update pipeline.layer4_review_items x set status = 'pending', decided_at = null
                where x.status = 'superseded' and x.id in (select (e #>> '{}')::uuid from jsonb_array_elements(coalesce(v_cascade->'reviews_superseded', '[]'::jsonb)) e)
               returning 1)
    select count(*) into v_rv from i;
    update pipeline.provider_archives set restored_at = now(), restored_by = p_actor, restore_note = left(p_note, 500) where id = v_id;
  end if;
  insert into pipeline.manual_edit_log(entity, entity_id, field, action, before, after, reason, actor)
  values ('provider', p_provider_id, 'lifecycle_status', 'restore', to_jsonb(v_life), to_jsonb('active'::text), left(coalesce(p_note, 'Restored'), 500), p_actor);
  insert into search.refresh_requests(requested_by) values (format('provider %s restored', left(p_provider_id::text, 8)));
  return jsonb_build_object('status', 'restored', 'provider_id', p_provider_id, 'publication_status', coalesce(v_prev_pub, 'published'), 'reviews_reopened', v_rv);
end $function$;
revoke all on function security.provider_restore_v1(uuid, text, uuid, boolean) from public, anon, authenticated;

-- 5. Admin calls: the checklist (preview), archive and restore. PIM Operator and above, as before. A reason is chosen from a short list.
create or replace function public.admin_provider_archive(p_provider_id uuid, p_reason text default null, p_preview boolean default false)
 returns jsonb
 language plpgsql
 security definer
 set search_path to ''
as $function$
begin
  if auth.uid() is null or security.current_role_rank() < 5 then raise exception 'PIM Operator role or above required' using errcode = '42501'; end if;
  if not exists (select 1 from catalogue.providers where id = p_provider_id) then raise exception 'provider not found'; end if;
  if p_preview then return security.provider_archive_preview_v1(p_provider_id); end if;
  return security.provider_archive_apply_v1(p_provider_id, 'manual', coalesce(nullif(btrim(p_reason), ''), 'Archived by hand'), auth.uid(), true);
end $function$;
revoke all on function public.admin_provider_archive(uuid, text, boolean) from public, anon;
grant execute on function public.admin_provider_archive(uuid, text, boolean) to authenticated;

create or replace function public.admin_provider_restore(p_provider_id uuid)
 returns jsonb
 language plpgsql
 security definer
 set search_path to ''
as $function$
begin
  if auth.uid() is null or security.current_role_rank() < 5 then raise exception 'PIM Operator role or above required' using errcode = '42501'; end if;
  return security.provider_restore_v1(p_provider_id, 'Restored by hand', auth.uid(), true);
end $function$;
revoke all on function public.admin_provider_restore(uuid) from public, anon;
grant execute on function public.admin_provider_restore(uuid) to authenticated;

-- 6. The Archived review screen: archived providers, courses that are not active (with why), and departures waiting for a decision.
create or replace function public.admin_archive_read(p_section text default 'providers', p_query text default null, p_limit integer default 50, p_offset integer default 0)
 returns jsonb
 language plpgsql
 stable security definer
 set search_path to ''
as $function$
declare v_rank int := security.current_role_rank(); v_q text := nullif(btrim(coalesce(p_query, '')), ''); v_lim int := greatest(1, least(coalesce(p_limit, 50), 200));
        v_off int := greatest(0, coalesce(p_offset, 0)); v_rows jsonb; v_total int;
begin
  if auth.uid() is null or v_rank < 3 then raise exception 'Curator role or above required' using errcode = '42501'; end if;
  if p_section = 'courses' then
    with base as (
      select c.id, coalesce(c.display_title, c.canonical_title) title, c.course_code code, c.lifecycle_status, p.id provider_id,
             coalesce(p.display_name, p.canonical_name) provider, p.lifecycle_status provider_status, r.reason retire_reason, r.retired_at,
             (select k.iso_alpha2 from ref.countries k where k.id = p.country_id) country,
             (select h.at from pipeline.manual_edit_log h where h.entity = 'course' and h.entity_id = c.id and h.action = 'archive' order by h.at desc limit 1) hand_at
        from catalogue.courses c join catalogue.providers p on p.id = c.provider_id
        left join lateral (select r0.reason, r0.retired_at from pipeline.layer1_course_retirements r0 where r0.course_id = c.id and r0.reactivated_at is null order by r0.retired_at desc limit 1) r on true
       where c.lifecycle_status is distinct from 'active'
         and (v_q is null or c.canonical_title ilike '%' || v_q || '%' or c.course_code ilike v_q || '%' or p.canonical_name ilike '%' || v_q || '%' or p.display_name ilike '%' || v_q || '%'))
    select (select count(*) from base),
           coalesce(jsonb_agg(jsonb_build_object('id', b.id, 'title', b.title, 'code', b.code, 'status', b.lifecycle_status, 'provider_id', b.provider_id,
             'provider', b.provider, 'provider_status', b.provider_status,
             'why', case when b.hand_at is not null and (b.retired_at is null or b.hand_at > b.retired_at) then 'Archived by hand'
                         when b.retire_reason is not null then b.retire_reason
                         when b.lifecycle_status = 'inactive' then 'Outside the import scope (Layer 1)'
                         when b.lifecycle_status = 'suspended' then 'Suspended'
                         else 'Status not known' end, 'country', b.country,
             'at', greatest(b.hand_at, b.retired_at)) order by greatest(b.hand_at, b.retired_at) desc nulls last, b.title), '[]'::jsonb)
      into v_total, v_rows
      from (select * from base order by greatest(hand_at, retired_at) desc nulls last, title limit v_lim offset v_off) b;
  else
    with base as (
      select p.id, coalesce(p.display_name, p.canonical_name) name, k.iso_alpha2 country, p.lifecycle_status, a.source, a.reason, a.archived_at,
             u.email archived_by, (select count(*) from catalogue.courses c where c.provider_id = p.id) courses,
             (select d.status from pipeline.layer1_provider_departures d where d.provider_id = p.id order by d.created_at desc limit 1) departure
        from catalogue.providers p left join ref.countries k on k.id = p.country_id
        left join pipeline.provider_archives a on a.provider_id = p.id and a.restored_at is null
        left join auth.users u on u.id = a.archived_by
       where p.lifecycle_status is distinct from 'active'
         and (v_q is null or p.canonical_name ilike '%' || v_q || '%' or p.display_name ilike '%' || v_q || '%'))
    select (select count(*) from base),
           coalesce(jsonb_agg(jsonb_build_object('id', b.id, 'name', b.name, 'country', b.country, 'status', b.lifecycle_status, 'source', b.source,
             'reason', b.reason, 'at', b.archived_at, 'by', b.archived_by, 'courses', b.courses, 'departure', b.departure) order by b.archived_at desc nulls last, b.name), '[]'::jsonb)
      into v_total, v_rows
      from (select * from base order by archived_at desc nulls last, name limit v_lim offset v_off) b;
  end if;
  return jsonb_build_object('section', coalesce(p_section, 'providers'), 'rows', v_rows, 'total', v_total, 'can_restore', v_rank >= 5,
    'counts', jsonb_build_object(
      'providers', (select count(*) from catalogue.providers p where p.lifecycle_status is distinct from 'active'),
      'courses', (select count(*) from catalogue.courses c where c.lifecycle_status is distinct from 'active'),
      'departures_waiting', (select count(*) from pipeline.layer1_provider_departures d where d.status = 'needs_review')));
end $function$;
revoke all on function public.admin_archive_read(text, text, integer, integer) from public, anon;
grant execute on function public.admin_archive_read(text, text, integer, integer) to authenticated;

-- 7. Layer 1: when all of a provider's registered courses leave the register, the provider is archived automatically (the departure is
--    still listed in Layer 4 › Provider departures to record a closure or a merger). When one of its courses comes back, a provider
--    archived this way is restored automatically. A failure here never stops the Layer 1 run; it is reported as a warning.
create or replace function security.trg_departure_archive_v1()
 returns trigger
 language plpgsql
 security definer
 set search_path to ''
as $function$
begin
  if not exists (select 1 from catalogue.courses c where c.provider_id = new.provider_id and c.lifecycle_status = 'active') then
    begin
      perform security.provider_archive_apply_v1(new.provider_id, 'layer1_departure', 'All its registered courses left the register', null, false);
    exception when others then
      raise warning 'provider % not archived after its departure: %', new.provider_id, sqlerrm;
    end;
  end if;
  return null;
end $function$;
revoke all on function security.trg_departure_archive_v1() from public, anon, authenticated;
create trigger layer1_departure_archive after insert on pipeline.layer1_provider_departures
  for each row execute function security.trg_departure_archive_v1();

create or replace function security.trg_retirement_restore_v1()
 returns trigger
 language plpgsql
 security definer
 set search_path to ''
as $function$
begin
  if exists (select 1 from pipeline.provider_archives a where a.provider_id = new.provider_id and a.restored_at is null and a.source = 'layer1_departure') then
    begin
      perform security.provider_restore_v1(new.provider_id, 'A registered course is listed by the register again', null, false);
    exception when others then
      raise warning 'provider % not restored after a course came back: %', new.provider_id, sqlerrm;
    end;
  end if;
  return null;
end $function$;
revoke all on function security.trg_retirement_restore_v1() from public, anon, authenticated;
create trigger layer1_retirement_restore after update of reactivated_at on pipeline.layer1_course_retirements
  for each row when (old.reactivated_at is null and new.reactivated_at is not null) execute function security.trg_retirement_restore_v1();

-- 8. A course that is not active is never served by a consumer API, even when asked for by its id.
create index if not exists courses_not_active_idx on catalogue.courses(id) where lifecycle_status is distinct from 'active';
create or replace view security.layer4_search_blocked_courses as
 SELECT layer4_active_blocks.entity_id AS course_id
   FROM security.layer4_active_blocks
  WHERE layer4_active_blocks.block_scope = 'search'::text AND layer4_active_blocks.entity_type = 'course'::text
UNION
 SELECT c.id AS course_id
   FROM security.layer4_active_blocks b
     JOIN catalogue.courses c ON c.provider_id = b.entity_id
  WHERE b.block_scope = 'search'::text AND b.entity_type = 'provider'::text
UNION
 SELECT c.id AS course_id
   FROM security.provider_hidden_v1 h
     JOIN catalogue.courses c ON c.provider_id = h.provider_id
UNION
 SELECT c.id AS course_id
   FROM catalogue.courses c
  WHERE c.lifecycle_status IS DISTINCT FROM 'active'::text;

CREATE OR REPLACE FUNCTION public.admin_provider_edit(p_provider_id uuid, p_action text, p_args jsonb DEFAULT '{}'::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_rank int := security.current_role_rank(); v_p catalogue.providers%rowtype; v_field text; v_before jsonb; v_after jsonb; v_val jsonb; v_url text;
        v_reason text := nullif(btrim(coalesce(p_args->>'reason', '')), '');
begin
  if auth.uid() is null or v_rank < 3 then raise exception 'Curator role or above required' using errcode = '42501'; end if;
  select * into v_p from catalogue.providers where id = p_provider_id;
  if v_p.id is null then raise exception 'provider not found'; end if;
  if p_action in ('archive','restore') and v_rank < 5 then raise exception 'PIM Operator role or above required' using errcode = '42501'; end if;
  perform set_config('cf.manual_edit', 'on', true);

  if p_action = 'set_core' then
    v_field := p_args->>'field';
    if v_field is null or v_field not in ('display_name','short_name','website','phone','email','description','primary_city','address_line1','postcode') then raise exception 'this field cannot be edited here'; end if;
    v_val := p_args->'value';
    if jsonb_typeof(v_val) = 'string' then v_val := to_jsonb(nullif(btrim(v_val #>> '{}'), '')); end if;
    if v_field = 'website' and v_val is not null and v_val <> 'null'::jsonb and (v_val #>> '{}') !~* '^https?://[^\s/]+\.[^\s]+$' then raise exception 'enter a full web address starting with https://'; end if;
    if v_field = 'website' and v_val is not null and v_val <> 'null'::jsonb and security.third_party_host_v1(v_val #>> '{}') then raise exception 'that is a third-party site (a course directory or similar), not the provider''s own website'; end if;
    if v_field = 'email' and v_val is not null and v_val <> 'null'::jsonb and (v_val #>> '{}') !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$' then raise exception 'enter a valid email address'; end if;
    v_before := to_jsonb(v_p)->v_field;
    update catalogue.providers p set display_name = r.display_name, short_name = r.short_name, website = r.website, phone = r.phone, email = r.email,
           description = r.description, primary_city = r.primary_city, address_line1 = r.address_line1, postcode = r.postcode, updated_at = now()
      from (select (jsonb_populate_record(x0, jsonb_build_object(v_field, v_val))).* from catalogue.providers x0 where x0.id = p_provider_id) r
     where p.id = p_provider_id;
    perform security.manual_lock_set('provider', p_provider_id, v_field, 'value');
    v_after := v_val;

  elsif p_action = 'set_course_finder' then
    v_field := 'course_finder'; v_url := btrim(coalesce(p_args->>'url', ''));
    if v_url !~* '^https?://[^\s/]+\.[^\s]+$' then raise exception 'enter a full web address starting with https://'; end if;
    if security.third_party_host_v1(v_url) then raise exception 'that is a third-party course directory: use the provider''s own website or the regulator''s page'; end if;
    select to_jsonb(d.website) into v_before from pipeline.coverage_provider_discovery d where d.provider_id = p_provider_id;
    insert into pipeline.coverage_provider_discovery(provider_id, website, status, attempts, next_due_at, updated_at)
    values (p_provider_id, v_url, 'pending', 0, now(), now())
    on conflict (provider_id) do update set website = excluded.website, status = 'pending', attempts = 0, next_due_at = now(), leased_until = null,
           last_error = null, updated_at = now();
    -- v2.15.232 (Fix 3): an address entered by hand is marked manual and locked, so automation never replaces it
    update pipeline.coverage_provider_discovery set site_source = 'manual', site_searched_at = now() where provider_id = p_provider_id;
    perform security.manual_lock_set('provider', p_provider_id, 'course_finder', 'value');
    v_after := to_jsonb(v_url);

  elsif p_action = 'release' then
    v_field := p_args->>'field';
    select to_jsonb(l) into v_before from pipeline.manual_locks l where entity = 'provider' and entity_id = p_provider_id and field = v_field;
    if v_before is null then raise exception 'nothing to release'; end if;
    delete from pipeline.manual_locks where entity = 'provider' and entity_id = p_provider_id and field = v_field;
    -- v2.15.232: handing the course finder address back to automation lets the site search replace it again
    if v_field = 'course_finder' then update pipeline.coverage_provider_discovery set site_source = null where provider_id = p_provider_id and site_source = 'manual'; end if;

  elsif p_action in ('archive','restore') then
    -- v2.15.238 (R5): archive and restore go through the clean-up workflow (status 'archived'; adapter, link search and waiting reviews
    -- switched off, and back on at restore). The workflow logs the change itself.
    if p_action = 'archive' then perform security.provider_archive_apply_v1(p_provider_id, 'manual', coalesce(v_reason, 'Archived by hand'), auth.uid(), true);
    else perform security.provider_restore_v1(p_provider_id, coalesce(v_reason, 'Restored by hand'), auth.uid(), true); end if;
    return public.admin_provider_edit_read(p_provider_id);

  else
    raise exception 'unknown action %', p_action;
  end if;

  insert into pipeline.manual_edit_log(entity, entity_id, field, action, before, after, reason, actor)
  values ('provider', p_provider_id, v_field, p_action, v_before, v_after, v_reason, auth.uid());
  return public.admin_provider_edit_read(p_provider_id);
end $function$;

CREATE OR REPLACE FUNCTION public.admin_provider_edit_read(p_provider_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_rank int := security.current_role_rank();
begin
  if auth.uid() is null or v_rank < 3 then raise exception 'assigned CourseFinder role required' using errcode = '42501'; end if;
  if not exists (select 1 from catalogue.providers where id = p_provider_id) then raise exception 'provider not found'; end if;
  return (select jsonb_build_object(
    'provider', jsonb_build_object('id', p.id, 'canonical_name', p.canonical_name, 'display_name', p.display_name, 'short_name', p.short_name,
               'website', p.website, 'phone', p.phone, 'email', p.email, 'description', p.description, 'primary_city', p.primary_city,
               'address_line1', p.address_line1, 'postcode', p.postcode, 'lifecycle_status', p.lifecycle_status, 'country', k.name, 'state', s.name,
               'manual_provider', p.stable_key like 'manual:%', 'website_verdict', security.provider_site_verdict_v1(p.id, p.website),
               'active_courses', (select count(*) from catalogue.courses c where c.provider_id = p.id and c.lifecycle_status = 'active')),
    'course_finder', (select jsonb_build_object('address', d.website, 'status', d.status, 'pages_found', d.kept_count, 'mapped_at', d.mapped_at,
                               'verdict', security.provider_site_verdict_v1(p.id, d.website), 'source', d.site_source)
                        from pipeline.coverage_provider_discovery d where d.provider_id = p.id),
    'link_recipe', (select jsonb_build_object('search_domain', r.search_domain, 'patterns', r.patterns, 'active', r.active)
                      from pipeline.course_link_recipes r where r.provider_id = p.id),
    -- v2.15.234 (Fix 2): where the public phone and email came from, and (PIM Operator and above) the regulator's contact, internal only
    'public_contact', (select jsonb_build_object('phone', cp.phone, 'email', cp.email, 'url', cp.source_url, 'at', cp.observed_at)
                         from pipeline.provider_contact_points cp where cp.provider_id = p.id and cp.kind = 'public_general' and cp.is_current),
    'regulatory_contact', case when v_rank >= 5 then (select jsonb_build_object('name', cp.name, 'title', cp.title, 'phone', cp.phone, 'email', cp.email, 'url', cp.source_url, 'at', cp.observed_at)
                         from pipeline.provider_contact_points cp where cp.provider_id = p.id and cp.kind = 'regulatory_peo' and cp.is_current) end,
    'regulatory_check', case when v_rank >= 5 then (select jsonb_build_object('outcome', k.outcome, 'at', k.checked_at) from pipeline.provider_contact_checks k where k.provider_id = p.id and k.kind = 'regulatory_peo') end,
    'locks', (select coalesce(jsonb_object_agg(l.field, jsonb_build_object('mode', l.mode, 'at', l.set_at)), '{}'::jsonb)
               from pipeline.manual_locks l where l.entity = 'provider' and l.entity_id = p.id),
    'history', (select coalesce(jsonb_agg(jsonb_build_object('at', h.at, 'field', h.field, 'action', h.action, 'before', h.before, 'after', h.after,
               'reason', h.reason, 'by', u.email) order by h.at desc), '[]'::jsonb)
               from (select * from pipeline.manual_edit_log where entity = 'provider' and entity_id = p.id order by at desc limit 20) h left join auth.users u on u.id = h.actor),
    -- v2.15.238 (R5): why and when the provider was archived
    'archive', (select jsonb_build_object('source', a.source, 'reason', a.reason, 'at', a.archived_at) from pipeline.provider_archives a where a.provider_id = p.id and a.restored_at is null),
    'can_edit', v_rank >= 3, 'can_manage', v_rank >= 5)
   from catalogue.providers p left join ref.countries k on k.id = p.country_id left join ref.subdivisions s on s.id = p.subdivision_id where p.id = p_provider_id);
end $function$;

CREATE OR REPLACE FUNCTION security.layer4_provider_departure_decide_v1(p_id bigint, p_decision text, p_successor_provider_id uuid, p_reason text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'security', 'pipeline', 'catalogue'
AS $function$
declare d pipeline.layer1_provider_departures; p catalogue.providers; s catalogue.providers; v_before jsonb; v_after jsonb; v_changed boolean:=false;
begin
  if auth.uid() is null then raise exception 'authentication required' using errcode='42501'; end if;
  if security.current_role_rank()<6 then raise exception 'Platform Admin role required' using errcode='42501'; end if;
  if p_decision not in ('closed','merged','reviewed') then raise exception 'decision must be closed, merged or reviewed' using errcode='22023'; end if;
  if length(btrim(coalesce(p_reason,'')))<8 then raise exception 'a reason of at least 8 characters is required' using errcode='22023'; end if;
  select * into d from pipeline.layer1_provider_departures where id=p_id for update;
  if not found then raise exception 'departure not found' using errcode='22023'; end if;
  if d.status<>'needs_review' then raise exception 'this departure was already decided (%)', d.status using errcode='55000'; end if;
  select * into p from catalogue.providers where id=d.provider_id for update;
  if exists (select 1 from catalogue.courses c where c.provider_id=p.id and c.lifecycle_status='active') and p_decision<>'reviewed' then
    raise exception 'the provider has active courses again; choose reviewed' using errcode='55000'; end if;
  if p_decision='merged' then
    if p_successor_provider_id is null then raise exception 'a merger needs a successor provider' using errcode='22023'; end if;
    select * into s from catalogue.providers where id=p_successor_provider_id;
    if not found or s.id=p.id then raise exception 'successor provider not valid' using errcode='22023'; end if;
    if s.country_id is distinct from p.country_id then raise exception 'successor must be in the same country' using errcode='22023'; end if;
    if s.lifecycle_status<>'active' then raise exception 'successor provider is not active' using errcode='22023'; end if;
  elsif p_successor_provider_id is not null then
    raise exception 'a successor is only recorded for a merger' using errcode='22023';
  end if;

  if p_decision in ('closed','merged') and p.lifecycle_status='active' then
    v_before:=security.consumer_api_snapshot_v1();
    -- v2.15.238 (R5): a closure or merger archives the provider through the clean-up workflow (usually already archived by Layer 1)
    perform security.provider_archive_apply_v1(p.id, 'departure_review', initcap(p_decision)||': '||btrim(p_reason), auth.uid(), true);
    v_changed:=true;
  end if;
  if p_decision='merged' then
    insert into catalogue.provider_associations(from_provider_id,to_provider_id,association_type,valid_from,status,notes)
    values(p.id, s.id, 'merged_into', current_date, 'active', left('Recorded on provider departure review: '||btrim(p_reason),500));
  end if;
  update pipeline.layer1_provider_departures set status=p_decision, successor_provider_id=p_successor_provider_id,
         note=left(coalesce(note,'')||' | Decision: '||btrim(p_reason),1000), reviewed_by=auth.uid(), reviewed_at=now()
   where id=p_id;
  if v_changed then
    v_after:=security.consumer_api_snapshot_v1();
    insert into pipeline.consumer_api_baselines(label, snapshot) values
      (format('before provider departure decision %s (%s)', p_id, p_decision), v_before),
      (format('after provider departure decision %s (%s)', p_id, p_decision), v_after);
    insert into search.refresh_requests(requested_by) values (format('provider departure %s: %s', p_id, p_decision));
  end if;
  return jsonb_build_object('id',p_id,'decision',p_decision,'provider_id',p.id,'provider_inactive',v_changed,'successor_provider_id',p_successor_provider_id);
end $function$;

CREATE OR REPLACE FUNCTION public.admin_course_edit(p_course_id uuid, p_action text, p_args jsonb DEFAULT '{}'::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_rank int := security.current_role_rank(); v_src uuid; v_c catalogue.courses%rowtype; v_field text; v_before jsonb; v_after jsonb;
        v_reason text := nullif(btrim(coalesce(p_args->>'reason', '')), ''); v_url text; x jsonb; v_test uuid; v_amount numeric; v_val jsonb;
        v_keep uuid[] := '{}'; v_n int;
begin
  if auth.uid() is null or v_rank < 3 then raise exception 'Curator role or above required' using errcode = '42501'; end if;
  select * into v_c from catalogue.courses where id = p_course_id;
  if v_c.id is null then raise exception 'course not found'; end if;
  if p_action in ('archive','restore') and v_rank < 5 then raise exception 'PIM Operator role or above required' using errcode = '42501'; end if;
  perform set_config('cf.manual_edit', 'on', true);
  select id into v_src from pipeline.sources where source_type = 'manual_entry' limit 1;

  if p_action = 'set_core' then
    v_field := p_args->>'field';
    if v_field is null or v_field not in ('display_title','description','duration_value','duration_unit','delivery_mode') then raise exception 'this field cannot be edited here'; end if;
    v_val := p_args->'value';
    if jsonb_typeof(v_val) = 'string' then v_val := to_jsonb(nullif(btrim(v_val #>> '{}'), '')); end if;
    if v_field = 'duration_value' and v_val is not null and v_val <> 'null'::jsonb and not ((v_val #>> '{}') ~ '^[0-9]+(\.[0-9]+)?$') then raise exception 'duration must be a number'; end if;
    v_before := to_jsonb(v_c)->v_field;
    update catalogue.courses c set display_title = r.display_title, description = r.description, duration_value = r.duration_value,
           duration_unit = r.duration_unit, delivery_mode = r.delivery_mode, updated_at = now()
      from (select (jsonb_populate_record(x0, jsonb_build_object(v_field, v_val))).* from catalogue.courses x0 where x0.id = p_course_id) r
     where c.id = p_course_id;
    perform security.manual_lock_set('course', p_course_id, v_field, 'value');
    v_after := v_val;

  elsif p_action = 'set_official_url' then
    v_field := 'official_url'; v_url := btrim(coalesce(p_args->>'url', ''));
    if v_url !~* '^https?://[^\s/]+\.[^\s]+$' then raise exception 'enter a full web address starting with https://'; end if;
    if security.third_party_host_v1(v_url) then raise exception 'that is a third-party course directory: the official page must be on the provider''s own website'; end if;
    select jsonb_agg(url) into v_before from catalogue.course_links where course_id = p_course_id and link_type = 'official_course' and status = 'active';
    update catalogue.course_links set status = 'inactive', is_primary = false, updated_at = now()
     where course_id = p_course_id and link_type = 'official_course' and status = 'active' and url <> v_url;
    insert into catalogue.course_links(course_id, link_type, url, label, is_primary, status, source_id, confidence, last_verified_at)
    values (p_course_id, 'official_course', v_url, 'Official course page', true, 'active', v_src, 1, now())
    on conflict (course_id, link_type, url) do update set status = 'active', is_primary = true, source_id = v_src, confidence = 1,
           last_verified_at = now(), updated_at = now(), evidence_id = null;
    update catalogue.courses set course_url = v_url, updated_at = now() where id = p_course_id;
    insert into pipeline.coverage_course_pages(course_id, provider_id, url, basis, status, bound_at, next_read_at, read_attempts)
    values (p_course_id, v_c.provider_id, v_url, 'manual', 'bound', now(), now(), 0)
    on conflict (course_id) do update set url = excluded.url, basis = 'manual', status = 'bound', bound_at = now(), score = null, runner_up = null,
           read_status = null, read_at = null, http_status = null, fetched_via = null, identity_basis = null, evidence_id = null, candidates = null,
           leased_until = null, read_attempts = 0, next_read_at = now();
    update pipeline.course_link_search set state = 'verified', bound_url = v_url, done_at = now() where course_id = p_course_id;
    perform security.manual_lock_set('course', p_course_id, 'official_url', 'value');
    perform security.manual_lock_set('course', p_course_id, 'course_url', 'value');
    v_after := to_jsonb(v_url);

  elsif p_action = 'remove_official_url' then
    v_field := 'official_url';
    select jsonb_agg(url) into v_before from catalogue.course_links where course_id = p_course_id and link_type = 'official_course' and status = 'active';
    update catalogue.course_links set status = 'inactive', is_primary = false, updated_at = now()
     where course_id = p_course_id and link_type = 'official_course' and status = 'active';
    update catalogue.courses set course_url = null, updated_at = now() where id = p_course_id;
    update pipeline.coverage_course_pages set status = 'mismatch', basis = 'manual', leased_until = null where course_id = p_course_id;
    delete from pipeline.course_link_search where course_id = p_course_id;
    perform security.manual_lock_set('course', p_course_id, 'official_url', 'removed');
    perform security.manual_lock_set('course', p_course_id, 'course_url', 'removed');

  elsif p_action = 'set_intakes' then
    v_field := 'intakes';
    if jsonb_typeof(p_args->'intakes') <> 'array' or jsonb_array_length(p_args->'intakes') = 0 then raise exception 'add at least one intake'; end if;
    select jsonb_agg(jsonb_build_object('label', intake_label, 'year', intake_year, 'start_date', start_date)) into v_before
      from catalogue.course_intakes where course_id = p_course_id and status = 'active';
    update catalogue.course_intakes set status = 'inactive' where course_id = p_course_id and status = 'active';
    for x in select * from jsonb_array_elements(p_args->'intakes') loop
      if nullif(btrim(coalesce(x->>'label', '')), '') is null then raise exception 'each intake needs a name, for example February'; end if;
      insert into catalogue.course_intakes(course_id, intake_year, intake_label, start_date, status, source_id, confidence, source_intake_key)
      values (p_course_id, nullif(x->>'year', '')::int, btrim(x->>'label'), nullif(x->>'start_date', '')::date, 'active', v_src, 1,
              'manual:' || lower(btrim(x->>'label')) || ':' || coalesce(nullif(x->>'year', ''), '') || ':' || coalesce(nullif(x->>'start_date', ''), ''))
      on conflict (course_id, source_id, source_intake_key) where source_id is not null and source_intake_key is not null
      do update set status = 'active', intake_year = excluded.intake_year, start_date = excluded.start_date, confidence = 1;
    end loop;
    perform security.manual_lock_set('course', p_course_id, 'intakes', 'value');
    v_after := p_args->'intakes';

  elsif p_action = 'remove_intakes' then
    v_field := 'intakes';
    select jsonb_agg(jsonb_build_object('label', intake_label, 'year', intake_year)) into v_before from catalogue.course_intakes where course_id = p_course_id and status = 'active';
    update catalogue.course_intakes set status = 'inactive' where course_id = p_course_id and status = 'active';
    perform security.manual_lock_set('course', p_course_id, 'intakes', 'removed');

  elsif p_action = 'set_english' then
    v_field := 'english';
    if jsonb_typeof(p_args->'tests') <> 'array' or jsonb_array_length(p_args->'tests') = 0 then raise exception 'add at least one English test score'; end if;
    select jsonb_agg(jsonb_build_object('test', t.code, 'overall', e.overall_score, 'components', e.component_scores)) into v_before
      from catalogue.course_english_requirements e join ref.english_tests t on t.id = e.english_test_id where e.course_id = p_course_id and e.status = 'active';
    for x in select * from jsonb_array_elements(p_args->'tests') loop
      select id into v_test from ref.english_tests where code = x->>'test';
      if v_test is null then raise exception 'unknown English test %', x->>'test'; end if;
      if (x->>'overall') is null or (x->>'overall') !~ '^[0-9]+(\.[0-9]+)?$' then raise exception 'enter an overall score for %', x->>'test'; end if;
      insert into catalogue.course_english_requirements(course_id, english_test_id, overall_score, component_scores, notes, source_id, evidence_id, confidence, source_requirement_key, status, last_verified_at)
      values (p_course_id, v_test, (x->>'overall')::numeric, coalesce(x->'components', '{}'::jsonb), 'Manual entry', v_src, null, 1, 'manual:' || lower(x->>'test'), 'active', now())
      on conflict (course_id, english_test_id) do update set overall_score = excluded.overall_score, component_scores = excluded.component_scores,
             notes = 'Manual entry', source_id = v_src, evidence_id = null, confidence = 1, source_requirement_key = excluded.source_requirement_key,
             status = 'active', last_verified_at = now();
      v_keep := v_keep || v_test;
    end loop;
    update catalogue.course_english_requirements set status = 'inactive' where course_id = p_course_id and status = 'active' and not (english_test_id = any(v_keep));
    perform security.manual_lock_set('course', p_course_id, 'english', 'value');
    v_after := p_args->'tests';

  elsif p_action = 'remove_english' then
    v_field := 'english';
    select jsonb_agg(jsonb_build_object('test', t.code, 'overall', e.overall_score)) into v_before
      from catalogue.course_english_requirements e join ref.english_tests t on t.id = e.english_test_id where e.course_id = p_course_id and e.status = 'active';
    update catalogue.course_english_requirements set status = 'inactive' where course_id = p_course_id and status = 'active';
    perform security.manual_lock_set('course', p_course_id, 'english', 'removed');

  elsif p_action = 'set_tuition' then
    v_field := 'tuition';
    if coalesce(p_args->>'amount', '') !~ '^[0-9]+(\.[0-9]+)?$' or (p_args->>'amount')::numeric < 100 then raise exception 'enter the fee as a number, for example 45000'; end if;
    if coalesce(p_args->>'basis', 'annual') not in ('annual','total_indicative','per_semester','per_trimester') then raise exception 'choose per year, per semester, per trimester or whole course'; end if;
    v_amount := (p_args->>'amount')::numeric;
    select jsonb_agg(jsonb_build_object('amount', amount, 'year', fee_year, 'basis', basis)) into v_before
      from catalogue.course_fees where course_id = p_course_id and fee_type = 'provider_current_tuition' and status = 'active';
    update catalogue.course_fees set status = 'superseded', updated_at = now(),
           notes = coalesce(notes, '') || ' | superseded by a manual entry ' || to_char(now(), 'YYYY-MM-DD')
     where course_id = p_course_id and fee_type = 'provider_current_tuition' and status = 'active';
    insert into catalogue.course_fees(course_id, fee_year, audience, fee_type, amount, currency_code, basis, notes, source_id, confidence, source_fee_key, status, last_verified_at)
    values (p_course_id, nullif(p_args->>'fee_year', '')::int, 'international', 'provider_current_tuition', v_amount, coalesce(nullif(p_args->>'currency', ''), (select k.default_currency_code::text from catalogue.providers pv join ref.countries k on k.id = pv.country_id where pv.id = v_c.provider_id), 'AUD'),
            coalesce(p_args->>'basis', 'annual'), 'Manual entry', v_src, 1, 'manual:' || extract(epoch from clock_timestamp())::bigint, 'active', now());
    perform security.manual_lock_set('course', p_course_id, 'tuition', 'value');
    v_after := jsonb_build_object('amount', v_amount, 'year', nullif(p_args->>'fee_year', ''), 'basis', coalesce(p_args->>'basis', 'annual'), 'currency', coalesce(nullif(p_args->>'currency', ''), (select k.default_currency_code::text from catalogue.providers pv join ref.countries k on k.id = pv.country_id where pv.id = v_c.provider_id), 'AUD'));

  elsif p_action = 'remove_tuition' then
    v_field := 'tuition';
    select jsonb_agg(jsonb_build_object('amount', amount, 'year', fee_year, 'basis', basis)) into v_before
      from catalogue.course_fees where course_id = p_course_id and fee_type = 'provider_current_tuition' and status = 'active';
    update catalogue.course_fees set status = 'inactive', updated_at = now(), notes = coalesce(notes, '') || ' | removed by hand ' || to_char(now(), 'YYYY-MM-DD')
     where course_id = p_course_id and fee_type = 'provider_current_tuition' and status = 'active';
    perform security.manual_lock_set('course', p_course_id, 'tuition', 'removed');

  elsif p_action = 'release' then
    v_field := p_args->>'field';
    select to_jsonb(l) into v_before from pipeline.manual_locks l where entity = 'course' and entity_id = p_course_id and field = v_field;
    if v_before is null then raise exception 'nothing to release'; end if;
    delete from pipeline.manual_locks where entity = 'course' and entity_id = p_course_id and (field = v_field or (v_field = 'official_url' and field = 'course_url'));
    if v_field = 'official_url' then
      update pipeline.coverage_course_pages set basis = 'released' where course_id = p_course_id and basis = 'manual';
    end if;

  elsif p_action in ('archive','restore') then
    v_field := 'lifecycle_status'; v_before := to_jsonb(v_c.lifecycle_status);
    update catalogue.courses set lifecycle_status = case p_action when 'archive' then 'inactive' else 'active' end, updated_at = now() where id = p_course_id;
    perform security.manual_lock_set('course', p_course_id, 'lifecycle_status', 'value');
    v_after := to_jsonb(case p_action when 'archive' then 'inactive' else 'active' end);
    -- v2.15.238 (R5, gap A): the search documents are rebuilt, so an archived course leaves search and a restored one returns
    insert into search.refresh_requests(requested_by) values (format('course %s %s by hand', left(p_course_id::text, 8), p_action || 'd'));

  else
    raise exception 'unknown action %', p_action;
  end if;

  if v_field in ('official_url','intakes','english','tuition') and p_action <> 'release' then
    perform security.manual_close_layer4(p_course_id, v_field);
  end if;
  insert into pipeline.manual_edit_log(entity, entity_id, field, action, before, after, reason, actor)
  values ('course', p_course_id, v_field, p_action, v_before, v_after, v_reason, auth.uid());
  perform search.refresh_course_enrichment_scoped_v1(array[p_course_id], true);
  return public.admin_course_edit_read(p_course_id);
end $function$;

-- 9. The 10 providers already waiting in Layer 4 › Provider departures (all their registered courses left the register) are archived now.
do $data$
declare r record; n int := 0;
begin
  for r in select d.provider_id from pipeline.layer1_provider_departures d
            where d.status = 'needs_review' and not exists (select 1 from catalogue.courses c where c.provider_id = d.provider_id and c.lifecycle_status = 'active') loop
    if (security.provider_archive_apply_v1(r.provider_id, 'layer1_departure', 'All its registered courses left the register', null, false))->>'status' = 'archived' then n := n + 1; end if;
  end loop;
  raise notice 'archived % providers whose courses left the register', n;
end $data$;

do $post$
declare v_expected jsonb := jsonb_build_object('public.admin_provider_edit(uuid,text,jsonb)', 'bc9e961a21381d479a92ba86ddf59a7b', 'public.admin_provider_edit_read(uuid)', 'c09d51ed8c463712b05f3842dc5f98d9', 'security.layer4_provider_departure_decide_v1(bigint,text,uuid,text)', '920518575f4965d26d00e250ae225754', 'public.admin_course_edit(uuid,text,jsonb)', '3fdf88627652182455859b079b503445');
  v_sig text;
begin
  for v_sig in select jsonb_object_keys(v_expected) loop
    if md5(replace(pg_get_functiondef(v_sig::regprocedure), E'\r', '')) <> v_expected->>v_sig then
      raise exception 'CF-247 v2.15.238 post-check: % not as intended', v_sig;
    end if;
  end loop;
end $post$;
do $post2$
begin
  if (select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace where (n.nspname, p.proname) in (('security','provider_archive_preview_v1'),('security','provider_archive_apply_v1'),
      ('security','provider_restore_v1'),('public','admin_provider_archive'),('public','admin_provider_restore'),('public','admin_archive_read'),('security','trg_departure_archive_v1'),('security','trg_retirement_restore_v1'))) <> 8
     or (select count(*) from pg_trigger where tgname in ('layer1_departure_archive','layer1_retirement_restore') and not tgisinternal) <> 2
     or pg_get_viewdef('security.layer4_search_blocked_courses'::regclass) !~ 'IS DISTINCT FROM ''active''' then
    raise exception 'CF-247 v2.15.238 post-check: new objects not as intended';
  end if;
end $post2$;
