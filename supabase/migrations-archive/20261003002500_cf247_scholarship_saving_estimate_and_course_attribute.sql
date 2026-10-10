-- CF-247 (3 Oct 2026, 22:30 AEST). Decision 247. Platform Admin, 21:43 and multiple choice 21:50:
-- (1) Saving per year for Australian courses: where no annual international tuition fee from the provider is recorded,
--     estimate it from the registered CRICOS course cost — registered total course tuition ÷ registered duration in years
--     (at least one year) — and work out the saving from that, recorded with fee basis
--     'estimated_annual_from_registered_total' and shown as an estimate. A provider's annual fee (Decision 212, and
--     Decision 242 when built) always comes first and replaces the estimate on the next nightly run.
-- (2) The course attribute: a course's scholarships (search projection, website, Zoho) are the scholarships linked to
--     it by decided course links, published, and open to international students — each with its value, audience,
--     nationalities, close date, page and saving per year (and its basis) — instead of every scholarship scoped to the
--     whole provider. Both projection functions are replaced under md5 guards; the calculation function too.
do $g$ declare v_oid oid; v_def text; v_old text; v_new text; begin
  -- 1. the saving calculation
  select p.oid into v_oid from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'scholarship' and p.proname = 'refresh_course_financial_calculation';
  if (select md5(prosrc) from pg_proc where oid = v_oid) is distinct from '7a25e441c1cb3d300d22a4bb4a5bbc32' then raise exception 'refresh_course_financial_calculation changed; not replacing'; end if;
  v_def := pg_get_functiondef(v_oid);
  v_old := $x$  v_result scholarship.course_financial_calculations%rowtype;
begin$x$;
  v_new := $x$  v_result scholarship.course_financial_calculations%rowtype;
  v_years numeric;
  v_est numeric(14,2);
