-- CF-247 s1048 (S1-RM-Design, S2-RM-Design brief 24 Nov 2026 15:16 AEDT, Platform Admin decisions 2 and 3).
-- Measured live 24 Nov 2026 15:05 to 15:20 (rolled-back read-backs; head 20261124173000): row-level partial admission (aer-partial-v1, s914) is already live (aer.partial_admit_on 1,
-- machine mode 2, effective 2): Adelaide went from 0 to 39 active rows within one run of s1038, so decision 1 needs no new rule. What still stops the machine check before it: Curtin University
-- (source on the CDN host s30991.pcdn.co, rule source_not_official_host) and Victoria University 00124K (126 proposed rows, rule host_shared: 02475D uses the same host vu.edu.au).
-- Changes:
-- 1. aer.provider_host_aliases gains "<Curtin University id>:s30991.pcdn.co", scoped to that provider only (Platform Admin 15:16), as s1038 did for Adelaide.
-- 2. host_shared resolves the primary record: when other active providers share the website host, the machine check goes on only for the provider with the most active courses, and only if
--    every other provider on that host has fewer (a tie stays held). Victoria University 00124K (279 active courses) passes; 02475D (35) and any smaller record on a shared host stay held.
--    Switch aer.host_shared_primary_on (1; 0 restores the old rule). One anchored edit of security.aer_matrix_machine_check_v1 (md5-guarded); every other check still applies, and
--    the partial admission rule (which calls this check) then takes the rows the completeness gate leaves.
-- G1: no job. G2: new switch setting, the alias list setting. G3: no consumer object (75/48). Manual locks untouched. Nothing dropped or removed.
-- Replaces: nothing (one live function edited in place, md5-guarded)
-- Retires: nothing
set local lock_timeout = '5s';  -- fixed: lock wait for the setting rows and the function

do $g$
declare v jsonb := security.consumer_api_check_v1();
begin
  if jsonb_array_length(coalesce(v->'drift', '[]'::jsonb)) <> 0 or (v->>'functions')::int <> 75 or (v->>'relations')::int <> 48 then
    raise exception 'guard: the consumer API is not at its baseline before this change: %', v;
  end if;
end $g$;
create temp table s1048_locks on commit drop as select count(*) n from pipeline.manual_locks;

-- 1. Curtin University's CDN host
do $c$
declare v_id uuid; v_n int; v_entry text;
begin
  select count(*), max(id::text)::uuid into v_n, v_id from catalogue.providers where canonical_name = 'Curtin University' and lifecycle_status = 'active';
  if v_n <> 1 then raise exception 'guard: expected one active Curtin University record, found %', v_n; end if;
  v_entry := v_id::text || ':s30991.pcdn.co';
  update pipeline.platform_toolset_settings set value = value || to_jsonb(v_entry), updated_at = now(),
         reason = 'Platform Admin 24 Nov 2026 15:16 (s1048): s30991.pcdn.co approved for Curtin University only'
   where toolset_key = 'pipeline' and key = 'aer.provider_host_aliases' and not (value ? v_entry);
  insert into pipeline.admin_control_events (area, action, target, detail, actor)
  values ('settings', 'migration', 'pipeline.platform_toolset_settings', jsonb_build_object('key', 'aer.provider_host_aliases', 'added', v_entry,
          'reason', 'Platform Admin 24 Nov 2026 15:16: s30991.pcdn.co approved for Curtin University only (s1048)', 'migration', '20261124213000'), security.system_actor_id());
end $c$;

-- 2. primary record on a shared host
insert into pipeline.platform_toolset_settings (toolset_key, key, label, help, kind, value, min_value, max_value, unit, sort, reason, section, used_by)
values ('pipeline', 'aer.host_shared_primary_on', 'Entry matrices: primary record on a shared website',
  '1: when several active providers share one website host, the machine admission check goes on for the one with the most active courses (every other record on that host has fewer; a tie stays held); the smaller records stay held. 0: any shared host holds every record (the earlier rule).',
  'number', to_jsonb(1), 0, 1, 'switch', 925,
  'Platform Admin 24 Nov 2026 15:16 (s1048): canonical primary record resolution for shared hosts (Victoria University 00124K over 02475D)', 'Entry requirements',
  'security.aer_matrix_machine_check_v1 (rule host_shared)')
