-- CF-247 S2 - BOOST (Platform Admin directive Thu 19 Nov 2026 05:40, item 4, s727): rule l4-campus-locality-v1 (S2-BOOST-Providers,
-- 20261118203000) settles a further basis, campus_name. What was read live (19 Nov 2026 ~06:10 AEDT, SELECT only): 31 Australian postcodes
-- (78 campuses) wait in Layer 4 > Campus locality, every one on basis "hold": their campuses give a suburb inside the area (Turvey Park,
-- Bundaberg Central, Mount Clarence) rather than the area's own name, so the suburb_name basis does not match. The platform holds no
-- suburb-to-area gazetteer, so the rule reads only what each campus says about itself:
--   campus_name: the area that holds more than half of the postcode's ABS mesh blocks (and at least destination.postcode_mesh_name_min_share)
--   is named, as a whole word, in the suburb of every waiting campus ("Bundaberg Central") or in its own campus name ("TAFE NSW Wagga Wagga",
--   "Albany Senior High School"), and never only through its provider's name: "Adelaide University, Roseworthy Campus" names the
--   university, and Roseworthy (5371) is outside Adelaide, so it waits.
-- On the live read this settles 3 postcodes and 9 campuses (2650 Wagga Wagga, 4670 Bundaberg, 6330 Albany); 28 postcodes (69 campuses) keep
-- waiting for a person (suburbs outside the area's name, a campus filed under the wrong postcode such as North Parramatta in 2800, or a
-- 50/50 postcode such as Kempsey 2440). Job layer4-campus-locality (hourly at minute 57) applies it; each settlement goes through
-- security.layer4_campus_locality_inbox_decide_v1 under the system automation account and is logged in pipeline.admin_control_events.
-- The two functions are replaced in place (CREATE OR REPLACE, same signatures); no table, function, job or setting is added (G3 75/48).
-- Numbered 20261119062000: above the live head (20261119052000), after 20261119061500 (S2-BOOST fields v2), clear of open PRs.
-- Replaces: security.campus_locality_rule_candidates_v1 and security.campus_locality_rule_v1 (bases mesh_share, outside, suburb_name) with the same plus campus_name
-- Retires: nothing

set local lock_timeout = '5s';

do $g$
begin
  if md5(pg_get_functiondef('security.campus_locality_rule_candidates_v1()'::regprocedure)) <> '28a5e96bab4c7b1a296449625adc70c6' then
    raise exception 'guard: security.campus_locality_rule_candidates_v1 is not the definition of 20261118203000';
  end if;
  if md5(pg_get_functiondef('security.campus_locality_rule_v1(integer)'::regprocedure)) <> '3665a17bd630e0c91b04dab4d633cfc0' then
    raise exception 'guard: security.campus_locality_rule_v1 is not the definition of 20261118203000';
  end if;
end $g$;

