-- CF-158 — Scholarship filter/search page guard
-- Filtered catalogue URLs remain enumeration Evidence and are not treated as individual Scholarship detail pages.
update pipeline.layer2_scholarship_discovery_candidates
set classification='catalogue_or_filter',
    classification_reason='international_only_gate: filtered/search catalogue URL retained as enumeration evidence; not an individual Scholarship detail',
    classified_at=now()
where classification='detail_ready'
  and (
    coalesce(detail_target_url,scholarship_url,'') ~* '/search\\?'
    or coalesce(detail_target_url,scholarship_url,'') ~* '[?&](query|collection|form|num_ranks|f\\.)='
    or coalesce(detail_target_url,scholarship_url,'') ~* 'residency[^#]*international'
  );
