CREATE OR REPLACE FUNCTION security.cdesc_subset_plan_v1(p_course uuid, p_provider uuid, p_value jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_s jsonb := coalesce(p_value->'sentences', '[]'::jsonb); n int; i int; s jsonb; f jsonb; t text; v_pol text;
        v_min int := greatest(1, security.pipeline_num_v1('enrich.course_description_min_sentences', 1)::int); v_max int := security.pipeline_num_v1('enrich.course_description_max_sentences', 4)::int;
        v_maxc int := security.pipeline_num_v1('enrich.course_description_max_chars', 700)::int; v_sup numeric := security.pipeline_num_v1('pdesc.support_min_share', 0.6);
        v_claim jsonb := coalesce(security.toolset_setting('pipeline', 'enrich.course_description_claim_words'), security.toolset_setting('pipeline', 'pdesc.claim_words'), '[]'::jsonb);
        v_mkt jsonb := coalesce(security.toolset_setting('pipeline', 'enrich.course_description_marketing_words'), security.toolset_setting('pipeline', 'pdesc.superlatives'), '[]'::jsonb);
        v_fault text[]; v_kept int[] := '{}'; v_drop jsonb := '[]'::jsonb; v_len int := 0; v_add int; v_over boolean; v_sents jsonb := '[]'::jsonb; v_chk jsonb; v_orig text; v_page text; v_title text; v_prov text; v_cnt int; v_tot int; v_first int; v_victim int; v_c int; v_bc int; v_p boolean; v_bp boolean; v_rc int; v_rl int; v_f boolean; v_bf boolean;
begin
  if jsonb_typeof(v_s) is distinct from 'array' or jsonb_array_length(v_s) = 0 then return jsonb_build_object('ok', false, 'rule', 'no_sentences', 'reason', 'the reading holds no sentences'); end if;
  n := jsonb_array_length(v_s); v_fault := array_fill(null::text, array[n]);
  -- 0. the bound page must be a page about this course (an institution-level About page never stands in for it)
  select coalesce(security.cdesc_page_kind_v1(g.url, c.canonical_title, g.identity_basis), 'ok') into v_page from pipeline.coverage_course_pages g join catalogue.courses c on c.id = g.course_id where g.course_id = p_course limit 1;
  if not found then v_page := 'no_bound_page'; end if; -- fails closed: no bound page row is no proof of the page
  if v_page <> 'ok' then return jsonb_build_object('ok', false, 'rule', v_page, 'reason', 'the bound page is not a page about this course (' || v_page || ')'); end if;
  -- 1. the sentences that fail a per-sentence test or the machine wording policy. The course's own title and provider are left out of a sentence's tests, exactly as the check does
  --    (security.course_description_check_with_v1), so a sentence the check would refuse is set aside here and not carried into the remainder
  select c.canonical_title, coalesce(p.display_name, p.canonical_name) into v_title, v_prov from catalogue.courses c left join catalogue.providers p on p.id = c.provider_id where c.id = p_course;
  for i in 1 .. n loop
    s := v_s->(i - 1);
    f := security.cdesc_sentence_fault_v1(security.cdesc_known_strip_v1(s->>'text', v_title, v_prov), s->>'quote', coalesce((s->>'on_page')::boolean, false), v_claim, v_mkt, v_sup);
    -- a ten-word run of the page is copied wording whether or not it runs through the course's title: the copy test is also run on the sentence as written
    if f is null then
      f := security.cdesc_sentence_fault_v1(s->>'text', s->>'quote', coalesce((s->>'on_page')::boolean, false), v_claim, v_mkt, v_sup);
      if f->>'rule' is distinct from 'copied_sentence' then f := null; end if;
    end if;
    if f is not null then v_fault[i] := f->>'rule';
    else
      v_pol := security.cdesc_machine_text_check_v1(p_provider, s->>'text', jsonb_build_array(s));
      if v_pol is not null then v_fault[i] := 'policy_' || split_part(v_pol, ':', 1); end if;
    end if;
  end loop;
  -- 1b. a passing sentence that opens by pointing back to the sentence before it, which is set aside, is set aside with it (it would be published as a fragment of it).
  --     In order, so a chain is followed. Only sentences are removed: what is kept is unchanged and goes through the same full check below
  for i in 2 .. n loop
    if v_fault[i] is null and v_fault[i - 1] is not null and security.cdesc_points_back_v1(v_s->(i - 1)->>'text') then v_fault[i] := 'depends_on_dropped_sentence'; end if;
  end loop;
  -- 1c. (Platform Admin 13 Nov 2026 12:16, conditional approval) a reading whose ONLY fault is its size (no sentence failed a test) and that is over the sentence or
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
  for i in 1 .. n loop
    s := v_s->(i - 1); t := btrim(coalesce(s->>'text', ''));
    if v_fault[i] is not null then v_drop := v_drop || jsonb_build_object('index', i, 'text', t, 'cause', v_fault[i]); continue; end if;
    v_add := length(t) + case when cardinality(v_kept) > 0 then 1 else 0 end;
    v_kept := v_kept || i; v_len := v_len + v_add; v_sents := v_sents || s;
  end loop;
  v_over := cardinality(v_kept) > v_max or v_len > v_maxc;
  if jsonb_array_length(v_drop) = 0 then
    if v_over then return jsonb_build_object('ok', false, 'rule', 'over_length_needs_decision', 'reason', 'every sentence passes; the reading is over the set sentence or character limit and cannot be brought within it by setting whole sentences aside without losing a protected sentence; it is held whole'); end if;
    return jsonb_build_object('ok', false, 'rule', 'nothing_to_drop', 'reason', 'every sentence passes: dropping sentences cannot change the outcome');
  end if;
  if cardinality(v_kept) < v_min then return jsonb_build_object('ok', false, 'rule', 'remainder_below_minimum', 'reason', cardinality(v_kept) || ' sentence(s) are left, fewer than the set minimum', 'dropped', v_drop); end if;
  -- 2a. (13 Nov 2026, read of 20 recovered descriptions) the opening sentence says what the course is. A remainder without it reads as a fragment
  --     ("Assessment includes written tasks ..."), so a reading whose first sentence was set aside is not recovered: it stays held
  if not (1 = any (v_kept)) then return jsonb_build_object('ok', false, 'rule', 'opening_sentence_dropped', 'reason', 'the opening sentence, which says what the course is, was set aside; what is left would read as a fragment, so the reading is held whole', 'dropped', v_drop); end if;
  if v_over then return jsonb_build_object('ok', false, 'rule', 'over_length_needs_decision', 'reason', 'the reading is still over the set sentence or character limit (a reading with a failing sentence is not shortened; a size-only reading could not be brought within it by whole sentences); it is held whole', 'dropped', v_drop); end if;
  -- 3. a kept sentence that points back to the sentence before it, which was set aside for a fault, would be published as a fragment of it (the opener list is wider than pronouns: QA, 10 Nov 2026)
  for i in 2 .. n loop
    continue when not (i = any (v_kept)) or v_fault[i - 1] is null;
    -- fixed: a structural test of the grammar (a sentence that opens with a pronoun, a connecting word, "the program" or a quote or bracket), not a tunable limit
    if security.cdesc_points_back_v1(v_s->(i - 1)->>'text') then
      return jsonb_build_object('ok', false, 'rule', 'depends_on_dropped_sentence', 'reason', 'sentence ' || i || ' opens by pointing back to sentence ' || (i - 1) || ', which is set aside', 'dropped', v_drop);
    end if;
  end loop;
  -- 4. the remainder goes through the SAME full check and the machine wording policy
  v_chk := security.course_description_check_v1(p_course, p_value || jsonb_build_object('sentences', v_sents));
  if not coalesce((v_chk->>'ok')::boolean, false) then return jsonb_build_object('ok', false, 'rule', 'remainder_' || coalesce(v_chk->>'rule', 'failed'), 'reason', v_chk->>'reason', 'dropped', v_drop); end if;
  v_pol := security.cdesc_machine_text_check_v1(p_provider, v_chk->>'text', v_sents);
  if v_pol is not null then return jsonb_build_object('ok', false, 'rule', 'remainder_policy_' || split_part(v_pol, ':', 1), 'reason', v_pol, 'dropped', v_drop); end if;
  select string_agg(btrim(x->>'text'), ' ' order by o) into v_orig from jsonb_array_elements(v_s) with ordinality e(x, o);
  return jsonb_build_object('ok', true, 'text', v_chk->>'text', 'sentences', v_sents, 'check', v_chk,
    'subset', jsonb_build_object('rule', 'subset_of_reading', 'original_count', n, 'kept_count', cardinality(v_kept), 'kept', to_jsonb(v_kept), 'dropped', v_drop,
                                 'original', jsonb_build_object('sentences', v_s, 'text', v_orig, 'check', p_value->'check')));
end $function$
