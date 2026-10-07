-- CF-247, 7 Oct 2026. Refile an already approved fee schedule: writes only the rows that now have no active fee (outcome 'new'), for example after a course's adapter fee was withdrawn by an exclusion. Nothing existing is changed.
create or replace function public.admin_provider_fee_schedule_refile(p_source_id uuid, p_note text)
returns jsonb language plpgsql security definer set search_path to '' as $f$
declare f pipeline.provider_fact_sources%rowtype; x record; v_src uuid; v_n int := 0; v_err int := 0; v_last text;
begin
  if auth.uid() is null or security.current_role_rank() < 6 then raise exception 'Platform Admin role required' using errcode = '42501'; end if;
  select * into f from pipeline.provider_fact_sources where id = p_source_id for update;
  if f.id is null or f.kind <> 'fee_schedule' or f.status <> 'parsed' or f.decision is distinct from 'approved' then raise exception 'not an approved parsed fee schedule'; end if;
  if length(btrim(coalesce(p_note, ''))) < 4 then raise exception 'give a reason (kept in the log)'; end if;
  if f.evidence_id is null or f.content_hash is null then raise exception 'the document has no stored evidence; read it again first'; end if;
  v_src := security.coverage_sweep_source(f.provider_id);
  for x in select * from security.provider_fee_proposal_rows(p_source_id) where outcome = 'new' loop
    begin
      perform security.coverage_apply_course_v1(x.course_id, v_src, f.evidence_id, f.url, f.content_hash,
        jsonb_build_object('fee_amount', x.amount, 'currency_code', x.currency_code, 'fee_year', x.fee_year, 'fee_basis', x.basis,
                           'fee_notes', 'From the provider''s international fee schedule; refiled by a Platform Admin'));
      v_n := v_n + 1;
    exception when others then v_err := v_err + 1; v_last := left(sqlerrm, 200);
    end;
  end loop;
  insert into pipeline.admin_control_events(area, action, target, detail, actor)
  values ('fees', 'fee_schedule_refiled', f.url, jsonb_build_object('source_id', f.id, 'provider_id', f.provider_id, 'written', v_n, 'refused', v_err, 'last_error', v_last, 'reason', left(p_note, 500)), auth.uid());
  return jsonb_build_object('written', v_n, 'refused', v_err, 'last_error', v_last);
end $f$;
revoke all on function public.admin_provider_fee_schedule_refile(uuid, text) from public, anon;
grant execute on function public.admin_provider_fee_schedule_refile(uuid, text) to authenticated, service_role;
