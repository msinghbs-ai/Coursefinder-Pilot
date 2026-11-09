-- HELD (not a migration): forward recovery for 20261110070000 (Fill / Recheck description on demand). Run only if the Platform Admin decides to go back to the text of public.admin_enrich_fields
-- before that migration. It removes the one dispatch block the migration added and so restores the function byte for byte (body md5 c9701d334b732a729a30a5147d9d016b), guarded by the md5 of what is
-- live now (f11db4466add68c4d7de5cb7c87d9bce). Run twice, the second run says already restored. The five new functions (security.cdesc_state_v1, security.cdesc_on_demand_v1,
-- security.cdesc_block_info_v1, security.cdesc_machine_ids_v1, public.admin_course_description_state_v1) are left in place (nothing calls them once the dispatch is gone); dropping them is for the Platform Admin to
-- run later, and the screens that call them (Course Catalogue, Course Detail, Provider Catalogue) stop working with the action, so release a front end without them first.
do $r$
declare v_def text; v_src text; v_old text := $old$  -- CF-247 F-CDESC.06 (Platform Admin 10 Nov 2026): Fill description / Recheck description for chosen courses or one university, and the read-back of what they delivered, run through this same task engine
  if p_action in ('verify', 'description_tasks') or (p_action in ('preview', 'start') and (p_args ? 'course_ids' or p_args ? 'mode')) then
    return security.cdesc_on_demand_v1(p_action, p_args, v_rank, auth.uid());
  end if;
$old$; v_c int;
begin
  select p.prosrc into v_src from pg_proc p where p.oid = to_regprocedure('public.admin_enrich_fields(text,jsonb)');
  if v_src is null then raise exception 'public.admin_enrich_fields is missing'; end if;
  if md5(v_src) = 'c9701d334b732a729a30a5147d9d016b' then raise notice 'public.admin_enrich_fields: already restored'; return; end if;
  if md5(v_src) <> 'f11db4466add68c4d7de5cb7c87d9bce' then raise exception 'live public.admin_enrich_fields differs from the text this recovery knows (body md5 %)', md5(v_src); end if;
  v_def := replace(pg_get_functiondef('public.admin_enrich_fields(text,jsonb)'::regprocedure), chr(13), '');
  v_c := (length(v_def) - length(replace(v_def, v_old, ''))) / length(v_old);
  if v_c <> 1 then raise exception 'the dispatch block must be found exactly once (found %)', v_c; end if;
  execute replace(v_def, v_old, '');
  select p.prosrc into v_src from pg_proc p where p.oid = to_regprocedure('public.admin_enrich_fields(text,jsonb)');
  if md5(v_src) <> 'c9701d334b732a729a30a5147d9d016b' then raise exception 'after the recovery the body md5 is %, expected c9701d334b732a729a30a5147d9d016b', md5(v_src); end if;
  raise notice 'public.admin_enrich_fields restored to body md5 c9701d334b732a729a30a5147d9d016b';
end $r$;
