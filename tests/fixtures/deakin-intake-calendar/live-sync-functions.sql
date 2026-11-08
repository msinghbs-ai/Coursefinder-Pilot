-- Guards: IQ-00313 (Deakin commencement-date contamination, 8 Nov 2026): the live Website and Zoho change-check functions, verbatim.
-- Each definition is the text of pg_get_functiondef read from production (fxcwkweaxjtknorudmwp) on 8 Nov 2026; tests/fixtures/deakin-intake-calendar/run.sh
-- checks the md5 of each against the production value, so the reconciliation test runs the scans the platform runs, not a copy written for the test.
-- website_sync_item_v1 cd15a2cb4c5cdb72c19c7792d9db430f, zoho_sync_item_v1 a4dce41ec4fd06e5262fdc7eb3e851d0, website_sync_check_v1 f8095625ca8c09526900c78c73a21a91,
-- zoho_sync_check_v1 ea89266fb8d0bccb6226b463b92aac4e, website_sync_candidates_v1 7ec06b8f3d039acc243a23c1db755864, zoho_sync_candidates_v1 d11a91ed6690ee705599e26d4e99b58a,
-- zoho_v2_course_extra_v1 95d188d374b3edbf0b5cdcdc910c2e1a.
set check_function_bodies = off;

CREATE OR REPLACE FUNCTION security.website_sync_item_v1(p_entity text, p_ref uuid, p_key text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v jsonb;
begin
  if p_entity = 'course' then v := case when p_ref is null then null else api.website_v2_course_item(p_ref, null, null) end;  -- the search item (Wix CF_Courses)
  elsif p_entity = 'scholarship' then v := public.website_v2_scholarship(p_key)->'item';
  elsif p_entity = 'reference' then v := public.website_v2_reference();
  elsif p_entity in ('provider', 'logo', 'rankings') then
    if p_ref is null or exists (select 1 from security.provider_hidden_v1 h where h.provider_id = p_ref)
       or not exists (select 1 from search.course_documents d where d.provider_id = p_ref) then return null; end if;
    if p_entity = 'provider' then v := public.website_v2_provider(p_key)->'item';
    elsif p_entity = 'logo' then
      v := api.website_v2_provider_logo(p_ref);
      v := case when v is null or v = 'null'::jsonb then null else jsonb_build_object('provider_id', p_key, 'logo', v) end;
    else
      v := public.website_v2_provider_rankings(p_ref);
      v := case when v is null or jsonb_typeof(v) <> 'array' or jsonb_array_length(v) = 0 then null else jsonb_build_object('provider_id', p_key, 'rankings', v) end;
    end if;
  end if;
  return case when v = 'null'::jsonb then null else v end;
end $function$;

CREATE OR REPLACE FUNCTION security.zoho_sync_item_v1(p_entity text, p_ref uuid, p_key text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v jsonb; v_country boolean;
begin
  if p_ref is null then return null; end if;
  if p_entity = 'provider' then
    select exists (select 1 from catalogue.providers p join ref.countries c on c.id = p.country_id where p.id = p_ref
                    and c.iso_alpha2 in (select jsonb_array_elements_text(coalesce((select s.value from pipeline.platform_toolset_settings s where s.toolset_key = 'pipeline' and s.key = 'zoho.sync_countries'), '["AU"]'::jsonb))))
      into v_country;
    v := case when v_country then security.zoho_v2_provider_item_v1(p_ref) end;
  elsif p_entity = 'campus' then
    v := security.zoho_v2_campus_item_v1(p_ref);
    if v is not null and not (v->>'country_code' in (select jsonb_array_elements_text(coalesce((select s.value from pipeline.platform_toolset_settings s where s.toolset_key = 'pipeline' and s.key = 'zoho.sync_countries'), '["AU"]'::jsonb)))) then v := null; end if;
  elsif p_entity = 'contact' then
    v := security.zoho_v2_contact_item_v1(p_key);
  elsif p_entity = 'course' then
    -- the website's stored course item (already built by its change check), else built now; then the Zoho extras
    select w.item into v from pipeline.website_sync_items w where w.entity = 'course' and w.item_key = p_key and w.removed_at is null;
    if v is null and exists (select 1 from search.course_documents d where d.course_id = p_ref) then v := api.website_v2_course_item(p_ref, null, null); end if;
    v := security.zoho_v2_course_extra_v1(v, p_ref);
    if v is not null and not (v->>'country_code' in (select jsonb_array_elements_text(coalesce((select s.value from pipeline.platform_toolset_settings s where s.toolset_key = 'pipeline' and s.key = 'zoho.sync_countries'), '["AU"]'::jsonb)))) then v := null; end if;
  end if;
  return case when v = 'null'::jsonb then null else v end;
end $function$;

CREATE OR REPLACE FUNCTION security.website_sync_check_v1(p_items integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_left int := greatest(coalesce(p_items, 0), 1); e text; r record; v jsonb; h text; it pipeline.website_sync_items%rowtype;
        st pipeline.website_sync_scan%rowtype; v_lim int; v_cnt int; v_w int; v_out jsonb := '{}'::jsonb; v_new int; v_chg int; v_rem int; v_ren int; v_renew interval;
begin
  if not pg_try_advisory_xact_lock(hashtext('website-sync-check')) then return jsonb_build_object('skipped', 'another run is working'); end if;  -- fixed: one run at a time
  v_renew := make_interval(days => greatest(security.pipeline_num_v1('website.logo_link_days', 365) - security.pipeline_num_v1('website.logo_renew_before_days', 30), 1)::int);
  -- a pass walks the entities in order; each run carries on where the last stopped; a new pass starts when all are done
  if not exists (select 1 from pipeline.website_sync_scan where not done) then update pipeline.website_sync_scan set done = false; end if;
  foreach e in array array['reference', 'provider', 'logo', 'rankings', 'scholarship', 'course'] loop
    exit when v_left <= 0;
    select * into st from pipeline.website_sync_scan where entity = e for update;
    continue when st.done;
    v_w := case e when 'reference' then 200 when 'provider' then 8 else 1 end;  -- fixed: build cost relative to a course item, measured 14 Oct 2026
    v_lim := greatest(ceil(v_left::numeric / v_w)::int, 1); v_cnt := 0; v_new := 0; v_chg := 0; v_rem := 0; v_ren := 0;
    for r in select c.item_key, c.ref_id from security.website_sync_candidates_v1(e) c
              where st.after_key is null or c.item_key > st.after_key order by c.item_key limit v_lim loop
      v_cnt := v_cnt + 1; v_left := v_left - v_w;
      v := security.website_sync_item_v1(e, r.ref_id, r.item_key);
      h := case when v is null then null else md5((v - 'generated_at' - 'freshness')::text) end;  -- CF-247 16 Oct 2026: freshness timestamps are not a change
      select * into it from pipeline.website_sync_items where entity = e and item_key = r.item_key;
      if it.item_key is null then
        if v is not null then
          insert into pipeline.website_sync_items(entity, item_key, ref_id, hash, seq, item) values (e, r.item_key, r.ref_id, h, nextval('pipeline.website_sync_seq'), v);
          v_new := v_new + 1;
        end if;
      elsif v is null then
        if it.removed_at is null then
          update pipeline.website_sync_items set removed_at = now(), hash = null, item = null, seq = nextval('pipeline.website_sync_seq'), seq_at = now() where entity = e and item_key = r.item_key;
          v_rem := v_rem + 1;
        end if;
      elsif it.removed_at is not null then
        update pipeline.website_sync_items set removed_at = null, hash = h, item = v, ref_id = r.ref_id, seq = nextval('pipeline.website_sync_seq'), seq_at = now() where entity = e and item_key = r.item_key;
        v_new := v_new + 1;
      elsif it.hash is null then
        update pipeline.website_sync_items set hash = h, item = v, ref_id = r.ref_id where entity = e and item_key = r.item_key;  -- first check: not a change
      elsif it.hash <> h then
        update pipeline.website_sync_items set hash = h, item = v, ref_id = r.ref_id, seq = nextval('pipeline.website_sync_seq'), seq_at = now() where entity = e and item_key = r.item_key;
        v_chg := v_chg + 1;
      elsif e = 'logo' and it.seq_at < now() - v_renew then
        update pipeline.website_sync_items set item = v, seq = nextval('pipeline.website_sync_seq'), seq_at = now() where entity = e and item_key = r.item_key;
        v_ren := v_ren + 1;
      elsif it.item is null then
        update pipeline.website_sync_items set item = v where entity = e and item_key = r.item_key;  -- CF-247 15 Oct 2026: unchanged, stored for sync
      end if;
      st.after_key := r.item_key;
    end loop;
    if v_cnt < v_lim then
      update pipeline.website_sync_scan set after_key = null, done = true, cycles = cycles + 1, last_cycle_at = now(), last_run_at = now(),
             last_result = jsonb_build_object('checked', v_cnt, 'new', v_new, 'changed', v_chg, 'removed', v_rem, 'renewed', v_ren) where entity = e;
    else
      update pipeline.website_sync_scan set after_key = st.after_key, last_run_at = now(),
             last_result = jsonb_build_object('checked', v_cnt, 'new', v_new, 'changed', v_chg, 'removed', v_rem, 'renewed', v_ren) where entity = e;
    end if;
    v_out := v_out || jsonb_build_object(e, jsonb_build_object('checked', v_cnt, 'new', v_new, 'changed', v_chg, 'removed', v_rem, 'renewed', v_ren));
  end loop;
  return v_out;
end $function$;

CREATE OR REPLACE FUNCTION security.zoho_sync_check_v1(p_items integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_left int := greatest(coalesce(p_items, 0), 1); e text; r record; v jsonb; h text; it pipeline.zoho_sync_items%rowtype;
        st pipeline.zoho_sync_scan%rowtype; v_lim int; v_cnt int; v_w int; v_out jsonb := '{}'::jsonb; v_new int; v_chg int; v_rem int; v_ren int; v_renew interval;
begin
  if not pg_try_advisory_xact_lock(hashtext('zoho-sync-check')) then return jsonb_build_object('skipped', 'another run is working'); end if;  -- fixed: one run at a time
  v_renew := make_interval(days => greatest(security.pipeline_num_v1('zoho.logo_link_days', 365) - security.pipeline_num_v1('zoho.logo_renew_before_days', 30), 1)::int);
  -- a pass walks the entities in order; each run carries on where the last stopped; a new pass starts when all are done
  if not exists (select 1 from pipeline.zoho_sync_scan where not done) then update pipeline.zoho_sync_scan set done = false; end if;
  foreach e in array array['provider', 'campus', 'contact', 'course'] loop
    exit when v_left <= 0;
    select * into st from pipeline.zoho_sync_scan where entity = e for update;
    continue when st.done;
    v_w := 1;  -- fixed: every Zoho item is about one course's build cost (providers and courses reuse stored items), measured 16 Oct 2026
    v_lim := greatest(ceil(v_left::numeric / v_w)::int, 1); v_cnt := 0; v_new := 0; v_chg := 0; v_rem := 0; v_ren := 0;
    for r in select c.item_key, c.ref_id from security.zoho_sync_candidates_v1(e) c
              where st.after_key is null or c.item_key > st.after_key order by c.item_key limit v_lim loop
      v_cnt := v_cnt + 1; v_left := v_left - v_w;
      v := security.zoho_sync_item_v1(e, r.ref_id, r.item_key);
      h := case when v is null then null else md5((v - 'generated_at' - 'freshness')::text) end;  -- CF-247 16 Oct 2026: freshness timestamps are not a change
      select * into it from pipeline.zoho_sync_items where entity = e and item_key = r.item_key;
      if it.item_key is null then
        if v is not null then
          insert into pipeline.zoho_sync_items(entity, item_key, ref_id, hash, seq, item) values (e, r.item_key, r.ref_id, h, nextval('pipeline.zoho_sync_seq'), v);
          v_new := v_new + 1;
        end if;
      elsif v is null then
        if it.removed_at is null then
          update pipeline.zoho_sync_items set removed_at = now(), hash = null, item = null, seq = nextval('pipeline.zoho_sync_seq'), seq_at = now() where entity = e and item_key = r.item_key;
          v_rem := v_rem + 1;
        end if;
      elsif it.removed_at is not null then
        update pipeline.zoho_sync_items set removed_at = null, hash = h, item = v, ref_id = r.ref_id, seq = nextval('pipeline.zoho_sync_seq'), seq_at = now() where entity = e and item_key = r.item_key;
        v_new := v_new + 1;
      elsif it.hash is null then
        update pipeline.zoho_sync_items set hash = h, item = v, ref_id = r.ref_id where entity = e and item_key = r.item_key;  -- first check: not a change
      elsif it.hash <> h then
        update pipeline.zoho_sync_items set hash = h, item = v, ref_id = r.ref_id, seq = nextval('pipeline.zoho_sync_seq'), seq_at = now() where entity = e and item_key = r.item_key;
        v_chg := v_chg + 1;
      elsif e = 'provider' and it.item ? 'logo' and it.seq_at < now() - v_renew then  -- a provider whose logo link is near its end is sent again
        update pipeline.zoho_sync_items set item = v, seq = nextval('pipeline.zoho_sync_seq'), seq_at = now() where entity = e and item_key = r.item_key;
        v_ren := v_ren + 1;
      elsif it.item is null then
        update pipeline.zoho_sync_items set item = v where entity = e and item_key = r.item_key;  -- CF-247 15 Oct 2026: unchanged, stored for sync
      end if;
      st.after_key := r.item_key;
    end loop;
    if v_cnt < v_lim then
      update pipeline.zoho_sync_scan set after_key = null, done = true, cycles = cycles + 1, last_cycle_at = now(), last_run_at = now(),
             last_result = jsonb_build_object('checked', v_cnt, 'new', v_new, 'changed', v_chg, 'removed', v_rem, 'renewed', v_ren) where entity = e;
    else
      update pipeline.zoho_sync_scan set after_key = st.after_key, last_run_at = now(),
             last_result = jsonb_build_object('checked', v_cnt, 'new', v_new, 'changed', v_chg, 'removed', v_rem, 'renewed', v_ren) where entity = e;
    end if;
    v_out := v_out || jsonb_build_object(e, jsonb_build_object('checked', v_cnt, 'new', v_new, 'changed', v_chg, 'removed', v_rem, 'renewed', v_ren));
  end loop;
  return v_out;
end $function$;

CREATE OR REPLACE FUNCTION security.website_sync_candidates_v1(p_entity text)
 RETURNS TABLE(item_key text, ref_id uuid)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  select k, max(r::text)::uuid from (
    select 'reference' k, null::uuid r where p_entity = 'reference'
    union all
    select p.stable_key, p.id from catalogue.providers p
     where p_entity in ('provider', 'logo', 'rankings') and p.stable_key is not null
       and p.id not in (select h.provider_id from security.provider_hidden_v1 h where h.provider_id is not null)
       and exists (select 1 from search.course_documents d where d.provider_id = p.id)
    union all
    select s.stable_key, s.id from scholarship.scholarships s where p_entity = 'scholarship' and s.stable_key is not null
    union all
    select d.course_stable_key, d.course_id from search.course_documents d where p_entity = 'course' and d.course_stable_key is not null
    union all
    select i.item_key, i.ref_id from pipeline.website_sync_items i where i.entity = p_entity and i.removed_at is null) z
  group by k
$function$;

CREATE OR REPLACE FUNCTION security.zoho_sync_candidates_v1(p_entity text)
 RETURNS TABLE(item_key text, ref_id uuid)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  with cn as (select c.id from ref.countries c
               where c.iso_alpha2 in (select jsonb_array_elements_text(coalesce((select s.value from pipeline.platform_toolset_settings s
                                       where s.toolset_key = 'pipeline' and s.key = 'zoho.sync_countries'), '["AU"]'::jsonb)))),
       pv as (select p.id, p.stable_key from catalogue.providers p
               where p.lifecycle_status = 'active' and p.stable_key is not null and p.country_id in (select id from cn)
                 and not exists (select 1 from security.provider_hidden_v1 h where h.provider_id = p.id))
  select k, max(r::text)::uuid from (
    select pv.stable_key k, pv.id r from pv where p_entity = 'provider'
    union all
    select coalesce(k.stable_key, k.id::text), k.id from catalogue.campuses k where p_entity = 'campus' and k.provider_id in (select id from pv) and coalesce(k.status, 'active') = 'active'
    union all
    select 'pt:' || cp.id, cp.provider_id from pipeline.provider_contact_points cp where p_entity = 'contact' and cp.is_current and cp.provider_id in (select id from pv)
    union all
    select 'pc:' || pc.id, pc.provider_id from pipeline.provider_contacts pc where p_entity = 'contact' and pc.lifecycle_status = 'active' and pc.deleted_at is null and pc.provider_id in (select id from pv)
    union all
    select d.course_stable_key, d.course_id from search.course_documents d where p_entity = 'course' and d.course_stable_key is not null and d.provider_id in (select id from pv)
    union all
    select i.item_key, i.ref_id from pipeline.zoho_sync_items i where i.entity = p_entity and i.removed_at is null) z
  group by k
$function$;

CREATE OR REPLACE FUNCTION security.zoho_v2_course_extra_v1(p_item jsonb, p_course_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v jsonb := p_item; v_pid uuid;
begin
  if v is null or v = 'null'::jsonb then return null; end if;
  select c.provider_id into v_pid from catalogue.courses c where c.id = p_course_id;
  v := v || jsonb_build_object(
    'cricos_course_code', (select upper(cr.registration_code) from catalogue.course_registrations cr where cr.course_id = p_course_id and lower(cr.scheme) = 'cricos' order by cr.registration_code limit 1),
    'publication_status', 'published');  -- Zoho v2: returned items are those the provider Published switch allows
  if jsonb_typeof(v->'provider') = 'object' then
    v := jsonb_set(v, '{provider,cricos_provider_code}', coalesce(to_jsonb(security.zoho_v2_provider_cricos_v1(v_pid)), 'null'::jsonb));
  end if;
  return v;
end $function$;

set check_function_bodies = on;
