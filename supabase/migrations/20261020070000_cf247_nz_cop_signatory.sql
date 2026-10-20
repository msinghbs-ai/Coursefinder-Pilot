-- CF-247 (20 Oct 2026). Platform Admin 10:35 "Proceed with task ... 5" (set the international-enrolment flag for New Zealand providers); choice
-- "NZQA Code signatory (Recommended)": the NZQA register shows whether an organisation is a signatory to the Code of Practice for the
-- pastoral care of international students; only signatories may enrol international students, so a signatory is set Yes and any other
-- provider No, with that as the basis, and it is read again with each NZQA run.
-- Found: all 415 active New Zealand providers have enrols_international blank (Australian providers take it from their CRICOS registration),
-- so no NZ provider qualifies for Firecrawl credits or re-find waves. The NZQA Layer 1 reader already stores each provider's NZQA page in
-- its batch files (pipeline.evidence_artifacts, regulatory/NZ/nzqa/...-offset-N-batch-20.json, detailsHtml), and that page carries the
-- sentence "This Education Organisation is a Signatory to the Code of Practice for the Pastoral Care of International Students."
-- 1 pipeline.nz_cop_reads (stored files read) and pipeline.nz_cop_status (per NZQA organisation number: signatory, the sentence, file).
-- 2 public.svc_nz_cop_next / svc_nz_cop_record (service only): the newest stored batch file of each part of the register not read yet
--   (the latest run: files within nz.cop_window_days of the newest), and what the worker found (coverage-sweep v0.34.0 mode nz_cop; no fetch, no credit).
-- 3 security.nz_cop_apply_v1: sets catalogue.providers.enrols_international for New Zealand providers matched by their NZQA number, only
--   where it is blank or was set by this rule (a value set by a person is never changed), and only when at least nz.cop_min_signatories
--   signatories were found (a page whose wording changed must not turn every provider to No). Logged in admin_control_events.
-- 4 security.nz_cop_fire_v1 and job nz-cop (every 10 minutes): reads unread files, then applies; does nothing when there is nothing new.
-- Replaces: nothing
-- Retires: nothing
-- Nothing dropped or deleted. Consumer API not touched (Decision 266): only the value of an existing provider column changes.

create table if not exists pipeline.nz_cop_reads (
  path text primary key,
  read_at timestamptz not null default now(),
  providers integer not null default 0,
  signatories integer not null default 0,
  error text
);
comment on table pipeline.nz_cop_reads is 'CF-247 20 Oct 2026: stored NZQA batch files read for the Code of Practice signatory sentence (coverage-sweep mode nz_cop).';

create table if not exists pipeline.nz_cop_status (
  provider_code text primary key,
  provider_name text,
  signatory boolean not null,
  quote text,
  nzqa_id text,
  path text,
  read_at timestamptz not null default now()
);
comment on table pipeline.nz_cop_status is 'CF-247 20 Oct 2026: per NZQA organisation number, whether its NZQA page says it is a signatory to the Code of Practice for international students, with the sentence and the stored file; sets catalogue.providers.enrols_international for NZ (security.nz_cop_apply_v1).';
alter table pipeline.nz_cop_reads enable row level security;
alter table pipeline.nz_cop_status enable row level security;

insert into pipeline.platform_toolset_settings(toolset_key, key, label, help, kind, value, min_value, max_value, unit, sort, reason, section, used_by) values
 ('pipeline', 'batch.nz_cop', 'NZQA stored files read per run', 'Each run of nz-cop reads this many stored NZQA batch files (about 20 providers and 1 MB each) for the Code of Practice signatory sentence.', 'number', to_jsonb(3), 1, 10, 'files', 327, 'CF-247, Platform Admin 20 Oct 2026 "NZQA Code signatory"', 'Job sizes', 'job nz-cop; coverage-sweep worker mode nz_cop'),
 ('pipeline', 'nz.cop_window_days', 'NZQA run length', 'NZQA batch files stored within this many days of the newest one make up the latest run; the newest file of each part of the register is read.', 'number', to_jsonb(3), 1, 30, 'days', 328, 'CF-247, Platform Admin 20 Oct 2026 "NZQA Code signatory"', 'Admission checks', 'public.svc_nz_cop_next'),
 ('pipeline', 'nz.cop_min_signatories', 'Fewest NZQA signatories before the flag is set', 'The New Zealand international-enrolment flag is set only when at least this many signatories were found, so a change in NZQA wording cannot turn every provider to No.', 'number', to_jsonb(20), 1, 1000, 'providers', 329, 'CF-247, Platform Admin 20 Oct 2026 "NZQA Code signatory"', 'Admission checks', 'security.nz_cop_apply_v1')
