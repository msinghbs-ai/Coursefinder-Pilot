-- CF-247 (15 Oct 2026): faster Wix full load. Platform Admin 17:46: "How can we burst it for wix"; decision (multiple choice): "Prepared items +
-- bigger pages". A full load was 1,426 sync calls (about 25 minutes): each call needs the previous cursor, and every item was built again on each
-- call (about 15 ms a course, 150 ms a provider) although the change check had already built it to compare. The change check now keeps the item
-- it built; sync serves that copy and fills a page by size; pages may hold up to 200 items.
-- Replaces: sync's per-call item build (now the stored copy, built on the fly only until the change check has stored it) and the fixed build-cost
--   weights per page (now the item's size)
-- Retires: nothing
-- 1 Column pipeline.website_sync_items.item  2 Settings  3 Change check stores the item  4 Sync serves it  Nothing dropped or deleted.

do $guard$
declare v_expected jsonb := '{"security.website_sync_check_v1(integer)": "2a8d3e598a6b0ba68dad075f54a815c2", "public.website_v2_sync(text,boolean,text[],integer)": "42b7597b7412df81d3cbda38c2c219b4"}'::jsonb;
  v_sig text;
begin
  for v_sig in select jsonb_object_keys(v_expected) loop
    if md5(replace(pg_get_functiondef(v_sig::regprocedure), E'\r', '')) <> v_expected->>v_sig then
      raise exception 'live % differs from the definition this change replaces', v_sig;
    end if;
  end loop;
end $guard$;

-- 1 The item as last built by the change check (the copy its hash was taken from)
alter table pipeline.website_sync_items add column if not exists item jsonb;
comment on column pipeline.website_sync_items.item is 'CF-247 15 Oct 2026: the item as the change check last built it (its hash is of this copy); sync serves it. Null for removed items and until first checked.';

-- 2 Settings
update pipeline.platform_toolset_settings set value = to_jsonb(200),
       reason = 'Platform Admin 15 Oct 2026: "How can we burst it for wix" (prepared items + bigger pages); was 50'
 where toolset_key = 'pipeline' and key = 'website.sync_page_max';
insert into pipeline.platform_toolset_settings(toolset_key, key, label, help, kind, value, min_value, max_value, unit, sort, reason, section, used_by) values
 ('pipeline', 'website.sync_item_unit_bytes', 'Sync page size unit', 'A sync page holds up to the page size in units of this many bytes: a course (about 1.4 KB) counts 1, a scholarship (about 18 KB) about 9, so a page stays near 400 KB.', 'number', to_jsonb(2048), 512, 65536, 'bytes', 306, 'Platform Admin 15 Oct 2026: prepared items + bigger pages', 'Website API', 'public.website_v2_sync')
on conflict do nothing;

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

CREATE OR REPLACE FUNCTION public.website_v2_sync(p_cursor text DEFAULT NULL::text, p_full boolean DEFAULT false, p_entities text[] DEFAULT NULL::text[], p_page_size integer DEFAULT NULL::integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_all text[] := array['reference', 'provider', 'logo', 'rankings', 'scholarship', 'course'];
        v_c jsonb; v_mode text; v_a bigint := 0; v_s bigint; v_e text[]; v_max int; v_size int; v_rows jsonb; v_n int; v_more boolean; v_last bigint;
        v_next jsonb; v_items jsonb; t text; v_unit numeric;
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
  v_max := greatest(security.pipeline_num_v1('website.sync_page_max', 200)::int, 1);
  v_unit := greatest(security.pipeline_num_v1('website.sync_item_unit_bytes', 2048), 1);
  v_size := least(greatest(coalesce(p_page_size, v_max), 1), v_max);
  -- 15 Oct 2026: a page is filled by build cost up to page_size (at least one item); has_more when rows are left
  select coalesce(jsonb_agg(to_jsonb(x) - 'cw' - 'rn' order by x.seq) filter (where x.rn = 1 or x.cw <= v_size), '[]'::jsonb), count(*) into v_rows, v_n from (
    -- CF-247 15 Oct 2026: a stored item counts by its size (one unit per setting bytes); one not yet stored by its build cost as before
    select y.*, sum(case when y.removed_at is not null then 1
                         when y.item is not null then greatest(ceil(octet_length(y.item::text)::numeric / v_unit), 1)::int
                         when y.entity = 'provider' then 16 when y.entity = 'scholarship' then 2 else 1 end) over (order by y.seq) cw,  -- fixed: build cost relative to a course item, measured 14 Oct 2026
           row_number() over (order by y.seq) rn
      from (select i.entity, i.item_key, i.ref_id, i.seq, i.removed_at, i.item from pipeline.website_sync_items i
             where i.entity = any (v_e) and i.seq > v_a
               and (v_mode = 'delta' or (i.removed_at is null and i.seq <= v_s))
             order by i.seq limit v_size + 1) y) x;
  v_more := jsonb_array_length(v_rows) < v_n;
  v_last := (v_rows->-1->>'seq')::bigint;
  select coalesce(jsonb_agg(case when z.item is null then jsonb_build_object('entity', z.entity, 'id', z.item_key, 'seq', z.seq, 'change', 'remove')
                                 else jsonb_build_object('entity', z.entity, 'id', z.item_key, 'seq', z.seq, 'change', 'upsert', 'item', z.item) end order by z.seq), '[]'::jsonb)
    into v_items
    from (select r->>'entity' entity, r->>'item_key' item_key, (r->>'seq')::bigint seq,
                 case when r->>'removed_at' is null then coalesce(nullif(r->'item', 'null'::jsonb), security.website_sync_item_v1(r->>'entity', (r->>'ref_id')::uuid, r->>'item_key')) end item
            from jsonb_array_elements(v_rows) r) z;
  v_next := case when v_mode = 'full' and v_more then jsonb_build_object('v', 1, 'm', 'full', 'a', v_last, 's', v_s, 'e', to_jsonb(v_e))
                 when v_mode = 'full' then jsonb_build_object('v', 1, 'm', 'delta', 'a', v_s, 'e', to_jsonb(v_e))
                 else jsonb_build_object('v', 1, 'm', 'delta', 'a', coalesce(v_last, v_a), 'e', to_jsonb(v_e)) end;
  return jsonb_build_object(
    'mode', v_mode, 'entities', to_jsonb(v_e), 'items', v_items, 'has_more', v_more,
    'full_load_complete', case when v_mode = 'full' then not v_more end,
    'next_cursor', rtrim(translate(replace(encode(convert_to(v_next::text, 'utf8'), 'base64'), E'\n', ''), '+/', '-_'), '='),
    'checked_through', (select case when bool_or(s.last_cycle_at is null) then null else min(s.last_cycle_at) end from pipeline.website_sync_scan s where s.entity = any (v_e)),
    'as_of', now());
end $function$;

insert into pipeline.component_register(kind, name, layer, purpose, status, introduced_in) values
 ('function', 'public.website_v2_sync(text,boolean,text[],integer)', 'Website API', 'Website sync: serves the items the change check stored', 'active', '20261015100000')
on conflict (kind, name) do update set purpose = excluded.purpose, introduced_in = excluded.introduced_in, updated_at = now();

do $post$
declare v_expected jsonb := '{"security.website_sync_check_v1(integer)": "5c4ed59ddaf352126a6fa13a09a5690a", "public.website_v2_sync(text,boolean,text[],integer)": "a30f1b45c0d326ec011c9b72e8d94c56"}'::jsonb;
  v_sig text;
begin
  for v_sig in select jsonb_object_keys(v_expected) loop
    if md5(replace(pg_get_functiondef(v_sig::regprocedure), E'\r', '')) <> v_expected->>v_sig then
      raise exception 'sync prepared items post-check: % not as intended', v_sig;
    end if;
  end loop;
end $post$;
do $dry$
declare t0 timestamptz; r jsonb; r2 jsonb; ms1 int; ms2 int;
begin
  update pipeline.website_sync_items i set item = security.website_sync_item_v1(i.entity, i.ref_id, i.item_key)
   where i.seq in (select seq from pipeline.website_sync_items where entity = 'course' and removed_at is null order by seq limit 400);
  t0 := clock_timestamp(); r := public.website_v2_sync(null, true, array['course'], 200); ms1 := extract(epoch from clock_timestamp()-t0)*1000;
  t0 := clock_timestamp(); r2 := public.website_v2_sync(r->>'next_cursor', false, null, 200); ms2 := extract(epoch from clock_timestamp()-t0)*1000;
  raise exception 'DRYRUN {"page1_items": %, "page1_ms": %, "page1_kb": %, "page2_items": %, "page2_ms": %, "same_as_built": %}',
    jsonb_array_length(r->'items'), ms1, round(length(r::text)/1024.0), jsonb_array_length(r2->'items'), ms2,
    ((r->'items'->0->'item') - 'generated_at') = (security.website_sync_item_v1('course', (select ref_id from pipeline.website_sync_items where entity='course' and item_key = r->'items'->0->>'id'), r->'items'->0->>'id') - 'generated_at');
end $dry$;
