-- CF-247 v2.15.235: contact quality after the first R3 runs (Platform Admin bug list of 10 Oct 2026, Fix 2).
-- The first runs picked mailboxes such as media@, security@ and feedback@ as the public email, and the CRICOS contact job spent a
-- Firecrawl search per provider although the CRICOS institution page is addressed by provider code. Both jobs were paused.
--  1. svc_provider_contact_record replaces a value it wrote earlier (or clears it when the new read finds none); empty values are
--     filled; a value entered by hand stays locked.
--  2. Every public contact check and every CRICOS check that found nothing is read again (worker coverage-sweep v0.17.34).
--  3. Both schedules are switched back on.
-- md5-checked before and after. Nothing is dropped or deleted.
do $guard$
begin
  if md5(replace(pg_get_functiondef('public.svc_provider_contact_record(uuid,text,text,text,jsonb)'::regprocedure), E'\r', '')) <> '7869de71bd8d7ff639d47ef4d6197452'
    then raise exception 'live svc_provider_contact_record differs from the definition this change replaces'; end if;
end $guard$;

CREATE OR REPLACE FUNCTION public.svc_provider_contact_record(p_provider_id uuid, p_phone text, p_email text, p_url text, p_evidence jsonb)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_phone text := nullif(btrim(coalesce(p_phone, '')), ''); v_email text := lower(nullif(btrim(coalesce(p_email, '')), ''));
        v_prev pipeline.provider_contact_points%rowtype;
begin
  if current_user <> 'postgres' and coalesce(auth.role(), '') <> 'service_role' then raise exception 'service_role required'; end if;
  if v_email is not null and v_email !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$' then v_email := null; end if;
  if v_phone is not null and length(regexp_replace(v_phone, '\D', '', 'g')) not between 8 and 15 then v_phone := null; end if;
  insert into pipeline.provider_contact_checks(provider_id, kind, checked_at, outcome, evidence)
  values (p_provider_id, 'public_general', now(), case when v_phone is null and v_email is null then 'not_found' else 'found' end, coalesce(p_evidence, '{}'::jsonb))
  on conflict (provider_id, kind) do update set checked_at = now(), outcome = excluded.outcome, evidence = excluded.evidence;
  select * into v_prev from pipeline.provider_contact_points where provider_id = p_provider_id and kind = 'public_general' and is_current;
  update pipeline.provider_contact_points set is_current = false where provider_id = p_provider_id and kind = 'public_general' and is_current;
  if v_phone is not null or v_email is not null then
    insert into pipeline.provider_contact_points(provider_id, kind, source, phone, email, source_url, evidence)
    values (p_provider_id, 'public_general', 'provider_site', v_phone, v_email, p_url, coalesce(p_evidence, '{}'::jsonb));
  end if;
  -- v2.15.235: a value this job wrote earlier is replaced (or cleared when the new read finds none); an empty value is filled; a value
  -- entered by hand is locked and kept by the manual-value guard.
  update catalogue.providers p
     set phone = case when p.phone is not distinct from v_prev.phone and v_prev.id is not null then v_phone else coalesce(p.phone, v_phone) end,
         email = case when p.email is not distinct from v_prev.email and v_prev.id is not null then v_email else coalesce(p.email, v_email) end,
         updated_at = now()
   where p.id = p_provider_id
     and ((p.phone is null and v_phone is not null) or (p.email is null and v_email is not null)
          or (v_prev.id is not null and ((p.phone is not distinct from v_prev.phone and p.phone is distinct from v_phone)
                                      or (p.email is not distinct from v_prev.email and p.email is distinct from v_email))));
end $function$;

update pipeline.provider_contact_checks set checked_at = now() - interval '365 days'
 where kind = 'public_general' or (kind = 'regulatory_peo' and outcome in ('not_found', 'budget'));
select cron.alter_job((select jobid from cron.job where jobname = 'provider-contact-page'), active := true);
select cron.alter_job((select jobid from cron.job where jobname = 'cricos-peo'), active := true);

do $post$
begin
  if md5(replace(pg_get_functiondef('public.svc_provider_contact_record(uuid,text,text,text,jsonb)'::regprocedure), E'\r', '')) <> 'f6dba8fb614dafa9d19a9448e93822cf'
    then raise exception 'CF-247 v2.15.235 post-check: svc_provider_contact_record not as intended'; end if;
end $post$;