create or replace function security.campus_locality_rule_candidates_v1()
returns table(country_code text, postcode text, ref text, campuses integer, basis text, locality_id uuid, locality text, geography_code text, mesh_share numeric)
language sql stable security definer set search_path to '' as $function$
  with o as (
    select o.country_code, o.postcode, o.campus_id, security.campus_suburb_norm_v1(k.city) suburb,
           lower(coalesce(k.city, '')) city_l, lower(coalesce(k.name, '')) name_l,
           lower(concat_ws(' | ', p.canonical_name, p.display_name, p.short_name)) provider_l
      from security.destination_campus_locality_open_v1(null) o join catalogue.campuses k on k.id = o.campus_id
      left join catalogue.providers p on p.id = k.provider_id
     where o.country_code = 'AU'),
  pc as (select o.country_code, o.postcode, count(*)::int campuses, min(o.campus_id::text) ref, array_agg(distinct o.suburb) suburbs from o group by 1, 2),
  s as (
    select a.postcode, a.sua_code, a.sua_name, a.mesh_blocks, sum(a.mesh_blocks) over (partition by a.postcode) tot,
           row_number() over (partition by a.postcode order by a.mesh_blocks desc, a.sua_code) rk
      from destination.abs_postcode_sua_shares a
     where a.boundary_vintage = (select max(x.boundary_vintage) from destination.abs_postcode_sua_shares x where x.postcode = a.postcode)),
  t as (
    select pc.*, s.sua_name, s.mesh_blocks::numeric / nullif(s.tot, 0) mshare, l.id locality_id, l.name locality, l.geography_code
      from pc join s on s.postcode = pc.postcode and s.rk = 1
      left join destination.localities l on l.country_code = 'AU' and l.geography_type = 'SUA' and l.geography_code = s.sua_code
           and exists (select 1 from destination.locality_postcodes p where p.country_code = 'AU' and p.postcode = pc.postcode and p.locality_id = l.id))
  select t.country_code, t.postcode, t.ref, t.campuses,
         case when t.locality_id is not null and t.mshare >= security.pipeline_num_v1('destination.postcode_mesh_min_share', 0.9) then 'mesh_share'
              when t.locality_id is null and t.sua_name ilike 'Not in any%' and t.mshare >= security.pipeline_num_v1('destination.postcode_mesh_min_share', 0.9) then 'outside'
              when t.locality_id is not null and t.mshare >= security.pipeline_num_v1('destination.postcode_mesh_name_min_share', 0.5)
                   and not exists (select 1 from unnest(t.suburbs) u
                                    where u = '' or u <> all (select security.campus_suburb_norm_v1(x) from regexp_split_to_table(t.locality, '\s+-\s+') x)) then 'suburb_name'
              -- s727 (19 Nov 2026): every waiting campus names the area as a whole word in its suburb ("Bundaberg Central") or in its own name
              -- ("TAFE NSW Wagga Wagga"), where the provider's name does not hold it ("Adelaide University, Roseworthy Campus" is not in Adelaide)
              when t.locality_id is not null and t.mshare >= security.pipeline_num_v1('destination.postcode_mesh_name_min_share', 0.5)
                   and t.mshare > 0.5  -- fixed: more than half the mesh blocks is more than any other part (a 50/50 postcode such as Kempsey 2440 waits)
                   and not exists (select 1 from o where o.country_code = t.country_code and o.postcode = t.postcode
                                     and not exists (select 1 from regexp_split_to_table(t.locality, '\s+-\s+') x,
                                                          lateral (select '\m' || regexp_replace(lower(x), '([^[:alnum:] ])', '\\\1', 'g') || '\M' re) r
                                                      where o.city_l ~ r.re or (o.name_l ~ r.re and o.provider_l !~ r.re))) then 'campus_name'
              else 'hold' end,
         t.locality_id, t.locality, t.geography_code, round(t.mshare, 4)
    from t
$function$;
revoke all on function security.campus_locality_rule_candidates_v1() from public, anon, authenticated;
comment on function security.campus_locality_rule_candidates_v1() is 'CF-247 rule l4-campus-locality-v1: each waiting Australian campus postcode with the Significant Urban Area that holds most of its ABS mesh blocks and the basis on which the rule may settle it (mesh_share, outside, suburb_name, campus_name from s727) or hold. Read only.';

create or replace function security.campus_locality_rule_v1(p_limit integer)
returns jsonb language plpgsql security definer set search_path to '' as $function$
declare w record; v_prev text; v_res jsonb;
        v_sys uuid := 'c0ffee00-0000-4000-8000-000000000150';  -- fixed: the system automation account that records rule decisions (Decision 263)
        v_lim int := least(greatest(coalesce(p_limit, 0), 0), 2000);  -- fixed: upper bound of the setting's range
        v_ok jsonb := '{}'::jsonb; v_campuses int := 0; v_fail int := 0;
