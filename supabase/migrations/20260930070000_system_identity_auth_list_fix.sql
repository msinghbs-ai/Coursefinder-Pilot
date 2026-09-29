-- Users & roles showed "Auth User List Failed" and no accounts (Platform Admin screenshot, 30 Sep 2026 01:46 IST).
-- Cause: the system automation identity (20260926190000_system_automation_identity) was inserted into auth.users with
-- NULL token columns. Supabase Auth reads these as text and fails the whole admin user list ("Scan error on column
-- confirmation_token: converting NULL to string"). No account or role was lost. Fix: empty strings, as Auth itself writes.
do $g$ begin
  if (select count(*) from auth.users where confirmation_token is null or recovery_token is null or email_change_token_new is null
        or email_change is null or email_change_token_current is null or phone_change_token is null or reauthentication_token is null)
     <> (select count(*) from auth.users where id='c0ffee00-0000-4000-8000-000000000150' and confirmation_token is null) then
    raise exception 'system_identity_auth_list_fix: other accounts have NULL token columns; review first';
  end if;
end $g$;
update auth.users set confirmation_token=coalesce(confirmation_token,''), recovery_token=coalesce(recovery_token,''),
  email_change_token_new=coalesce(email_change_token_new,''), email_change=coalesce(email_change,''),
  email_change_token_current=coalesce(email_change_token_current,''), phone_change_token=coalesce(phone_change_token,''),
  reauthentication_token=coalesce(reauthentication_token,'')
 where id='c0ffee00-0000-4000-8000-000000000150';
do $v$ begin
  if exists (select 1 from auth.users where confirmation_token is null or recovery_token is null or email_change_token_new is null or email_change is null) then
    raise exception 'NULL token columns remain';
  end if;
end $v$;
