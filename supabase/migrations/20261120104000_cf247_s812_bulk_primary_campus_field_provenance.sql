-- CF-247 S1-RM-Design (Platform Admin 20 Nov 2026 08:06, s812): two reads/writes for the Providers grid and the detail drawers, with no new public object.
--   1 Bulk Flag Primary Campus: the s797 B2 rule (the campus with the most active courses) for the ticked providers only. A preview shows what each provider would get
--     or why it is skipped; the apply needs the Platform Admin and a reason, skips providers that already have a primary campus, have a hand lock on it, or tie, and
--     writes one audit event. The size of one request is the setting bulk.primary_campus_max (G2).
--   2 Field locks for the drawers: which tracked fields of one provider or course a person has locked (pipeline.manual_locks, read only), for the "Human Locked" pill.
-- Both are actions of the existing public.admin_layer4_inbox(text, jsonb) (one in-place, md5-guarded edit, signature unchanged), handled by the new security function
-- security.s812_bulk_admin_v1(text, jsonb) (not callable by the browser roles). No new public function, table or view.
-- G1: no job. G2: the one limit is a setting. G3: no consumer API object; security.consumer_api_check_v1() is read before and after (75 functions, 48 relations, no drift).
-- Replaces: nothing
-- Retires: nothing
-- Nothing dropped, deleted or renamed.
set local lock_timeout = '5s';

do $g$
declare v jsonb := security.consumer_api_check_v1();
begin
  if jsonb_array_length(coalesce(v->'drift', '[]'::jsonb)) <> 0 or (v->>'functions')::int <> 75 or (v->>'relations')::int <> 48 then
    raise exception 'guard: the consumer API is not at its baseline before this change: %', v;
  end if;
end $g$;

insert into pipeline.platform_toolset_settings(toolset_key, key, label, help, kind, value, min_value, max_value, unit, sort, section, used_by, reason)
values ('pipeline', 'bulk.primary_campus_max', 'Bulk flag primary campus: providers in one request',
        'How many ticked providers one Flag primary campus request may cover. The preview and the apply both stop at this number.',
        'number', to_jsonb(100), 1, 500, 'providers', 970, 'Bulk actions', 'public.admin_layer4_inbox (campus_primary_preview, campus_primary_apply)', 'CF-247 s812 (Platform Admin 20 Nov 2026 08:06)')
on conflict (toolset_key, key) do nothing;

create or replace function security.s812_bulk_admin_v1(p_action text, p_args jsonb)
returns jsonb language plpgsql security definer set search_path to '' as $f$
declare
  v_rank int := coalesce(security.current_role_rank(), 0);
  v_max int := security.pipeline_num_v1('bulk.primary_campus_max', 100)::int;
  v_ids jsonb; v_n int; v_reason text := btrim(coalesce(p_args->>'reason', '')); v_rows jsonb; v_marked int := 0; v_by jsonb; v_entity text; v_id uuid; v_locks jsonb;
