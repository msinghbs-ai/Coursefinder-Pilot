-- CF-247 F-AER.03 (country and qualification variants) AER qualification-first storage: international qualifications kept with their identity, not dropped for having no country (Platform Admin 11 Nov 2026
-- decisions, item 2 "Qualification-first design": "Do not introduce International as a synthetic country and do not duplicate qualifications across countries ... Store
-- canonical qualification identity, awarding body, level, grading scheme, aliases and evidence-backed recognition separately from applicant country ... A Nepalese or Indian
-- student holding IB must be able to retrieve the relevant university IB requirements without requiring duplicate country rows"; item 3 phase 1: European applicant
-- countries in the qualification and AER country-reference model using authoritative ISO identities). Design: AER-TECHNICAL-DESIGN §13 (SS-017), smallest additive form.
-- Guards: G1 (no job), G2 (switches and lists are settings), G3 (additive: new tables beside catalogue.provider_entry_matrix; nothing the consumer API reads is altered),
--   Decision 260, Layer 4 authority unchanged (every qualification row is proposed and admitted only by the person's decision on the same entry-matrix item).
-- Evidence (production, read only, 11 Nov 2026 17:15 AEDT): the entry matrix reader has dropped 183 rows as unknown_country. They are not unknown countries: international
--   qualifications and global scopes (IB/IB Diploma/IB Certificate about 40, INT/Worldwide/All countries/GLOBAL/ANY/General/International about 60, GAC, Cambridge
--   International, Pearson Edexcel, NCUK, AP International Diploma), regions ("Pacific Islands") and UK/GB-SCT tokens (the alias switch is off). catalogue.provider_entry_matrix
--   requires a country (country_code NOT NULL), so these rows have nowhere to go. Active matrix rows name IB 0 times by qualification; 10 of 44 European countries have any rows.
-- What:
--   1. ref.aer_qualifications NEW: canonical identity of a qualification family (code, name, awarding body, level, scope international or national, ISO country of a national
--      qualification, grading scheme as published by the awarding body, aliases). Seeded with the international families of design §13.2 and European national school-leaving
--      qualifications. Reference identity only: no row here is admission evidence; every requirement keeps its own provider quote.
--   2. catalogue.provider_qualification_requirements NEW, beside the matrix: a provider's published requirement for a qualification, with applicability (global only when the
--      page says so: an explicit "all countries / worldwide / international" scope; otherwise unresolved), level, grade or value and scale, quote, source, evidence, read, status.
--   3. public.svc_entry_matrix_record (md5-guarded edit): qualification rows the reader returns (p_result.qualification_rows) are recorded as proposed for a recognised
--      international qualification and go on the same Layer 4 item as the read's matrix rows; unknown ones are dropped as unknown_qualification.
--   4. security.entry_matrix_review_apply_v1 (md5-guarded edit): the person's decision on that item applies to its qualification rows too (approve, approve except, reject).
--   5. public.svc_aer_qualifications_v1 NEW (service role): the international qualifications and their aliases, and the global scope tokens, for the reader.
--   6. public.admin_aer_qualification_lookup NEW (rank 4, read only): by qualification (code or alias) and optional education country, each provider's active and waiting
--      requirements for it, plus that country's matrix rows naming it; the qualification list.
--   7. Settings: reading.entry_qualification_first_on (1), reading.entry_global_scope_tokens; reading.entry_country_aliases_on 0 -> 1 (decision item 3, phase 1: UK and the
--      GB home nations read as GB, the ISO identity).
-- Not here: re-reading the stored pages whose earlier reads dropped these rows is a separate step after the reader that returns them (coverage-sweep v0.70.0) is live.
-- Live definitions this change edits (pg_proc.prosrc md5, read 11 Nov 2026 18:20 AEDT by Database function snapshot run 42977913332), before -> after:
--   public.svc_entry_matrix_record(uuid,jsonb,numeric,text) 3e76d77b83bc8c1f9514b40f7cb4ac3e -> 7eee2ef2229520266fd56c8aa8f1f1fb
--   security.entry_matrix_review_apply_v1(uuid,text,jsonb,text,uuid) 6d7b47fe7d2cd40b9cfb8f3547bad158 -> c46ef6d3f9820c3d4d822846909e35ce
-- Replaces: public.svc_entry_matrix_record, security.entry_matrix_review_apply_v1 (same names; md5-guarded text edits, resulting md5 checked); taken back by
--   supabase/held/aer_qualification_first_forward_recovery.sql
-- Retires: nothing.
-- Reversal without code: reading.entry_qualification_first_on 0 (no qualification row is recorded; the reader's rows are dropped as before).

do $g$
declare r record;
begin
  for r in select * from (values ('public.svc_entry_matrix_record(uuid,jsonb,numeric,text)'), ('security.entry_matrix_review_apply_v1(uuid,text,jsonb,text,uuid)'),
                                 ('security.entry_level_map_v1(text)'), ('security.pipeline_num_v1(text,numeric)'), ('security.current_role_rank()')) v(sig) loop
    if to_regprocedure(r.sig) is null then raise exception 'required % is missing', r.sig; end if;
  end loop;
  if to_regclass('catalogue.provider_entry_matrix') is null or to_regclass('pipeline.entry_matrix_runs') is null or to_regclass('ref.countries') is null then
    raise exception 'a table this change reads is missing'; end if;
end $g$;

-- 1. canonical qualifications ----------------------------------------------------------------------------------------------------------------------
create table if not exists ref.aer_qualifications (
  code text primary key,
  family text not null,
  name text not null,
  awarding_body text,
  level text not null check (level in ('upper_secondary', 'subject_level', 'foundation')),
  scope text not null check (scope in ('international', 'national')),
  country_code text,
  grading_scheme text,
  aliases text[] not null default '{}',
  notes text,
  created_at timestamptz not null default now(),
  check ((scope = 'national') = (country_code is not null))
);
comment on table ref.aer_qualifications is 'CF-247 F-AER.03: canonical identity of the qualifications AER requirements refer to (family, awarding body, level, international or national scope with its ISO country, grading scheme, aliases). Reference identity only, never admission evidence: each provider requirement keeps its own quote and source.';

insert into ref.aer_qualifications(code, family, name, awarding_body, level, scope, country_code, grading_scheme, aliases) values
 ('IB_DP', 'International Baccalaureate', 'International Baccalaureate Diploma', 'International Baccalaureate Organization', 'upper_secondary', 'international', null,
  'Diploma points out of 45', array['international baccalaureate', 'international baccalaureate diploma', 'ib diploma', 'ibdp', 'ib', 'international baccalaureate ib', 'international baccalaureate ib diploma', 'global ib']),
 ('IB_COURSES', 'International Baccalaureate', 'International Baccalaureate Diploma Programme courses (certificates)', 'International Baccalaureate Organization', 'subject_level', 'international', null,
  'Subject grades 1 to 7', array['international baccalaureate certificate', 'ib certificate', 'international baccalaureate certificate ib', 'ib courses', 'ib diploma programme courses']),
 ('IB_CP', 'International Baccalaureate', 'International Baccalaureate Career-related Programme', 'International Baccalaureate Organization', 'upper_secondary', 'international', null,
  null, array['ib career-related programme', 'ibcp', 'international baccalaureate career-related programme']),
 ('EB', 'European Baccalaureate', 'European Baccalaureate', 'Board of Governors of the European Schools', 'upper_secondary', 'international', null,
  'Final mark out of 100', array['european baccalaureate', 'baccalaureat europeen']),
 ('GCE_A', 'GCE Advanced Level', 'GCE A Level', 'UK awarding bodies (AQA, OCR, Pearson Edexcel, WJEC/Eduqas, CCEA)', 'upper_secondary', 'international', null,
  'Grades A* to E', array['gce a level', 'gce a levels', 'a level', 'a levels', 'a-level', 'a-levels', 'gce advanced level', 'advanced level']),
 ('GCE_AS', 'GCE Advanced Level', 'GCE AS Level', 'UK awarding bodies (AQA, OCR, Pearson Edexcel, WJEC/Eduqas, CCEA)', 'subject_level', 'international', null,
  'Grades A to E', array['gce as level', 'as level', 'as levels', 'as-level']),
 ('CAIE_AL', 'Cambridge International', 'Cambridge International AS & A Level', 'Cambridge Assessment International Education', 'upper_secondary', 'international', null,
  'Grades A* to E', array['cambridge international as and a level', 'cambridge international a level', 'cambridge international examinations', 'cambridge international examinations cie', 'cie', 'caie', 'cie a level', 'cambridge a level']),
 ('IGCSE', 'International GCSE', 'International GCSE', 'Cambridge Assessment International Education; Pearson Edexcel', 'subject_level', 'international', null,
  'Grades 9 to 1 or A* to G', array['igcse', 'international gcse', 'cambridge igcse', 'pearson edexcel international gcse', 'cie pearson edexcel igcse levels']),
 ('PEARSON_IAL', 'Pearson Edexcel International', 'Pearson Edexcel International Advanced Level', 'Pearson Edexcel', 'upper_secondary', 'international', null,
  'Grades A* to E', array['pearson edexcel international advanced level', 'pearson edexcel international a level', 'international advanced level', 'pearson edexcel', 'edexcel']),
 ('GAC', 'Global Assessment Certificate', 'Global Assessment Certificate', 'ACT Education Solutions', 'foundation', 'international', null,
  null, array['global assessment certificate', 'gac']),
 ('APID', 'Advanced Placement', 'Advanced Placement International Diploma', 'College Board', 'upper_secondary', 'international', null,
  'AP examination scores 1 to 5', array['advanced placement international diploma', 'advanced placement international diploma apid', 'apid', 'ap international diploma']),
 ('AP', 'Advanced Placement', 'Advanced Placement examinations', 'College Board', 'subject_level', 'international', null,
  'AP examination scores 1 to 5', array['advanced placement', 'ap exams', 'ap examinations']),
 ('US_HSD', 'US High School Diploma', 'United States High School Diploma', null, 'upper_secondary', 'national', 'US',
  'Grade point average, usually out of 4.0', array['american high school diploma', 'us high school diploma', 'united states high school diploma']),
 ('NCUK_IFY', 'NCUK', 'NCUK International Foundation Year', 'NCUK (Northern Consortium UK)', 'foundation', 'international', null,
  null, array['ncuk international foundation year', 'ncuk international foundation year ncuk ify', 'ncuk ify', 'northern consortium uk international foundation year', 'northern consortium united kingdom ncuk', 'ncuk']),
 -- European national school-leaving qualifications (ISO country of the awarding system)
 ('DE_ABITUR', 'Abitur', 'Allgemeine Hochschulreife (Abitur)', 'German Länder', 'upper_secondary', 'national', 'DE', 'Overall grade 1.0 (best) to 4.0', array['abitur', 'allgemeine hochschulreife']),
 ('AT_MATURA', 'Matura', 'Reifeprüfung (Matura)', 'Austria', 'upper_secondary', 'national', 'AT', 'Grades 1 (best) to 5', array['reifeprufung', 'osterreichische matura']),
 ('CH_MATURITY', 'Matura', 'Swiss Federal Maturity Certificate', 'Switzerland', 'upper_secondary', 'national', 'CH', 'Grades 1 to 6 (best)', array['swiss maturity certificate', 'federal maturity certificate', 'maturitat', 'maturite']),
 ('FR_BAC', 'Baccalauréat', 'Baccalauréat (France)', 'France', 'upper_secondary', 'national', 'FR', 'Out of 20', array['baccalaureat', 'french baccalaureate', 'baccalaureat general']),
 ('IT_MATURITA', 'Esame di Stato', 'Diploma di Esame di Stato (Maturità)', 'Italy', 'upper_secondary', 'national', 'IT', 'Out of 100', array['maturita', 'diploma di esame di stato', 'esame di stato']),
 ('ES_BACHILLER', 'Bachillerato', 'Título de Bachiller', 'Spain', 'upper_secondary', 'national', 'ES', 'Out of 10', array['bachillerato', 'titulo de bachiller']),
 ('PT_SECUNDARIO', 'Ensino Secundário', 'Diploma de Ensino Secundário', 'Portugal', 'upper_secondary', 'national', 'PT', 'Out of 20', array['diploma de ensino secundario', 'ensino secundario']),
 ('NL_VWO', 'VWO', 'VWO diploma', 'Netherlands', 'upper_secondary', 'national', 'NL', 'Grades 1 to 10', array['vwo', 'vwo diploma']),
 ('BE_CESS', 'Secondary education certificate', 'Certificat d''enseignement secondaire supérieur / Diploma van secundair onderwijs', 'Belgium', 'upper_secondary', 'national', 'BE', null, array['cess', 'diploma van secundair onderwijs', 'certificat d enseignement secondaire superieur']),
 ('IE_LC', 'Leaving Certificate', 'Leaving Certificate (Ireland)', 'State Examinations Commission', 'upper_secondary', 'national', 'IE', 'Points (CAO)', array['irish leaving certificate', 'leaving certificate']),
 ('GB_SQA_HIGHER', 'Scottish Highers', 'Scottish Highers and Advanced Highers', 'Scottish Qualifications Authority', 'upper_secondary', 'national', 'GB', 'Grades A to D', array['scottish highers', 'advanced highers', 'sqa highers']),
 ('DK_STX', 'Studentereksamen', 'Studentereksamen', 'Denmark', 'upper_secondary', 'national', 'DK', '7-point scale (-3 to 12)', array['studentereksamen', 'stx']),
 ('SE_GYMNASIE', 'Gymnasieexamen', 'Högskoleförberedande examen (Gymnasieexamen)', 'Sweden', 'upper_secondary', 'national', 'SE', 'Grades A to F', array['gymnasieexamen', 'hogskoleforberedande examen']),
 ('NO_VITNEMAL', 'Vitnemål', 'Vitnemål fra videregående opplæring', 'Norway', 'upper_secondary', 'national', 'NO', 'Grades 1 to 6 (best)', array['vitnemal', 'videregaende']),
 ('FI_YO', 'Ylioppilastutkinto', 'Finnish Matriculation Examination (Ylioppilastutkinto)', 'Finland', 'upper_secondary', 'national', 'FI', null, array['ylioppilastutkinto', 'finnish matriculation examination']),
 ('PL_MATURA', 'Matura', 'Świadectwo dojrzałości (Matura)', 'Poland', 'upper_secondary', 'national', 'PL', 'Percentages', array['swiadectwo dojrzalosci', 'polish matura']),
 ('CZ_MATURITA', 'Maturita', 'Maturitní vysvědčení', 'Czechia', 'upper_secondary', 'national', 'CZ', 'Grades 1 (best) to 5', array['maturitni vysvedceni', 'czech maturita']),
 ('HU_ERETTSEGI', 'Érettségi', 'Érettségi bizonyítvány', 'Hungary', 'upper_secondary', 'national', 'HU', 'Grades 1 to 5 (best)', array['erettsegi', 'erettsegi bizonyitvany']),
 ('RO_BAC', 'Bacalaureat', 'Diplomă de Bacalaureat', 'Romania', 'upper_secondary', 'national', 'RO', 'Out of 10', array['bacalaureat', 'diploma de bacalaureat']),
 ('GR_APOLYTIRIO', 'Apolytirio', 'Apolytirio (Lykeio)', 'Greece', 'upper_secondary', 'national', 'GR', 'Out of 20', array['apolytirio', 'lykeio']),
 ('TR_LISE', 'Lise Diploması', 'Lise Diploması', 'Türkiye', 'upper_secondary', 'national', 'TR', 'Out of 100', array['lise diplomasi']),
 ('RU_ATTESTAT', 'Attestat', 'Certificate of Secondary (Complete) General Education (Attestat)', 'Russian Federation', 'upper_secondary', 'national', 'RU', 'Grades 2 to 5 (best)', array['attestat', 'certificate of secondary complete general education']),
 ('UA_ATESTAT', 'Atestat', 'Certificate of Complete General Secondary Education (Atestat)', 'Ukraine', 'upper_secondary', 'national', 'UA', null, array['atestat', 'certificate of complete general secondary education'])
on conflict (code) do nothing;

-- 2. a provider's requirement for a qualification, beside the matrix --------------------------------------------------------------------------
create table if not exists catalogue.provider_qualification_requirements (
  id uuid primary key default gen_random_uuid(),
  provider_id uuid not null references catalogue.providers(id),
  qualification_code text not null references ref.aer_qualifications(code),
  qualification_label text not null,
  applicability text not null check (applicability in ('global', 'countries', 'unresolved')),
  applicable_countries text[] not null default '{}',
  level_label text,
  study_level_id uuid,
  min_grade text,
  min_value numeric,
  grade_scale text not null default 'none',
  conditions jsonb not null default '{}'::jsonb,
  quote text not null,
  source_url text,
  source_id uuid,
  evidence_id uuid,
  content_hash text,
  run_id uuid,
  confidence numeric,
  status text not null default 'proposed' check (status in ('proposed', 'active', 'inactive', 'superseded')),
  status_reason text,
  provenance jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
comment on table catalogue.provider_qualification_requirements is 'CF-247 F-AER.03: a provider''s published entry requirement for a qualification (ref.aer_qualifications), held apart from the applicant''s country: applicability global only when the page says so, otherwise unresolved; each row keeps its quote, source and read; proposed rows are admitted by the person''s decision on the entry-matrix Layer 4 item. Beside catalogue.provider_entry_matrix; not read by the consumer API.';
create index if not exists provider_qualification_requirements_provider_idx on catalogue.provider_qualification_requirements (provider_id, qualification_code, status);
create index if not exists provider_qualification_requirements_run_idx on catalogue.provider_qualification_requirements (run_id);
create index if not exists provider_qualification_requirements_code_idx on catalogue.provider_qualification_requirements (qualification_code, status);

-- 7. settings ------------------------------------------------------------------------------------------------------------------------------------
insert into pipeline.platform_toolset_settings(toolset_key, key, label, help, kind, value, min_value, max_value, unit, sort, section, used_by, reason) values
 ('pipeline', 'reading.entry_qualification_first_on', 'Entry requirements: keep international qualifications (qualification-first)',
  '1 keeps an entry-matrix row for a recognised international qualification (IB, European Baccalaureate, A Levels, Cambridge International, GAC and the others in the qualification list) that names no country of education, recorded with its qualification identity and applicability for the person''s decision. 0 drops such rows as before.',
  'number', to_jsonb(1), 0, 1, 'switch', 1510, 'Entry requirements', 'public.svc_entry_matrix_record; coverage-sweep entry_ai',
  'Platform Admin decision 11 Nov 2026, item 2: qualification-first design'),
 ('pipeline', 'reading.entry_global_scope_tokens', 'Entry requirements: words a page uses for "every country"',
  'Country headings the entry matrix reader treats as an explicit every-country scope (the row is kept only for a recognised qualification; applicability global).',
  'list', '["ALL", "ANY", "INT", "GLOBAL", "WORLDWIDE", "INTERNATIONAL", "ALL COUNTRIES", "ANY COUNTRY", "GENERAL"]'::jsonb, null, null, 'words', 1511, 'Entry requirements',
  'public.svc_aer_qualifications_v1; coverage-sweep entry_ai', 'CF-247 F-AER.03: tokens measured in the unknown_country drops (11 Nov 2026)')
on conflict (toolset_key, key) do nothing;
update pipeline.platform_toolset_settings set value = to_jsonb(1),
       reason = 'Platform Admin decision 11 Nov 2026, item 3 phase 1: European applicant countries by their ISO identity (UK and the GB home nations read as GB)', updated_at = now()
 where toolset_key = 'pipeline' and key = 'reading.entry_country_aliases_on' and value = to_jsonb(0);

-- 5-6. reads -----------------------------------------------------------------------------------------------------------------------------------
create or replace function public.svc_aer_qualifications_v1() returns jsonb
language plpgsql stable security definer set search_path = '' as $f$
begin
  if current_user <> 'postgres' and coalesce(auth.role(), '') <> 'service_role' then raise exception 'service_role required'; end if;
  return jsonb_build_object(
    'on', security.pipeline_num_v1('reading.entry_qualification_first_on', 0) >= 1,
    'qualifications', (select coalesce(jsonb_agg(jsonb_build_object('code', q.code, 'aliases', to_jsonb(array_append(q.aliases, lower(q.name)))) order by q.code), '[]'::jsonb)
                         from ref.aer_qualifications q where q.scope = 'international'),
    'global_tokens', coalesce(security.toolset_setting('pipeline', 'reading.entry_global_scope_tokens'), '[]'::jsonb));
end $f$;
revoke all on function public.svc_aer_qualifications_v1() from public, anon, authenticated;
grant execute on function public.svc_aer_qualifications_v1() to service_role;
comment on function public.svc_aer_qualifications_v1() is 'CF-247 F-AER.03: for the entry matrix reader (service role): whether qualification-first is on, the international qualifications with their aliases, and the every-country scope tokens.';

create or replace function public.admin_aer_qualification_lookup(p_args jsonb default '{}'::jsonb) returns jsonb
language plpgsql stable security definer set search_path = '' as $f$
declare v_rank int := coalesce(security.current_role_rank(), 0); v_in text := lower(btrim(coalesce(p_args->>'qualification', ''))); v_cc text := upper(nullif(btrim(p_args->>'country'), ''));
        v_code text; v_q ref.aer_qualifications%rowtype; v_lim int := least(greatest(coalesce((p_args->>'limit')::int, 200), 1), 1000);  -- fixed: list bounds of a screen read
begin
  if (auth.uid() is not null or coalesce(auth.role(), '') <> '') and (auth.uid() is null or v_rank < 4) then
    raise exception 'Pipeline Operator or above required' using errcode = '42501'; end if;
  if v_in = '' then
    return jsonb_build_object('qualifications', (select coalesce(jsonb_agg(to_jsonb(q) - 'created_at' order by q.scope, q.family, q.code), '[]'::jsonb) from ref.aer_qualifications q));
  end if;
  select * into v_q from ref.aer_qualifications q where lower(q.code) = v_in or lower(q.name) = v_in or v_in = any(q.aliases) order by (lower(q.code) = v_in) desc limit 1;
  if v_q.code is null then return jsonb_build_object('qualification', null, 'why', 'no qualification has this code, name or alias'); end if;
  return jsonb_build_object(
    'qualification', to_jsonb(v_q) - 'created_at',
    'education_country', v_cc,
    -- qualification-first requirements: global ones apply whatever the education country; a country-restricted one only for its countries; unresolved shown as such
    'requirements', (select coalesce(jsonb_agg(jsonb_build_object('provider_id', r.provider_id, 'provider', coalesce(p.display_name, p.canonical_name), 'status', r.status,
                       'applicability', r.applicability, 'applies_to_country', case when r.applicability = 'global' then true when r.applicability = 'countries' then v_cc = any(r.applicable_countries) end,
                       'level', r.level_label, 'min_grade', r.min_grade, 'min_value', r.min_value, 'scale', r.grade_scale, 'conditions', r.conditions, 'quote', r.quote, 'source_url', r.source_url)
                       order by coalesce(p.display_name, p.canonical_name), r.level_label), '[]'::jsonb)
                       from (select * from catalogue.provider_qualification_requirements r0 where r0.qualification_code = v_q.code and r0.status in ('active', 'proposed') limit v_lim) r
                       join catalogue.providers p on p.id = r.provider_id),
    -- the education country's matrix rows that name this qualification (a national route printed under the country)
    'country_matrix_rows', case when v_cc is null then '[]'::jsonb else (select coalesce(jsonb_agg(jsonb_build_object('provider_id', m.provider_id, 'provider', coalesce(p.display_name, p.canonical_name),
                       'status', m.status, 'level', m.level_label, 'qualification', m.qualification_name, 'min_grade', m.min_grade, 'min_value', m.min_value, 'scale', m.grade_scale, 'quote', m.quote)), '[]'::jsonb)
                       from (select * from catalogue.provider_entry_matrix m0 where m0.country_code = v_cc and m0.status in ('active', 'proposed')
                               and exists (select 1 from unnest(array_append(v_q.aliases, lower(v_q.name))) a where length(a) >= 3 and lower(m0.qualification_name) like '%' || a || '%') limit v_lim) m
                       join catalogue.providers p on p.id = m.provider_id) end);
end $f$;
revoke all on function public.admin_aer_qualification_lookup(jsonb) from public, anon;
grant execute on function public.admin_aer_qualification_lookup(jsonb) to authenticated;
comment on function public.admin_aer_qualification_lookup(jsonb) is 'CF-247 F-AER.03: Catalogue › Entry requirements, by qualification: with no qualification, the qualification list; with a code, name or alias (and an optional education country), each provider''s active and waiting qualification-first requirements (global ones apply whatever the country) and that country''s matrix rows naming the qualification. Rank 4 and above; read only; not part of the consumer API.';

-- 3-4. the guarded edits ------------------------------------------------------------------------------------------------------------------------
do $m$
declare r record; v_def text; v_src text; v_c int; k int; v_sig regprocedure;
begin
  for r in select * from (values
    ('public.svc_entry_matrix_record(uuid,jsonb,numeric,text)', '3e76d77b83bc8c1f9514b40f7cb4ac3e', '7eee2ef2229520266fd56c8aa8f1f1fb',
     array[$o$        v_all_conf boolean := true;$o$,
           $o$    v_in := v_in + 1;
  end loop;
  if v_in > 0 then$o$,
           $o$              jsonb_build_object('run_id', r.id, 'url', f.url, 'rows', v_in, 'dropped', jsonb_array_length(v_dropped),$o$,
           $o$'page_basis', p_result->'page_basis', 'completeness', p_result->'completeness'),$o$,
           $o$  if v_in = 0 and f.read_via = 'firecrawl'$o$,
           $o$  return jsonb_build_object('ok', true, 'status', case when v_in = 0 then 'no_rows' when v_item is not null then 'layer4' else 'admitted' end,
                            'rows', v_in, 'dropped', jsonb_array_length(v_dropped), 'review_item_id', v_item);$o$],
     array[$n$        v_all_conf boolean := true;
        v_qin int := 0; v_qx jsonb; v_qcode text;  -- 12 Nov 2026 (F-AER.03): qualification rows$n$,
           $n$    v_in := v_in + 1;
  end loop;
  -- 12 Nov 2026 (F-AER.03 qualification-first): rows the reader kept for a recognised international qualification that name no country of education are recorded
  -- beside the matrix with their identity and applicability, on the same Layer 4 item; an unrecognised qualification is dropped (unknown_qualification)
  if security.pipeline_num_v1('reading.entry_qualification_first_on', 0) >= 1 then
    for v_qx in select * from jsonb_array_elements(coalesce(p_result->'qualification_rows', '[]'::jsonb)) loop
      select q.code into v_qcode from ref.aer_qualifications q where q.code = v_qx->>'qualification_code' and q.scope = 'international';
      v_conf := nullif(v_qx->>'confidence', '')::numeric;
      if v_qcode is null then v_dropped := v_dropped || jsonb_build_array(jsonb_build_object('reason', 'unknown_qualification', 'country', v_qx->>'country_token', 'qualification', v_qx->>'qualification_name')); continue; end if;
      if coalesce(v_conf, 0) < v_min_conf then v_dropped := v_dropped || jsonb_build_array(jsonb_build_object('reason', 'low_confidence', 'qualification', v_qcode)); continue; end if;
      if nullif(trim(v_qx->>'quote'), '') is null then v_dropped := v_dropped || jsonb_build_array(jsonb_build_object('reason', 'missing_quote_or_qualification', 'qualification', v_qcode)); continue; end if;
      if (v_qx->>'min_value') is not null and coalesce(v_qx->>'grade_scale', 'none') = 'none' then
        v_dropped := v_dropped || jsonb_build_array(jsonb_build_object('reason', 'value_without_scale', 'qualification', v_qcode)); continue; end if;
      insert into catalogue.provider_qualification_requirements(provider_id, qualification_code, qualification_label, applicability, level_label, study_level_id, min_grade, min_value,
               grade_scale, conditions, quote, source_url, source_id, evidence_id, content_hash, run_id, confidence, status, provenance)
      values (r.provider_id, v_qcode, left(coalesce(nullif(trim(v_qx->>'qualification_name'), ''), v_qcode), 300),
              case when v_qx->>'applicability' = 'global' then 'global' else 'unresolved' end,
              nullif(trim(v_qx->>'study_level'), ''), security.entry_level_map_v1(v_qx->>'study_level'), nullif(trim(v_qx->>'min_grade'), ''), (v_qx->>'min_value')::numeric,
              coalesce(nullif(v_qx->>'grade_scale', ''), 'none'), coalesce(v_qx->'conditions', '{}'::jsonb), left(trim(v_qx->>'quote'), 300), f.url, f.id, f.evidence_id,
              r.content_hash, r.id, v_conf, 'proposed',
              jsonb_build_object('reader', 'entry_ai', 'model', r.model_code, 'run_id', r.id, 'worker', p_result->>'worker', 'prompt', p_result->>'prompt_version',
                                 'country_token', v_qx->>'country_token', 'applicability_basis', v_qx->>'applicability_basis'));
      v_qin := v_qin + 1;
    end loop;
  end if;
  if v_in + v_qin > 0 then$n$,
           $n$              jsonb_build_object('run_id', r.id, 'url', f.url, 'rows', v_in, 'dropped', jsonb_array_length(v_dropped),
                'qualification_rows', v_qin,
                'qualification_sample', (select jsonb_agg(jsonb_build_object('id', q.id, 'qualification', q.qualification_code, 'label', q.qualification_label, 'applicability', q.applicability,
                                   'level', q.level_label, 'min_grade', q.min_grade, 'min_value', q.min_value, 'scale', q.grade_scale, 'quote', q.quote) order by q.qualification_code, q.level_label)
                             from (select * from catalogue.provider_qualification_requirements q2 where q2.run_id = r.id order by q2.qualification_code, q2.level_label limit 12) q),$n$,
           $n$'page_basis', p_result->'page_basis', 'completeness', p_result->'completeness', 'qualification_rows', v_qin),$n$,
           $n$  if v_in + v_qin = 0 and f.read_via = 'firecrawl'$n$,
           $n$  return jsonb_build_object('ok', true, 'status', case when v_in + v_qin = 0 then 'no_rows' when v_item is not null then 'layer4' else 'admitted' end,
                            'rows', v_in, 'qualification_rows', v_qin, 'dropped', jsonb_array_length(v_dropped), 'review_item_id', v_item);$n$]),
    ('security.entry_matrix_review_apply_v1(uuid,text,jsonb,text,uuid)', '6d7b47fe7d2cd40b9cfb8f3547bad158', 'c46ef6d3f9820c3d4d822846909e35ce',
     array[$o$declare r pipeline.entry_matrix_runs%rowtype; v_ex uuid[]; v_on int := 0; v_off int := 0; v_sup int := 0; v_map jsonb; v_ret int := 0; v_gate jsonb;$o$,
           $o$    update catalogue.provider_entry_matrix m set status = 'active', status_reason = null, updated_at = now()
     where m.run_id = r.id and m.status = 'proposed';
    get diagnostics v_on = row_count;$o$,
           $o$    update catalogue.provider_entry_matrix m set status = 'inactive', status_reason = 'quarantined (' || p_action || '): ' || coalesce(p_reason, ''), updated_at = now()
     where m.run_id = r.id and m.status = 'proposed';
    get diagnostics v_off = row_count;$o$,
           $o$  return jsonb_build_object('entry_matrix_run', r.id, 'admitted', v_on, 'quarantined', v_off, 'superseded', v_sup)$o$],
     array[$n$declare r pipeline.entry_matrix_runs%rowtype; v_ex uuid[]; v_on int := 0; v_off int := 0; v_sup int := 0; v_map jsonb; v_ret int := 0; v_gate jsonb;
        v_qon int := 0; v_qoff int := 0; v_qsup int := 0;  -- 12 Nov 2026 (F-AER.03): qualification rows of the read$n$,
           $n$    update catalogue.provider_entry_matrix m set status = 'active', status_reason = null, updated_at = now()
     where m.run_id = r.id and m.status = 'proposed';
    get diagnostics v_on = row_count;
    -- 12 Nov 2026 (F-AER.03): the read's qualification rows follow the same decision: a row left out stays out; an earlier active row of this source for the same
    -- qualification is replaced by the approved one; the rest become active
    update catalogue.provider_qualification_requirements q set status = 'inactive',
           status_reason = 'excluded by approve except (Layer 4 item ' || coalesce(p_item, r.review_item_id)::text || '): ' || coalesce(p_reason, ''), updated_at = now()
     where q.run_id = r.id and q.status = 'proposed' and q.id = any(v_ex);
    update catalogue.provider_qualification_requirements a set status = 'superseded', status_reason = 'replaced by run ' || r.id, updated_at = now()
     where a.provider_id = r.provider_id and a.source_id = r.source_id and a.status = 'active' and a.run_id is distinct from r.id
       and exists (select 1 from catalogue.provider_qualification_requirements p where p.run_id = r.id and p.status = 'proposed' and p.qualification_code = a.qualification_code);
    get diagnostics v_qsup = row_count;
    update catalogue.provider_qualification_requirements q set status = 'active', status_reason = null, updated_at = now() where q.run_id = r.id and q.status = 'proposed';
    get diagnostics v_qon = row_count;$n$,
           $n$    update catalogue.provider_entry_matrix m set status = 'inactive', status_reason = 'quarantined (' || p_action || '): ' || coalesce(p_reason, ''), updated_at = now()
     where m.run_id = r.id and m.status = 'proposed';
    get diagnostics v_off = row_count;
    update catalogue.provider_qualification_requirements q set status = 'inactive', status_reason = 'quarantined (' || p_action || '): ' || coalesce(p_reason, ''), updated_at = now()
     where q.run_id = r.id and q.status = 'proposed';
    get diagnostics v_qoff = row_count;$n$,
           $n$  return jsonb_build_object('entry_matrix_run', r.id, 'admitted', v_on, 'quarantined', v_off, 'superseded', v_sup)
         || jsonb_build_object('qualification_admitted', v_qon, 'qualification_quarantined', v_qoff, 'qualification_superseded', v_qsup)$n$])
  ) v(sig, md5_before, md5_after, olds, news) loop
    v_sig := to_regprocedure(r.sig);
    v_src := (select p.prosrc from pg_proc p where p.oid = v_sig);
    -- fixed: the guard is the md5 of the live function body (pg_proc.prosrc), the same text on PostgreSQL 16 and 17
    if md5(v_src) = r.md5_after then raise notice '%: already applied', r.sig; continue; end if;
    if md5(v_src) <> r.md5_before then raise exception 'live % differs from the definition this change edits (body md5 %)', r.sig, md5(v_src); end if;
    v_def := replace(pg_get_functiondef(v_sig), chr(13), '');
    for k in 1 .. array_length(r.olds, 1) loop
      v_c := (length(v_def) - length(replace(v_def, r.olds[k], ''))) / length(r.olds[k]);
      if v_c <> 1 then raise exception '%: edit % must apply exactly once (found %)', r.sig, k, v_c; end if;
      v_def := replace(v_def, r.olds[k], r.news[k]);
    end loop;
    execute v_def;
    v_src := (select p.prosrc from pg_proc p where p.oid = v_sig);
    if md5(v_src) <> r.md5_after then raise exception '% after the edit has body md5 %, expected %', r.sig, md5(v_src), r.md5_after; end if;
    raise notice '%: applied', r.sig;
  end loop;
end $m$;

insert into pipeline.component_register(kind, name, layer, purpose, status, replaces, introduced_in) values
 ('table', 'ref.aer_qualifications', 'Reference', 'Canonical identity of the qualifications AER requirements refer to (international and national)', 'active', '{}', '20261112060000'),
 ('table', 'catalogue.provider_qualification_requirements', 'Layer 4', 'A provider''s published requirement for a qualification, apart from the applicant''s country (qualification-first)', 'active', '{}', '20261112060000'),
 ('function', 'public.svc_aer_qualifications_v1', 'Layer 2', 'International qualifications, aliases and every-country tokens for the entry matrix reader', 'active', '{}', '20261112060000'),
 ('function', 'public.admin_aer_qualification_lookup', 'Platform', 'Entry requirements by qualification and education country (read only)', 'active', '{}', '20261112060000')
on conflict do nothing;

do $post$ begin
  if position('provider_qualification_requirements' in (select p.prosrc from pg_proc p where p.oid = 'public.svc_entry_matrix_record(uuid,jsonb,numeric,text)'::regprocedure)) = 0 then raise exception 'post-check: qualification rows are not recorded'; end if;
  if position('provider_qualification_requirements' in (select p.prosrc from pg_proc p where p.oid = 'security.entry_matrix_review_apply_v1(uuid,text,jsonb,text,uuid)'::regprocedure)) = 0 then raise exception 'post-check: the decision does not reach qualification rows'; end if;
  if position('entry_matrix_gate_v1' in (select p.prosrc from pg_proc p where p.oid = 'security.entry_matrix_review_apply_v1(uuid,text,jsonb,text,uuid)'::regprocedure)) = 0 then raise exception 'post-check: the D-R3 gate was lost'; end if;
  if (select count(*) from ref.aer_qualifications where scope = 'international') < 10 then raise exception 'post-check: international qualifications not seeded'; end if;
end $post$;
