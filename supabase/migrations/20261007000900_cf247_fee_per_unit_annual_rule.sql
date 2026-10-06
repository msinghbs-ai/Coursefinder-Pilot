-- CF-247, 7 Oct 2026 (Platform Admin: "Annualise per-term + pick annual"): when a course has exactly two annual amounts
-- and the larger is exactly eight times the smaller, the smaller is a per-unit price and the larger is the full-time year.
-- The larger amount is used; the per-unit row is not written. Everything else keeps its outcome.
do $p$
declare v_src text; v_new text; v_a1 text; v_a2 text;
begin
  select prosrc into v_src from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'security' and p.proname = 'provider_fee_proposal_rows';
  if md5(v_src) <> 'f13278b7554585b78a1cbb594e7af946' then raise exception 'provider_fee_proposal_rows changed since this migration was written (%)', md5(v_src); end if;
  v_a1 := 'bool_or(fr.basis = ''annual'') over (partition by fr.course_code) has_annual';
  v_a2 := 'when r.amin <> r.amax then ''several_amounts''';
  if (length(v_src) - length(replace(v_src, v_a1, ''))) <> length(v_a1) or (length(v_src) - length(replace(v_src, v_a2, ''))) <> length(v_a2) then raise exception 'anchor not found exactly once'; end if;
  v_new := replace(v_src, v_a1, v_a1 || E',\n           count(*) over (partition by fr.course_code, fr.basis) rcnt');
  v_new := replace(v_new, v_a2,
    'when r.basis = ''annual'' and r.rcnt = 2 and r.amax = 8 * r.amin and r.amount = r.amin then ''per_unit_row''' || E'\n              ' ||
    'when r.amin <> r.amax and not (r.basis = ''annual'' and r.rcnt = 2 and r.amax = 8 * r.amin) then ''several_amounts''');
  execute 'create or replace function security.provider_fee_proposal_rows(p_source_id uuid) returns table(row_id uuid, course_code text, course_id uuid, course_title text, amount numeric, currency_code text, basis text, fee_year integer, current_amount numeric, current_basis text, outcome text) language sql stable security definer set search_path to '''' as $f$' || v_new || '$f$';
end $p$;