begin
  if security.pipeline_num_v1('destination.campus_locality_rule_on', 0) < 1 or v_lim = 0 then return jsonb_build_object('ok', false, 'reason', 'off'); end if;
  perform pg_advisory_xact_lock(hashtext('cf247:campus_locality_rule'));  -- fixed: one run at a time
  for w in select c.* from security.campus_locality_rule_candidates_v1() c where c.basis <> 'hold' order by c.postcode limit v_lim loop
    v_prev := current_setting('request.jwt.claim.sub', true);
    perform set_config('request.jwt.claim.sub', v_sys::text, true);
    begin
      v_res := security.layer4_campus_locality_inbox_decide_v1(w.ref, case when w.basis = 'outside' then 'no_locality' else 'choose_locality' end,
        case when w.basis = 'outside' then null else w.geography_code end,
        left(format('[rule l4-campus-locality-v1] %s Approved by Platform Admin 18 Nov 2026 17:03',
          case w.basis
            when 'mesh_share' then format('%s holds %s%% of the mesh blocks of postcode %s (ABS postcode correspondence).', w.locality, round(w.mesh_share * 100), w.postcode)
            when 'outside' then format('%s%% of the mesh blocks of postcode %s are outside every Significant Urban Area (ABS postcode correspondence).', round(w.mesh_share * 100), w.postcode)
            when 'suburb_name' then format('Every waiting campus in postcode %s gives %s as its suburb, and %s holds %s%% of the postcode''s mesh blocks, more than any other part.', w.postcode, w.locality, w.locality, round(w.mesh_share * 100))
            else format('Every waiting campus in postcode %s names %s in its suburb or its own campus name (not through its provider''s name), and %s holds %s%% of the postcode''s mesh blocks, more than half.', w.postcode, w.locality, w.locality, round(w.mesh_share * 100)) end), 1000));
      perform set_config('request.jwt.claim.sub', coalesce(v_prev, ''), true);
      if coalesce((v_res->>'ok')::boolean, false) then
        v_ok := jsonb_set(v_ok, array[w.basis], to_jsonb(coalesce((v_ok->>w.basis)::int, 0) + 1));
        v_campuses := v_campuses + w.campuses;
      else v_fail := v_fail + 1;
      end if;
    exception when others then perform set_config('request.jwt.claim.sub', coalesce(v_prev, ''), true); v_fail := v_fail + 1;
    end;
  end loop;
  if v_ok <> '{}'::jsonb or v_fail > 0 then
    insert into pipeline.admin_control_events(area, action, target, detail, actor)
    values ('layer4', 'rule_execute', 'l4-campus-locality-v1', jsonb_build_object('postcodes_settled', v_ok, 'campuses', v_campuses, 'failed', v_fail), v_sys);
  end if;
  return jsonb_build_object('ok', true, 'postcodes_settled', v_ok, 'campuses', v_campuses, 'failed', v_fail,
    'waiting', (select count(*) from security.destination_campus_locality_open_v1(null)));
end $function$;
revoke all on function security.campus_locality_rule_v1(integer) from public, anon, authenticated;
comment on function security.campus_locality_rule_v1(integer) is 'CF-247 rule l4-campus-locality-v1 (Platform Admin 18 Nov 2026 17:03; campus names from s727, 19 Nov 2026 05:40): settles a waiting campus postcode through the existing Layer 4 Inbox decision, under the system automation account, on the ABS mesh-block share, the campuses'' own suburb name, or the area named in each campus''s suburb or own name; every other postcode waits for a person.';

do $c$
declare v_bad int;
begin
  if not exists (select 1 from pg_proc where oid = 'security.campus_locality_rule_candidates_v1()'::regprocedure and prosrc like '%then ''campus_name''%') then
    raise exception 'post-check: the candidates do not name the campus_name basis';
  end if;
  -- a campus named only through its provider's name never settles its postcode: Roseworthy (5371) waits while it is open
  if exists (select 1 from security.campus_locality_rule_candidates_v1() where postcode = '5371' and basis <> 'hold') then
    raise exception 'post-check: postcode 5371 (Roseworthy, named only through Adelaide University) would be settled';
  end if;
  select count(*) into v_bad from security.campus_locality_rule_candidates_v1() where basis = 'campus_name';
  raise notice 'campus_name postcodes now: %', v_bad;
  if exists (select 1 from security.campus_locality_rule_candidates_v1() where basis = 'campus_name' and mesh_share <= 0.5) then
    raise exception 'post-check: a campus_name postcode holds half or less of the mesh blocks';
  end if;
end $c$;
