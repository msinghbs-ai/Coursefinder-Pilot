-- CF-247, 7 Oct 2026 (Platform Admin: relabel mislabelled fee years). Some course pages print an indicative fee with no year, and the adapter filed it as the
-- earlier year although it equals the provider's later-year schedule. Two approved schedules (earlier year and later year) are compared: where the page fee on record
-- equals the later schedule's fee, the later-year fee is filed and the earlier schedule's own figure replaces the earlier-year fee. 'preview' writes nothing.
create or replace function public.admin_provider_fee_year_relabel(p_action text, p_source_later uuid, p_source_earlier uuid, p_note text default null)
returns jsonb language plpgsql security definer set search_path to '' as $f$
declare fl pipeline.provider_fact_sources%rowtype; fe pipeline.provider_fact_sources%rowtype; v_rows jsonb; v_all jsonb; x jsonb; v_src uuid; v_n int := 0; v_err int := 0; v_last text;
begin
  if auth.uid() is null or security.current_role_rank() < 6 then raise exception 'Platform Admin role required' using errcode = '42501'; end if;
  if p_action not in ('preview', 'apply') then raise exception 'action must be preview or apply'; end if;
  select * into fl from pipeline.provider_fact_sources where id = p_source_later for update;
  select * into fe from pipeline.provider_fact_sources where id = p_source_earlier for update;
  if fl.id is null or fe.id is null or fl.provider_id <> fe.provider_id or fl.kind <> 'fee_schedule' or fe.kind <> 'fee_schedule'
     or fl.decision is distinct from 'approved' or fe.decision is distinct from 'approved' or fl.status <> 'parsed' or fe.status <> 'parsed' then
    raise exception 'two approved parsed fee schedules of one provider are required'; end if;
  select coalesce(jsonb_agg(jsonb_build_object('course_id', l.course_id, 'title', l.course_title, 'later_amount', l.amount, 'later_year', l.fee_year, 'later_basis', l.basis, 'later_currency', l.currency_code,
         'earlier_amount', e.amount, 'earlier_year', e.fee_year, 'earlier_basis', e.basis, 'earlier_currency', e.currency_code) order by l.course_title), '[]'::jsonb) into v_all
    from security.provider_fee_proposal_rows(p_source_later) l
    join security.provider_fee_proposal_rows(p_source_earlier) e on e.course_id = l.course_id
   where l.fee_year is not null and e.fee_year is not null and l.fee_year > e.fee_year and l.course_id is not null and l.basis = 'annual' and e.basis = 'annual'
     and exists (select 1 from catalogue.course_fees y where y.course_id = l.course_id and y.fee_type = 'provider_current_tuition' and y.status = 'active' and y.audience = 'international'
                 and y.fee_year = e.fee_year and abs(y.amount - l.amount) < 1)
     and abs(e.amount - l.amount) >= 1
     and not exists (select 1 from catalogue.course_fees y where y.course_id = l.course_id and y.fee_type = 'provider_current_tuition' and y.status = 'active' and y.audience = 'international' and y.fee_year = l.fee_year);
  select coalesce(jsonb_agg(el - 'course_id'), '[]'::jsonb) into v_rows from jsonb_array_elements(v_all) el;
  if p_action = 'preview' then return jsonb_build_object('count', jsonb_array_length(v_all), 'rows', v_rows); end if;
  if length(btrim(coalesce(p_note, ''))) < 4 then raise exception 'give a reason (kept in the log)'; end if;
  if fl.evidence_id is null or fe.evidence_id is null or fl.content_hash is null or fe.content_hash is null then raise exception 'both documents need stored evidence'; end if;
  v_src := security.coverage_sweep_source(fl.provider_id);
  for x in select el from jsonb_array_elements(v_all) el loop
    begin
      perform security.coverage_apply_course_v1((x->>'course_id')::uuid, v_src, fe.evidence_id, fe.url, fe.content_hash,
        jsonb_build_object('fee_amount', (x->>'earlier_amount')::numeric, 'currency_code', x->>'earlier_currency', 'fee_year', (x->>'earlier_year')::int, 'fee_basis', x->>'earlier_basis',
          'fee_notes', 'Earlier-year fee from the provider''s international fee schedule; the page figure was the later year; approved by a Platform Admin'));
      perform security.coverage_apply_course_v1((x->>'course_id')::uuid, v_src, fl.evidence_id, fl.url, fl.content_hash,
        jsonb_build_object('fee_amount', (x->>'later_amount')::numeric, 'currency_code', x->>'later_currency', 'fee_year', (x->>'later_year')::int, 'fee_basis', x->>'later_basis',
          'fee_notes', 'Later-year fee from the provider''s international fee schedule; matches the course page; approved by a Platform Admin'));
      v_n := v_n + 1;
    exception when others then v_err := v_err + 1; v_last := left(sqlerrm, 200);
    end;
  end loop;
  insert into pipeline.admin_control_events(area, action, target, detail, actor)
  values ('fees', 'fee_year_relabelled', fl.url, jsonb_build_object('later_source', fl.id, 'earlier_source', fe.id, 'provider_id', fl.provider_id, 'courses', v_n, 'refused', v_err, 'last_error', v_last, 'reason', left(p_note, 500)), auth.uid());
  return jsonb_build_object('courses', v_n, 'refused', v_err, 'last_error', v_last);
end $f$;
revoke all on function public.admin_provider_fee_year_relabel(text, uuid, uuid, text) from public, anon;
grant execute on function public.admin_provider_fee_year_relabel(text, uuid, uuid, text) to authenticated, service_role;
