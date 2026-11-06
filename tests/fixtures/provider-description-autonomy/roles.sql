-- Guards: Provider Description production role authority; controlled auth.uid boundary only.
alter table security.roles add column if not exists code text;
alter table security.roles add column if not exists name text;
alter table security.roles add column if not exists rank int2;
alter table security.roles add column if not exists description text;
alter table security.roles add column if not exists status text default 'active'::text;
alter table security.roles alter column status set default 'active'::text;
alter table security.user_roles add column if not exists user_id uuid;
alter table security.user_roles add column if not exists role_code text;
alter table security.user_roles add column if not exists granted_at timestamptz default now();
alter table security.user_roles alter column granted_at set default now();
alter table security.user_roles add column if not exists granted_by uuid;
alter table security.user_roles add column if not exists expires_at timestamptz;
insert into auth.users(id,email) values('90000000-0000-0000-0000-0000000000aa','isolated-operator@example.invalid') on conflict do nothing;
do $p$ begin if not exists(select 1 from pg_constraint where conrelid='security.roles'::regclass and conname='roles_pkey') then alter table security.roles add constraint roles_pkey PRIMARY KEY (code); end if; end $p$;
do $p$ begin if not exists(select 1 from pg_constraint where conrelid='security.roles'::regclass and conname='roles_rank_key') then alter table security.roles add constraint roles_rank_key UNIQUE (rank); end if; end $p$;
do $p$ begin if not exists(select 1 from pg_constraint where conrelid='security.user_roles'::regclass and conname='user_roles_granted_by_fkey') then alter table security.user_roles add constraint user_roles_granted_by_fkey FOREIGN KEY (granted_by) REFERENCES auth.users(id); end if; end $p$;
do $p$ begin if not exists(select 1 from pg_constraint where conrelid='security.user_roles'::regclass and conname='user_roles_pkey') then alter table security.user_roles add constraint user_roles_pkey PRIMARY KEY (user_id, role_code); end if; end $p$;
do $p$ begin if not exists(select 1 from pg_constraint where conrelid='security.user_roles'::regclass and conname='user_roles_role_code_fkey') then alter table security.user_roles add constraint user_roles_role_code_fkey FOREIGN KEY (role_code) REFERENCES security.roles(code); end if; end $p$;
do $p$ begin if not exists(select 1 from pg_constraint where conrelid='security.user_roles'::regclass and conname='user_roles_user_id_fkey') then alter table security.user_roles add constraint user_roles_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE; end if; end $p$;
alter table security.roles alter column rank type smallint;
update security.roles set name=code;
alter table security.roles alter column name set not null;
alter table security.user_roles alter column user_id set not null;
alter table security.user_roles alter column role_code set not null;
alter table security.user_roles alter column granted_at set not null;
drop function security.current_role_rank();
CREATE OR REPLACE FUNCTION security.current_role_rank()
 RETURNS smallint
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'security', 'auth'
AS $function$
select coalesce(max(r.rank),0)::smallint
from security.user_roles ur join security.roles r on r.code=ur.role_code
where ur.user_id=auth.uid() and (ur.expires_at is null or ur.expires_at>now()) and r.status='active'
$function$
;