begin
  if auth.uid() is null then raise exception 'Sign in required' using errcode = '42501'; end if;
  if p_action = 'field_provenance' then
    if v_rank < 3 then raise exception 'Curator role or above required' using errcode = '42501'; end if;
    v_entity := p_args->>'entity';
    if v_entity not in ('provider', 'course') then raise exception 'INVALID_INPUT: entity must be provider or course'; end if;
    begin v_id := (p_args->>'id')::uuid; exception when others then raise exception 'INVALID_INPUT: id must be a uuid'; end;
    select coalesce(jsonb_object_agg(l.field, jsonb_build_object('mode', l.mode, 'set_at', l.set_at)), '{}'::jsonb) into v_locks
      from pipeline.manual_locks l where l.entity = v_entity and l.entity_id = v_id;
    return jsonb_build_object('entity', v_entity, 'id', v_id, 'locks', v_locks, 'as_of', now());
  end if;
  if p_action not in ('campus_primary_preview', 'campus_primary_apply') then raise exception 'unknown action %', p_action; end if;
  if v_rank < 6 then raise exception 'Platform Admin role required' using errcode = '42501'; end if;
  v_ids := coalesce(p_args->'provider_ids', '[]'::jsonb);
  if jsonb_typeof(v_ids) <> 'array' then raise exception 'INVALID_INPUT: provider_ids must be a list'; end if;
  select count(distinct x) into v_n from jsonb_array_elements_text(v_ids) x;
  if v_n = 0 then raise exception 'INVALID_INPUT: tick at least one provider'; end if;
  if v_n > v_max then raise exception 'INVALID_INPUT: at most % providers in one request (Settings > Pipeline settings)', v_max; end if;
  if p_action = 'campus_primary_apply' and char_length(v_reason) < 4 then raise exception 'INVALID_INPUT: a reason of at least 4 characters is required'; end if;

  with ids as (select distinct x::uuid id from jsonb_array_elements_text(v_ids) x),
  prov as (
    select p.id, p.canonical_name nm, p.lifecycle_status ls, k.iso_alpha2 cc
      from ids join catalogue.providers p on p.id = ids.id left join ref.countries k on k.id = p.country_id),
  cnt as (
    select k.provider_id, k.id campus_id, k.name cn,
           (select count(distinct cc.course_id) from catalogue.course_campuses cc join catalogue.courses c on c.id = cc.course_id and c.lifecycle_status = 'active'
             where cc.campus_id = k.id)::int n
      from catalogue.campuses k join prov on prov.id = k.provider_id where k.status = 'active'),
  ranked as (
    select provider_id, campus_id, cn, n, rank() over (partition by provider_id order by n desc) rk, count(*) over (partition by provider_id, n) top from cnt),
  res as (
    select prov.id provider_id, prov.nm,
           (select r.campus_id from ranked r where r.provider_id = prov.id and r.rk = 1 and r.top = 1) pick_id,
           (select r.cn from ranked r where r.provider_id = prov.id and r.rk = 1 and r.top = 1) pick_name,
           (select r.n from ranked r where r.provider_id = prov.id and r.rk = 1 and r.top = 1) pick_n,
           case
             when prov.ls <> 'active' then 'not_active'
             when coalesce(prov.cc, '') not in ('AU', 'NZ', 'CA') then 'outside_rule'
             when exists (select 1 from catalogue.campuses x where x.provider_id = prov.id and x.is_primary) then 'has_primary'
             when exists (select 1 from pipeline.manual_locks l join catalogue.campuses x on x.id = l.entity_id
                           where l.entity = 'campus' and l.field in ('is_primary', 'primary_basis') and x.provider_id = prov.id) then 'locked'
             when not exists (select 1 from cnt where cnt.provider_id = prov.id) then 'no_campus'
             when not exists (select 1 from ranked r where r.provider_id = prov.id and r.rk = 1 and r.top = 1) then 'tie'
             else 'will_mark' end outcome
      from prov)
  select coalesce(jsonb_agg(jsonb_build_object('provider_id', provider_id, 'name', nm, 'outcome', outcome, 'campus_id', pick_id, 'campus', pick_name, 'courses', pick_n) order by nm), '[]'::jsonb)
    into v_rows from res;

  if p_action = 'campus_primary_apply' then
    update catalogue.campuses k set is_primary = true, primary_basis = 'highest_course_count', updated_at = now()
      from jsonb_to_recordset(v_rows) r(provider_id uuid, outcome text, campus_id uuid)
     where r.outcome = 'will_mark' and r.campus_id = k.id and k.is_primary is distinct from true
       and not exists (select 1 from catalogue.campuses x where x.provider_id = r.provider_id and x.is_primary);
    get diagnostics v_marked = row_count;
  end if;
  select coalesce(jsonb_object_agg(o, c), '{}'::jsonb) into v_by from (select r.outcome o, count(*) c from jsonb_to_recordset(v_rows) r(outcome text) group by 1) z;
  if p_action = 'campus_primary_apply' then
    insert into pipeline.admin_control_events (area, action, target, detail, actor)
    values ('providers', 'campus_primary_bulk_flag', 'catalogue.campuses.is_primary',
            jsonb_build_object('rule', 'B2: the campus with the most active courses, for the ticked providers only', 'reason', v_reason, 'ticked', v_n, 'marked', v_marked, 'by_outcome', v_by,
                               'providers', (select coalesce(jsonb_agg(r.provider_id), '[]'::jsonb) from jsonb_to_recordset(v_rows) r(provider_id uuid, outcome text) where r.outcome = 'will_mark')), auth.uid());
  end if;
  return jsonb_build_object('action', p_action, 'applied', p_action = 'campus_primary_apply', 'ticked', v_n, 'will_mark', coalesce((v_by->>'will_mark')::int, 0), 'marked', v_marked,
                            'by_outcome', v_by, 'rows', v_rows, 'limit', v_max);
end $f$;
revoke all on function security.s812_bulk_admin_v1(text, jsonb) from public, anon, authenticated;
comment on function security.s812_bulk_admin_v1(text, jsonb) is 'CF-247 s812: Bulk Flag Primary Campus (preview and apply, Platform Admin) and the field locks read for the detail drawers (Curator and above). Reached only through public.admin_layer4_inbox.';

