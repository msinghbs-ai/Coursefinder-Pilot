-- CF-CHG-20260902-078
-- Restore the governed Users & Roles administration journey while presenting the
-- existing rank-5 PIM role as PIM Operator. Internal role code/rank remain stable.

update security.roles
set name = 'PIM Operator',
    description = 'PIM configuration and catalogue administration without Platform Admin identity/security access'
where code = 'pim_admin'
  and rank = 5;
