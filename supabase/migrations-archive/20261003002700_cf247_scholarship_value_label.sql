-- CF-247 (3 Oct 2026, 23:00 AEST). Decision 248. The value counsellors see is built from the recorded value, never from
-- page text: some records hold a fragment of the page as award_value_text ("rnational Study level Undergraduate …"),
-- and that fragment reached the course attribute and the Zoho read. scholarship.value_label(id) gives:
--   percentage   → "20% of tuition fees" ("Up to 50% …" when the page says up to; "% off fees" when what it applies to
--                  is not stated), with "for the course" / "a semester" when the page states how long;
--   fixed amount → "A$10,000 a year" / "A$5,000 one-off" / "A$5,000" (period as recorded; other currencies by code);
--   page tiers   → the range written by Decision 245 ("20% to 70% of tuition fees");
--   otherwise    → null (shown as "Value not stated"; such a record is not publishable).
-- The course attribute (both projection functions) and the Zoho scholarships read now carry this label as
-- award_value_text; the page's wording stays on the record and in the evidence. Replaced under md5 guards.
create or replace function scholarship.value_label(p_id uuid)
returns text language sql stable security definer set search_path to 'pg_catalog', 'scholarship' as $f$
  select case
    when s.award_value_type = 'percentage' and s.award_percentage is not null then
      case when s.award_value_is_maximum then 'Up to ' else '' end
      || trim(to_char(s.award_percentage, 'FM990.##'), '.') || '%'
      || case when s.award_applies_to_fee_type = 'tuition_fee' then ' of tuition fees' else ' off fees' end
      || case s.award_duration_basis when 'program_duration' then ' for the course' when 'annual_program_duration' then ' for the course' when 'per_semester' then ' a semester' when 'one_off' then ', one-off' else '' end
    when s.award_value_type = 'fixed_amount' and s.award_amount is not null then
      case when s.award_value_is_maximum then 'Up to ' else '' end
      || case when coalesce(s.award_currency_code, 'AUD') = 'AUD' then 'A$' else s.award_currency_code || ' ' end
      || to_char(s.award_amount, 'FM999,999,999')
      || case s.award_duration_basis when 'annual' then ' a year' when 'annual_program_duration' then ' a year for the course' when 'one_off' then ' one-off' when 'per_semester' then ' a semester' when 'program_duration' then ' for the course' else '' end
    when exists (select 1 from scholarship.award_tiers t where t.scholarship_id = s.id and t.tier_code like 'page_tier_%') then s.award_value_text
    else null end
  from scholarship.scholarships s where s.id = p_id
$f$;
grant execute on function scholarship.value_label(uuid) to authenticated, service_role;

do $g$ declare v_oid oid; v_def text; begin
  for v_oid in select p.oid from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'search' and p.proname in ('refresh_course_enrichment_core_v1', 'refresh_course_enrichment_core_scoped_v1') loop
    if (select md5(prosrc) from pg_proc where oid = v_oid) not in ('396764add7bbfad4c3e494d941b45c2e', '47d94e7b2ffd6bbabda7c4da14c564c3') then raise exception 'projection function % changed; not replacing', v_oid; end if;
    v_def := pg_get_functiondef(v_oid);
    if (length(v_def) - length(replace(v_def, $x$'name',s.name,'award_value_text',s.award_value_text,$x$, ''))) / length($x$'name',s.name,'award_value_text',s.award_value_text,$x$) <> 1 then raise exception 'projection value key not found exactly once in %', v_oid; end if;
    execute replace(v_def, $x$'name',s.name,'award_value_text',s.award_value_text,$x$, $x$'name',s.name,'award_value_text',scholarship.value_label(s.id),$x$);
  end loop;
  select p.oid into v_oid from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'public' and p.proname = 'zoho_edge_scholarships_v1';
  if (select md5(prosrc) from pg_proc where oid = v_oid) is distinct from '950654ebf9cb2777c797ae2826e40c67' then raise exception 'zoho_edge_scholarships_v1 changed; not replacing'; end if;
  v_def := pg_get_functiondef(v_oid);
  if (length(v_def) - length(replace(v_def, $x$'text', s.award_value_text,$x$, ''))) / length($x$'text', s.award_value_text,$x$) <> 1 then raise exception 'zoho value text not found exactly once'; end if;
  execute replace(v_def, $x$'text', s.award_value_text,$x$, $x$'text', scholarship.value_label(s.id),$x$);
end $g$;

select security.scholarship_course_attribute_sync_v1(true);
