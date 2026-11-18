-- CF-247 (20 Oct 2026). Check of the first NZ international-enrolment flag run (v2.15.300, job nz-cop at 03:50 UTC): 189 providers set Yes and
-- 226 set No, but all eight New Zealand universities were among the No. Their NZQA pages do not carry the sentence "This Education
-- Organisation is a Signatory to the Code of Practice ...", so a missing sentence does not mean a provider is not a signatory.
-- 1 The rule: Yes when the page says it is a signatory; No only when the page says it is not; otherwise the flag is left blank (a person
--   or a later reading decides). The 226 No values this rule set are cleared back to blank now; the 189 Yes stay.
-- 2 Each provider's NZQA type (UNI, POLLY, WANA, PTE, GTE), whether its page states it is not a signatory, and the words around "Code"
--   are kept (coverage-sweep v0.34.1), so the university wording can be read and the rule extended on evidence.
-- 3 The stored files are read again once by the new reader (reader v2); svc_nz_cop_record takes the reader.
-- Replaces: public.svc_nz_cop_next(integer), security.nz_cop_apply_v1(); public.svc_nz_cop_record(text,jsonb,text) by the 4-argument form
-- Retires: public.svc_nz_cop_record(text,jsonb,text) (no caller after the worker update; dropped by a paste file after 14 days)
-- Nothing dropped or deleted. Consumer API not touched (Decision 266): only values of enrols_international change.

do $chk$ begin
  if md5(pg_get_functiondef('public.svc_nz_cop_next(integer)'::regprocedure)) <> '35909667e83b8fef0e9cc613d8968913'
     or md5(pg_get_functiondef('security.nz_cop_apply_v1()'::regprocedure)) <> 'd3c286ac5d48006c5ed93d3c154d776d' then
    raise exception 'live nz_cop functions differ from the definitions this change replaces';
  end if;
end $chk$;

alter table pipeline.nz_cop_status add column if not exists explicit_no boolean not null default false;
alter table pipeline.nz_cop_status add column if not exists nzqa_type text;
alter table pipeline.nz_cop_status add column if not exists snippet text;
alter table pipeline.nz_cop_reads add column if not exists reader text not null default 'v1';
comment on column pipeline.nz_cop_status.explicit_no is 'CF-247 20 Oct 2026: the NZQA page says the organisation is not a signatory (only then is the flag set No)';
comment on column pipeline.nz_cop_status.snippet is 'CF-247 20 Oct 2026: the words around "Code of Practice", "Pastoral Care" or "Signatory" on the NZQA page';

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
          where not exists (select 1 from pipeline.nz_cop_reads r where r.path = x.storage_path and r.error is null and r.reader = 'v2')  -- fixed: the current reader
          order by x.part limit greatest(1, least(coalesce(p_limit, 3), 10))) z), '[]'::jsonb);  -- fixed: bounds of one call
end $function$;
revoke execute on function public.svc_nz_cop_next(integer) from public, anon, authenticated;

