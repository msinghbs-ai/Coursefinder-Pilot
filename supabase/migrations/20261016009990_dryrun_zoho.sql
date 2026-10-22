-- CF-247 (23 Oct 2026). Platform Admin 07:47 chose "Page bound by a person, exact title, title and level" as proofs that admit a
-- page's international fee for NZ (238 NZ courses held a safely read international fee that was never admitted because NZ fees only
-- accepted CRICOS or NZQA code proof; the fee still goes through the AI fee check before admission). Exact title and title with level
-- were set on Settings › 4 Identify the page (logged in pipeline.admin_control_events). "Page bound by a person" (manual) could not be
-- set there: the settings write accepted only six proofs, and it refused any change to a row that already held manual, host_page,
-- adapter_code or adapter_title (English, intakes and official address for AU, NZ and CA), so those three columns could not be changed
-- from the screen at all.
-- 1 public.admin_pipeline_settings_write accepts every proof the gate reads: adds manual, host_page, adapter_code, adapter_title
--   (md5-guarded edit in place).
-- 2 NZ tuition: adds manual, through the settings write (logged like a screen change).
-- Replaces: nothing (public.admin_pipeline_settings_write edited in place, md5-guarded)
-- Retires: nothing
do $do$
declare v_def text := pg_get_functiondef('public.admin_pipeline_settings_write(text,jsonb)'::regprocedure);
  v_old text := $o$x not in ('cricos_code', 'nzqa_code', 'exact_title', 'title_level', 'field_award', 'degree_name')$o$;
  v_new text := $n$x not in ('cricos_code', 'nzqa_code', 'exact_title', 'title_level', 'field_award', 'degree_name', 'manual', 'host_page', 'adapter_code', 'adapter_title')$n$;
begin
  if md5(v_def) <> '47491f592951aaeada568c06411cd8be' then raise exception 'public.admin_pipeline_settings_write is not the expected version (md5 %)', md5(v_def); end if;
  if (length(v_def) - length(replace(v_def, v_old, ''))) / length(v_old) <> 1 then raise exception 'settings write: expected one identity list'; end if;
  execute replace(v_def, v_old, v_new);
end $do$;

-- 2 NZ tuition also admits pages bound by a person (Platform Admin decision 23 Oct 07:47)
do $do$
declare v_cur jsonb;
begin
  select a.identities->'tuition' into v_cur from pipeline.coverage_admission_countries a join ref.countries k on k.id = a.country_id where k.iso_alpha2 = 'NZ';
  if not coalesce(v_cur ? 'manual', false) then
    update pipeline.coverage_admission_countries c
       set identities = jsonb_set(c.identities, '{tuition}', coalesce(v_cur, '[]'::jsonb) || '["manual"]'::jsonb, true), updated_at = now(),
           approved_ref = c.approved_ref || '; Platform Admin 23 Oct 2026 07:47 (tuition: page bound by a person)'
      from ref.countries k where k.id = c.country_id and k.iso_alpha2 = 'NZ';
    insert into pipeline.admin_control_events(area, action, target, detail, actor)
    values ('settings', 'change', 'identity.attribute', jsonb_build_object('value', jsonb_build_object('country', 'NZ', 'attribute', 'tuition', 'identities', coalesce(v_cur, '[]'::jsonb) || '["manual"]'::jsonb), 'before', v_cur, 'reason', 'Platform Admin 23 Oct 07:47: NZ fees from pages bound by a person'), '63ba56cb-48d4-4169-98c2-7c4d1f72925b');
  end if;
end $do$;

select 'identity settings accept every proof; NZ tuition admits pages bound by a person' ok;
do $t$ declare r jsonb; v jsonb; begin
  perform set_config('request.jwt.claims', '{"sub":"63ba56cb-48d4-4169-98c2-7c4d1f72925b","role":"authenticated"}', true);
  perform set_config('request.jwt.claim.sub', '63ba56cb-48d4-4169-98c2-7c4d1f72925b', true);
  select a.identities into v from pipeline.coverage_admission_countries a join ref.countries k on k.id = a.country_id where k.iso_alpha2 = 'NZ';
  r := public.admin_pipeline_settings_write('identity.attribute', jsonb_build_object('country', 'NZ', 'attribute', 'english', 'identities', v->'english'));
  raise exception 'DRYRUN OK %', jsonb_build_object('nz_tuition', (select a.identities->'tuition' from pipeline.coverage_admission_countries a join ref.countries k on k.id = a.country_id where k.iso_alpha2 = 'NZ'), 'english_write_ok', r is not null,
    'allowed', security.coverage_identity_allowed((select id from catalogue.providers where display_name = 'University of Auckland'), 'manual', 'tuition')); end $t$;