begin$x$;
  if (length(v_def) - length(replace(v_def, v_old, ''))) / length(v_old) <> 1 then raise exception 'declare block not found exactly once'; end if;
  v_def := replace(v_def, v_old, v_new);
  v_old := $x$    if v_fee.id is null then
      v_status:='fee_not_found'; v_reason:='No annual international tuition fee is recorded for this course.';$x$;
  v_new := $x$    if v_fee.id is null then
      -- Decision 247: no annual fee from the provider; estimate one from the registered CRICOS course cost
      select f.* into v_fee from catalogue.course_fees f join pipeline.sources src on src.id = f.source_id
       where f.course_id = v_map.course_id and f.audience in ('international', 'all') and f.fee_type = 'tuition' and f.basis = 'registered_total_course'
         and src.label = 'CRICOS Providers, Courses and Locations' and f.amount > 0 and coalesce(f.status, 'active') = 'active'
       order by f.updated_at desc nulls last, f.id limit 1;
      select case c.duration_unit when 'weeks' then c.duration_value / 52.0 when 'months' then c.duration_value / 12.0 when 'years' then c.duration_value end
        into v_years from catalogue.courses c where c.id = v_map.course_id;
      if v_fee.id is null or coalesce(v_years, 0) <= 0 then
        v_fee := null; v_status:='fee_not_found'; v_reason:='No annual international tuition fee is recorded for this course, and no registered course cost and duration to estimate one.';
      elsif v_s.award_currency_code is not null and v_s.award_currency_code <> v_fee.currency_code then
        v_status:='currency_mismatch'; v_reason:='Scholarship and Course fee currencies differ.';
      else
        v_est := round(v_fee.amount / greatest(v_years, 1), 2);
        v_saving := round(v_est * (v_s.award_percentage / 100.0), 2);
        v_net := round(v_est - v_saving, 2);
        v_formula := 'estimated annual tuition = registered total course tuition / registered duration in years (at least 1); saving = estimate * (award_percentage / 100), per year';
        v_status := 'calculated';
        v_reason := 'Estimated from the registered CRICOS course cost (Decision 247); replaced by the provider''s annual fee when one is recorded.';
      end if;$x$;
  if (length(v_def) - length(replace(v_def, v_old, ''))) / length(v_old) <> 1 then raise exception 'fee_not_found branch not found exactly once'; end if;
  v_def := replace(v_def, v_old, v_new);
  v_old := $x$coalesce(v_s.award_currency_code,v_fee.currency_code),v_fee.amount,v_fee.fee_type,
    case when v_fee.id is not null then 'annual' end,v_fee.fee_year,$x$;
  v_new := $x$coalesce(v_s.award_currency_code,v_fee.currency_code),coalesce(v_est,v_fee.amount),v_fee.fee_type,
    case when v_est is not null then 'estimated_annual_from_registered_total' when v_fee.id is not null then 'annual' end,v_fee.fee_year,$x$;
  if (length(v_def) - length(replace(v_def, v_old, ''))) / length(v_old) <> 1 then raise exception 'insert values not found exactly once'; end if;
  execute replace(v_def, v_old, v_new);

  -- 2. the course attribute, in both projection functions
  v_old := $x$    select jsonb_agg(distinct jsonb_build_object('scholarship_key',s.stable_key,'name',s.name,'award_value_text',s.award_value_text,'academic_year',s.academic_year,'application_close_date',s.application_close_date,'source_url',s.source_url)) options,
      string_agg(distinct s.name,' ' order by s.name) semantic_text
    from scholarship.scopes ss join scholarship.scholarships s on s.id=ss.scholarship_id
    where s.lifecycle_status='active' and s.publication_status in ('published','internal')
      and coalesce(ss.include_exclude,'include')='include'
      and ((ss.scope_type='course' and ss.course_id=d.course_id) or (ss.scope_type='provider' and ss.provider_id=d.provider_id))$x$;
  v_new := $x$    select jsonb_agg(jsonb_build_object('scholarship_key',s.stable_key,'name',s.name,'award_value_text',s.award_value_text,'academic_year',s.academic_year,'application_close_date',s.application_close_date,'source_url',s.source_url,
             'audience',s.audience,'nationalities',s.nationalities,'is_maximum',s.award_value_is_maximum,
             'saving_per_year',fc.scholarship_saving_amount,'saving_currency',fc.currency_code,'saving_basis',fc.fee_basis)
             order by fc.scholarship_saving_amount desc nulls last, s.name) options,
      string_agg(s.name,' ' order by s.name) semantic_text
    from scholarship.course_mappings cm join scholarship.scholarships s on s.id=cm.scholarship_id
    left join scholarship.course_financial_calculations fc on fc.mapping_id=cm.id and fc.calculation_status='calculated'
    where cm.course_id=d.course_id and cm.mapping_state='mapped'
      and s.lifecycle_status='active' and s.publication_status in ('published','internal')
      and s.audience in ('international','international_and_domestic')$x$;
  for v_oid in select p.oid from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'search' and p.proname in ('refresh_course_enrichment_core_v1', 'refresh_course_enrichment_core_scoped_v1') loop
    if (select md5(prosrc) from pg_proc where oid = v_oid) not in ('0722fc0c8ad86ddacc56feac1eaab8bd', '77d6ca62f9d5cd1e4cc806010fe66474') then raise exception 'projection function % changed; not replacing', v_oid; end if;
    v_def := pg_get_functiondef(v_oid);
    if (length(v_def) - length(replace(v_def, v_old, ''))) / length(v_old) <> 1 then raise exception 'scholarship lateral not found exactly once in %', v_oid; end if;
    execute replace(v_def, v_old, v_new);
  end loop;
end $g$;

-- the Zoho read says whether a saving is an estimate
do $g$ declare v_oid oid; v_def text; begin
  select p.oid into v_oid from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'public' and p.proname = 'zoho_edge_scholarships_v1';
  if (select md5(prosrc) from pg_proc where oid = v_oid) is distinct from '3ca36e664656051bf2fb100401bfcbf4' then raise exception 'zoho_edge_scholarships_v1 changed; not replacing'; end if;
  v_def := pg_get_functiondef(v_oid);
  if (length(v_def) - length(replace(v_def, $x$'net', fc.net_fee_amount)$x$, ''))) / length($x$'net', fc.net_fee_amount)$x$) <> 1 then raise exception 'zoho saving object not found exactly once'; end if;
  execute replace(v_def, $x$'net', fc.net_fee_amount)$x$, $x$'net', fc.net_fee_amount, 'basis', fc.fee_basis, 'estimate', fc.fee_basis = 'estimated_annual_from_registered_total')$x$);
end $g$;
