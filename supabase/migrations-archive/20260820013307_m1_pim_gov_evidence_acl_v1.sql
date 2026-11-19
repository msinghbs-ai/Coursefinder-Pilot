-- CF-CHG-20260820-006 — keep Evidence browser access behind the governed Curator+ admin_read boundary.
-- No evidence rows or source records are modified.

revoke all on function public.ui_evidence_governance_list(integer) from public,anon,authenticated;
grant execute on function public.ui_evidence_governance_list(integer) to service_role;

comment on function public.ui_evidence_governance_list(integer) is
  'Internal Evidence governance projection. Browser access is governed through public.admin_read, which requires Curator-or-higher role.';
