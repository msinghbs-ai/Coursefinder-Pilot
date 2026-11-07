-- Live production definitions (read via pg_get_functiondef on fxcwkweaxjtknorudmwp, 7 Nov 2026), unedited. md5 of each is asserted by run.sh against the value the migration guards.
CREATE OR REPLACE FUNCTION public.svc_provider_facts_read_next(p_limit integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v jsonb;
begin
  if current_user <> 'postgres' and coalesce(auth.role(), '') <> 'service_role' then raise exception 'service_role required'; end if;
  with pick as (
    select f.id from pipeline.provider_fact_sources f
     where ((f.kind = 'fee_schedule' and security.tuition_chase_enabled(f.provider_id))
            or f.kind in ('english_policy', 'intake_calendar'))
       and (f.status = 'found' or (f.status = 'reading' and f.updated_at < now() - interval '20 minutes')) and f.attempts < security.pipeline_num_v1('retry.provider_facts_attempts', 3)
       and not exists (select 1 from security.provider_hidden_v1 h where h.provider_id = f.provider_id)  -- v2.15.237: paused while the provider is unpublished or archived
     order by (f.linked_from is null), f.rank,
              (select count(*) from catalogue.courses c where c.provider_id = f.provider_id and c.lifecycle_status = 'active') desc, f.created_at limit greatest(1, least(coalesce(p_limit, 10), 30))
     for update skip locked),
  upd as (update pipeline.provider_fact_sources f set status = 'reading', attempts = f.attempts + 1, updated_at = now() from pick where f.id = pick.id
          returning f.id, f.provider_id, f.kind, f.url)
  select coalesce(jsonb_agg(jsonb_build_object('id', u.id, 'provider_id', u.provider_id, 'kind', u.kind, 'url', u.url,
           'country', (select k.iso_alpha2 from catalogue.providers p join ref.countries k on k.id = p.country_id where p.id = u.provider_id),
           'currency', (select a.currency_code from catalogue.providers p join pipeline.coverage_admission_countries a on a.country_id = p.country_id where p.id = u.provider_id))), '[]'::jsonb)
    into v from upd u;
  return v;
end $function$
;
CREATE OR REPLACE FUNCTION public.svc_provider_facts_read_record(p_id uuid, p_status text, p_http integer, p_storage_path text, p_sha256 text, p_mime text, p_rows jsonb, p_summary jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare f pipeline.provider_fact_sources%rowtype; v_src uuid; v_ev uuid; v_cur text; v_n int := 0;
begin
  if current_user <> 'postgres' and coalesce(auth.role(), '') <> 'service_role' then raise exception 'service_role required'; end if;
  select * into f from pipeline.provider_fact_sources where id = p_id for update;
  if f.id is null then raise exception 'source not found'; end if;
  if p_status not in ('read','failed') then raise exception 'status must be read or failed'; end if;
  if p_status = 'failed' then
    update pipeline.provider_fact_sources set status = case when attempts >= 3 then 'failed' else 'found' end, http_status = p_http,
           parse_summary = p_summary, updated_at = now() where id = p_id;
    return jsonb_build_object('status', 'failed');
  end if;
  if p_storage_path is not null and p_sha256 ~ '^[0-9a-f]{64}$' then
    v_src := security.coverage_sweep_source(f.provider_id);
    select id into v_ev from pipeline.evidence_artifacts where source_id = v_src and content_hash = p_sha256 and source_url = f.url limit 1;
    if v_ev is null then
      v_ev := public.svc_coursefacts_register_evidence(v_src, f.url, p_storage_path, p_sha256, coalesce(p_mime, 'text/markdown'),
                jsonb_build_object('layer', 2, 'kind', 'provider_' || f.kind, 'worker', 'coverage-sweep', 'provider_fact_source_id', f.id));
    end if;
  end if;
  select a.currency_code into v_cur from catalogue.providers p join pipeline.coverage_admission_countries a on a.country_id = p.country_id where p.id = f.provider_id;
  -- a re-read replaces the rows parsed before (kept, marked not current, for the record)
  update pipeline.provider_fee_rows set current = false where source_id = p_id and current;
  if f.kind = 'fee_schedule' and v_cur is not null then
    insert into pipeline.provider_fee_rows(source_id, provider_id, course_code, amount, currency_code, basis, fee_year, column_label, row_text)
    select p_id, f.provider_id, upper(btrim(r->>'course_code')), (r->>'amount')::numeric, v_cur, nullif(r->>'basis', ''), nullif(r->>'fee_year', '')::int,
           left(r->>'column_label', 120), left(r->>'row_text', 500)
      from jsonb_array_elements(coalesce(p_rows, '[]'::jsonb)) r
     where coalesce(r->>'course_code', '') ~ '^[0-9A-Za-z]{4,12}$' and coalesce(r->>'amount', '') ~ '^[0-9]+(\.[0-9]+)?$'
       and (r->>'amount')::numeric between 1000 and 200000
       and coalesce(nullif(r->>'basis', ''), 'annual') in ('annual','per_semester','per_trimester','total_indicative')
    on conflict on constraint provider_fee_rows_key do update set current = true, fee_year = excluded.fee_year, column_label = excluded.column_label, row_text = excluded.row_text;
    get diagnostics v_n = row_count;
  end if;
  update pipeline.provider_fact_sources set status = case when f.kind <> 'fee_schedule' then 'read' when v_n > 0 then 'parsed' else 'no_values' end,
         http_status = p_http, evidence_id = coalesce(v_ev, evidence_id), content_hash = coalesce(p_sha256, content_hash), read_at = now(),
         parse_summary = coalesce(p_summary, '{}'::jsonb) || jsonb_build_object('fee_rows', v_n), updated_at = now()
   where id = p_id;
  return jsonb_build_object('status', 'read', 'fee_rows', v_n, 'evidence_id', v_ev);
end $function$
;
