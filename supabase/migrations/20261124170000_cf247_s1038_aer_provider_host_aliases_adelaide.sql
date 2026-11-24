-- CF-247 s1038 (S1-RM-Design, S2-RM-Design brief 24 Nov 2026 14:21 AEDT, item 1: "Explicitly add adelaide.edu.au as an approved legacy domain alias for Adelaide University").
-- Measured live 24 Nov 2026 14:15 (rolled-back read-back, head 20261124150000): the machine check of the AER first-read rule (security.aer_matrix_machine_check_v1) refuses
-- Adelaide University's 40 proposed rows with source_not_official_host: the one stored source is a PDF on adelaide.edu.au, the provider's website is adelaideuni.edu.au.
-- Of the 94 pending first-read items the same rule also refuses Curtin University (34 rows; its PDF is on a CDN host, s30991.pcdn.co, which is NOT aliased here: not decided).
-- Changes:
-- 1. New G2 list setting aer.provider_host_aliases: entries "<provider id>:<host>"; a source on that host (or a subdomain) counts as the provider's own site for the machine check only.
--    It is read nowhere else (the register check aer_source_check_v1 and the scholarship site checks are unchanged). First entry: Adelaide University and adelaide.edu.au.
-- 2. security.aer_matrix_machine_check_v1: one anchored edit of the host condition to read the setting (md5-guarded). Every other machine rule (evidence, quotes, confidence, host_shared,
--    locks, protected rejection) still applies; nothing is admitted here: the machine admission job takes the item on its next run if every rule passes.
-- G1: no job. G3: no consumer object (75/48). Manual locks untouched. Nothing dropped or removed.
-- Replaces: nothing (one live function edited in place, md5-guarded)
-- Retires: nothing
set local lock_timeout = '5s';  -- fixed: lock wait for the setting row and the function

do $g$
declare v jsonb := security.consumer_api_check_v1();
begin
  if jsonb_array_length(coalesce(v->'drift', '[]'::jsonb)) <> 0 or (v->>'functions')::int <> 75 or (v->>'relations')::int <> 48 then
    raise exception 'guard: the consumer API is not at its baseline before this change: %', v;
  end if;
end $g$;
create temp table s1038_locks on commit drop as select count(*) n from pipeline.manual_locks;

insert into pipeline.platform_toolset_settings (toolset_key, key, label, help, kind, value, unit, sort, reason, section, used_by)
values ('pipeline', 'aer.provider_host_aliases', 'Entry matrices: provider site aliases',
  'Each entry is "<provider id>:<host>". A stored entry-requirement source on that host (or a subdomain of it) counts as the provider''s own website for the machine admission check, for a provider whose website host differs from the host its documents are on (Adelaide University: adelaideuni.edu.au and adelaide.edu.au). It changes no other check; a host shared with another active provider is still refused.',
  'list', '["de2201a1-69ee-40ff-b6aa-0e54e535e6c0:adelaide.edu.au"]'::jsonb, 'hosts', 924,
  'Platform Admin 24 Nov 2026 14:21 (S2-RM-Design brief item 1, s1038): adelaide.edu.au is an approved legacy domain of Adelaide University', 'Entry requirements',
  'security.aer_matrix_machine_check_v1 (rule source_not_official_host)')
on conflict (toolset_key, key) do nothing;
insert into pipeline.admin_control_events (area, action, target, detail, actor)
values ('settings', 'migration', 'pipeline.platform_toolset_settings', jsonb_build_object('key', 'aer.provider_host_aliases', 'after', '["de2201a1-69ee-40ff-b6aa-0e54e535e6c0:adelaide.edu.au"]'::jsonb,
        'reason', 'Platform Admin 24 Nov 2026 14:21: adelaide.edu.au approved for Adelaide University (s1038)', 'migration', '20261124170000'), security.system_actor_id());

do $f$
declare
  v_fn regprocedure := 'security.aer_matrix_machine_check_v1(uuid)'::regprocedure;
  v_def text := pg_get_functiondef('security.aer_matrix_machine_check_v1(uuid)'::regprocedure);
  a text := 'if v_sh is null or v_ph is null or not (v_sh = v_ph or v_sh like ''%.'' || v_ph) then';
  b text := 'if v_sh is null or v_ph is null or not (v_sh = v_ph or v_sh like ''%.'' || v_ph or exists (select 1 from jsonb_array_elements_text(coalesce(security.toolset_setting(''pipeline'', ''aer.provider_host_aliases''), ''[]''::jsonb)) x(al) where split_part(x.al, '':'', 1) = i.entity_id::text and v_sh is not null and (v_sh = split_part(x.al, '':'', 2) or v_sh like ''%.'' || split_part(x.al, '':'', 2)))) then';
begin
  if strpos(v_def, 'aer.provider_host_aliases') > 0 then return; end if;
  if md5(v_def) <> 'd3d038ebe92f4c3b81c088ed0fbc4169' then raise exception 'guard: aer_matrix_machine_check_v1 changed since the live read-back; rebase and re-verify'; end if;
  if (length(v_def) - length(replace(v_def, a, ''))) <> length(a) then raise exception 'guard: host condition anchor absent or repeated'; end if;
  execute replace(v_def, a, b);
  if strpos(pg_get_functiondef(v_fn), 'aer.provider_host_aliases') = 0 then raise exception 'post-check: the machine check edit was not applied'; end if;
end $f$;

do $p$
declare v jsonb := security.consumer_api_check_v1(); v_rule text; v_it uuid;
begin
  if jsonb_array_length(coalesce(v->'drift', '[]'::jsonb)) <> 0 or (v->>'functions')::int <> 75 or (v->>'relations')::int <> 48 then raise exception 'post-check: the consumer API moved: %', v; end if;
  if (select count(*) from pipeline.manual_locks) <> (select n from s1038_locks) then raise exception 'post-check: manual locks changed'; end if;
  -- Adelaide's pending first read no longer stops at the host rule
  select i.id into v_it from pipeline.layer4_review_items i where i.entity_id = 'de2201a1-69ee-40ff-b6aa-0e54e535e6c0' and i.status = 'pending' and i.field_code = 'entry_matrix_first_run' limit 1;
  if v_it is not null then
    v_rule := security.aer_matrix_machine_check_v1(v_it)->>'rule';
    if v_rule = 'source_not_official_host' then raise exception 'post-check: Adelaide still stops at the host rule'; end if;
    raise notice 'Adelaide first-read item % now answers rule %', v_it, coalesce(v_rule, 'ok');
  end if;
end $p$;
