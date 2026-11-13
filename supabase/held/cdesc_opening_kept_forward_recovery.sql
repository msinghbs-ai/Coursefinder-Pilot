-- HELD forward recovery for migration 20261113320000_cf247_cdesc_opening_sentence_kept.sql. Not applied by deploy.
-- Puts security.cdesc_subset_plan_v1 back to the body that migration edited (reverse edit, md5-guarded): a reading whose first sentence was set aside can be recovered again.
-- Replaces: the body named above. Retires: nothing.

create or replace function pg_temp.edit_all(p_sig text, p_before text, p_after text, p_olds text[], p_news text[]) returns text language plpgsql as $f$
declare v_def text := pg_get_functiondef(p_sig::regprocedure); v_src text := (select p.prosrc from pg_proc p where p.oid = p_sig::regprocedure); v_c int; i int;
begin
  -- fixed: the guard is the md5 of the function body (pg_proc.prosrc), the same text on PostgreSQL 16 and 17
  if md5(v_src) = p_after then return p_sig || ': already applied'; end if;
  if md5(v_src) <> p_before then raise exception 'live % differs from the definition this change replaces (body md5 %)', p_sig, md5(v_src); end if;
  -- fixed: line endings are normalised, so the edit applies the same however the text arrives
  v_def := replace(v_def, chr(13), '');
  for i in 1 .. array_length(p_olds, 1) loop
    v_c := (length(v_def) - length(replace(v_def, p_olds[i], ''))) / length(p_olds[i]);
    if v_c <> 1 then raise exception '%: edit % must apply exactly once (found %)', p_sig, i, v_c; end if;
    v_def := replace(v_def, p_olds[i], p_news[i]);
  end loop;
  execute v_def;
  v_src := (select p.prosrc from pg_proc p where p.oid = p_sig::regprocedure);
  if md5(v_src) <> p_after then raise exception '% after the edit has body md5 %, expected %', p_sig, md5(v_src), p_after; end if;
  return p_sig || ': applied';
end $f$;

select pg_temp.edit_all('security.cdesc_subset_plan_v1(uuid,uuid,jsonb)', '89e86ee2fe13eb582d7cac0f1ed4f7fa', '2fd1a050b0e70c0ae9298a0d7419b075',
  array[$o0$  if cardinality(v_kept) < v_min then return jsonb_build_object('ok', false, 'rule', 'remainder_below_minimum', 'reason', cardinality(v_kept) || ' sentence(s) are left, fewer than the set minimum', 'dropped', v_drop); end if;
  -- 2a. (13 Nov 2026, read of 20 recovered descriptions) the opening sentence says what the course is. A remainder without it reads as a fragment
  --     ("Assessment includes written tasks ..."), so a reading whose first sentence was set aside is not recovered: it stays held
  if not (1 = any (v_kept)) then return jsonb_build_object('ok', false, 'rule', 'opening_sentence_dropped', 'reason', 'the opening sentence, which says what the course is, was set aside; what is left would read as a fragment, so the reading is held whole', 'dropped', v_drop); end if;
$o0$],
  array[$n0$  if cardinality(v_kept) < v_min then return jsonb_build_object('ok', false, 'rule', 'remainder_below_minimum', 'reason', cardinality(v_kept) || ' sentence(s) are left, fewer than the set minimum', 'dropped', v_drop); end if;
$n0$]);
