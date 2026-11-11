-- Forward recovery for 20261112010000_cf247_pdesc_prompt_based.sql (apply as a NEW migration only if prompt-based descriptions must be undone).
-- Step 1 is enough to return the reader to its earlier behaviour: with pdesc.prompt_on 0 the lease hands over no prompt (the worker uses its
-- built-in prompt v2), the validator applies every wording rule as before, and the prompt version stamp is not set. The on-demand exemptions
-- act only on reads marked by Fill description, so they are inert while nobody clicks it; to remove the button as well, revert the screens.
-- Nothing is dropped or deleted: the prompt table, its versions and the new settings stay (component_register keeps them listed).
update pipeline.platform_toolset_settings set value = '0'::jsonb, updated_at = now(), reason = 'forward recovery of 20261112010000: back to the built-in prompt v2'
 where toolset_key = 'pipeline' and key = 'pdesc.prompt_on';
-- Step 2 (only if the function bodies themselves must return): take the bodies recorded before 20261112010000 from the live database's
-- migration history (supabase_migrations.schema_migrations, versions 20261110250000 to 20261110254000 and the earlier migrations they name)
-- and re-create them in a new migration, each guarded by the md5 of the body 20261112010000 leaves.
