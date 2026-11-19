-- CF-CHG-20260820-001 — keep the corrected completeness projection behind the governed Admin read boundary.
revoke all on function public.ui_course_completeness_list(integer) from public,anon,authenticated;
grant execute on function public.ui_course_completeness_list(integer) to service_role;
comment on function public.ui_course_completeness_list(integer) is
  'Internal Admin operational completeness/readiness projection. Direct browser EXECUTE is revoked; browser access is through public.admin_read. Presence signals are canonical/relational, not Search publication flags. fee_amount is CRICOS tuition with registered_total_course basis only; score is display-only and not publication approval.';
