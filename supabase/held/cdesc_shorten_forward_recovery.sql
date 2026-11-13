-- HELD forward recovery for migration 20261113310000_cf247_cdesc_shorten_by_sentence.sql. Not applied by deploy.
-- Puts security.cdesc_subset_plan_v1 back to the body that migration edited (reverse edits, md5-guarded): no reading is shortened for size again.
-- security.cdesc_sentence_substance_v1, security.cdesc_refers_back_v1 and security.cdesc_refers_within_v1 stay (nothing calls them afterwards). Descriptions already admitted are not touched.
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

select pg_temp.edit_all('security.cdesc_subset_plan_v1(uuid,uuid,jsonb)', '2fd1a050b0e70c0ae9298a0d7419b075', '3c263a1984a33a133a331883cc6f8eae',
  array[$o0$v_page text; v_title text; v_prov text; v_cnt int; v_tot int; v_first int; v_victim int; v_c int; v_bc int; v_p boolean; v_bp boolean; v_rc int; v_rl int; v_f boolean; v_bf boolean;
begin$o0$,
        $o1$  -- 1c. (Platform Admin 13 Nov 2026 12:16, conditional approval) a reading whose ONLY fault is its size (no sentence failed a test) and that is over the sentence or
  --     character limit is shortened by whole sentences, never inside one. Each pass looks at every kept sentence but the first (it says what the course is) together
  --     with the sentences after it that refer back to it (security.cdesc_refers_back_v1: they would dangle, so they go with it), and sets aside the choice that
  --     (a) by itself brings the reading within the limits, before one that does not, then (b) loses least course-specific substance
  --     (security.cdesc_sentence_substance_v1), the later sentence on a tie. A choice that would remove a sentence about a qualification, registration, recognition,
  --     pathway, placement or entry condition is never taken, nor one that a later kept sentence may refer to (security.cdesc_refers_within_v1): if only such
  --     choices are left, nothing more is set aside and the reading stays held below.
  --     Repeated until the reading fits. A reading that cannot fit stays held. A reading with a failing sentence AND a size problem is outside the approval:
  --     it is not shortened here and stays held (over_length_needs_decision).
  if not exists (select 1 from unnest(v_fault) x(f) where x.f is not null) then
    loop
      select count(*), coalesce(sum(length(btrim(coalesce(v_s->(k - 1)->>'text', '')))), 0) + greatest(count(*) - 1, 0), min(k) into v_cnt, v_tot, v_first from generate_series(1, n) k where v_fault[k] is null;
      exit when v_cnt <= 1 or (v_cnt <= v_max and v_tot <= v_maxc);
      v_victim := null;
      for k in reverse n .. v_first + 1 loop
        continue when v_fault[k] is not null;
        v_c := 0; v_p := false; v_rc := 0; v_rl := 0; i := k;
        loop
          v_c := v_c + security.cdesc_sentence_substance_v1(v_s->(i - 1)->>'text', v_s->(i - 1)->>'quote');
          v_rc := v_rc + 1; v_rl := v_rl + length(btrim(coalesce(v_s->(i - 1)->>'text', ''))) + 1;
          -- fixed: a structural test of what a sentence is about (a qualification, registration, recognition, pathway, placement or entry condition), not a tunable limit
          v_p := v_p or coalesce(v_s->(i - 1)->>'text', '') ~* '\m(regist|licen|qualif|recogni|endors|certif|accredit|pathway|eligib|pre-?requisit|placement|practicum|internship|admission|entry requirement|must (hold|have|be|complete))';
          i := i + 1;
          exit when i > n or v_fault[i] is not null or not security.cdesc_refers_back_v1(v_s->(i - 1)->>'text');
        end loop;
        -- a later sentence that stays and says "these", "those", "such" or "this" may refer to this choice: the choice is then not taken (as a protected one)
        v_p := v_p or exists (select 1 from generate_series(i, n) j where v_fault[j] is null and security.cdesc_refers_within_v1(v_s->(j - 1)->>'text'));
        -- does the reading still not fit once this choice is set aside
        v_f := not (v_cnt - v_rc <= v_max and v_tot - v_rl <= v_maxc);
        if v_victim is null or (v_p, v_f, v_c) < (v_bp, v_bf, v_bc) then v_victim := k; v_bp := v_p; v_bf := v_f; v_bc := v_c; end if;
      end loop;
      -- only protected choices are left: nothing more is set aside, the reading stays held
      exit when v_victim is null or v_bp;
      v_fault[v_victim] := 'over_limit';
      for i in v_victim + 1 .. n loop
        exit when v_fault[i] is not null or not security.cdesc_refers_back_v1(v_s->(i - 1)->>'text');
        v_fault[i] := 'depends_on_dropped_sentence';
      end loop;
    end loop;
  end if;
  -- 2. every sentence that passes and was not set aside for size is kept, in its original order. No sentence is ever cut inside: a reading that cannot be brought within the limits by whole sentences stays held
$o1$,
        $o2$'every sentence passes; the reading is over the set sentence or character limit and cannot be brought within it by setting whole sentences aside without losing a protected sentence; it is held whole'$o2$,
        $o3$'the reading is still over the set sentence or character limit (a reading with a failing sentence is not shortened; a size-only reading could not be brought within it by whole sentences); it is held whole'$o3$],
  array[$n0$v_page text; v_title text; v_prov text;
begin$n0$,
        $n1$  -- 2. every sentence that passes is kept, in its original order. Nothing is cut for length or sentence count: a reading whose only fault is its size stays held (the Platform Admin decides that separately)
$n1$,
        $n2$'every sentence passes; the reading is over the set sentence or character limit and is held whole (a decision to cut is not taken here)'$n2$,
        $n3$'after the failing sentences are set aside the remainder is still over the set sentence or character limit; it is held whole (a decision to cut is not taken here)'$n3$]);
