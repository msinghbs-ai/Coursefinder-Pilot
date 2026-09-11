# CF-093 Workflow catalogue

The runtime-backed catalogue must distinguish:

- authoritative/regulatory/statistical/reference ingestion;
- deterministic enrichment;
- Evidence interpretation;
- human-resolution exceptions;
- maintenance/reconciliation.

Business labels are primary; technical IDs are secondary.

No workflow is exposed as runnable unless its current server-side contract can enforce the selected scope.
