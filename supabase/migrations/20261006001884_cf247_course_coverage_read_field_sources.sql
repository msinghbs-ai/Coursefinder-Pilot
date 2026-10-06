do $p$
declare v_def text; v_new text; v_a text; v_b text; v_w text;
begin
  select pg_get_functiondef(p.oid) into v_def from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='security' and p.proname='admin_course_coverage_read' and p.pronargs=2;
  if v_def is null then raise exception 'security.admin_course_coverage_read not found'; end if;
  if (select md5(p.prosrc) from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='security' and p.proname='admin_course_coverage_read' and p.pronargs=2) <> '76426134291383868b10c64a677f2a0c' then raise exception 'live admin_course_coverage_read differs from the assumed definition'; end if;
  v_w := $w$ where (v_tier is null or s.tier=v_tier) and (v_country is null or s.country_code=v_country) and (v_provider is null or s.provider_id=v_provider) group by 2$w$;
  v_a := $a$      'completeness_state_map',$a$;
  v_b := $b$      -- Who supplied intakes, English and fees (adapter, central page, reader, hand-entered, other, or missing); snapshot rebuilt hourly.
      'field_sources',(select jsonb_agg(jsonb_build_object('field',z.field,'source',z.src,'courses',z.n) order by z.field,z.src) from (
          select 'intakes' field, s.intakes_src src, count(*) n from pipeline.course_field_source s$b$ || v_w || $b$
          union all select 'english', s.english_src, count(*) from pipeline.course_field_source s$b$ || v_w || $b$
          union all select 'fee', s.fee_src, count(*) from pipeline.course_field_source s$b$ || v_w || $b$) z),
      'field_sources_at',(select max(computed_at) from pipeline.course_field_source),
      'completeness_state_map',$b$;
  if (length(v_def)-length(replace(v_def,v_a,'')))<>length(v_a) then raise exception 'anchor not found exactly once'; end if;
  v_new := replace(v_def,v_a,v_b);
  if v_new = v_def then raise exception 'no change made'; end if;
  execute v_new;
end $p$