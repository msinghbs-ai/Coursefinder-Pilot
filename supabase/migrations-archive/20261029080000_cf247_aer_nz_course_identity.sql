-- CF-247 AER NZ course-level identity (Platform Admin mandate 29 Oct 2026 12:23, B4: "Enable NZ course-level reading using existing trusted
-- NZ identity proofs, including NZQA code on the provider's official course page and other already-approved equivalent proofs. Require:
-- stored official NZ course page; provider/course identity match; no title-only inference; quote-on-page and score/basis validation; no
-- English-test duplication; no inferred international applicability; existing Layer 4 admission. Add contract and live dry-run coverage
-- before activation. Do not weaken AU identity rules or create a separate NZ reader lane.")
--
-- NZ course pages are read for academic entry requirements on the existing Enrich fields lane, under the same B1 rules as Australia
-- (security.enrich_entry_record_v1: quote on the page, a score only with its printed basis, a band only when printed, no English-test rows,
-- audience only from the quote's own words, rows proposed and admitted by a person in Layer 4 course_entry_first_read).
-- 1. Field source rule NZ entry_requirements = {ai_stored}: the stored official course page only (security.field_sources_for_v1 gives an
--    NZ item no source without it).
-- 2. NZ coverage_admission_countries.identities.entry_requirements = the strong NZ proofs that are already approved for other NZ fields:
--      nzqa_code    - the NZQA code printed on the provider's official course page; approved for NZ english, intakes, tuition, official_url
--      adapter_code - the provider adapter's own course code; approved for NZ english, intakes, official_url (and for AU entry_requirements);
--                     security.coverage_identity_allowed still needs an enabled, admitting adapter for the provider
--      manual       - a person bound the page; approved for every NZ field (and for AU entry_requirements)
--    Not admitted (title-only or weak): adapter_title (identity.adapter_title_countries makes it count as a title in NZ), exact_title,
--    title_level, degree_name, title_match, host_page. cricos_code stays refused outside Australia (security.coverage_identity_allowed).
-- 3. entry.course_read_providers: the plan's NZ providers are appended AFTER the Australian ones (unchanged, still first): the NZ providers
--    of entry.providers in that order, then EIT, NorthTec, UCOL, Toi Ohomai and the University of Canterbury.
-- 4. entry.course_read_countries ["AU"] -> ["AU", "NZ"] (activation), count-guarded: the NZ eligible count from
--    security.course_entry_eligible_v1() must lie in the range measured on 29 Oct 2026 (421 courses; 380-470 allowed), no NZ eligible
--    course may rest on a title-only proof, and the Australian eligible count must be the same before and after.
-- 5. security.enrich_entry_record_v1 (md5-guarded, NZ-only generalisation): an NZ quote naming NCEA or University Entrance (UE) is a
--    domestic school-leaver route, as VCE/ATAR/VTAC/STAT are in Australia, so it is stored as audience 'domestic', not 'all' (no inferred
--    international applicability). Australian rows are decided exactly as before.
-- Replaces: security.enrich_entry_record_v1 (same name, md5-guarded edit); the entry.course_read_providers and entry.course_read_countries values
-- Retires: nothing
-- Nothing dropped, deleted or renamed. The consumer API is not touched (Decision 266). No new job, table, status, Layer 4 field or reader
-- lane; the AU identity rules and the AU field source rule are unchanged (guarded below).

create or replace function pg_temp.edit_n(p_sig text, p_md5 text, p_edits text[][], p_times int[]) returns void language plpgsql as $f$
declare v_def text := pg_get_functiondef(p_sig::regprocedure); i int; v_c int;
begin
  if md5(v_def) <> p_md5 then raise exception 'live % differs from the definition this change edits (md5 %)', p_sig, md5(v_def); end if;
  for i in 1 .. array_length(p_edits, 1) loop
    v_c := (length(v_def) - length(replace(v_def, p_edits[i][1], ''))) / length(p_edits[i][1]);
    if v_c <> p_times[i] then raise exception '%: edit % must apply exactly % times (found %)', p_sig, i, p_times[i], v_c; end if;
    v_def := replace(v_def, p_edits[i][1], p_edits[i][2]);
  end loop;
  execute v_def;
end $f$;

-- ---------------------------------------------------------------- preconditions and the Australian baseline
do $$
declare v_nz jsonb; v_au jsonb; v_prov jsonb; v_au_n int;
begin
  select a.identities into v_nz from pipeline.coverage_admission_countries a join ref.countries k on k.id = a.country_id where k.iso_alpha2 = 'NZ' and a.active;
  select a.identities into v_au from pipeline.coverage_admission_countries a join ref.countries k on k.id = a.country_id where k.iso_alpha2 = 'AU' and a.active;
  if v_nz is null then raise exception 'NZ admission row is missing or inactive'; end if;
  if v_nz ? 'entry_requirements' then raise exception 'NZ entry_requirements identities are already set: %', v_nz->'entry_requirements'; end if;
  -- each proof admitted below is already approved for NZ english and intakes (the existing approval this change relies on)
  if not (v_nz->'english' ?& array['nzqa_code', 'adapter_code', 'manual'] and v_nz->'intakes' ?& array['nzqa_code', 'adapter_code', 'manual']) then
    raise exception 'an NZ proof is not already approved for english and intakes: %', v_nz;
  end if;
  if v_au->'entry_requirements' is distinct from '["cricos_code", "adapter_code", "manual"]'::jsonb then raise exception 'AU entry_requirements identities differ: %', v_au->'entry_requirements'; end if;
  if security.toolset_setting('pipeline', 'entry.course_read_countries') is distinct from '["AU"]'::jsonb then
    raise exception 'entry.course_read_countries is not ["AU"]: %', security.toolset_setting('pipeline', 'entry.course_read_countries');
  end if;
  v_prov := security.toolset_setting('pipeline', 'entry.course_read_providers');
  if jsonb_array_length(v_prov) <> 21 or v_prov->>0 <> '543b87b8-f0dd-4bc7-80d6-76252cfaabec' or v_prov->>20 <> '36086f5e-9fe0-4878-aa40-1897a7d8cb24' then
    raise exception 'entry.course_read_providers is not the 21 Australian providers of 20261029030000: %', v_prov;
  end if;
  select count(*) into v_au_n from security.course_entry_eligible_v1() e where security.coverage_country(e.provider_id) = 'AU';
  perform set_config('cf247.nz_entry_au_before', v_au_n::text, true);
  perform set_config('cf247.nz_entry_au_identities', v_au::text, true);
  perform set_config('cf247.nz_entry_au_providers', v_prov::text, true);
end $$;

-- ---------------------------------------------------------------- 1. NZ field source rule (stored page only)
insert into pipeline.field_source_rules(country_code, field, sources, reason, updated_at)
values ('NZ', 'entry_requirements', array['ai_stored'], 'CF-247 AER NZ course-level identity (Platform Admin mandate 29 Oct 2026 12:23 B4): academic entry requirements from the stored official course page only', now())
on conflict do nothing;

-- ---------------------------------------------------------------- 2. NZ strong proofs only (already approved for other NZ fields)
update pipeline.coverage_admission_countries a
   set identities = a.identities || jsonb_build_object('entry_requirements', jsonb_build_array('nzqa_code', 'adapter_code', 'manual'))
  from ref.countries k
 where k.id = a.country_id and k.iso_alpha2 = 'NZ' and not (a.identities ? 'entry_requirements');

-- ---------------------------------------------------------------- 3. the plan's NZ providers, after the Australian ones
update pipeline.platform_toolset_settings
   set value = value || '["00e5f26c-446e-453c-a3fb-bc5239a4feec", "229dc07d-c573-44a3-b5dc-cc423cc2c300", "248374d1-0629-41cd-a6f4-0804c422a4ff",
                          "39301fa8-bff2-4389-bbcd-32d8415fae04", "66f6fcc9-15f8-46e6-b3b3-0576ab4bcce3", "742eef0a-1341-46ef-a4ab-4d105c47be9b",
                          "87576ec2-c4b0-4a00-ab94-64422c77d545", "ab12c7f8-e368-453d-9dfe-4ab8bd744829", "becd7287-5ede-4a62-800e-b2cd15d62c33",
                          "cd27693c-6c80-42f4-8b76-1ed2d94e0b45", "dbf22c45-062e-4c5d-92a9-aaabd8c452f7", "e096aba7-e1eb-4903-9a63-2bfb71e9a8b8",
                          "e2dd4b2b-1379-46c5-abe1-e8f24e685913", "34616965-b2b7-42a7-8da7-50ffbf120958", "40f9891f-c8da-45cc-aced-154e63d41cff",
                          "ea5a3fa6-31f4-4553-9cfd-6bff49c36a6b", "d72e0120-a3a2-4909-8ddf-bcad1ec60150", "adeb0bbb-5b07-4130-aaeb-ad404bf40ff7",
                          "38f8ea71-2269-407c-aab6-68a5f09fc01a", "db910e88-67d1-4d2b-a65c-cea290aa0692"]'::jsonb,
       updated_at = now(),
       reason = 'CF-247 AER NZ course-level identity (Platform Admin mandate 29 Oct 2026 12:23 B4): the plan''s NZ providers (entry.providers NZ, then EIT, NorthTec, UCOL, Toi Ohomai, University of Canterbury) after the Australian ones'
 where toolset_key = 'pipeline' and key = 'entry.course_read_providers'
   and not (value ? '00e5f26c-446e-453c-a3fb-bc5239a4feec');

-- ---------------------------------------------------------------- 5. NZ school-leaver routes are domestic (md5-guarded; AU unchanged)
select pg_temp.edit_n('security.enrich_entry_record_v1(bigint,jsonb)', 'b338ca230101470b3d17bae094167185', array[
  array[$o$select pg.provider_id, pg.identity_basis, pg.url, pg.evidence_id, e.captured_at into g$o$,
        $n$select pg.provider_id, pg.identity_basis, pg.url, pg.evidence_id, e.captured_at, security.coverage_country(pg.provider_id) cc into g$n$],
  array[$o$when v_q ~* '(\mVCE\M|\mATAR\M|\mVTAC\M|\mSTAT\M|Australian Year 12)' then 'domestic' else 'all' end;$o$,
        $n$when v_q ~* '(\mVCE\M|\mATAR\M|\mVTAC\M|\mSTAT\M|Australian Year 12)' then 'domestic'
                  -- CF-247 AER NZ (Platform Admin mandate 29 Oct 2026 12:23 B4): NZ school-leaver routes, never inferred to apply internationally
                  when g.cc = 'NZ' and v_q ~* '(\mNCEA\M|University Entrance|\mUE\M)' then 'domestic' else 'all' end;$n$]], array[1, 1]);

-- ---------------------------------------------------------------- 4. activation, count-guarded
update pipeline.platform_toolset_settings set value = '["AU", "NZ"]'::jsonb, updated_at = now(),
       reason = 'CF-247 AER NZ course-level identity (Platform Admin mandate 29 Oct 2026 12:23 B4): NZ course pages read with an already-approved strong NZ proof; dry run count-guarded'
 where toolset_key = 'pipeline' and key = 'entry.course_read_countries' and value = '["AU"]'::jsonb;

do $$
declare v_nz int; v_weak int; v_au int; v_rule text[]; v_prov jsonb;
begin
  -- the NZ rule is the stored page only
  select r.sources into v_rule from pipeline.field_source_rules r where r.country_code = 'NZ' and r.field = 'entry_requirements';
  if v_rule is distinct from array['ai_stored'] then raise exception 'NZ entry_requirements source rule is %', v_rule; end if;
  if (select r.sources from pipeline.field_source_rules r where r.country_code = 'AU' and r.field = 'entry_requirements') is distinct from array['ai_stored'] then
    raise exception 'AU entry_requirements source rule changed';
  end if;
  -- the NZ identities are the three strong proofs, no title-only basis; the AU row is unchanged
  if (select a.identities->'entry_requirements' from pipeline.coverage_admission_countries a join ref.countries k on k.id = a.country_id where k.iso_alpha2 = 'NZ')
     is distinct from '["nzqa_code", "adapter_code", "manual"]'::jsonb then raise exception 'NZ entry_requirements identities are not the three strong proofs'; end if;
  if (select a.identities from pipeline.coverage_admission_countries a join ref.countries k on k.id = a.country_id where k.iso_alpha2 = 'AU')::text
     is distinct from current_setting('cf247.nz_entry_au_identities', true) then raise exception 'AU identities changed'; end if;
  -- the Australian providers stay first and in the same order
  v_prov := security.toolset_setting('pipeline', 'entry.course_read_providers');
  if jsonb_array_length(v_prov) <> 41 or (select jsonb_agg(x order by o) from jsonb_array_elements(v_prov) with ordinality t(x, o) where o <= 21)::text
     is distinct from current_setting('cf247.nz_entry_au_providers', true) then raise exception 'entry.course_read_providers: AU order changed or NZ list incomplete: %', v_prov; end if;
  -- title-only and CRICOS proofs stay refused for NZ entry requirements; the strong proofs are admitted
  if security.coverage_identity_allowed('ab12c7f8-e368-453d-9dfe-4ab8bd744829', 'adapter_title', 'entry_requirements')
     or security.coverage_identity_allowed('ab12c7f8-e368-453d-9dfe-4ab8bd744829', 'exact_title', 'entry_requirements')
     or security.coverage_identity_allowed('ab12c7f8-e368-453d-9dfe-4ab8bd744829', 'title_level', 'entry_requirements')
     or security.coverage_identity_allowed('ab12c7f8-e368-453d-9dfe-4ab8bd744829', 'degree_name', 'entry_requirements')
     or security.coverage_identity_allowed('ab12c7f8-e368-453d-9dfe-4ab8bd744829', 'title_match', 'entry_requirements')
     or security.coverage_identity_allowed('ab12c7f8-e368-453d-9dfe-4ab8bd744829', 'host_page', 'entry_requirements')
     or security.coverage_identity_allowed('39301fa8-bff2-4389-bbcd-32d8415fae04', 'cricos_code', 'entry_requirements') then
    raise exception 'a title-only or CRICOS proof admits NZ entry requirements';
  end if;
  if not (security.coverage_identity_allowed('39301fa8-bff2-4389-bbcd-32d8415fae04', 'nzqa_code', 'entry_requirements')
          and security.coverage_identity_allowed('34616965-b2b7-42a7-8da7-50ffbf120958', 'manual', 'entry_requirements')) then
    raise exception 'the strong NZ proofs do not admit NZ entry requirements';
  end if;
  -- count guard: the NZ eligible courses measured on 29 Oct 2026 (421), none on a title-only proof; Australia unchanged
  select count(*), count(*) filter (where g.identity_basis is null or g.identity_basis not in ('nzqa_code', 'adapter_code', 'manual'))
    into v_nz, v_weak
    from security.course_entry_eligible_v1() e join pipeline.coverage_course_pages g on g.course_id = e.course_id and g.status = 'bound'
   where security.coverage_country(e.provider_id) = 'NZ';
  if v_weak <> 0 then raise exception 'NZ eligible courses on a title-only or unknown proof: %', v_weak; end if;
  if v_nz not between 380 and 470 then raise exception 'NZ eligible course count % is outside the measured range 380-470 (421 on 29 Oct 2026)', v_nz; end if;
  select count(*) into v_au from security.course_entry_eligible_v1() e where security.coverage_country(e.provider_id) = 'AU';
  if v_au::text is distinct from current_setting('cf247.nz_entry_au_before', true) then
    raise exception 'AU eligible course count changed: % before, % after', current_setting('cf247.nz_entry_au_before', true), v_au;
  end if;
  raise notice 'CF-247 AER NZ course identity: NZ eligible %, AU eligible % (unchanged)', v_nz, v_au;
end $$;

comment on function security.enrich_entry_record_v1(bigint, jsonb) is 'CF-247 Track C Step B (B1): admits a course page''s entry-requirement rows as proposed under the B1 rules (quote, basis, band printed, no English duplicate, audience from the quote; NZ NCEA/University Entrance routes are domestic, 29 Oct 2026 B4) and opens Layer 4 course_entry_first_read.';
