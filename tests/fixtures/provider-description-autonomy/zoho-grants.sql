-- Guards: Provider Description mandate §8: exact production consumer/helper EXECUTE grants.
revoke all on function public.zoho_v2_provider(text) from public,anon,authenticated,service_role;
grant EXECUTE on function public.zoho_v2_provider(text) to "postgres";
grant EXECUTE on function public.zoho_v2_provider(text) to "service_role";
revoke all on function security.zoho_v2_provider_cricos_v1(uuid) from public,anon,authenticated,service_role;
grant EXECUTE on function security.zoho_v2_provider_cricos_v1(uuid) to "postgres";
revoke all on function security.zoho_v2_provider_item_v1(uuid) from public,anon,authenticated,service_role;
grant EXECUTE on function security.zoho_v2_provider_item_v1(uuid) to "postgres";
revoke all on function security.zoho_v2_campus_item_v1(uuid) from public,anon,authenticated,service_role;
grant EXECUTE on function security.zoho_v2_campus_item_v1(uuid) to "postgres";
revoke all on function security.zoho_v2_contact_item_v1(text) from public,anon,authenticated,service_role;
grant EXECUTE on function security.zoho_v2_contact_item_v1(text) to "postgres";
revoke all on function security.website_sync_item_v1(text,uuid,text) from public,anon,authenticated,service_role;
grant EXECUTE on function security.website_sync_item_v1(text,uuid,text) to "postgres";
