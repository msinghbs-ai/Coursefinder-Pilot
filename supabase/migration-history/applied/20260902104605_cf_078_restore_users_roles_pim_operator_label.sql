update security.roles
set name = 'PIM Operator',
    description = 'PIM configuration and catalogue administration without Platform Admin identity/security access'
where code = 'pim_admin' and rank = 5;
