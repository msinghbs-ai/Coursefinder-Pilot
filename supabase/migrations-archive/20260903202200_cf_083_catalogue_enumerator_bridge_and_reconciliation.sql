begin;

create or replace function pipeline.svc_pilot_invoke_layer2(p_function text,p_body jsonb default '{}'::jsonb)
returns bigint language plpgsql security definer
set search_path='pipeline','vault','net','public' as $$
declare v_key text;v_id bigint;
begin
 if p_function not in (
   'layer2-acquire-v2',
   'layer2-extract-v2',
   'layer2-course-fact-extract-v2',
   'layer2-scholarship-extract',
   'layer2-scholarship-catalogue-enumerate',
   'layer2-provider-page-fanout',
   'layer2-provider-asset-promote'
 ) then raise exception 'Layer2 automation function not allowlisted';end if;

 select decrypted_secret into v_key
 from vault.decrypted_secrets
 where name='coursefinder_pilot_automation_key'
 limit 1;
 if v_key is null then raise exception 'Pilot automation secret missing';end if;

 select net.http_post(
   url:='https://fxcwkweaxjtknorudmwp.supabase.co/functions/v1/'||p_function,
   headers:=jsonb_build_object('content-type','application/json','x-cf-pilot-key',v_key),
   body:=coalesce(p_body,'{}'::jsonb),
   timeout_milliseconds:=120000
 ) into v_id;
 return v_id;
end $$;
revoke all on function pipeline.svc_pilot_invoke_layer2(text,jsonb) from public,anon,authenticated;
grant execute on function pipeline.svc_pilot_invoke_layer2(text,jsonb) to service_role;

update pipeline.scholarship_source_records
set status='rejected',
    error_text='CF-083: catalogue-level page was incorrectly interpreted as one Scholarship; use catalogue enumeration then detail extraction',
    payload=coalesce(payload,'{}'::jsonb)||jsonb_build_object(
      'rejected_by','CF-CHG-20260903-083',
      'rejection_reason','catalogue_page_not_individual_scholarship'
    )
where evidence_id in (
 '9d7bb0d0-911f-4f58-98a4-ad6a83f81d22',
 '72236901-5007-4d52-8060-370cc5c9c34b',
 'ee9632fd-df4b-4ebe-936c-d6db09414755',
 'bc57bdde-d2c7-484e-9bc2-cd0b158671a7',
 '9624cf6c-c6c1-4a01-a89b-aa6b45c31d98',
 '6f1c081b-6aa9-4c93-a2ee-6aeb24d1e07f'
)
and status='captured';

commit;