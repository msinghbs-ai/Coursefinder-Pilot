-- CF-247 Wave 2 admission groundwork (S2-Build; Platform Admin 18 Nov 2026 07:34: "Register the four missing ref.registration_schemes entries
-- (uk_hesa, uk_ukvi, ie_ilep, us_ipeds_completions) so the 9 Wave 2 drafts ... can be mapped, sample-tested, and admitted cleanly (reconciling any
-- older duplicate source rows for OfS/Discover Uni/IRQ/UKVI before activation)").
-- 1. Four schemes, status planned like the other Wave 2 schemes (S1-RM-Design, 20261118004000), so step 1 of the four drafts that had none can be
--    finished: UKVI licensed sponsors (GB), Discover Uni / HESA courses (GB), ILEP (IE), IPEDS completions (US). Each draft gets its scheme and kind
--    (only where both are still empty; nothing else in a draft changes).
-- 2. Four seed source rows from 11 Aug 2026 duplicate the Wave 2 drafts (Office for Students Register, Discover Uni Dataset, Irish Register of
--    Qualifications, UKVI Register of Licensed Student Sponsors). None has Layer 1 controls, and no row in any of the 46 tables that reference
--    pipeline.sources points at them (read 18 Nov 07:4x AEDT). public.admin_layer1_add_source refuses an address a non-retired source already holds,
--    so the UKVI and IRQ drafts could not be activated. They are marked retired (not deleted), each naming the draft that replaces it.
-- 3. Two pairs of drafts read different files listed on one landing page (IRQ providers and programmes; IPEDS institutions and completions), so the
--    second of each pair would be refused as a duplicate address. public.admin_layer1_add_source now refuses an address only when a non-retired
--    source with the same address also has the same name (md5-guarded edit, one exact replacement).
-- No source is activated or switched on here: activation stays the Platform Admin's (wizard step 6). G3 surface untouched; nothing dropped.
-- Replaces: the address-only duplicate check in public.admin_layer1_add_source.
-- Retires: the four seed source rows above (status retired; they held no data).

insert into ref.registration_schemes(scheme, kind, country_code, authority, label, never_mixed_with, status) values
 ('uk_ukvi', 'provider_registration', 'GB', 'UK Visas and Immigration (Home Office)', 'UKVI licensed student sponsor (Register of Licensed Sponsors: Students)',
  array['uk_ofs', 'uk_qaa', 'cricos', 'ircc_dli'], 'planned'),
 ('uk_hesa', 'course_registration', 'GB', 'Higher Education Statistics Agency (Jisc)', 'Discover Uni / HESA course (UKPRN with KISCOURSEID and study mode)',
  array['cricos', 'nzqa', 'ie_qqi', 'mtcu', 'us_ipeds_completions'], 'planned'),
 ('ie_ilep', 'course_registration', 'IE', 'Immigration Service Delivery, Department of Justice', 'Interim List of Eligible Programmes (ILEP) programme',
  array['ie_qqi', 'cricos', 'nzqa'], 'planned'),
 ('us_ipeds_completions', 'course_registration', 'US', 'National Center for Education Statistics, US Department of Education',
  'IPEDS completions programme (unit ID with CIP code and award level)', array['cricos', 'nzqa', 'ie_qqi', 'uk_hesa'], 'planned')
on conflict (scheme, kind, country_code) do nothing;

update pipeline.layer1_source_inductions i
   set payload = i.payload || jsonb_build_object('scheme', x.scheme, 'scheme_kind', x.kind), updated_at = now()
  from (values ('e3547fbc-b62c-4ec6-b584-3c7096857a32'::uuid, 'uk_ukvi', 'provider_registration'),
               ('e236702c-9ade-4c02-8141-4aede7e25825'::uuid, 'uk_hesa', 'course_registration'),
               ('437a8795-cec8-4775-8672-4abfa6ae80c4'::uuid, 'ie_ilep', 'course_registration'),
               ('bc13db81-dca8-4243-96ff-3ec3743a1c7d'::uuid, 'us_ipeds_completions', 'course_registration')) x(id, scheme, kind)
 where i.id = x.id and i.status = 'draft' and coalesce(i.payload->>'scheme', '') = '' and coalesce(i.payload->>'scheme_kind', '') = '';

-- 2. retire the four unused seed rows (guarded: still unused, no Layer 1 controls)
do $$
declare v_ids uuid[] := array['bb4f83f2-5878-457b-acfb-c47439d7cbf1', '7825db93-dc34-427a-b33e-c15cb914cb42', 'f403874c-ad4b-49d1-8db7-06448d056589',
                              '5c75e8d5-1d36-4511-9af2-2b5f1cc69db3']::uuid[];
        r record; v_n bigint;
begin
  for r in select c.conrelid::regclass t, a.attname col from pg_constraint c join pg_attribute a on a.attrelid = c.conrelid and a.attnum = any(c.conkey)
            where c.confrelid = 'pipeline.sources'::regclass and c.contype = 'f' loop
    execute format('select count(*) from %s where %I = any($1)', r.t, r.col) into v_n using v_ids;
    if v_n > 0 then raise exception 'a seed source row is now referenced by %.% (% rows): not retired, nothing changed', r.t, r.col, v_n; end if;
  end loop;
  update pipeline.sources s set status = 'retired', updated_at = now(),
         metadata = s.metadata || jsonb_build_object('retired_on', current_date, 'retired_by', 'migration 20261118080000 (S2-Build)',
                      'superseded_by_induction', x.induction, 'retired_reason', 'duplicate of a Wave 2 induction draft; held no data')
    from (values ('bb4f83f2-5878-457b-acfb-c47439d7cbf1'::uuid, '1fe2703e-81b9-4883-b108-f7778bfa5604'),
                 ('7825db93-dc34-427a-b33e-c15cb914cb42'::uuid, 'e236702c-9ade-4c02-8141-4aede7e25825'),
                 ('f403874c-ad4b-49d1-8db7-06448d056589'::uuid, '4e4cf611-51fb-4abb-85d5-4392e8826ea2 and 0df25fd1-003a-4b64-a797-f6edb76e6eb6'),
                 ('5c75e8d5-1d36-4511-9af2-2b5f1cc69db3'::uuid, 'e3547fbc-b62c-4ec6-b584-3c7096857a32')) x(id, induction)
   where s.id = x.id and s.status <> 'retired'
     and not exists (select 1 from pipeline.layer1_source_operations o where o.source_id = s.id);
  insert into pipeline.admin_control_events(area, action, target, detail, actor)
  select 'layer1', 'source_retired_duplicate', s.id::text, jsonb_build_object('label', s.label, 'url', s.url, 'superseded_by_induction', s.metadata->>'superseded_by_induction', 'by', 'migration 20261118080000'), null
    from pipeline.sources s where s.id = any(v_ids) and s.metadata->>'retired_by' = 'migration 20261118080000 (S2-Build)';
end $$;

-- 3. duplicate-address check also compares the name (md5-guarded)
do $e$
declare v_src text := (select prosrc from pg_proc where oid = 'public.admin_layer1_add_source(jsonb)'::regprocedure); v_def text; v_out text; v_c int;
        v_old text := $o$if exists (select 1 from pipeline.sources s where lower(s.url) = lower(v_url) and s.status <> 'retired') then raise exception 'a source with this address already exists'; end if;$o$;
        v_new text := $n$if exists (select 1 from pipeline.sources s where lower(s.url) = lower(v_url) and lower(btrim(s.label)) = lower(btrim(v_label)) and s.status <> 'retired') then raise exception 'a source with this address and name already exists'; end if;  -- Wave 2 (18 Nov 2026): several files on one landing page are separate sources$n$;
begin
  if position('Wave 2 (18 Nov 2026): several files on one landing page' in v_src) > 0 then raise notice 'admin_layer1_add_source: already applied'; return; end if;
  if md5(v_src) <> 'af4ddf6016526eb12c06a27c94b54970' then raise exception 'live public.admin_layer1_add_source differs from the definition this change edits (body md5 %)', md5(v_src); end if;
  v_def := replace(pg_get_functiondef('public.admin_layer1_add_source(jsonb)'::regprocedure), chr(13), '');
  v_c := (length(v_def) - length(replace(v_def, v_old, ''))) / length(v_old);
  if v_c <> 1 then raise exception 'admin_layer1_add_source: the edit must apply exactly once (found %)', v_c; end if;
  execute replace(v_def, v_old, v_new);
  v_out := replace(v_src, v_old, v_new);
  if md5((select prosrc from pg_proc where oid = 'public.admin_layer1_add_source(jsonb)'::regprocedure)) <> md5(v_out) then raise exception 'admin_layer1_add_source after the edit is not the expected body'; end if;
end $e$;

do $$
begin
  if (select count(*) from ref.registration_schemes where scheme in ('uk_ukvi', 'uk_hesa', 'ie_ilep', 'us_ipeds_completions')) <> 4 then raise exception 'post-check: schemes'; end if;
  if exists (select 1 from pipeline.layer1_source_inductions i where i.status = 'draft' and i.created_at < now() and coalesce(i.payload->>'notes', '') like 'Wave 2 draft%'
              and not (security.layer1_induction_steps_v1(i)->>'scheme')::boolean) then
    raise exception 'post-check: a Wave 2 draft still has step 1 unfinished';
  end if;
  if exists (select 1 from pipeline.sources where id in ('bb4f83f2-5878-457b-acfb-c47439d7cbf1', '7825db93-dc34-427a-b33e-c15cb914cb42', 'f403874c-ad4b-49d1-8db7-06448d056589',
              '5c75e8d5-1d36-4511-9af2-2b5f1cc69db3') and status <> 'retired') then raise exception 'post-check: a duplicate seed source row is not retired'; end if;
  if exists (select 1 from pipeline.layer1_source_inductions i join pipeline.sources s on lower(s.url) = lower(i.payload->>'source_url') and lower(btrim(s.label)) = lower(btrim(i.payload->>'source_label'))
              where i.status = 'draft' and s.status <> 'retired') then raise exception 'post-check: a draft would still be refused as a duplicate source'; end if;
end $$;
