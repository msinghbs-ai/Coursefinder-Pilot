-- CF-247 v2.15.277 (Platform Admin, 14 Oct 2026 20:43: "For ranking, we can pass it on v2 api and for logos we can pass it on as file links to be
-- stored in wix platform with maximun validity. And subsequent api requests only pass changed data unless queried for full load.")
-- Platform Admin decisions (multiple choice): "Yes, approved to display", "1 year, renewed in delta", "New sync action with cursor".
--   1 Rankings and logos approved for display: terms_status reads 'approved' from two settings (Settings > Pipeline settings > Website API),
--     no longer a fixed value in five functions. Switching a setting off returns 'management_decision_pending' again.
--   2 Logo links: valid website.logo_link_days (365) from the edge function, read through svc_website_settings_v1 (no longer 24 hours in code).
--   3 New action "sync" (additive; every existing action answers as before): no cursor or full_load returns everything, in pages; each reply
--     gives next_cursor, and passing it back returns only what changed since, including removals. Entities: reference, provider, logo,
--     rankings, scholarship, course. Change detection: pipeline.website_sync_items keeps a hash of each item as the API returns it and a
--     sequence number; the catalogued job website-sync-check builds items in a rolling pass (batch.website_sync_check a minute) and gives a
--     changed, new or removed item the next sequence number. A logo is given a new number when its link is within
--     website.logo_renew_before_days of expiry, so a delta carries a fresh link before the old one ends.
-- Nothing dropped or deleted.

do $guard$
declare v_expected jsonb := '{"api.website_v2_provider_logo(uuid)": "37fe1dcdc16e99938f0981fd28ea7d9a", "api.website_v2_ranking_summary(uuid)": "5e5b2d19e70cb571c39d40858cdb38f1", "public.website_v2_provider_rankings(uuid)": "4b50d415c1e69cf3bab7c81d6d2b8060", "public.website_v2_rankings(jsonb,integer,integer)": "9a9e95982ae5db7d318e16a86f7ac9cc", "public.website_v2_reference()": "c8f3256cd721ed738166f3eeecc7530d"}'::jsonb;
  v_sig text;
begin
  for v_sig in select jsonb_object_keys(v_expected) loop
    if md5(replace(pg_get_functiondef(v_sig::regprocedure), E'\r', '')) <> v_expected->>v_sig then
      raise exception 'live % differs from the definition this change replaces', v_sig;
    end if;
  end loop;
end $guard$;

-- 1 Settings (Settings > Pipeline settings)
insert into pipeline.platform_toolset_settings(toolset_key, key, label, help, kind, value, min_value, max_value, unit, sort, reason, section, used_by) values
 ('pipeline', 'website.rankings_display_approved', 'Website: rankings approved for display', 'Yes: rankings are returned with terms_status approved and the website may display them. No: terms_status management_decision_pending.', 'boolean', 'true'::jsonb, null, null, 'yes or no', 300, 'Platform Admin 14 Oct 2026 20:43: "For ranking, we can pass it on v2 api" (approved to display)', 'Website API', 'website API v2: rankings, provider rankings, ranking summary, reference'),
 ('pipeline', 'website.logos_display_approved', 'Website: logos approved for display', 'Yes: logos are returned with terms_status approved and the website may display them. No: terms_status management_decision_pending.', 'boolean', 'true'::jsonb, null, null, 'yes or no', 301, 'Platform Admin 14 Oct 2026 20:43: logos passed as file links to be stored on Wix (approved to display)', 'Website API', 'website API v2: provider logo'),
 ('pipeline', 'website.logo_link_days', 'Website: logo link valid for', 'How long a logo link given to the website stays valid. The website copies the file to Wix Media.', 'number', to_jsonb(365), 1, 730, 'days', 302, 'Platform Admin decision 14 Oct 2026: "1 year, renewed in delta"', 'Website API', 'wix-course-api (logo links)'),
 ('pipeline', 'website.logo_renew_before_days', 'Website: resend a logo before its link ends', 'A logo is sent again in the sync delta this many days before its link would end, with a new link.', 'number', to_jsonb(30), 1, 180, 'days', 303, 'Platform Admin decision 14 Oct 2026: "1 year, renewed in delta"', 'Website API', 'website-sync-check job'),
 ('pipeline', 'website.sync_page_max', 'Website: sync items a page (most)', 'The most items one sync reply carries.', 'number', to_jsonb(50), 10, 200, 'items', 304, 'CF-247 v2.15.277: the page size the website contract already uses', 'Website API', 'website API v2: sync'),
 ('pipeline', 'batch.website_sync_check', 'Website sync: items checked a run', 'Items the change check builds and compares each minute (a full pass of about 46,000 items takes about 75 minutes at 600).', 'number', to_jsonb(600), 100, 3000, 'items', 107, 'CF-247 v2.15.277: about 5 seconds a run', 'Job sizes', 'website-sync-check job')
on conflict do nothing;

-- 2 Display terms from the settings
CREATE OR REPLACE FUNCTION security.website_terms_status_v1(p_kind text)
 RETURNS text
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  select case when coalesce((select (s.value #>> '{}')::boolean from pipeline.platform_toolset_settings s
                              where s.toolset_key = 'pipeline' and s.key = 'website.' || p_kind || '_display_approved'), false)
              then 'approved' else 'management_decision_pending' end
$function$;
revoke all on function security.website_terms_status_v1(text) from public, anon, authenticated;
grant execute on function security.website_terms_status_v1(text) to service_role;

-- 3 Settings the edge function reads (service role only)
CREATE OR REPLACE FUNCTION public.svc_website_settings_v1()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  if current_user <> 'postgres' and coalesce(auth.role(), '') <> 'service_role' then raise exception 'service_role required'; end if;
  return jsonb_build_object('logo_link_days', security.pipeline_num_v1('website.logo_link_days', 365),
                            'logo_renew_before_days', security.pipeline_num_v1('website.logo_renew_before_days', 30),
                            'sync_page_max', security.pipeline_num_v1('website.sync_page_max', 50));
end $function$;
revoke all on function public.svc_website_settings_v1() from public, anon, authenticated;
grant execute on function public.svc_website_settings_v1() to service_role;

-- 4 Change tracking
create sequence if not exists pipeline.website_sync_seq;
create table if not exists pipeline.website_sync_items (
  entity text not null check (entity in ('reference', 'provider', 'logo', 'rankings', 'scholarship', 'course')),
  item_key text not null,
  ref_id uuid,
  hash text,
  seq bigint not null,
  seq_at timestamptz not null default now(),
  removed_at timestamptz,
  primary key (entity, item_key));
create index if not exists idx_website_sync_items_seq on pipeline.website_sync_items (seq);
alter table pipeline.website_sync_items enable row level security;
create table if not exists pipeline.website_sync_scan (
  entity text primary key,
  after_key text,
  done boolean not null default false,
  cycles int not null default 0,
  last_cycle_at timestamptz,
  last_run_at timestamptz,
  last_result jsonb);
alter table pipeline.website_sync_scan enable row level security;
insert into pipeline.website_sync_scan(entity) values ('reference'), ('provider'), ('logo'), ('rankings'), ('scholarship'), ('course') on conflict do nothing;

-- One item exactly as the website API returns it (null when the API would not return it)
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
revoke all on function security.website_sync_item_v1(text, uuid, text) from public, anon, authenticated;

-- The keys the check walks for an entity: what could be returned now, plus what was sent before (so a removal is seen)
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
revoke all on function security.website_sync_candidates_v1(text) from public, anon, authenticated;

-- The rolling check (job website-sync-check)
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
      h := case when v is null then null else md5((v - 'generated_at')::text) end;
      select * into it from pipeline.website_sync_items where entity = e and item_key = r.item_key;
      if it.item_key is null then
        if v is not null then
          insert into pipeline.website_sync_items(entity, item_key, ref_id, hash, seq) values (e, r.item_key, r.ref_id, h, nextval('pipeline.website_sync_seq'));
          v_new := v_new + 1;
        end if;
      elsif v is null then
        if it.removed_at is null then
          update pipeline.website_sync_items set removed_at = now(), hash = null, seq = nextval('pipeline.website_sync_seq'), seq_at = now() where entity = e and item_key = r.item_key;
          v_rem := v_rem + 1;
        end if;
      elsif it.removed_at is not null then
        update pipeline.website_sync_items set removed_at = null, hash = h, ref_id = r.ref_id, seq = nextval('pipeline.website_sync_seq'), seq_at = now() where entity = e and item_key = r.item_key;
        v_new := v_new + 1;
      elsif it.hash is null then
        update pipeline.website_sync_items set hash = h, ref_id = r.ref_id where entity = e and item_key = r.item_key;  -- first check: not a change
      elsif it.hash <> h then
        update pipeline.website_sync_items set hash = h, ref_id = r.ref_id, seq = nextval('pipeline.website_sync_seq'), seq_at = now() where entity = e and item_key = r.item_key;
        v_chg := v_chg + 1;
      elsif e = 'logo' and it.seq_at < now() - v_renew then
        update pipeline.website_sync_items set seq = nextval('pipeline.website_sync_seq'), seq_at = now() where entity = e and item_key = r.item_key;
        v_ren := v_ren + 1;
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
revoke all on function security.website_sync_check_v1(integer) from public, anon, authenticated;

-- 5 The sync action
CREATE OR REPLACE FUNCTION public.website_v2_sync(p_cursor text DEFAULT NULL::text, p_full boolean DEFAULT false, p_entities text[] DEFAULT NULL::text[], p_page_size integer DEFAULT NULL::integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_all text[] := array['reference', 'provider', 'logo', 'rankings', 'scholarship', 'course'];
        v_c jsonb; v_mode text; v_a bigint := 0; v_s bigint; v_e text[]; v_max int; v_size int; v_rows jsonb; v_n int; v_more boolean; v_last bigint;
        v_next jsonb; v_items jsonb; t text;
begin
  if current_user <> 'postgres' and coalesce(auth.role(), '') <> 'service_role' then raise exception 'service_role required'; end if;
  if nullif(btrim(p_cursor), '') is not null and not coalesce(p_full, false) then
    begin
      t := translate(btrim(p_cursor), '-_', '+/');
      v_c := convert_from(decode(t || repeat('=', (4 - length(t) % 4) % 4), 'base64'), 'utf8')::jsonb;
    exception when others then return jsonb_build_object('error', jsonb_build_object('code', 'INVALID_INPUT', 'detail', 'cursor'));
    end;
    if v_c->>'v' is distinct from '1' or v_c->>'m' not in ('full', 'delta') or (v_c->>'a') !~ '^\d+$' then
      return jsonb_build_object('error', jsonb_build_object('code', 'INVALID_INPUT', 'detail', 'cursor')); end if;
    v_mode := v_c->>'m'; v_a := (v_c->>'a')::bigint; v_s := nullif(v_c->>'s', '')::bigint;
    v_e := array(select jsonb_array_elements_text(coalesce(v_c->'e', to_jsonb(v_all))));
  else
    v_mode := 'full'; v_a := 0; v_s := (select coalesce(max(seq), 0) from pipeline.website_sync_items);
    v_e := coalesce(nullif(p_entities, '{}'::text[]), v_all);
  end if;
  if not (v_e <@ v_all) or (v_mode = 'full' and v_s is null) then
    return jsonb_build_object('error', jsonb_build_object('code', 'INVALID_INPUT', 'detail', 'entities')); end if;
  v_max := greatest(security.pipeline_num_v1('website.sync_page_max', 50)::int, 1);
  v_size := least(greatest(coalesce(p_page_size, v_max), 1), v_max);
  select coalesce(jsonb_agg(to_jsonb(x) order by x.seq), '[]'::jsonb) into v_rows from (
    select i.entity, i.item_key, i.ref_id, i.seq, i.removed_at from pipeline.website_sync_items i
     where i.entity = any (v_e) and i.seq > v_a
       and (v_mode = 'delta' or (i.removed_at is null and i.seq <= v_s))
     order by i.seq limit v_size + 1) x;
  v_n := jsonb_array_length(v_rows); v_more := v_n > v_size;
  if v_more then v_rows := v_rows - v_size; end if;
  v_last := (v_rows->-1->>'seq')::bigint;
  select coalesce(jsonb_agg(case when z.item is null then jsonb_build_object('entity', z.entity, 'id', z.item_key, 'seq', z.seq, 'change', 'remove')
                                 else jsonb_build_object('entity', z.entity, 'id', z.item_key, 'seq', z.seq, 'change', 'upsert', 'item', z.item) end order by z.seq), '[]'::jsonb)
    into v_items
    from (select r->>'entity' entity, r->>'item_key' item_key, (r->>'seq')::bigint seq,
                 case when r->>'removed_at' is null then security.website_sync_item_v1(r->>'entity', (r->>'ref_id')::uuid, r->>'item_key') end item
            from jsonb_array_elements(v_rows) r) z;
  v_next := case when v_mode = 'full' and v_more then jsonb_build_object('v', 1, 'm', 'full', 'a', v_last, 's', v_s, 'e', to_jsonb(v_e))
                 when v_mode = 'full' then jsonb_build_object('v', 1, 'm', 'delta', 'a', v_s, 'e', to_jsonb(v_e))
                 else jsonb_build_object('v', 1, 'm', 'delta', 'a', coalesce(v_last, v_a), 'e', to_jsonb(v_e)) end;
  return jsonb_build_object(
    'mode', v_mode, 'entities', to_jsonb(v_e), 'items', v_items, 'has_more', v_more,
    'full_load_complete', case when v_mode = 'full' then not v_more end,
    'next_cursor', rtrim(translate(replace(encode(convert_to(v_next::text, 'utf8'), 'base64'), E'\n', ''), '+/', '-_'), '='),
    'checked_through', (select min(s.last_cycle_at) from pipeline.website_sync_scan s where s.entity = any (v_e)),
    'as_of', now());
end $function$;
revoke all on function public.website_v2_sync(text, boolean, text[], integer) from public, anon, authenticated;
grant execute on function public.website_v2_sync(text, boolean, text[], integer) to service_role;

-- 6 The job (catalogued, G1; size from a setting, G2)
insert into pipeline.automation_catalogue(jobname, area, sort, label, description, control_rank, batch_editable)
values ('website-sync-check', 'Search and API', 40, 'Website sync: change check',
        'Every minute: builds website API items in a rolling pass and numbers each new, changed or removed item (and each logo whose link is near its end) for the sync action.', 6, true)
on conflict do nothing;
select cron.schedule('website-sync-check', '* * * * *', 'select security.website_sync_check_v1(security.pipeline_num_v1(''batch.website_sync_check'', 600)::int)');

CREATE OR REPLACE FUNCTION api.website_v2_provider_logo(p_provider_id uuid)
 RETURNS jsonb
 LANGUAGE sql
 STABLE
 SET search_path TO 'pg_catalog', 'catalogue'
AS $function$
  select jsonb_build_object('storage_path', a.storage_path, 'mime_type', a.mime_type, 'content_hash', a.content_hash,
           'updated_at', coalesce(a.verified_at, a.observed_at), 'source_url', a.source_url,
           'attribution', 'Logo of the provider, from the provider''s own website', 'terms_status', security.website_terms_status_v1('logos'))
  from catalogue.provider_assets a
  where a.provider_id = p_provider_id and a.asset_type = 'logo' and a.status = 'approved' and a.is_primary and a.storage_path is not null
  order by coalesce(a.verified_at, a.observed_at) desc nulls last limit 1
$function$;

CREATE OR REPLACE FUNCTION api.website_v2_ranking_summary(p_provider_id uuid)
 RETURNS jsonb
 LANGUAGE sql
 STABLE
 SET search_path TO 'pg_catalog', 'ranking'
AS $function$
  with r as (
    select distinct on (s.code) s.code, e.edition_year, o.rank_display, o.rank_low, o.rank_exact
    from ranking.observation_provider_links l
    join ranking.observations o on o.id = l.observation_id
    join ranking.editions e on e.id = o.edition_id and e.status = 'accepted'
    join ranking.systems s on s.id = e.system_id
    where l.provider_id = p_provider_id
    order by s.code, e.edition_year desc, l.is_primary desc nulls last
  )
  select case when count(*) = 0 then null else jsonb_object_agg(r.code, jsonb_build_object(
    'edition_year', r.edition_year, 'rank_display', r.rank_display, 'rank_low', coalesce(r.rank_low, r.rank_exact),
    'terms_status', security.website_terms_status_v1('rankings'))) end
  from r
$function$;

CREATE OR REPLACE FUNCTION public.website_v2_provider_rankings(p_provider_id uuid)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'ranking'
AS $function$
  select coalesce(jsonb_agg(jsonb_build_object(
      'system_code', s.code, 'system_name', s.ranking_name, 'publisher', s.publisher_name, 'edition_year', e.edition_year,
      'rank_display', o.rank_display, 'rank_low', coalesce(o.rank_low,o.rank_exact), 'rank_high', coalesce(o.rank_high,o.rank_exact), 'is_tied', coalesce(o.is_tied,false),
      'overall_score_display', o.overall_score_display,
      'indicators', (select coalesce(jsonb_agg(jsonb_build_object('code', io.indicator_code, 'label', io.indicator_label, 'value_display', io.value_display, 'rank_display', io.rank_display) order by io.indicator_code), '[]'::jsonb)
                     from ranking.indicator_observations io where io.observation_id=o.id),
      'methodology_url', e.methodology_url, 'source_url', coalesce(e.source_url, s.official_url),
      'attribution', s.publisher_name || ', ' || s.ranking_name || ' ' || e.edition_year,
      'terms_status', security.website_terms_status_v1('rankings'))
    order by s.code, e.edition_year desc), '[]'::jsonb)
  from (select distinct on (o2.edition_id) o2.* from ranking.observation_provider_links l join ranking.observations o2 on o2.id=l.observation_id
        where l.provider_id=p_provider_id order by o2.edition_id, l.is_primary desc nulls last) o
  join ranking.editions e on e.id=o.edition_id and e.status='accepted' join ranking.systems s on s.id=e.system_id
$function$;

CREATE OR REPLACE FUNCTION public.website_v2_rankings(p_filters jsonb DEFAULT '{}'::jsonb, p_page integer DEFAULT 1, p_page_size integer DEFAULT 20)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'ranking', 'catalogue', 'ref', 'search', 'security', 'api'
AS $function$
declare
  f jsonb := coalesce(p_filters,'{}'::jsonb);
  v_page int := coalesce(p_page,1); v_size int := coalesce(p_page_size,20);
  v_systems text[] := coalesce(api.website_text_array(f->'system_codes'), array['qs_wur','the_wur']);
  v_year int := nullif(f->>'edition_year','')::int;
  v_countries text[] := (select array_agg(upper(x)) from unnest(api.website_text_array(coalesce(f->'country_codes',f->'country_code'))) x);
  v_providers text[] := api.website_text_array(f->'provider_ids');
  v_rank_max int := nullif(f->>'rank_max','')::int;
  v_known text[] := array['system_codes','edition_year','country_codes','country_code','provider_ids','rank_max'];
  v_not_applied jsonb; v_total bigint; v_items jsonb;
begin
  if v_page < 1 or v_size < 1 or v_size > 50 then raise exception 'INVALID_INPUT: page must be >= 1 and page_size 1-50' using errcode='22023'; end if;
  select coalesce(jsonb_agg(k),'[]'::jsonb) into v_not_applied from jsonb_object_keys(f) k where k <> all(v_known);
  with ed as (
    select e.id, e.edition_year, s.code, s.ranking_name, s.publisher_name, e.methodology_url, coalesce(e.source_url, s.official_url) source_url
    from ranking.editions e join ranking.systems s on s.id=e.system_id
    where e.status='accepted' and s.code = any(v_systems)
      and e.edition_year = coalesce(v_year, (select max(e2.edition_year) from ranking.editions e2 where e2.system_id=s.id and e2.status='accepted'))
  ), rows as (
    select distinct on (ed.id, l.provider_id) ed.*, o.id obs_id, o.rank_display, coalesce(o.rank_low,o.rank_exact) rank_low, coalesce(o.rank_high,o.rank_exact) rank_high,
           coalesce(o.is_tied,false) is_tied, o.overall_score_display, l.provider_id, p.stable_key provider_stable_key, coalesce(p.display_name,p.canonical_name) provider_name, c.iso_alpha2 country_code
    from ed join ranking.observations o on o.edition_id=ed.id
    join ranking.observation_provider_links l on l.observation_id=o.id
    join catalogue.providers p on p.id=l.provider_id join ref.countries c on c.id=p.country_id
    where (v_countries is null or trim(c.iso_alpha2::text) = any(v_countries))
      and not exists (select 1 from security.layer4_search_blocked_providers b where b.provider_id = p.id)  -- v2.15.236
      and (v_providers is null or p.stable_key = any(v_providers))
      and (v_rank_max is null or coalesce(o.rank_low,o.rank_exact) <= v_rank_max)
    order by ed.id, l.provider_id, l.is_primary desc nulls last
  ), ordered as (select *, count(*) over () total, row_number() over (order by code, rank_low nulls last, provider_name) rn from rows)
  select coalesce(max(total),0), coalesce(jsonb_agg(jsonb_build_object(
      'provider', jsonb_build_object('provider_id', o.provider_stable_key, 'name', security.provider_presentable_name(o.provider_name), 'country_code', trim(o.country_code::text), 'logo', api.website_v2_provider_logo(o.provider_id)),
      'system_code', o.code, 'system_name', o.ranking_name, 'publisher', o.publisher_name, 'edition_year', o.edition_year,
      'rank_display', o.rank_display, 'rank_low', o.rank_low, 'rank_high', o.rank_high, 'is_tied', o.is_tied, 'overall_score_display', o.overall_score_display,
      'indicators', (select coalesce(jsonb_agg(jsonb_build_object('code', io.indicator_code, 'label', io.indicator_label, 'value_display', io.value_display, 'rank_display', io.rank_display) order by io.indicator_code), '[]'::jsonb)
                     from ranking.indicator_observations io where io.observation_id=o.obs_id),
      'methodology_url', o.methodology_url, 'source_url', o.source_url,
      'attribution', o.publisher_name || ', ' || o.ranking_name || ' ' || o.edition_year,
      'terms_status', security.website_terms_status_v1('rankings')) order by o.rn) filter (where o.rn > (v_page-1)*v_size and o.rn <= v_page*v_size), '[]'::jsonb)
  into v_total, v_items from ordered o;
  return jsonb_build_object('contract_version','website-search-v2','total',v_total,'page',v_page,'page_size',v_size,'filters_not_applied',v_not_applied,'items',v_items);
end $function$;

CREATE OR REPLACE FUNCTION public.website_v2_reference()
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'search', 'ref', 'catalogue', 'scholarship', 'security', 'api'
AS $function$
  select jsonb_build_object(
    'contract_version','website-search-v2',
    'countries', (select jsonb_agg(jsonb_build_object(
        'country_code', c.country_code, 'courses', c.n,
        'study_levels', (select jsonb_agg(jsonb_build_object('code', x.code, 'name', (select sl.name from ref.study_levels sl where sl.code=x.code limit 1), 'courses', x.n) order by x.n desc)
                         from (select study_level_code code, count(*) n from search.course_documents where country_code=c.country_code and study_level_code is not null group by 1) x),
        'study_areas', (select jsonb_agg(jsonb_build_object('code', x.code, 'name', x.name, 'courses', x.n) order by x.n desc)
                        from (select primary_field_code code, min(primary_field_name) name, count(*) n from search.course_documents where country_code=c.country_code and primary_field_code is not null group by 1) x),
        'subdivisions', (select jsonb_agg(jsonb_build_object('code', x.code, 'courses', x.n) order by x.code)
                         from (select s code, count(*) n from search.course_documents d, unnest(d.subdivision_codes) s where d.country_code=c.country_code group by 1) x),
        'cities', (select jsonb_agg(jsonb_build_object('city', x.city, 'metro_area', x.metro, 'courses', x.n) order by x.n desc)
                   from (select security.place_presentable(k.city) city, min(rc.metro_area) metro, count(distinct cc.course_id) n
                         from search.course_documents d join catalogue.course_campuses cc on cc.course_id=d.course_id join catalogue.campuses k on k.id=cc.campus_id
                         left join pipeline.campus_regional_class rc on rc.campus_id=k.id
                         where d.country_code=c.country_code and nullif(btrim(k.city),'') is not null group by 1 having count(distinct cc.course_id) >= 5) x),
        'intake_months', (select jsonb_agg(jsonb_build_object('month', x.m, 'courses', x.n) order by x.m)
                          from (select api.website_v2_label_month(i->>'label') m, count(distinct d.course_id) n from search.course_documents d, jsonb_array_elements(coalesce(d.intake_options,'[]'::jsonb)) i
                                where d.country_code=c.country_code and api.website_v2_label_month(i->>'label') is not null group by 1) x),
        'english_tests', (select jsonb_agg(jsonb_build_object('code', x.code, 'courses', x.n) order by x.n desc)
                          from (select upper(e->>'test_code') code, count(distinct d.course_id) n from search.course_documents d, jsonb_array_elements(coalesce(d.english_requirement_options,'[]'::jsonb)) e
                                where d.country_code=c.country_code and e->>'test_code' is not null group by 1) x)
      ) order by c.n desc) from (select country_code, count(*) n from search.course_documents group by 1) c),
    'regional_categories', jsonb_build_array(jsonb_build_object('code',1,'name','Major city'), jsonb_build_object('code',2,'name','City or major regional centre'), jsonb_build_object('code',3,'name','Regional centre or other regional area')),
    'institution_types', (select jsonb_agg(jsonb_build_object('code', t.code, 'name', t.name, 'description', t.description,
                             'providers', (select count(*) from catalogue.providers p where p.provider_type_id = t.id and p.publication_status = 'published' and p.lifecycle_status = 'active')) order by t.name)
                           from ref.provider_types t where t.status = 'active'),
    'university_groups', (select jsonb_agg(jsonb_build_object('code', replace(gic.code,'au_',''), 'name', gic.name,
                           'members', (select count(*) from catalogue.provider_collection_memberships gm where gm.collection_id=gic.id and gm.status='active')))
                          from ref.institution_collections gic where gic.collection_type='university_group' and gic.status='active'),
    'ranking_systems', (select jsonb_agg(jsonb_build_object('code', s.code, 'name', s.ranking_name, 'publisher', s.publisher_name,
                         'editions', (select jsonb_agg(e.edition_year order by e.edition_year desc) from ranking.editions e where e.system_id=s.id and e.status='accepted'),
                         'terms_status', security.website_terms_status_v1('rankings'))) from ranking.systems s where exists (select 1 from ranking.editions e where e.system_id=s.id and e.status='accepted')),
    'scholarship_amount_types', jsonb_build_array('percentage_tuition','fixed_amount','full_tuition'),
    'scholarship_study_stages', jsonb_build_array('commencing','current'),
    'scholarship_student_types', jsonb_build_array('international','domestic','both'),
    'course_sorts', jsonb_build_array('relevance','title_asc','tuition_annual_asc','tuition_annual_desc','duration_asc','updated_asc'),
    'provider_sorts', jsonb_build_array('name_asc','qs_rank_asc','the_rank_asc','course_count_desc'),
    'generated_at', now())
$function$;

-- 7 First numbering, so a full load works at once (hash null: the first check records it without counting a change)
insert into pipeline.website_sync_items(entity, item_key, ref_id, seq) values ('reference', 'reference', null, nextval('pipeline.website_sync_seq')) on conflict do nothing;
insert into pipeline.website_sync_items(entity, item_key, ref_id, seq)
select 'provider', p.stable_key, p.id, nextval('pipeline.website_sync_seq')
  from (select p.stable_key, p.id from catalogue.providers p where p.stable_key is not null
          and p.id not in (select h.provider_id from security.provider_hidden_v1 h where h.provider_id is not null)
          and exists (select 1 from search.course_documents d where d.provider_id = p.id) order by p.stable_key) p
on conflict do nothing;
insert into pipeline.website_sync_items(entity, item_key, ref_id, seq)
select 'logo', i.item_key, i.ref_id, nextval('pipeline.website_sync_seq') from (select * from pipeline.website_sync_items where entity = 'provider' order by seq) i
 where api.website_v2_provider_logo(i.ref_id) is not null
on conflict do nothing;
insert into pipeline.website_sync_items(entity, item_key, ref_id, seq)
select 'rankings', i.item_key, i.ref_id, nextval('pipeline.website_sync_seq') from (select * from pipeline.website_sync_items where entity = 'provider' order by seq) i
 where jsonb_array_length(coalesce(public.website_v2_provider_rankings(i.ref_id), '[]'::jsonb)) > 0
on conflict do nothing;
do $$ declare v_page int := 1; v jsonb; begin
  loop
    v := public.website_v2_scholarships('{}'::jsonb, v_page, 50);
    exit when jsonb_array_length(coalesce(v->'items', '[]'::jsonb)) = 0;
    insert into pipeline.website_sync_items(entity, item_key, ref_id, seq)
    select 'scholarship', x->>'scholarship_id', s.id, nextval('pipeline.website_sync_seq')
      from jsonb_array_elements(v->'items') x join scholarship.scholarships s on s.stable_key = x->>'scholarship_id'
    on conflict do nothing;
    v_page := v_page + 1;
    exit when v_page > 1000;  -- fixed: safety stop for the first numbering loop
  end loop;
end $$;
insert into pipeline.website_sync_items(entity, item_key, ref_id, seq)
select 'course', d.course_stable_key, d.course_id, nextval('pipeline.website_sync_seq')
  from (select d.course_stable_key, d.course_id from search.course_documents d where d.course_stable_key is not null
          and not exists (select 1 from security.layer4_search_blocked_courses b where b.course_id = d.course_id) order by d.course_stable_key) d
on conflict do nothing;

do $post$
declare v_expected jsonb := '{"api.website_v2_provider_logo(uuid)": "ed09e7d2016f7b4e1bae1f6471fd97db", "api.website_v2_ranking_summary(uuid)": "889a4c7f140362f985309aac65aa3419", "public.website_v2_provider_rankings(uuid)": "173e3a9fc579cf82273e8472b343f411", "public.website_v2_rankings(jsonb,integer,integer)": "9c5f725e1865f0b3d77a29c06137b328", "public.website_v2_reference()": "28ea2093f42a1886380ae444b6bf37dd"}'::jsonb;
  v_sig text;
begin
  for v_sig in select jsonb_object_keys(v_expected) loop
    if md5(replace(pg_get_functiondef(v_sig::regprocedure), E'\r', '')) <> v_expected->>v_sig then
      raise exception 'v2.15.277 post-check: % not as intended', v_sig;
    end if;
  end loop;
end $post$;

do $$ declare n jsonb; begin
  select jsonb_object_agg(entity, c) into n from (select entity, count(*) c from pipeline.website_sync_items group by entity) z;
  if coalesce((n->>'course')::int, 0) < 30000 or coalesce((n->>'provider')::int, 0) < 1500 or coalesce((n->>'scholarship')::int, 0) < 1000 or (n->>'reference')::int <> 1 then
    raise exception 'v2.15.277 post-check: first numbering incomplete %', n; end if;
  if security.website_terms_status_v1('rankings') <> 'approved' or security.website_terms_status_v1('logos') <> 'approved' then
    raise exception 'v2.15.277 post-check: display terms not approved'; end if;
  if (select count(*) from cron.job where jobname = 'website-sync-check' and active) <> 1 then raise exception 'v2.15.277 post-check: job missing'; end if;
end $$;

do $t$ declare r jsonb := '{}'::jsonb; s jsonb; c text; a bigint; begin
  select max(seq) into a from pipeline.website_sync_items;
  c := rtrim(translate(replace(encode(convert_to(jsonb_build_object('v',1,'m','delta','a',a,'e',jsonb_build_array('course'))::text,'utf8'),'base64'),E'\n',''),'+/','-_'),'=');
  s := public.website_v2_sync(c, false, null, 50);
  r := r || jsonb_build_object('empty_before', jsonb_array_length(s->'items'));
  update pipeline.website_sync_scan set done = true where entity <> 'course';
  insert into pipeline.website_sync_items(entity, item_key, ref_id, hash, seq) values ('course', 'course:fake:zzz', null, 'h', nextval('pipeline.website_sync_seq'));
  update pipeline.website_sync_scan set after_key = 'course:fake:zzy' where entity = 'course';
  perform security.website_sync_check_v1(1);
  s := public.website_v2_sync(c, false, null, 50);
  r := r || jsonb_build_object('delta_items', jsonb_array_length(s->'items'), 'item', s->'items'->-1, 'next_differs', (s->>'next_cursor') <> c);
  s := public.website_v2_sync(s->>'next_cursor', false, null, 50);
  r := r || jsonb_build_object('after_consumed', jsonb_array_length(s->'items'));
  raise exception 'TESTRESULT %', r;
end $t$;
