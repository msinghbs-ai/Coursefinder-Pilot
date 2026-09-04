-- CF-173: extend guarded Scholarship runtime reporting with reconciliation maturity.
-- Runtime SQL already applied in Pilot. This repository migration records the accepted contract.

comment on function security.admin_scholarship_runtime_read(jsonb) is
'CF-173 guarded Scholarship runtime read: includes captured/applied source records, reconciliation-ready and reconciled-unpublished counts in addition to acquisition/mapping/calculation statistics.';

comment on function security.admin_scholarship_runtime_uat(text) is
'CF-173 live Scholarship UAT includes reconciliation service existence, browser denial, unpublished-only canonical roots, generic/navigation exclusion and Evidence/source-record retention.';