CREATE OR REPLACE FUNCTION public.svc_nz_cop_record(p_path text, p_rows jsonb, p_error text, p_reader text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_n int := 0; v_yes int := 0;
begin
  if current_user <> 'postgres' and coalesce(auth.role(), '') <> 'service_role' then raise exception 'service_role required'; end if;
  if p_error is null then
    insert into pipeline.nz_cop_status(provider_code, provider_name, signatory, explicit_no, quote, nzqa_id, nzqa_type, snippet, path, read_at)
    select r->>'code', r->>'name', coalesce((r->>'signatory')::boolean, false), coalesce((r->>'explicit_no')::boolean, false), r->>'quote', r->>'nzqa_id',
           r->>'type', left(r->>'snippet', 500), p_path, now()
      from jsonb_array_elements(coalesce(p_rows, '[]'::jsonb)) r where nullif(r->>'code', '') is not null
    on conflict (provider_code) do update set provider_name = excluded.provider_name, signatory = excluded.signatory, explicit_no = excluded.explicit_no,
           quote = excluded.quote, nzqa_id = excluded.nzqa_id, nzqa_type = excluded.nzqa_type, snippet = excluded.snippet, path = excluded.path, read_at = excluded.read_at
     where excluded.path >= coalesce(pipeline.nz_cop_status.path, '');  -- an older file never overwrites a newer one (paths start with their time)
    get diagnostics v_n = row_count;
    select count(*) into v_yes from jsonb_array_elements(coalesce(p_rows, '[]'::jsonb)) r where (r->>'signatory')::boolean;
  end if;
  insert into pipeline.nz_cop_reads(path, read_at, providers, signatories, error, reader) values (p_path, now(), v_n, v_yes, p_error, coalesce(p_reader, 'v1'))
  on conflict (path) do update set read_at = now(), providers = excluded.providers, signatories = excluded.signatories, error = excluded.error, reader = excluded.reader;
  return jsonb_build_object('providers', v_n, 'signatories', v_yes);
end $function$;
revoke execute on function public.svc_nz_cop_record(text, jsonb, text, text) from public, anon, authenticated;

CREATE OR REPLACE FUNCTION security.nz_cop_apply_v1()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_yes int; v_min int := security.pipeline_num_v1('nz.cop_min_signatories', 20)::int; v_set int := 0; v_no int := 0; v_clear int := 0;
begin
  select count(*) filter (where signatory) into v_yes from pipeline.nz_cop_status;
  if v_yes < v_min then return jsonb_build_object('applied', false, 'signatories', v_yes, 'needed', v_min); end if;
  -- Yes when the page says it is a signatory; No only when the page says it is not; otherwise blank. Values a person set are never changed.
  with m as (
    select distinct on (p.id) p.id,
           case when s.signatory then true when s.explicit_no then false end val,
           case when s.signatory then 'NZQA Code of Practice signatory' when s.explicit_no then 'NZQA Code of Practice: not a signatory' end basis
      from pipeline.nz_cop_status s
      join catalogue.provider_registrations r on r.registration_scheme = 'nzqa' and r.registration_code = s.provider_code
      join catalogue.providers p on p.id = r.provider_id
     where security.coverage_country(p.id) = 'NZ'
       and (p.enrols_international is null or coalesce(p.enrols_international_basis, '') like 'NZQA Code of Practice%')
     order by p.id, s.signatory desc, s.explicit_no desc),
  u as (update catalogue.providers p set enrols_international = m.val, enrols_international_basis = m.basis
          from m where p.id = m.id and (p.enrols_international is distinct from m.val or p.enrols_international_basis is distinct from m.basis)
        returning p.id, m.val)
  select count(*), count(*) filter (where val = false), count(*) filter (where val is null) into v_set, v_no, v_clear from u;
  if v_set > 0 then
    insert into pipeline.admin_control_events(area, action, target, detail, actor)
    values ('layer1', 'nz_cop_apply', 'NZ', jsonb_build_object('changed', v_set, 'set_no', v_no, 'cleared', v_clear, 'set_yes', v_set - v_no - v_clear, 'signatories_found', v_yes, 'rule', 'no only when stated'), null);
  end if;
  return jsonb_build_object('applied', true, 'changed', v_set, 'set_yes', v_set - v_no - v_clear, 'set_no', v_no, 'cleared', v_clear, 'signatories', v_yes);
end $function$;
revoke execute on function security.nz_cop_apply_v1() from public, anon, authenticated;

insert into pipeline.component_register(kind, name, layer, purpose, status, introduced_in) values
 ('function', 'public.svc_nz_cop_record(text,jsonb,text,text)', 'Layer 1', 'Records what the worker found on the stored NZQA pages (reader, type and wording)', 'active', '20261020090000')
on conflict (kind, name) do nothing;
update pipeline.component_register set status = 'retiring', replaced_by = 'public.svc_nz_cop_record(text,jsonb,text,text)', retire_after = current_date + 14, updated_at = now()
 where kind = 'function' and name = 'public.svc_nz_cop_record' and status = 'active';

-- 1 now: the 226 No values set from a missing sentence go back to blank (explicit_no is false for every row read so far)
select security.nz_cop_apply_v1();
