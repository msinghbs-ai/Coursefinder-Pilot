begin;
update pipeline.provider_asset_candidates
set status='rejected',
    metadata=metadata||jsonb_build_object('review_reason','CF-082 bounded UAT: image mentions Provider but is not a logo','reviewed_at',now())
where (provider_id='f02d9d9b-0eb2-4f0e-8215-27a36ae63aa6'::uuid and asset_url like '%campus%')
   or (provider_id='6f5cb7f7-7c70-4c06-970f-f368c3a786e2'::uuid and asset_url like '%CR%20Boosted%');
commit;