on conflict (toolset_key, key) do nothing;

do $f$
declare
  v_fn regprocedure := 'security.aer_matrix_machine_check_v1(uuid)'::regprocedure;
  v_def text := pg_get_functiondef('security.aer_matrix_machine_check_v1(uuid)'::regprocedure);
  a text := 'if exists (select 1 from catalogue.providers o where o.id <> i.entity_id and o.lifecycle_status = ''active'' and security.site_host_v1(o.website) = v_ph) then';
  b text := 'if exists (select 1 from catalogue.providers o where o.id <> i.entity_id and o.lifecycle_status = ''active'' and security.site_host_v1(o.website) = v_ph) '
         || 'and not (security.pipeline_num_v1(''aer.host_shared_primary_on'', 1) >= 1 and not exists (select 1 from catalogue.providers o2 where o2.id <> i.entity_id and o2.lifecycle_status = ''active'' and security.site_host_v1(o2.website) = v_ph '
         || 'and (select count(*) from catalogue.courses c2 where c2.provider_id = o2.id and c2.lifecycle_status = ''active'') >= (select count(*) from catalogue.courses c1 where c1.provider_id = i.entity_id and c1.lifecycle_status = ''active''))) then';
begin
  if strpos(v_def, 'aer.host_shared_primary_on') > 0 then return; end if;
  if md5(v_def) <> 'c08b4151e77f16fdbfef38e29fe1035c' then raise exception 'guard: aer_matrix_machine_check_v1 changed since the live read-back; rebase and re-verify'; end if;
  if (length(v_def) - length(replace(v_def, a, ''))) <> length(a) then raise exception 'guard: host_shared anchor absent or repeated'; end if;
  execute replace(v_def, a, b);
  if strpos(pg_get_functiondef(v_fn), 'aer.host_shared_primary_on') = 0 then raise exception 'post-check: the host_shared edit was not applied'; end if;
end $f$;

do $p$
declare v jsonb := security.consumer_api_check_v1(); v_vu uuid; v_vu2 uuid; v_cu uuid; v_r1 text; v_r2 text; v_r3 text;
begin
  if jsonb_array_length(coalesce(v->'drift', '[]'::jsonb)) <> 0 or (v->>'functions')::int <> 75 or (v->>'relations')::int <> 48 then raise exception 'post-check: the consumer API moved: %', v; end if;
  if (select count(*) from pipeline.manual_locks) <> (select n from s1048_locks) then raise exception 'post-check: manual locks changed'; end if;
  -- read-back of the three cases: primary clears host_shared, the smaller record stays held, Curtin clears the host rule
  select i.id into v_vu from pipeline.layer4_review_items i where i.entity_id = 'bac82321-ded7-4e10-a71d-b18f3ae4d1c7' and i.status = 'pending' and i.field_code = 'entry_matrix_first_run' limit 1;
  select i.id into v_vu2 from pipeline.layer4_review_items i where i.entity_id = '0f5373c8-d724-4303-9267-739530a5ce53' and i.status = 'pending' and i.field_code = 'entry_matrix_first_run' limit 1;
  select i.id into v_cu from pipeline.layer4_review_items i join catalogue.providers p on p.id = i.entity_id where p.canonical_name = 'Curtin University' and i.status = 'pending' and i.field_code = 'entry_matrix_first_run' limit 1;
  if v_vu is not null then v_r1 := security.aer_matrix_machine_check_v1(v_vu)->>'rule'; if v_r1 = 'host_shared' then raise exception 'post-check: Victoria University 00124K still stops at host_shared'; end if; end if;
  if v_vu2 is not null then v_r2 := security.aer_matrix_machine_check_v1(v_vu2)->>'rule'; if v_r2 is distinct from 'host_shared' then raise exception 'post-check: the smaller Victoria University record is no longer held at host_shared: %', v_r2; end if; end if;
  if v_cu is not null then v_r3 := security.aer_matrix_machine_check_v1(v_cu)->>'rule'; if v_r3 = 'source_not_official_host' then raise exception 'post-check: Curtin still stops at the host rule'; end if; end if;
  raise notice 'read-back: VU 00124K %, VU 02475D %, Curtin %', coalesce(v_r1, 'no item'), coalesce(v_r2, 'no item'), coalesce(v_r3, 'no item');
end $p$;
