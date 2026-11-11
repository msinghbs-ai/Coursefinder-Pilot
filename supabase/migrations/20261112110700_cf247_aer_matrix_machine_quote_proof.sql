-- CF-247 F-AER.04 machine admission of country tables and qualification rows (Platform Admin decision D1, 11 Nov 2026): the published minimum must be in the row's own quote.
-- D1: "exact published minimum and grade scale ... Do not infer ... missing scores. Keep unsupported, ambiguous or conflicting rows in Layer 4."
-- Guards: G1 (no job added), G2 (no new value), G3 (no consumer API object read or changed), Decision 260 (housekeeping), "a passing qualification never switches anything on by itself".
-- Evidence (production, read only, 11 Nov 2026 21:00 AEDT): the first validation of rule aer-matrix-machine-v1 (security.aer_matrix_machine_validate_v1, rolled back) did not
--   pass: of 34 entry-matrix items people decided, the rule would admit 27; people approved 26 and rejected one, a6e3bcb2 (ANU, Austrian Maturity Certificate, 31 Oct 2026:
--   "proposes only one row, reverses printed entrance rank 70 and indicative score 3.3, and cites generic introduction rather than table"). Its one row's quote is the page's
--   introduction; neither its minimum (70) nor its band (3.3) is in it. The rule checked the quote's length, not that it proves the minimum.
-- What: security.aer_quote_has_value_v1 NEW (the minimum grade text, or the minimum value, appears in the quote as a whole token); security.aer_matrix_machine_check_v1
--   (md5-guarded edit): a proposed country or qualification row whose quote does not carry its published minimum fails row_minimum_not_in_quote and the item stays with a person;
--   security.aer_matrix_machine_validate_v1 (md5-guarded edit): its replay of past human decisions applies the same row rule, so validation measures the rule that admits.
--   Live dry run (rolled back) with both edits: history 34 human decisions, the rule would admit 25, all 25 approved by a person (0 disagreements; a6e3bcb2 now declined);
--   shadow 20 results, 8 would admit, 0 regressions on re-check: the validation passes. A pass switches nothing on.
-- Live definitions this change edits (pg_proc.prosrc md5, read 11 Nov 2026 21:05 AEDT), before -> after:
--   security.aer_matrix_machine_check_v1(uuid) 6eece704435e4c72cdbcbccc683b194f -> 8b25b3dcb246a08561dd0ebd48f0ff37
--   security.aer_matrix_machine_validate_v1() c4cb5e0f02bcee4b04c5bb0702c2a8c7 -> 5c9d6e287b60f1a48fb28f71f4c3dba3
-- Replaces: security.aer_matrix_machine_check_v1, security.aer_matrix_machine_validate_v1 (same names; md5-guarded text edit, resulting md5 checked); taken back by supabase/held/aer_matrix_machine_quote_proof_forward_recovery.sql
-- Retires: nothing.

do $g$ begin
  if to_regprocedure('security.aer_matrix_machine_check_v1(uuid)') is null or to_regprocedure('security.aer_matrix_machine_validate_v1()') is null then raise exception 'a function this change edits is missing'; end if;
end $g$;

create or replace function security.aer_quote_has_value_v1(p_quote text, p_grade text, p_value numeric)
returns boolean language sql immutable set search_path = '' as $f$
  -- the published minimum is in the quote as a whole token: the grade text when the row has one, otherwise the value (70, 3.3; never 170 or 3.35)
  select case when nullif(btrim(coalesce(p_grade, '')), '') is not null
              then coalesce(p_quote, '') ~* ('(^|[^0-9A-Za-z.])' || regexp_replace(btrim(p_grade), '([.*+?^${}()|\[\]\\])', '\\\1', 'g') || '($|[^0-9A-Za-z])')
              when p_value is not null
              then coalesce(p_quote, '') ~ ('(^|[^0-9.])' || replace(trim_scale(p_value)::text, '.', '\.') || '($|[^0-9])')
              else false end
$f$;
comment on function security.aer_quote_has_value_v1(text, text, numeric) is 'CF-247 F-AER.04 D1: true when a row''s published minimum (grade text, or value) is in its quote as a whole token.';

