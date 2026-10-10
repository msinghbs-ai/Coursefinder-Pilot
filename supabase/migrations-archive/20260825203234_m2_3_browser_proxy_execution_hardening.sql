-- CF-CHG-20260825-037 / CF-CHG-20260825-038
-- Correct invoker-to-private-helper execution deadlock without exposing private helpers.
-- Public facades execute as their owner with fixed search_path; private helpers remain service_role-only
-- and continue to enforce auth.uid() plus current_role_rank() internally.

alter function public.important_date_upsert_v2(
  uuid,text,text,text,text,uuid,text,uuid,uuid,text,uuid,text,timestamptz,timestamptz,date,date,text,text,integer,timestamptz,smallint
) security definer;

alter function public.refresh_policy_upsert_v2(
  uuid,text,smallint,uuid,uuid,text,uuid,text,integer,timestamptz,boolean,boolean,boolean,text
) security definer;

alter function public.layer4_review_context(uuid) security definer;

alter function public.onboarding_cases_list(text,text,text,text,integer) security definer;
alter function public.onboarding_case_context(uuid) security definer;
alter function public.onboarding_case_create(text,text,text,uuid,uuid,uuid,uuid,text,text,text,text) security definer;
alter function public.onboarding_case_transition(uuid,text,text,text,jsonb,uuid,text) security definer;
alter function public.onboarding_case_metadata_update(uuid,text,jsonb,jsonb,jsonb,jsonb,text,text) security definer;

-- Explicitly retain hardened ACLs on private helpers.
revoke all on function security.important_date_upsert_v2_impl(
  uuid,text,text,text,text,uuid,text,uuid,uuid,text,uuid,text,timestamptz,timestamptz,date,date,text,text,integer,timestamptz,smallint
) from public,anon,authenticated;
revoke all on function security.refresh_policy_upsert_v2_impl(
  uuid,text,smallint,uuid,uuid,text,uuid,text,integer,timestamptz,boolean,boolean,boolean,text
) from public,anon,authenticated;
revoke all on function security.layer4_review_context_impl(uuid) from public,anon,authenticated;
revoke all on function security.onboarding_cases_list_impl(text,text,text,text,integer) from public,anon,authenticated;
revoke all on function security.onboarding_case_context_impl(uuid) from public,anon,authenticated;
revoke all on function security.onboarding_case_create_impl(text,text,text,uuid,uuid,uuid,uuid,text,text,text,text) from public,anon,authenticated;
revoke all on function security.onboarding_case_transition_impl(uuid,text,text,text,jsonb,uuid,text) from public,anon,authenticated;
revoke all on function security.onboarding_case_metadata_update_impl(uuid,text,jsonb,jsonb,jsonb,jsonb,text,text) from public,anon,authenticated;

-- Public browser facades remain inaccessible to anonymous callers.
revoke all on function public.important_date_upsert_v2(
  uuid,text,text,text,text,uuid,text,uuid,uuid,text,uuid,text,timestamptz,timestamptz,date,date,text,text,integer,timestamptz,smallint
) from public,anon;
revoke all on function public.refresh_policy_upsert_v2(
  uuid,text,smallint,uuid,uuid,text,uuid,text,integer,timestamptz,boolean,boolean,boolean,text
) from public,anon;
revoke all on function public.layer4_review_context(uuid) from public,anon;
revoke all on function public.onboarding_cases_list(text,text,text,text,integer) from public,anon;
revoke all on function public.onboarding_case_context(uuid) from public,anon;
revoke all on function public.onboarding_case_create(text,text,text,uuid,uuid,uuid,uuid,text,text,text,text) from public,anon;
revoke all on function public.onboarding_case_transition(uuid,text,text,text,jsonb,uuid,text) from public,anon;
revoke all on function public.onboarding_case_metadata_update(uuid,text,jsonb,jsonb,jsonb,jsonb,text,text) from public,anon;

grant execute on function public.important_date_upsert_v2(
  uuid,text,text,text,text,uuid,text,uuid,uuid,text,uuid,text,timestamptz,timestamptz,date,date,text,text,integer,timestamptz,smallint
) to authenticated,service_role;
grant execute on function public.refresh_policy_upsert_v2(
  uuid,text,smallint,uuid,uuid,text,uuid,text,integer,timestamptz,boolean,boolean,boolean,text
) to authenticated,service_role;
grant execute on function public.layer4_review_context(uuid) to authenticated,service_role;
grant execute on function public.onboarding_cases_list(text,text,text,text,integer) to authenticated,service_role;
grant execute on function public.onboarding_case_context(uuid) to authenticated,service_role;
grant execute on function public.onboarding_case_create(text,text,text,uuid,uuid,uuid,uuid,text,text,text,text) to authenticated,service_role;
grant execute on function public.onboarding_case_transition(uuid,text,text,text,jsonb,uuid,text) to authenticated,service_role;
grant execute on function public.onboarding_case_metadata_update(uuid,text,jsonb,jsonb,jsonb,jsonb,text,text) to authenticated,service_role;