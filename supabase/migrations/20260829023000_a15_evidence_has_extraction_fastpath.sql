-- A15 bounded integration hardening.
-- admin_evidence_has_extraction and admin_evidence_observation_count cover the same
-- governed observation tables. Reuse the count helper to avoid the unstable
-- UNION ALL EXISTS plan observed during mobile Evidence-detail UAT.
create or replace function security.admin_evidence_has_extraction(p_evidence_id uuid)
returns boolean
language sql
stable
set search_path to 'pg_catalog','security'
as $$
  select security.admin_evidence_observation_count(p_evidence_id) > 0
$$;