create or replace function pg_temp.cf_edit_def(p_sig regprocedure, p_md5 text, p_old text[], p_new text[])
returns void language plpgsql as $f$
declare v_def text := replace(pg_get_functiondef(p_sig), chr(13), ''); v_c int; i int;
begin
  if md5(v_def) <> p_md5 then raise exception 'pre-check: % changed since it was read (definition md5 %)', p_sig, md5(v_def); end if;
  for i in 1 .. array_length(p_old, 1) loop
    v_c := (length(v_def) - length(replace(v_def, p_old[i], ''))) / length(p_old[i]);
    if v_c <> 1 then raise exception 'pre-check: %: fragment % must occur exactly once (found %)', p_sig, i, v_c; end if;
    v_def := replace(v_def, p_old[i], p_new[i]);
  end loop;
  execute v_def;
end $f$;

-- the Inbox dispatcher: three more actions routed to the new security function (no new public function; signature and every other path unchanged)
select pg_temp.cf_edit_def('public.admin_layer4_inbox(text,jsonb)'::regprocedure, '52024a627bc04976b2e5b489a7d969af',
  array[$o$    return security.human_edit_admin_v1(p_action, p_args);  -- s804/s805
  end if;$o$],
  array[$n$    return security.human_edit_admin_v1(p_action, p_args);  -- s804/s805
  end if;
  if p_action in ('campus_primary_preview', 'campus_primary_apply', 'field_provenance') then
    return security.s812_bulk_admin_v1(p_action, p_args);  -- s812
  end if;$n$]);

-- post-checks, as a signed-in Platform Admin: reads only, plus one apply in a sub-block that is always rolled back
do $$
declare v_admin uuid; r jsonb; v_prov uuid; v_cnt int; v_ids jsonb; v_o text := '';
begin
  select ur.user_id into v_admin from security.user_roles ur join security.roles ro on ro.code = ur.role_code
   where ro.status = 'active' and ro.rank >= 6 and (ur.expires_at is null or ur.expires_at > now()) order by ur.user_id limit 1;
  if v_admin is null then raise exception 'post-check: no Platform Admin to act as'; end if;
  perform set_config('request.jwt.claims', jsonb_build_object('sub', v_admin::text, 'role', 'authenticated')::text, true);
  select l.entity_id into v_prov from pipeline.manual_locks l where l.entity = 'provider' and l.field = 'website' limit 1;
  r := public.admin_layer4_inbox('field_provenance', jsonb_build_object('entity', 'provider', 'id', v_prov));
  if v_prov is not null and not (r->'locks' ? 'website') then raise exception 'post-check: the website lock is not read %', r; end if;
  v_o := 'field locks read';
  select coalesce(jsonb_agg(p.id), '[]'::jsonb) into v_ids from (select id from catalogue.providers where lifecycle_status = 'active' order by canonical_name limit 20) p;
  r := public.admin_layer4_inbox('campus_primary_preview', jsonb_build_object('provider_ids', v_ids));
  if (r->>'ticked')::int <> 20 or (r->>'applied')::boolean then raise exception 'post-check: preview %', left(r::text, 300); end if;
  v_o := v_o || ' | preview ' || (r->'by_outcome')::text;
  if (select count(*) from pipeline.admin_control_events where action = 'campus_primary_bulk_flag') <> 0 then raise exception 'post-check: a preview wrote an audit event'; end if;
  begin
    r := public.admin_layer4_inbox('campus_primary_apply', jsonb_build_object('provider_ids', v_ids, 'reason', 'post-check (rolled back)'));
    if (r->>'marked')::int <> coalesce((r->'by_outcome'->>'will_mark')::int, 0) then raise exception 'post-check: apply marked % of %', r->>'marked', r->'by_outcome'->>'will_mark'; end if;
    if (select count(*) from pipeline.admin_control_events where action = 'campus_primary_bulk_flag') <> 1 then raise exception 'post-check: no audit event'; end if;
    v_o := v_o || ' | apply marked ' || (r->>'marked') || ' (rolled back)';
    raise exception 'ROLLBACK-POSTCHECK';
  exception when others then
    if sqlerrm <> 'ROLLBACK-POSTCHECK' then raise; end if;
  end;
  if (select count(*) from pipeline.admin_control_events where action = 'campus_primary_bulk_flag') <> 0 then raise exception 'post-check: the apply was not rolled back'; end if;
  begin perform public.admin_layer4_inbox('campus_primary_preview', '{}'::jsonb); raise exception 'post-check: an empty request was accepted';
  exception when others then if sqlerrm like 'post-check:%' then raise; end if; end;
  raise notice 's812 post-checks: %', v_o;
end $$;

do $g$
declare v jsonb := security.consumer_api_check_v1();
begin
  if jsonb_array_length(coalesce(v->'drift', '[]'::jsonb)) <> 0 or (v->>'functions')::int <> 75 or (v->>'relations')::int <> 48 then
    raise exception 'guard: the consumer API moved during this change: %', v;
  end if;
end $g$;
