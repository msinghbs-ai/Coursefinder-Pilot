-- CF-247 Layer 1: Canadian catalogue and register sources on Layer 1 (phase A).
-- Platform Admin decision 9 Oct 2026 (multiple choice): "Canada Layer 1 schedule". None of the Canadian catalogue
-- and register sources had a Layer 1 operations row; their evidence was last captured 13 to 18 August 2026.
--
-- Phase A: 26 sources whose reader reads the whole catalogue in one call (23 college and provincial catalogues,
-- Aurora and Yukon through the shared first-party reader) and the IRCC Designated Learning Institutions register
-- (read whole, applied in slices). Each source names its reader in metadata.layer1_reader; source_system CA_READER
-- routes it in layer1-operations-control v1.8.0 and layer1-operations-scheduled v1.4.0.
-- Phase B (not here): ALIS, EducationPlannerBC, NSCC, Saskatchewan Polytechnic and Quebec MES, whose readers page.
-- Course-page sweep sources (western providers) are Layer 2 and unchanged. Outcome datasets are unchanged.
--
-- Nothing runs automatically yet: verification is due now; the schedule (monthly) is set by a Platform Admin after
-- each source's first verified run. Nothing is deleted.

-- readers that accept a one-time run token but were not on the allow-list
insert into pipeline.pilot_nonce_functions(function_name, note)
select f, 'CF-247 Canada Layer 1 reader (phase A)'
  from unnest(array['layer1-ca-boreal-programs','layer1-ca-cambrian-programs','layer1-ca-centennial-programs',
                    'layer1-ca-confederation-programs','layer1-ca-fanshawe-programs','layer1-ca-fleming-programs',
                    'layer1-ca-georgian-catalogue','layer1-ca-lambton-programs','layer1-ca-loyalist-programs',
                    'layer1-ca-northern-programs','layer1-ca-sault-programs','layer1-ca-seneca-catalogue',
                    'layer1-ca-sheridan-programs','layer1-ca-stclair-programs','layer1-ca-stlawrence-programs']) f
 where not exists (select 1 from pipeline.pilot_nonce_functions x where x.function_name = f);

create temp table _ca_readers(system_code text primary key, reader jsonb) on commit drop;
insert into _ca_readers values
 ('ca_ircc_dli',                     '{"function":"layer1-ca-live","auth":"service_key","paging":"offset","batch":200}'),
 ('ca_algonquin_catalogue',          '{"function":"layer1-ca-algonquin-catalogue"}'),
 ('ca_on_boreal_programs',           '{"function":"layer1-ca-boreal-programs"}'),
 ('ca_on_cambrian_programs',         '{"function":"layer1-ca-cambrian-programs"}'),
 ('ca_on_centennial_programs',       '{"function":"layer1-ca-centennial-programs"}'),
 ('ca_nl_cna_programs',              '{"function":"layer1-ca-cna-programs"}'),
 ('ca_on_conestoga_catalogue',       '{"function":"layer1-ca-conestoga-catalogue"}'),
 ('ca_on_confederation_programs',    '{"function":"layer1-ca-confederation-programs"}'),
 ('ca_on_durham_program_api',        '{"function":"layer1-ca-durham-programs"}'),
 ('ca_on_fanshawe_programs',         '{"function":"layer1-ca-fanshawe-programs"}'),
 ('ca_on_fleming_programs',          '{"function":"layer1-ca-fleming-programs"}'),
 ('ca_on_georgian_catalogue',        '{"function":"layer1-ca-georgian-catalogue"}'),
 ('ca_on_lambton_programs',          '{"function":"layer1-ca-lambton-programs"}'),
 ('ca_on_loyalist_programs',         '{"function":"layer1-ca-loyalist-programs"}'),
 ('ca_mb_student_aid_programs',      '{"function":"layer1-ca-mb-programs"}'),
 ('ca_on_mohawk_catalogue',          '{"function":"layer1-ca-mohawk-catalogue"}'),
 ('ca_on_niagara_availability',      '{"function":"layer1-ca-niagara-catalogue"}'),
 ('ca_on_northern_programs',         '{"function":"layer1-ca-northern-programs"}'),
 ('ca_on_public_college_programs',   '{"function":"layer1-ca-on-college-programs"}'),
 ('ca_on_sault_programs',            '{"function":"layer1-ca-sault-programs"}'),
 ('ca_on_seneca_catalogue',          '{"function":"layer1-ca-seneca-catalogue"}'),
 ('ca_on_sheridan_sitecore_programs','{"function":"layer1-ca-sheridan-programs"}'),
 ('ca_on_stclair_programs',          '{"function":"layer1-ca-stclair-programs"}'),
 ('ca_on_stlawrence_programs',       '{"function":"layer1-ca-stlawrence-programs"}'),
 ('ca_nt_aurora_programs',           '{"function":"layer1-ca-firstparty-catalogues","payload":{"source":"aurora"}}'),
 ('ca_yt_yukon_programs',            '{"function":"layer1-ca-firstparty-catalogues","payload":{"source":"yukon"}}');

do $check$
declare n int;
begin
  select count(*) into n from _ca_readers r join integration.systems sy on sy.code = r.system_code
    join pipeline.sources s on s.system_id = sy.id join ref.countries k on k.id = s.country_id and k.iso_alpha2 = 'CA';
  if n <> 26 then raise exception 'expected 26 Canadian sources for the reader map, found %', n; end if;
end $check$;

update pipeline.sources s
   set metadata = s.metadata || jsonb_build_object('source_system','CA_READER','layer1_reader', r.reader, 'layer1_phase','A'),
       updated_at = now()
  from _ca_readers r join integration.systems sy on sy.code = r.system_code
 where s.system_id = sy.id and s.country_id = (select id from ref.countries where iso_alpha2 = 'CA');

insert into pipeline.layer1_source_operations(source_id, authority_name, authority_domains, expected_format, expected_count_kind,
       active, paused, verification_cadence_days, ingestion_cadence_days, auto_ingest, next_verification_at, change_reason)
select s.id, s.label, array[security.url_base_host(s.url)],
       'Canadian Layer 1 reader ' || (r.reader->>'function') || coalesce(' (' || (r.reader->'payload'->>'source') || ')', ''),
       case when r.system_code = 'ca_ircc_dli' then 'designated learning institutions' else 'programmes' end,
       true, false, 30, 30, false, now(),
       'CF-247 Canada Layer 1 schedule (Platform Admin decision 9 Oct 2026); first verification due now'
  from _ca_readers r join integration.systems sy on sy.code = r.system_code
  join pipeline.sources s on s.system_id = sy.id and s.country_id = (select id from ref.countries where iso_alpha2 = 'CA')
on conflict (source_id) do nothing;
