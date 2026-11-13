-- HELD forward recovery for migration 20261113310000_cf247_cdesc_shorten_by_sentence.sql. Not applied by deploy.
-- Puts security.cdesc_subset_plan_v1 back to the body that migration edited (reverse edits, md5-guarded): no reading is shortened for size again.
-- security.cdesc_sentence_substance_v1 stays (nothing calls it afterwards). Descriptions already admitted are not touched.
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

select pg_temp.edit_all('security.cdesc_subset_plan_v1(uuid,uuid,jsonb)', '3d6fc72b6736b7c58a0eaf85e93dc460', '3c263a1984a33a133a331883cc6f8eae',
  array[$o0$  -- 1c. (Platform Admin 13 Nov 2026 12:16, conditional approval) a reading still over the sentence or character limit is shortened by whole sentences, never inside one.
  --     The kept sentence with the least course-specific substance (security.cdesc_sentence_substance_v1: the fewest distinct words that are also in its own quote) is set aside,
  --     the later one on a tie, and never the first kept sentence (it says what the course is). A sentence that then points back to it goes with it, as in 1b.
  --     Repeated until the reading fits. If it cannot fit (one sentence left and still too long) nothing more is set aside and the reading stays held below.
  loop
    select count(*), coalesce(sum(length(btrim(coalesce(v_s->(k - 1)->>'text', '')))), 0) + greatest(count(*) - 1, 0) into v_cnt, v_tot from generate_series(1, n) k where v_fault[k] is null;
    exit when v_cnt <= 1 or (v_cnt <= v_max and v_tot <= v_maxc);
    v_victim := null;
    select k into v_victim from generate_series(1, n) k
     where v_fault[k] is null and k > (select min(k2) from generate_series(1, n) k2 where v_fault[k2] is null)
     order by security.cdesc_sentence_substance_v1(v_s->(k - 1)->>'text', v_s->(k - 1)->>'quote'), k desc limit 1;
    exit when v_victim is null;
    v_fault[v_victim] := 'over_limit';
    for i in v_victim + 1 .. n loop
      exit when v_fault[i] is not null or not security.cdesc_points_back_v1(v_s->(i - 1)->>'text');
      v_fault[i] := 'depends_on_dropped_sentence';
    end loop;
  end loop;
  -- 2. every sentence that passes and was not set aside for size is kept, in its original order. No sentence is ever cut inside: a reading that cannot be brought within the limits by whole sentences stays held
$o0$,
        $o1$v_page text; v_title text; v_prov text; v_cnt int; v_tot int; v_victim int;
begin$o1$],
  array[$n0$  -- 2. every sentence that passes is kept, in its original order. Nothing is cut for length or sentence count: a reading whose only fault is its size stays held (the Platform Admin decides that separately)
$n0$,
        $n1$v_page text; v_title text; v_prov text;
begin$n1$]);
