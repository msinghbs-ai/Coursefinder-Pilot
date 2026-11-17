-- CF-247 (15 Oct 2026): a white logo drawn for dark backgrounds shows as a blank tile; worker v0.25.2 never uses one. A white logo the finder
-- attached is set aside (superseded, kept) and its provider checked again (it is flagged when nothing else is on its home page).
-- Replaces: nothing (corrects data written by coverage-sweep v0.25.1 mode logo_find)
-- Retires: nothing
with w as (
  update catalogue.provider_assets a set is_primary = false, status = 'superseded',
         metadata = a.metadata || jsonb_build_object('superseded_reason', 'white logo: a blank tile on a white background (15 Oct 2026)')
   where a.metadata->>'source_class' = 'website_logo_finder' and a.is_primary and a.status = 'approved'
     and lower(regexp_replace(split_part(a.source_url, '?', 1), '^.*/', '')) ~ '(white|reverse|inverse|negative|knockout)'
  returning a.provider_id)
update pipeline.provider_logo_finds f set status = 'queued', reason = 'white logo set aside', updated_at = now() from w where f.provider_id = w.provider_id;
