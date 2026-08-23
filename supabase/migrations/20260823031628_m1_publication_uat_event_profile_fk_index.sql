-- CF-CHG-20260823-024 — performance-adviser follow-up.
create index if not exists publication_events_profile_code_idx
  on publishing.publication_events(profile_code);
