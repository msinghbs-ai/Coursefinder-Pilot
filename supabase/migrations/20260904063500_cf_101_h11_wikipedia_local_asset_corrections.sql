begin;
update pipeline.provider_asset_candidates
set asset_url=case id
  when '57c11d4b-4c07-426a-a5a7-d4e30204138d'::uuid then 'https://en.wikipedia.org/wiki/Special:FilePath/Griffith_University_Logo_Variant_2023.svg'
  when '4201ca4f-b542-4523-bc1f-2568144a7250'::uuid then 'https://en.wikipedia.org/wiki/Special:FilePath/UniversityofTasmaniaLogo.svg'
  when '4ddd040b-4a42-488a-8bc4-173d9b62af97'::uuid then 'https://en.wikipedia.org/wiki/Special:FilePath/The_University_of_Notre_Dame_Australia_Logo.svg'
  else asset_url end,
  metadata=coalesce(metadata,'{}'::jsonb)||jsonb_build_object(
    'asset_host_class','wikipedia_local_file',
    'asset_url_verified_at',now(),
    'change_control_ref','CF-CHG-20260903-101'
  ),
  discovered_at=now()
where id in (
 '57c11d4b-4c07-426a-a5a7-d4e30204138d'::uuid,
 '4201ca4f-b542-4523-bc1f-2568144a7250'::uuid,
 '4ddd040b-4a42-488a-8bc4-173d9b62af97'::uuid
);
commit;