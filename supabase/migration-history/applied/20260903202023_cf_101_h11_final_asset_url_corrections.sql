begin;

-- CF-CHG-20260903-101 — correct final H11 fallback asset URLs after source verification.
update pipeline.provider_asset_candidates
set asset_url=case id
  when '3c22b6bb-7b94-48cb-a5c6-052fb84a49d4'::uuid then 'https://commons.wikimedia.org/wiki/Special:FilePath/Logo_AustralianCatholicUniversity.svg'
  when '57c11d4b-4c07-426a-a5a7-d4e30204138d'::uuid then 'https://commons.wikimedia.org/wiki/Special:FilePath/Griffith_University_Logo_Variant_2023.svg'
  when '4201ca4f-b542-4523-bc1f-2568144a7250'::uuid then 'https://commons.wikimedia.org/wiki/Special:FilePath/UniversityofTasmaniaLogo.svg'
  when '468fc57b-e025-46db-8cd7-1149d91310d4'::uuid then 'https://www.otago.ac.nz/__data/assets/image/0026/568430/University-of-Otago-horizontal-wordmark-image-1880.jpg'
  when '4ddd040b-4a42-488a-8bc4-173d9b62af97'::uuid then 'https://commons.wikimedia.org/wiki/Special:FilePath/The_University_of_Notre_Dame_Australia_Logo.svg'
  when 'c8a4449a-e6a1-4df9-9050-8c1e95ed2a69'::uuid then 'https://commons.wikimedia.org/wiki/Special:FilePath/University_of_New_England_-_Logo.svg'
  else asset_url end,
    metadata=coalesce(metadata,'{}'::jsonb)||jsonb_build_object(
      'asset_url_verified_at',now(),
      'asset_url_fix','cf101_final_h11_source_correction',
      'change_control_ref','CF-CHG-20260903-101'
    ),
    discovered_at=now()
where id in (
 '3c22b6bb-7b94-48cb-a5c6-052fb84a49d4'::uuid,
 '57c11d4b-4c07-426a-a5a7-d4e30204138d'::uuid,
 '4201ca4f-b542-4523-bc1f-2568144a7250'::uuid,
 '468fc57b-e025-46db-8cd7-1149d91310d4'::uuid,
 '4ddd040b-4a42-488a-8bc4-173d9b62af97'::uuid,
 'c8a4449a-e6a1-4df9-9050-8c1e95ed2a69'::uuid
);

commit;
