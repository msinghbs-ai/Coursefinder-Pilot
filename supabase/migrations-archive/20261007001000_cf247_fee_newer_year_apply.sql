-- CF-247, 7 Oct 2026 (Platform Admin: older-year rows ignored, newer-year rows queued for a decision).
-- One admin function with two actions on an approved fee schedule: 'preview' lists the rows whose fee year is later than the fee
-- on record (nothing written); 'apply' writes those rows as the later year's fee, with a reason kept in the log.
-- The fee on record is not removed: the later year is added beside it and the existing year rules choose the latest.
create or replace function public.admin_provider_fee_newer_year(p_action text, p_source_id uuid, p_note text default null)
returns jsonb language plpgsql security definer set search_path to '' as $f$
declare f pipeline.provider_fact_sources%rowtype; x record; v_src uuid; v_n int := 0; v_err int := 0; v_last text; v_rows jsonb;
begin
  if auth.uid() is null or security.current_role_rank() < 6 then raise exception 'Platform Admin role required' using errcode = '42501'; end if;
  if p_action not in ('preview', 'apply') then raise exception 'action must be preview or apply'; end if;
  select * into f from pipeline.provider_fact_sources where id = p_source_id for update;
  if f.id is null or f.kind <> 'fee_schedule' or f.status <> 'parsed' or f.decision is distinct from 'approved' then raise exception 'not an approved parsed fee schedule'; end if;
  if p_action = 'preview' then
    select coalesce(jsonb_agg(jsonb_build_object('course_code', course_code, 'title', course_title, 'schedule_amount', amount, 'schedule_year', fee_year, 'current_amount', current_amount, 'current_year', cur_year) order by course_title), '[]'::jsonb) into v_rows from (select o.*, cf.fee_year cur_year from security.provider_fee_proposal_rows(p_source_id) o
    join lateral (select y.fee_year from catalogue.course_fees y where y.course_id = o.course_id and y.fee_type = 'provider_current_tuition' and y.status = 'active' and y.audience = 'international'
                   order by y.fee_year desc nulls last limit 1) cf on true
   where o.outcome = 'differs' and o.fee_year is not null and cf.fee_year is not null and o.fee_year > cf.fee_year) ny;
    return jsonb_build_object('rows', v_rows, 'count', jsonb_array_length(v_rows));
  end if;
  if length(btrim(coalesce(p_note, ''))) < 4 then raise exception 'give a reason (kept in the log)'; end if;
  if f.evidence_id is null or f.content_hash is null then raise exception 'the document has no stored evidence; read it again first'; end if;
  v_src := security.coverage_sweep_source(f.provider_id);
  for x in select o.*, cf.fee_year cur_year from security.provider_fee_proposal_rows(p_source_id) o
    join lateral (select y.fee_year from catalogue.course_fees y where y.course_id = o.course_id and y.fee_type = 'provider_current_tuition' and y.status = 'active' and y.audience = 'international'
                   order by y.fee_year desc nulls last limit 1) cf on true
   where o.outcome = 'differs' and o.fee_year is not null and cf.fee_year is not null and o.fee_year > cf.fee_year loop
    begin
      perform security.coverage_apply_course_v1(x.course_id, v_src, f.evidence_id, f.url, f.content_hash,
        jsonb_build_object('fee_amount', x.amount, 'currency_code', x.currency_code, 'fee_year', x.fee_year, 'fee_basis', x.basis,
          'fee_notes', 'Later-year fee from the provider''s international fee schedule; approved by a Platform Admin'));
      v_n := v_n + 1;
    exception when others then v_err := v_err + 1; v_last := left(sqlerrm, 200);
    end;
  end loop;
  insert into pipeline.admin_control_events(area, action, target, detail, actor)
  values ('fees', 'newer_year_fees_applied', f.url, jsonb_build_object('source_id', f.id, 'provider_id', f.provider_id, 'written', v_n, 'refused', v_err, 'last_error', v_last, 'reason', left(p_note, 500)), auth.uid());
  return jsonb_build_object('written', v_n, 'refused', v_err, 'last_error', v_last);
end $f$;
revoke all on function public.admin_provider_fee_newer_year(text, uuid, text) from public, anon;
grant execute on function public.admin_provider_fee_newer_year(text, uuid, text) to authenticated, service_role;