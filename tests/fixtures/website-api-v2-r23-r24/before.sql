-- Snapshots of the live definitions' output before the migration: the builders (as the owner) and the consumer wrappers called as
-- service_role, the role the edge function website-api-v2 uses. fixtures.sql compares the output after the migration with these.
grant usage on schema fx to service_role; grant select, insert on fx.before to service_role; grant execute on function fx.i(text) to service_role;
insert into fx.before select 'campus', k, api.website_v2_provider_campuses(fx.i(k)) from unnest(array['P1','P2','P3','P4']) k;
insert into fx.before select 'item', k, api.website_v2_scholarship_item(fx.i(k))
  from unnest(array['S1','S2','S3','S4','S5','S6','S7','S8','S9','S10','S11','S12','S13','S14']) k;
set role service_role;
insert into fx.before values ('providers', 'all', public.website_v2_providers('{}'::jsonb, 1, 50, null)),
  ('providers', 'auckland', public.website_v2_providers('{"cities":["Auckland"]}'::jsonb, 1, 50, 'course_count_desc')),
  ('scholarships', 'all', public.website_v2_scholarships('{}'::jsonb, 1, 50)),
  ('scholarships', 'nat', public.website_v2_scholarships('{"nationality_codes":["VN","R-SASIA","CN"]}'::jsonb, 1, 50));
insert into fx.before select 'detail', k, public.website_v2_scholarship('scholarship:fx:'||lower(k))
  from unnest(array['S1','S2','S3','S4','S5','S6','S7','S8','S9','S10','S11','S12','S13','S14']) k;
reset role;
do $d$
declare v jsonb := (select j from fx.before where kind = 'campus' and k = 'P1');
begin
  raise notice 'before (defect R23): provider P1 holds 3 active campuses with a city; the API returns % item(s) with no campus name, identity or course count: %', jsonb_array_length(v), v;
  raise notice 'before (defect R24): S3 (nothing held) and S4 (explicitly any nationality) both return citizenship_eligibility % and %, nothing tells them apart',
    (select j->'citizenship_eligibility' from fx.before where kind = 'item' and k = 'S3'), (select j->'citizenship_eligibility' from fx.before where kind = 'item' and k = 'S4');
end $d$;
