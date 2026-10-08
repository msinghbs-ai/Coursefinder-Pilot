-- CF-247 Scholarships: New Zealand register (Platform Admin decision 9 Oct 2026: "Take recommended
-- decisions" - New Zealand next, as a record). Manaaki New Zealand Scholarships (MFAT, run by Education
-- New Zealand) become a Layer 1 source read by scholarships-au-etl feed nz_manaaki. Study with New Zealand
-- is not used: its scholarship pages sit behind a browser check and its sitemap lists no scholarship pages.
-- Nothing runs automatically: the schedule is set by a Platform Admin after the first verified run.

update scholarship.registers
   set status = 'live', reader = 'scholarships-au-etl nz_manaaki', url = 'https://www.nzscholarships.govt.nz/international-tertiary-students/',
       notes = 'Government award read from the Manaaki pages (eligible countries by region, levels, approved institutions, rounds) into a scholarship record. Study with New Zealand pages are behind a browser check and are not read.',
       updated_at = now()
 where code = 'nz_mfat_manaaki';

update pipeline.sources
   set metadata = metadata || jsonb_build_object('source_system','SCHOLARSHIP_REGISTER','register_code','nz_mfat_manaaki','layer1_register',true,
                                                 'scholarship_role','ingest'),
       url = 'https://www.nzscholarships.govt.nz/international-tertiary-students/',
       updated_at = now()
 where id = '717432c7-32f9-47c3-9111-7f75fd79c128';

insert into pipeline.layer1_source_operations(source_id, authority_name, authority_domains, expected_format, expected_count_kind,
       active, paused, verification_cadence_days, ingestion_cadence_days, auto_ingest, change_reason)
values ('717432c7-32f9-47c3-9111-7f75fd79c128','Ministry of Foreign Affairs and Trade (New Zealand) / Education New Zealand',array['nzscholarships.govt.nz'],
        'Manaaki New Zealand Scholarships pages: tertiary, eligible countries, eligibility criteria, approved institutions, how to apply, types',
        'government awards',true,false,30,30,false,'CF-247 scholarships central register: New Zealand (Platform Admin decision 9 Oct 2026)')
on conflict (source_id) do nothing;
