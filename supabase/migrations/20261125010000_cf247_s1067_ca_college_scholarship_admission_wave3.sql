-- CF-247 s1067: thirteen more Canadian colleges take the scholarship admission route (S2-Scholarship-Readers, Platform Admin 24 Nov 2026 17:01: whole Canadian backlog).
-- Measured live after s1066: these active Canadian colleges, each with its own website, still have scholarship pages refused only as "not a university provider in a scholarship country" (they have no provider type):
-- Aurora, BCIT, Coast Mountain, College of New Caledonia, College of the Rockies, Confederation, Justice Institute of BC, Langara, Mohawk, Niagara, Okanagan, Selkirk, Vancouver Community College.
-- Replaces: nothing (adds ids to the s1066 setting scholarship.ca_college_providers)
-- Retires: nothing
-- G2: the list is a setting. G3: nothing the consumer API reads is touched.

do $p$
declare v_old jsonb; v_new jsonb; v_add text[] := array['69ac4368-98a0-4471-b265-d1e16fcb1ed0','60b274ad-14cf-4343-9e1a-9779fd5466b1','3a48beb7-d61f-468c-b93c-6fa61ab96921','e7af5ef9-f719-4b94-b6b5-abf88071b9ce','d5a30625-74a1-43ff-83bb-81b2bf587cb2','bd10d0cd-daec-40ff-a9e0-200d8db91102','b0f95837-8e85-4936-8166-b40b48e1044f','89bab0e8-22c2-431b-8da4-ebf8ffbe5cdb','0af6c3f4-752e-42e3-b818-74c2eaf31671','e7caf3bf-0dba-49e1-a654-09427531cd26','5b6ad653-99f7-4347-a56e-f0d2928bd34d','6cc65e88-af6c-4fa9-b4a8-512d37b01d4f','5a2a154f-1e11-4851-aa96-0a172ba5314d']; p text; v_pass int;
begin
  select value into v_old from pipeline.platform_toolset_settings where toolset_key = 'pipeline' and key = 'scholarship.ca_college_providers' for update;
  if v_old is null then raise exception 'guard: scholarship.ca_college_providers is missing (s1066 must be applied first)'; end if;
  v_new := v_old;
  foreach p in array v_add loop
    if not v_new ? p then v_new := v_new || to_jsonb(p); end if;
  end loop;
  if v_new <> v_old then
    update pipeline.platform_toolset_settings set value = v_new, updated_at = now(),
           reason = 'CF-247 s1067 (Platform Admin 24 Nov 2026 17:01): thirteen more Canadian colleges allowed through scholarship admission'
     where toolset_key = 'pipeline' and key = 'scholarship.ca_college_providers';
    insert into pipeline.admin_control_events (area, action, target, detail, actor)
    values ('settings', 'migration', 'pipeline.platform_toolset_settings', jsonb_build_object('key', 'scholarship.ca_college_providers', 'before', v_old, 'after', v_new,
            'reason', 'Platform Admin 24 Nov 2026 17:01: Canadian college scholarship admission wave 3 (s1067)', 'migration', '20261125010000'), security.system_actor_id());
  end if;
  select count(*) into v_pass from catalogue.providers pr where pr.id::text = any (v_add) and security.scholarship_admission_provider_ok_v1(pr.id);
  if v_pass <> 13 then raise exception 'post-check: % of the 13 added colleges pass (expected 13)', v_pass; end if;
  raise notice 's1067: % colleges added; all pass the admission provider check', array_length(v_add, 1);
end $p$;