do $m$
declare r record; v_def text; v_src text; v_c int; k int; v_sig regprocedure;
begin
  for r in select * from (values
    ('security.aer_matrix_machine_check_v1(uuid)', '6eece704435e4c72cdbcbccc683b194f', '8b25b3dcb246a08561dd0ebd48f0ff37',
     array[$o$                when not ((m.min_value is not null and coalesce(m.grade_scale, 'none') <> 'none') or nullif(btrim(coalesce(m.min_grade, '')), '') is not null) then 'no_minimum' end why$o$,
           $o$                when not ((q.min_value is not null and coalesce(q.grade_scale, 'none') <> 'none') or nullif(btrim(coalesce(q.min_grade, '')), '') is not null) then 'no_minimum' end$o$],
     array[$n$                when not ((m.min_value is not null and coalesce(m.grade_scale, 'none') <> 'none') or nullif(btrim(coalesce(m.min_grade, '')), '') is not null) then 'no_minimum'
                when not security.aer_quote_has_value_v1(m.quote, m.min_grade, m.min_value) then 'minimum_not_in_quote' end why$n$,
           $n$                when not ((q.min_value is not null and coalesce(q.grade_scale, 'none') <> 'none') or nullif(btrim(coalesce(q.min_grade, '')), '') is not null) then 'no_minimum'
                when not security.aer_quote_has_value_v1(q.quote, q.min_grade, q.min_value) then 'minimum_not_in_quote' end$n$]),
    ('security.aer_matrix_machine_validate_v1()', 'c4cb5e0f02bcee4b04c5bb0702c2a8c7', '5c9d6e287b60f1a48fb28f71f4c3dba3',
     array[$o$                                  or not ((m.min_value is not null and coalesce(m.grade_scale, 'none') <> 'none') or nullif(btrim(coalesce(m.min_grade, '')), '') is not null)))$o$],
     array[$n$                                  or not ((m.min_value is not null and coalesce(m.grade_scale, 'none') <> 'none') or nullif(btrim(coalesce(m.min_grade, '')), '') is not null)
                                  or not security.aer_quote_has_value_v1(m.quote, m.min_grade, m.min_value)))$n$])
  ) v(sig, md5_before, md5_after, olds, news) loop
    v_sig := to_regprocedure(r.sig);
    v_src := (select p.prosrc from pg_proc p where p.oid = v_sig);
    -- fixed: the guard is the md5 of the live function body (pg_proc.prosrc), the same text on PostgreSQL 16 and 17
    if md5(v_src) = r.md5_after then raise notice '%: already applied', r.sig; continue; end if;
    if md5(v_src) <> r.md5_before then raise exception 'live % differs from the definition this change edits (body md5 %)', r.sig, md5(v_src); end if;
    v_def := replace(pg_get_functiondef(v_sig), chr(13), '');
    for k in 1 .. array_length(r.olds, 1) loop
      v_c := (length(v_def) - length(replace(v_def, r.olds[k], ''))) / length(r.olds[k]);
      if v_c <> 1 then raise exception '%: edit % must apply exactly once (found %)', r.sig, k, v_c; end if;
      v_def := replace(v_def, r.olds[k], r.news[k]);
    end loop;
    execute v_def;
    v_src := (select p.prosrc from pg_proc p where p.oid = v_sig);
    if md5(v_src) <> r.md5_after then raise exception '% after the edit has body md5 %, expected %', r.sig, md5(v_src), r.md5_after; end if;
    raise notice '%: applied', r.sig;
  end loop;
end $m$;

insert into pipeline.component_register(kind, name, layer, purpose, status, replaces, introduced_in) values
 ('function', 'security.aer_quote_has_value_v1', 'Layer 2', 'D1: a row''s published minimum is in its quote', 'active', '{}', '20261112110700')
on conflict do nothing;

do $post$ begin
  if position('minimum_not_in_quote' in (select p.prosrc from pg_proc p where p.oid = 'security.aer_matrix_machine_check_v1(uuid)'::regprocedure)) = 0 then raise exception 'post-check: the quote proof is not checked'; end if;
  if position('aer_quote_has_value_v1' in (select p.prosrc from pg_proc p where p.oid = 'security.aer_matrix_machine_validate_v1()'::regprocedure)) = 0 then raise exception 'post-check: the validation replays another rule'; end if;
  if not security.aer_quote_has_value_v1('IB Diploma 24 points', null, 24) or security.aer_quote_has_value_v1('IB Diploma 124 points', null, 24)
     or security.aer_quote_has_value_v1('Please see the table below', '70', null) or not security.aer_quote_has_value_v1('Entrance rank 70 | 3.3', '70', null) then
    raise exception 'post-check: the quote proof misjudges a value'; end if;
end $post$;
