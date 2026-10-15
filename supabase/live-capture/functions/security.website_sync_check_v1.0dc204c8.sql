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
end $function$