on conflict (toolset_key, key) do nothing;

CREATE OR REPLACE FUNCTION public.svc_nz_cop_next(p_limit integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  if current_user <> 'postgres' and coalesce(auth.role(), '') <> 'service_role' then raise exception 'service_role required'; end if;
  return coalesce((select jsonb_agg(jsonb_build_object('path', z.storage_path, 'captured_at', z.captured_at) order by z.part)
    from (select x.* from (
            select distinct on (substring(e.storage_path from '-offset-([0-9]+)-')) substring(e.storage_path from '-offset-([0-9]+)-')::int part, e.storage_path, e.captured_at
              from pipeline.evidence_artifacts e join pipeline.sources s on s.id = e.source_id
             where s.url like 'https://www.nzqa.govt.nz/providers/%' and e.storage_path like 'regulatory/NZ/nzqa/%-offset-%'
               and e.captured_at > (select max(e2.captured_at) from pipeline.evidence_artifacts e2 where e2.source_id = e.source_id and e2.storage_path like 'regulatory/NZ/nzqa/%-offset-%')
                                   - make_interval(days => security.pipeline_num_v1('nz.cop_window_days', 3)::int)
             order by substring(e.storage_path from '-offset-([0-9]+)-'), e.captured_at desc) x
          where not exists (select 1 from pipeline.nz_cop_reads r where r.path = x.storage_path and r.error is null)
          order by x.part limit greatest(1, least(coalesce(p_limit, 3), 10))) z), '[]'::jsonb);  -- fixed: bounds of one call
end $function$;
revoke execute on function public.svc_nz_cop_next(integer) from public, anon, authenticated;

CREATE OR REPLACE FUNCTION public.svc_nz_cop_record(p_path text, p_rows jsonb, p_error text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_n int := 0; v_yes int := 0;
begin
  if current_user <> 'postgres' and coalesce(auth.role(), '') <> 'service_role' then raise exception 'service_role required'; end if;
  if p_error is null then
    insert into pipeline.nz_cop_status(provider_code, provider_name, signatory, quote, nzqa_id, path, read_at)
    select r->>'code', r->>'name', coalesce((r->>'signatory')::boolean, false), r->>'quote', r->>'nzqa_id', p_path, now()
      from jsonb_array_elements(coalesce(p_rows, '[]'::jsonb)) r where nullif(r->>'code', '') is not null
    on conflict (provider_code) do update set provider_name = excluded.provider_name, signatory = excluded.signatory, quote = excluded.quote,
           nzqa_id = excluded.nzqa_id, path = excluded.path, read_at = excluded.read_at
     where excluded.path >= coalesce(pipeline.nz_cop_status.path, '');  -- an older file never overwrites a newer one (paths start with their time)
    get diagnostics v_n = row_count;
    select count(*) into v_yes from jsonb_array_elements(coalesce(p_rows, '[]'::jsonb)) r where (r->>'signatory')::boolean;
  end if;
  insert into pipeline.nz_cop_reads(path, read_at, providers, signatories, error) values (p_path, now(), v_n, v_yes, p_error)
  on conflict (path) do update set read_at = now(), providers = excluded.providers, signatories = excluded.signatories, error = excluded.error;
  return jsonb_build_object('providers', v_n, 'signatories', v_yes);
end $function$;
revoke execute on function public.svc_nz_cop_record(text, jsonb, text) from public, anon, authenticated;

CREATE OR REPLACE FUNCTION security.nz_cop_apply_v1()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_yes int; v_min int := security.pipeline_num_v1('nz.cop_min_signatories', 20)::int; v_set int := 0; v_no int := 0;
begin
  select count(*) filter (where signatory) into v_yes from pipeline.nz_cop_status;
  if v_yes < v_min then return jsonb_build_object('applied', false, 'signatories', v_yes, 'needed', v_min); end if;
  with m as (
    select distinct on (p.id) p.id, s.signatory, s.quote
      from pipeline.nz_cop_status s
      join catalogue.provider_registrations r on r.registration_scheme = 'nzqa' and r.registration_code = s.provider_code
      join catalogue.providers p on p.id = r.provider_id
     where security.coverage_country(p.id) = 'NZ'
       and (p.enrols_international is null or coalesce(p.enrols_international_basis, '') like 'NZQA Code of Practice%')
     order by p.id, s.signatory desc),
  u as (update catalogue.providers p set enrols_international = m.signatory,
               enrols_international_basis = case when m.signatory then 'NZQA Code of Practice signatory' else 'NZQA Code of Practice: not a signatory' end
          from m where p.id = m.id and (p.enrols_international is distinct from m.signatory or p.enrols_international_basis is distinct from
               case when m.signatory then 'NZQA Code of Practice signatory' else 'NZQA Code of Practice: not a signatory' end)
        returning p.id, m.signatory)
  select count(*), count(*) filter (where not signatory) into v_set, v_no from u;
  if v_set > 0 then
    insert into pipeline.admin_control_events(area, action, target, detail, actor)
    values ('layer1', 'nz_cop_apply', 'NZ', jsonb_build_object('changed', v_set, 'set_no', v_no, 'set_yes', v_set - v_no, 'signatories_found', v_yes), null);
  end if;
  return jsonb_build_object('applied', true, 'changed', v_set, 'set_yes', v_set - v_no, 'set_no', v_no, 'signatories', v_yes);
end $function$;
revoke execute on function security.nz_cop_apply_v1() from public, anon, authenticated;

CREATE OR REPLACE FUNCTION security.nz_cop_fire_v1()
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  if jsonb_array_length(public.svc_nz_cop_next(1)) > 0 then
    perform pipeline.svc_pilot_submit_nonce('coverage-sweep', jsonb_build_object('mode', 'nz_cop', 'limit', security.pipeline_num_v1('batch.nz_cop', 3)::int));
    return 1;
  end if;
  perform security.nz_cop_apply_v1();
  return 0;
end $function$;
revoke execute on function security.nz_cop_fire_v1() from public, anon, authenticated;

insert into pipeline.automation_catalogue(jobname, area, sort, label, description, control_rank, batch_editable) values
 ('nz-cop', 'Layer 1 register', 8, 'New Zealand: international-enrolment flag from NZQA', 'Every 10 minutes while new NZQA files are stored: reads each New Zealand provider''s stored NZQA page for the Code of Practice signatory sentence, then sets the international-enrolment flag (signatory Yes, otherwise No; values set by a person are kept). Does nothing when nothing is new.', 5, true)
on conflict (jobname) do nothing;
select cron.schedule('nz-cop', '*/10 * * * *', $$select security.nz_cop_fire_v1()$$);

insert into pipeline.component_register(kind, name, layer, purpose, status, introduced_in) values
 ('table', 'pipeline.nz_cop_reads', 'Layer 1', 'NZQA stored files read for the Code signatory sentence', 'active', '20261020070000'),
 ('table', 'pipeline.nz_cop_status', 'Layer 1', 'NZ providers: NZQA Code of Practice signatory, with the sentence', 'active', '20261020070000'),
 ('function', 'public.svc_nz_cop_next', 'Layer 1', 'NZQA stored files to read for the Code signatory sentence', 'active', '20261020070000'),
 ('function', 'public.svc_nz_cop_record', 'Layer 1', 'Records what the worker found on the stored NZQA pages', 'active', '20261020070000'),
 ('function', 'security.nz_cop_apply_v1', 'Layer 1', 'Sets the NZ international-enrolment flag from the NZQA Code signatory', 'active', '20261020070000'),
 ('function', 'security.nz_cop_fire_v1', 'Layer 1', 'Starts nz_cop reads or applies the flag', 'active', '20261020070000'),
 ('job', 'nz-cop', 'Layer 1', 'NZ international-enrolment flag from NZQA (Code signatory)', 'active', '20261020070000')
on conflict (kind, name) do nothing;
