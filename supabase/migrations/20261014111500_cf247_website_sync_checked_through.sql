-- CF-247 v2.15.277 fix (found verifying the sync action live, 14 Oct 2026): checked_through took the earliest finished pass of the chosen
-- entities and ignored entities not yet checked once, so it gave a time while most items had not been checked. It is now null until every
-- chosen entity has finished a pass. Nothing dropped or deleted.

do $guard$
declare v_expected jsonb := '{"public.website_v2_sync(text,boolean,text[],integer)": "abeece26983fbc85904f373b1e08f934"}'::jsonb;
  v_sig text;
begin
  for v_sig in select jsonb_object_keys(v_expected) loop
    if md5(replace(pg_get_functiondef(v_sig::regprocedure), E'\r', '')) <> v_expected->>v_sig then
      raise exception 'live % differs from the definition this change replaces', v_sig;
    end if;
  end loop;
end $guard$;

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
    'checked_through', (select case when bool_or(s.last_cycle_at is null) then null else min(s.last_cycle_at) end from pipeline.website_sync_scan s where s.entity = any (v_e)),
    'as_of', now());
end $function$;

do $post$
declare v_expected jsonb := '{"public.website_v2_sync(text,boolean,text[],integer)": "92414ce77934afd539785d4bd99c0cf9"}'::jsonb;
  v_sig text;
begin
  for v_sig in select jsonb_object_keys(v_expected) loop
    if md5(replace(pg_get_functiondef(v_sig::regprocedure), E'\r', '')) <> v_expected->>v_sig then
      raise exception 'v2.15.277 fix post-check: % not as intended', v_sig;
    end if;
  end loop;
end $post$;
