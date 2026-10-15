-- CF-247 (15 Oct 2026): the logo finder's first runs (worker v0.25.0) took a campus photo whose folder was named "new-brand" and a white
-- logo drawn for dark backgrounds, and refused wide wordmarks by their short side. Worker v0.25.1 fixes the picker; every logo the first
-- version attached is set aside (superseded, kept) and its provider is checked again, as are providers it did not find.
-- Replaces: nothing (corrects data written by coverage-sweep v0.25.0 mode logo_find)
-- Retires: nothing
update catalogue.provider_assets a set is_primary = false, status = 'superseded',
       metadata = a.metadata || jsonb_build_object('superseded_reason', 'logo finder v0.25.0 picks re-checked by v0.25.1 (15 Oct 2026)')
 where a.metadata->>'source_class' = 'website_logo_finder' and a.is_primary and a.status = 'approved'
   and a.metadata->>'worker' = 'coverage-sweep-worker-v0.25.0';
update pipeline.provider_logo_finds f set status = 'queued', reason = 'checked again by worker v0.25.1', updated_at = now()
 where f.status in ('found', 'not_found', 'failed');

do $post$
begin
  if exists (select 1 from catalogue.provider_assets where metadata->>'worker' = 'coverage-sweep-worker-v0.25.0' and is_primary) then
    raise exception 'recheck post-check: a v0.25.0 logo is still primary';
  end if;
end $post$;
