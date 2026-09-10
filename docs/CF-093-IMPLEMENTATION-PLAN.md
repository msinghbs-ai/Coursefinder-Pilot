# CF-093 Scheduled Workflow Orchestrator — Implementation Plan

## Goal

Replace opaque source/profile UUID-first Scheduled Tasks operation with a task-first workflow model while preserving the accepted CF-092 scheduler/RPC/security baseline.

## UI model

Primary operator sequence:

`Job / Dataset -> Country -> Scope Type -> Target -> Processing Mode -> Run now / Schedule`

Primary labels must be business-readable. Technical source/profile/policy IDs are retained under progressive disclosure only.

## Processing modes

- Automatic governed pipeline: deterministic acquisition first; Layer 3 only where an accepted Evidence/profile/model contract requires it; Layer 4 only for unresolved eligible work.
- Acquisition only: stop after the deterministic authorised stage.
- Reprocess governed Evidence: no reacquisition; enabled only for accepted Layer 3 profiles.

## Compatibility / no-regression

- Existing `scheduler_policies_list_v1`, `scheduler_policy_edit_v1` and `scheduler_policy_run_now_v1` semantics remain authoritative until an additive server contract is accepted.
- Existing policy rows remain editable/runnable.
- No browser service-role/provider secret exposure.
- No automatic Search/Publication admission.
- Raw IDs remain available for audit/support.

## First implementation slice

1. Humanise existing Scheduled Tasks rows using source/profile metadata already available through governed read surfaces.
2. Add workflow/dataset and bounded-scope presentation to the schedule editor/run-now dialog.
3. Add a task-first run builder only for target combinations that the runtime can currently enforce.
4. Keep unsupported future combinations visibly unavailable rather than emulating them client-side.
5. Extend UAT and release metadata.

## Acceptance

See coursefinder-admin CF-093 acceptance plan and Change Control.
