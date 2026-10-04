-- CF-247 Decision 254 (5 Oct 2026). The measures reported after each adapter wave, worked out the same way every time:
-- for each university, pages read, and what its adapter read itself (intakes, fees, IELTS, extra fields) compared with
-- what the catalogue holds (agree, differ, new). Read-only. Used for the wave reports and the admin documents.
-- No text value in this file contains a semicolon.

create or replace function public.admin_adapter_measures(p_provider_ids uuid[]) returns jsonb
language plpgsql stable security definer set search_path = '' as $f$
declare v_rank int := security.current_role_rank();
begin
  if current_user <> 'postgres' and (auth.uid() is null or coalesce(v_rank, 0) < 5) then raise exception 'Platform Admin or Operator required' using errcode = '42501'; end if;
  return coalesce((select jsonb_agg(x order by x->>'name') from (
    select jsonb_build_object('provider_id', p.id, 'name', coalesce(p.display_name, p.canonical_name), 'country', security.coverage_country(p.id),
      'adapter', (select case when not u.enabled then 'off' when u.admit then 'admitting' else 'testing' end from pipeline.uni_adapters u where u.provider_id = p.id),
      'pages_read', count(*),
      'intakes', count(*) filter (where q.ia), 'intakes_agree', count(*) filter (where q.ia and q.held_itk = q.ad_itk), 'intakes_differ', count(*) filter (where q.ia and q.held_itk is not null and q.held_itk <> q.ad_itk), 'intakes_new', count(*) filter (where q.ia and q.held_itk is null),
      'fees', count(*) filter (where q.fa), 'fees_equal', count(*) filter (where q.fa and q.fee_held), 'fees_differ', count(*) filter (where q.fa and not q.fee_held and q.any_fee), 'fees_new', count(*) filter (where q.fa and not q.any_fee),
      'ielts', count(*) filter (where q.ea), 'extra', count(*) filter (where q.xa)) x
    from catalogue.providers p
    join lateral (
      select pg.candidates->>'intakes_by' = 'adapter' ia, pg.candidates->>'fee_by' = 'adapter' fa, pg.candidates->>'english_by' = 'adapter' ea, pg.candidates ? 'adapter_extra' xa,
             (select array_agg(distinct m order by m) from jsonb_array_elements_text(coalesce(pg.candidates->'intakes', '[]'::jsonb)) m) ad_itk,
             (select array_agg(distinct i.intake_label order by i.intake_label) from catalogue.course_intakes i where i.course_id = pg.course_id and i.status = 'active') held_itk,
             exists (select 1 from catalogue.course_fees f where f.course_id = pg.course_id and f.status = 'active' and f.fee_type = 'provider_current_tuition' and f.audience = 'international' and f.amount = nullif(pg.candidates->'fee'->>'value', '')::numeric) fee_held,
             exists (select 1 from catalogue.course_fees f where f.course_id = pg.course_id and f.status = 'active' and f.fee_type = 'provider_current_tuition' and f.audience = 'international') any_fee
        from pipeline.coverage_course_pages pg where pg.provider_id = p.id and pg.read_status = 'read') q on true
    where p.id = any (p_provider_ids)
    group by p.id) s), '[]'::jsonb);
end $f$;
revoke all on function public.admin_adapter_measures(uuid[]) from public, anon;
grant execute on function public.admin_adapter_measures(uuid[]) to authenticated;
