-- CF-247 s1053 (S1-Build; Platform Admin 24 Nov 2026 17:14 AEDT, "Approved: register official URLs and complete Item 2"; UAT feedback-4 for
-- Adelaide University and The University of Newcastle): the official 2027 fee lists, English language procedures and scholarship terms are
-- registered and read through the existing readers, the universities' published English test equivalence tables reach their courses, and a GPA
-- threshold that states its scale as "on a 7.0 scale" is read as stated.
-- Found live (rolled back, 24 Nov 2026 17:20 to 18:10 AEDT; head 20261124234000):
--   * Fees: Adelaide holds 207 course fees, all 2026; Newcastle 229, all 2026. Their 2027 lists were not stored. The fee reader (job fee-reader,
--     worker mode fee_ai, pinned model) reads each stored fee page and records each row's printed fee year.
--   * English: both approved policies give IELTS only. Adelaide's admissions page publishes a table of tests "equivalent to IELTS" (overall and
--     subscores); Newcastle's English Language Proficiency Procedure (effective 26 March 2026) publishes Table 1 (overall and section
--     equivalences). Neither table was read into course rows.
--   * Scholarships: Adelaide's university-wide merit awards state "GPA of 4.5 (on a 7.0 scale)" and similar; security.gpa_scale_of_v1 only knew
--     "out of N" and "/N", so s1021 held them as stating no scale. Newcastle's Vice-Chancellor's International Academic Merit Scholarship 2027
--     terms give "4.5 / 7 GPA in an eligible qualification (for postgraduate students)"; its International Excellence 2027 terms give no entry
--     GPA (only a 4.0 pass GPA to keep it).
-- What changes (live on deploy):
--   1. Registered (found_via manual, the Platform Admin's approval in each event): Adelaide's 2027 International Student Guide (fee_schedule),
--      Newcastle's 2027 undergraduate and postgraduate international course fee lists (fee_schedule) and English Language Proficiency Procedure
--      (english_policy); Adelaide's English language proficiency page is read again. They are fetched by the existing governed queue
--      (pipeline.elr_central_fetches, sent by job elr-det-sweep, Firecrawl, one on-demand request 'claude_session' scoped to central). The fee
--      reader then reads the stored fee pages by its own rules; nothing here writes a fee.
--      Newcastle's two scholarship terms documents are offered to the scholarship reader as registered pages of their awards.
--   2. security.gpa_scale_of_v1 also reads "on a N scale" and "N-point scale". Open "Scholarship GPA scale" reviews whose own text now states a
--      scale that the threshold fits are settled by that statement (scale written to value_json, criterion admitted, review closed and logged);
--      the others stay open.
--   3. pipeline.english_concordance holds each university's published table (one row a test and IELTS level, with its quote and source page), and
--      security.provider_english_concordance_apply_v1(p_provider) adds the equivalent PTE, TOEFL iBT and CAE rows to courses whose active IELTS row
--      has an overall score and four equal band scores that the table lists. Insert only; a course holding the test keeps it; regulated
--      disciplines (health, teaching, law, social work, psychology) are left out because the universities publish their own tables for them;
--      only from a stored copy of the table's page. Run now for Adelaide (its page is stored); Newcastle's runs by trigger the moment its procedure is
--      stored (security.english_concordance_on_store_tg on pipeline.elr_central_fetches).
--   4. The Vice-Chancellor's International Academic Merit Scholarship gets its postgraduate entry GPA, 4.5 out of 7, from its 2027 conditions.
-- G1: no new job (elr-det-sweep and fee-reader carry the work). G2: no operational value (the tables are published facts; the page bound is the
--   existing batch.elr_central_fetch). G3: no consumer object changed (checked before and after). Manual locks and active cron checked unchanged.
-- Spend: Firecrawl only under the on-demand request (estimate in it); the fee reader's model calls are logged as fee_ai under the US$5.00 day cap.
-- Parity: live head 20261124234000 read 24 Nov 2026 17:20 AEDT; open migrations 20261125010000 and 20261125020000; this file is above both.
-- Replaces: the s1021 scale reading that missed "on a N scale".
-- Retires: nothing. Nothing dropped or deleted.
set local lock_timeout = '5s';  -- fixed: lock wait for the guard reads
set local statement_timeout = '120s';  -- fixed: the course writes and the consumer API check

do $g$
declare v jsonb := security.consumer_api_check_v1();
begin
  if jsonb_array_length(coalesce(v->'drift', '[]'::jsonb)) <> 0 or (v->>'functions')::int <> 75 or (v->>'relations')::int <> 48 then
    raise exception 'guard: the consumer API is not at its baseline before this change: %', v;
  end if;
end $g$;
create temp table s1053_locks on commit drop as select count(*) n from pipeline.manual_locks;
create temp table s1053_cron on commit drop as select count(*) n from cron.job where active;

-- 1. official sources, registered as a person registers a page (admin_fee_reader page_add), and queued for the governed fetch
do $src$
declare r record; v_id uuid; v_approval text := 'Platform Admin (chat, 24 Nov 2026 17:14 AEDT): register and read the official university URLs';
begin
  for r in select * from (values
      ('de2201a1-69ee-40ff-b6aa-0e54e535e6c0'::uuid, 'fee_schedule', 'https://adelaide.edu.au/content/dam/adelaideuniversity/documents/about/pdfs/2027-international-student-guide.pdf', 'fees'),
      ('1822b40a-8b13-44dc-8c37-106ae31bb447'::uuid, 'fee_schedule', 'https://www.newcastle.edu.au/__data/assets/pdf_file/0003/1159905/2027-Undergraduate-International-Course-Fee-List.pdf', 'fees'),
      ('1822b40a-8b13-44dc-8c37-106ae31bb447'::uuid, 'fee_schedule', 'https://www.newcastle.edu.au/__data/assets/pdf_file/0008/1159919/2027-Postgraduate-International-Course-Fee-List.pdf', 'fees'),
      ('1822b40a-8b13-44dc-8c37-106ae31bb447'::uuid, 'english_policy', 'https://www.newcastle.edu.au/__data/assets/pdf_file/0008/1160981/English-Language-Proficiency-Procedure.pdf', 'policies'),
      ('de2201a1-69ee-40ff-b6aa-0e54e535e6c0'::uuid, 'english_policy', 'https://adelaide.edu.au/study/international-students/how-to-apply/entry-requirements/english-language-proficiency/', 'policies')
    ) x(provider_id, kind, url, area) loop
    insert into pipeline.provider_fact_sources(provider_id, kind, url, title, rank, found_via, status)
    values (r.provider_id, r.kind, r.url, null, 9, 'manual', 'found')
    on conflict (provider_id, kind, url) do update set rank = 9, found_via = 'manual', attempts = 0, updated_at = now()
    returning id into v_id;
    insert into pipeline.elr_central_fetches(fact_source_id, provider_id, url, status)
    values (v_id, r.provider_id, r.url, 'queued')
    on conflict (fact_source_id) do update set status = 'queued', on_demand_id = null, request_id = null, sent_at = null, done_at = null, result = null
      where pipeline.elr_central_fetches.status not in ('queued', 'sent');
    insert into pipeline.admin_control_events(area, action, target, detail, actor)
    values (r.area, 'page_add', r.provider_id::text, jsonb_build_object('page', v_id, 'kind', r.kind, 'url', r.url, 'reason', 'Official university page for Item 2 (feedback-4)',
            'approved_by', v_approval, 'via', 'CF-247 s1053 migration'), null);
  end loop;
end $src$;

do $od$
declare v_ids uuid[]; v_n int; v_id uuid; v_est jsonb; v_reason text := 'CF-247 s1053 (Platform Admin 24 Nov 2026 17:14): official 2027 fee lists and English procedures for Adelaide University and The University of Newcastle';
begin
  select array_agg(distinct provider_id), count(*) into v_ids, v_n from pipeline.elr_central_fetches f where f.status = 'queued' and (f.on_demand_id is null or not exists (select 1 from pipeline.on_demand_requests r where r.id = f.on_demand_id and r.state = 'open' and r.expires_at > now()));
  if coalesce(v_n, 0) = 0 then raise exception 's1053: nothing queued to fetch'; end if;
  v_est := jsonb_build_object('pages', v_n, 'firecrawl_credits', 60, 'firecrawl_credits_most', 150, 'basis', 'one credit a page; the fee lists and the guide are PDFs, charged by their pages');
  perform security.on_demand_open_v1('claude_session', v_reason, v_ids, v_est, null, array['firecrawl']);
  select r.id into v_id from pipeline.on_demand_requests r where r.requested_via = 'claude_session' and r.reason = v_reason and r.state = 'open' order by r.opened_at desc limit 1;
  if v_id is null then raise exception 's1053: the on-demand request was not opened'; end if;
  perform security.on_demand_scope_v1(v_id, array['central']);
  update pipeline.elr_central_fetches f set on_demand_id = v_id where f.status = 'queued' and (f.on_demand_id is null or not exists (select 1 from pipeline.on_demand_requests r where r.id = f.on_demand_id and r.state = 'open' and r.expires_at > now()));
  insert into pipeline.elr_central_fetch_state (on_demand_id, estimate) values (v_id, v_est || jsonb_build_object('credit_left_before', security.on_demand_credit_left_v1()));
  raise notice 's1053: % pages queued under on-demand request %; estimate %; credit left %', v_n, v_id, v_est, security.on_demand_credit_left_v1();
end $od$;

-- Newcastle's scholarship terms, offered to the scholarship reader as registered pages of their own awards ($0 direct read first)
insert into pipeline.scholarship_page_candidates(provider_id, url, url_norm, title, source, matched_scholarship_id, match_basis, matched_at)
select s.provider_id, x.url, security.scholarship_url_norm(x.url), x.title, 'register', s.id, 'registered terms (CF-247 s1053, Platform Admin 24 Nov 2026 17:14)', now()
  from (values
    ('International Excellence Scholarship', 'https://www.newcastle.edu.au/__data/assets/pdf_file/0014/1136300/UNI_053-International-Excellence-Scholarship-2027-T-and-Cs-04092026.pdf', 'International Excellence 2027 Scholarship terms and conditions'),
    ('Vice-Chancellor''s International Academic Merit Scholarship', 'https://www.newcastle.edu.au/__data/assets/pdf_file/0015/1136301/UNI_059-Vice-Chancellors-International-Academic-Merit-Scholarship-2027-conditions-07072026.pdf', 'Vice-Chancellor''s International Academic Merit Scholarship 2027 conditions')
  ) x(name, url, title)
  join scholarship.scholarships s on s.provider_id = '1822b40a-8b13-44dc-8c37-106ae31bb447' and s.name = x.name and s.lifecycle_status = 'active'
on conflict (provider_id, url_norm) do nothing;

-- 2. a GPA scale stated as "on a 7.0 scale" or "7-point scale" is a stated scale
CREATE OR REPLACE FUNCTION security.gpa_scale_of_v1(p_value_json jsonb, p_text text)
 RETURNS numeric
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO ''
AS $function$
  select coalesce(
    case when jsonb_typeof(p_value_json -> 'scale') = 'number' then (p_value_json ->> 'scale')::numeric end,
    (select m[1]::numeric from regexp_matches(coalesce(p_text, ''), '(?:out of|/)\s*([0-9]+(?:\.[0-9]+)?)', 'i') m limit 1),
    (select m[1]::numeric from regexp_matches(coalesce(p_text, ''), '\mon an?\s+([0-9]+(?:\.[0-9]+)?)(?:[ -]point)?\s+(?:GPA\s+)?scale\M', 'i') m limit 1),
    (select m[1]::numeric from regexp_matches(coalesce(p_text, ''), '\m([0-9]+(?:\.[0-9]+)?)[ -]point\s+(?:GPA\s+)?scale\M', 'i') m limit 1))
$function$;
comment on function security.gpa_scale_of_v1(jsonb, text) is 'CF-247 s1021, s1053: the scale a GPA threshold states: value_json.scale, or "out of N", "/N", "on a N scale" or "N-point scale" in its own text; null when none is stated.';

do $gpa$
declare r record; v_n int := 0; v_ids uuid[] := '{}';
begin
  for r in select g.id, g.criterion_id, g.threshold, security.gpa_scale_of_v1(null, c.human_text) sc
             from pipeline.gpa_scale_reviews g join scholarship.criteria c on c.id = g.criterion_id
            where g.status = 'open' and security.gpa_scale_of_v1(null, c.human_text) is not null
              and (g.threshold is null or g.threshold <= security.gpa_scale_of_v1(null, c.human_text)) loop
    update scholarship.criteria set value_json = coalesce(value_json, '{}'::jsonb) || jsonb_build_object('scale', r.sc, 'scale_set_by', 'stated_text'), status = 'active'
     where id = r.criterion_id;
    update pipeline.gpa_scale_reviews set status = 'scale_set', decision = 'stated_on_page', decided_scale = r.sc,
           reason = 'The threshold''s own text states its scale (CF-247 s1053)', decided_at = now()
     where id = r.id;
    v_n := v_n + 1; v_ids := v_ids || r.criterion_id;
  end loop;
  insert into pipeline.admin_control_events(area, action, target, detail, actor)
  values ('layer4', 'gpa_scale_stated', 'scholarship_gpa_scale', jsonb_build_object('reviews_closed', v_n, 'criteria', to_jsonb(v_ids),
          'approved_by', 'Platform Admin (chat, 24 Nov 2026 17:14 AEDT)', 'via', 'CF-247 s1053 migration'), null);
  raise notice 's1053: % GPA scale reviews settled by their own stated scale', v_n;
end $gpa$;

-- 3. published English test equivalence tables
create table if not exists pipeline.english_concordance (
  provider_id    uuid not null references catalogue.providers(id),
  fact_source_id uuid not null references pipeline.provider_fact_sources(id),
  ielts          numeric not null,
  test_code      text not null,
  overall_score  numeric not null,
  section_scores jsonb not null,
  quote          text not null,
  approved_by    text not null,
  added_at       timestamptz not null default now(),
  primary key (provider_id, ielts, test_code)
);
comment on table pipeline.english_concordance is 'CF-247 s1053: a university''s own published table of English tests equivalent to IELTS (overall and section scores), one row a test and IELTS level, with its quote and the registered page it is from. Read by security.provider_english_concordance_apply_v1.';
alter table pipeline.english_concordance enable row level security;
revoke all on pipeline.english_concordance from public, anon, authenticated;

insert into pipeline.english_concordance(provider_id, fact_source_id, ielts, test_code, overall_score, section_scores, quote, approved_by)
select x.provider_id, f.id, x.ielts, x.test_code, x.overall, x.sections, x.quote, 'Platform Admin (chat, 24 Nov 2026 17:14 AEDT)'
  from (values
    -- Adelaide University: "The table below lists the English language testing systems accepted by Adelaide University, and grades equivalent to IELTS." (overall row and Subscores table)
    ('de2201a1-69ee-40ff-b6aa-0e54e535e6c0'::uuid, 'https://adelaide.edu.au/study/international-students/how-to-apply/entry-requirements/english-language-proficiency/', 6.0, 'TOEFL_IBT', 60, '{"speaking": 18, "reading": 13, "listening": 12, "writing": 21}'::jsonb, 'IELTS (Academic) 6.0: TOEFL iBT 60; Subscores TOEFL iBT (Speaking) 18, (Reading) 13, (Listening) 12, (Writing) 21'),
    ('de2201a1-69ee-40ff-b6aa-0e54e535e6c0', 'https://adelaide.edu.au/study/international-students/how-to-apply/entry-requirements/english-language-proficiency/', 6.5, 'TOEFL_IBT', 79, '{"speaking": 20, "reading": 19, "listening": 20, "writing": 24}', 'IELTS (Academic) 6.5: TOEFL iBT 79; Subscores TOEFL iBT (Speaking) 20, (Reading) 19, (Listening) 20, (Writing) 24'),
    ('de2201a1-69ee-40ff-b6aa-0e54e535e6c0', 'https://adelaide.edu.au/study/international-students/how-to-apply/entry-requirements/english-language-proficiency/', 7.0, 'TOEFL_IBT', 94, '{"speaking": 23, "reading": 24, "listening": 24, "writing": 27}', 'IELTS (Academic) 7.0: TOEFL iBT 94; Subscores TOEFL iBT (Speaking) 23, (Reading) 24, (Listening) 24, (Writing) 27'),
    ('de2201a1-69ee-40ff-b6aa-0e54e535e6c0', 'https://adelaide.edu.au/study/international-students/how-to-apply/entry-requirements/english-language-proficiency/', 7.5, 'TOEFL_IBT', 107, '{"speaking": 24, "reading": 27, "listening": 27, "writing": 29}', 'IELTS (Academic) 7.5: TOEFL iBT 107; Subscores TOEFL iBT (Speaking) 24, (Reading) 27, (Listening) 27, (Writing) 29'),
    ('de2201a1-69ee-40ff-b6aa-0e54e535e6c0', 'https://adelaide.edu.au/study/international-students/how-to-apply/entry-requirements/english-language-proficiency/', 8.0, 'TOEFL_IBT', 112, '{"speaking": 26, "reading": 29, "listening": 28, "writing": 30}', 'IELTS (Academic) 8.0: TOEFL iBT 112; Subscores TOEFL iBT (Speaking) 26, (Reading) 29, (Listening) 28, (Writing) 30'),
    ('de2201a1-69ee-40ff-b6aa-0e54e535e6c0', 'https://adelaide.edu.au/study/international-students/how-to-apply/entry-requirements/english-language-proficiency/', 6.0, 'PTE', 60, '{"speaking": 60, "reading": 60, "listening": 60, "writing": 60}', 'IELTS (Academic) 6.0: PTE 60; Subscores PTE 60'),
    ('de2201a1-69ee-40ff-b6aa-0e54e535e6c0', 'https://adelaide.edu.au/study/international-students/how-to-apply/entry-requirements/english-language-proficiency/', 6.5, 'PTE', 64, '{"speaking": 64, "reading": 64, "listening": 64, "writing": 64}', 'IELTS (Academic) 6.5: PTE 64; Subscores PTE 64'),
    ('de2201a1-69ee-40ff-b6aa-0e54e535e6c0', 'https://adelaide.edu.au/study/international-students/how-to-apply/entry-requirements/english-language-proficiency/', 7.0, 'PTE', 72, '{"speaking": 72, "reading": 72, "listening": 72, "writing": 72}', 'IELTS (Academic) 7.0: PTE 72; Subscores PTE 72'),
    ('de2201a1-69ee-40ff-b6aa-0e54e535e6c0', 'https://adelaide.edu.au/study/international-students/how-to-apply/entry-requirements/english-language-proficiency/', 7.5, 'PTE', 74, '{"speaking": 74, "reading": 74, "listening": 74, "writing": 74}', 'IELTS (Academic) 7.5: PTE 74; Subscores PTE 74'),
    ('de2201a1-69ee-40ff-b6aa-0e54e535e6c0', 'https://adelaide.edu.au/study/international-students/how-to-apply/entry-requirements/english-language-proficiency/', 8.0, 'PTE', 82, '{"speaking": 82, "reading": 82, "listening": 82, "writing": 82}', 'IELTS (Academic) 8.0: PTE 82; Subscores PTE 82'),
    ('de2201a1-69ee-40ff-b6aa-0e54e535e6c0', 'https://adelaide.edu.au/study/international-students/how-to-apply/entry-requirements/english-language-proficiency/', 6.0, 'CAE', 169, '{"speaking": 169, "reading": 169, "listening": 169, "writing": 169}', 'IELTS (Academic) 6.0: C1 / C2 169; Subscores C1 / C2 169'),
    ('de2201a1-69ee-40ff-b6aa-0e54e535e6c0', 'https://adelaide.edu.au/study/international-students/how-to-apply/entry-requirements/english-language-proficiency/', 6.5, 'CAE', 176, '{"speaking": 176, "reading": 176, "listening": 176, "writing": 176}', 'IELTS (Academic) 6.5: C1 / C2 176; Subscores C1 / C2 176'),
    ('de2201a1-69ee-40ff-b6aa-0e54e535e6c0', 'https://adelaide.edu.au/study/international-students/how-to-apply/entry-requirements/english-language-proficiency/', 7.0, 'CAE', 185, '{"speaking": 185, "reading": 185, "listening": 185, "writing": 185}', 'IELTS (Academic) 7.0: C1 / C2 185; Subscores C1 / C2 185'),
    ('de2201a1-69ee-40ff-b6aa-0e54e535e6c0', 'https://adelaide.edu.au/study/international-students/how-to-apply/entry-requirements/english-language-proficiency/', 7.5, 'CAE', 191, '{"speaking": 191, "reading": 191, "listening": 191, "writing": 191}', 'IELTS (Academic) 7.5: C1 / C2 191; Subscores C1 / C2 191'),
    ('de2201a1-69ee-40ff-b6aa-0e54e535e6c0', 'https://adelaide.edu.au/study/international-students/how-to-apply/entry-requirements/english-language-proficiency/', 8.0, 'CAE', 200, '{"speaking": 200, "reading": 200, "listening": 200, "writing": 200}', 'IELTS (Academic) 8.0: C1 / C2 200; Subscores C1 / C2 200'),
    -- The University of Newcastle, English Language Proficiency Procedure (effective 26 March 2026), Table 1: overall and section equivalences;
    -- "unless indicated by separate section scores, the minimum subtest score must be achieved in all sub-tests"
    ('1822b40a-8b13-44dc-8c37-106ae31bb447', 'https://www.newcastle.edu.au/__data/assets/pdf_file/0008/1160981/English-Language-Proficiency-Procedure.pdf', 6.0, 'TOEFL_IBT', 70, '{"reading": 16, "listening": 16, "speaking": 18, "writing": 21}', 'IELTS 6.0: TOEFL iBT 70; section R16, L16, S18, W21'),
    ('1822b40a-8b13-44dc-8c37-106ae31bb447', 'https://www.newcastle.edu.au/__data/assets/pdf_file/0008/1160981/English-Language-Proficiency-Procedure.pdf', 6.5, 'TOEFL_IBT', 85, '{"reading": 19, "listening": 20, "speaking": 20, "writing": 24}', 'IELTS 6.5: TOEFL iBT 85; section R19, L20, S20, W24'),
    ('1822b40a-8b13-44dc-8c37-106ae31bb447', 'https://www.newcastle.edu.au/__data/assets/pdf_file/0008/1160981/English-Language-Proficiency-Procedure.pdf', 7.0, 'TOEFL_IBT', 94, '{"reading": 24, "listening": 24, "speaking": 23, "writing": 27}', 'IELTS 7.0: TOEFL iBT 94; section R24, L24, S23, W27'),
    ('1822b40a-8b13-44dc-8c37-106ae31bb447', 'https://www.newcastle.edu.au/__data/assets/pdf_file/0008/1160981/English-Language-Proficiency-Procedure.pdf', 7.5, 'TOEFL_IBT', 102, '{"reading": 27, "listening": 27, "speaking": 24, "writing": 29}', 'IELTS 7.5: TOEFL iBT 102; section R27, L27, S24, W29'),
    ('1822b40a-8b13-44dc-8c37-106ae31bb447', 'https://www.newcastle.edu.au/__data/assets/pdf_file/0008/1160981/English-Language-Proficiency-Procedure.pdf', 8.0, 'TOEFL_IBT', 110, '{"reading": 29, "listening": 28, "speaking": 26, "writing": 30}', 'IELTS 8.0: TOEFL iBT 110; section R29, L28, S26, W30'),
    ('1822b40a-8b13-44dc-8c37-106ae31bb447', 'https://www.newcastle.edu.au/__data/assets/pdf_file/0008/1160981/English-Language-Proficiency-Procedure.pdf', 6.0, 'PTE', 52, '{"reading": 52, "listening": 52, "speaking": 52, "writing": 52}', 'IELTS 6.0: PTE Academic 52; section 52'),
    ('1822b40a-8b13-44dc-8c37-106ae31bb447', 'https://www.newcastle.edu.au/__data/assets/pdf_file/0008/1160981/English-Language-Proficiency-Procedure.pdf', 6.5, 'PTE', 59, '{"reading": 59, "listening": 59, "speaking": 59, "writing": 59}', 'IELTS 6.5: PTE Academic 59; section 59'),
    ('1822b40a-8b13-44dc-8c37-106ae31bb447', 'https://www.newcastle.edu.au/__data/assets/pdf_file/0008/1160981/English-Language-Proficiency-Procedure.pdf', 7.0, 'PTE', 66, '{"reading": 66, "listening": 66, "speaking": 66, "writing": 66}', 'IELTS 7.0: PTE Academic 66; section 66'),
    ('1822b40a-8b13-44dc-8c37-106ae31bb447', 'https://www.newcastle.edu.au/__data/assets/pdf_file/0008/1160981/English-Language-Proficiency-Procedure.pdf', 7.5, 'PTE', 75, '{"reading": 75, "listening": 75, "speaking": 75, "writing": 75}', 'IELTS 7.5: PTE Academic 75; section 75'),
    ('1822b40a-8b13-44dc-8c37-106ae31bb447', 'https://www.newcastle.edu.au/__data/assets/pdf_file/0008/1160981/English-Language-Proficiency-Procedure.pdf', 8.0, 'PTE', 82, '{"reading": 82, "listening": 82, "speaking": 82, "writing": 82}', 'IELTS 8.0: PTE Academic 82; section 82'),
    ('1822b40a-8b13-44dc-8c37-106ae31bb447', 'https://www.newcastle.edu.au/__data/assets/pdf_file/0008/1160981/English-Language-Proficiency-Procedure.pdf', 6.0, 'CAE', 169, '{"reading": 169, "listening": 169, "speaking": 169, "writing": 169}', 'IELTS 6.0: Cambridge English Advanced (CAE) 169; section 169'),
    ('1822b40a-8b13-44dc-8c37-106ae31bb447', 'https://www.newcastle.edu.au/__data/assets/pdf_file/0008/1160981/English-Language-Proficiency-Procedure.pdf', 6.5, 'CAE', 176, '{"reading": 176, "listening": 176, "speaking": 176, "writing": 176}', 'IELTS 6.5: Cambridge English Advanced (CAE) 176; section 176'),
    ('1822b40a-8b13-44dc-8c37-106ae31bb447', 'https://www.newcastle.edu.au/__data/assets/pdf_file/0008/1160981/English-Language-Proficiency-Procedure.pdf', 7.0, 'CAE', 185, '{"reading": 185, "listening": 185, "speaking": 185, "writing": 185}', 'IELTS 7.0: Cambridge English Advanced (CAE) 185; section 185'),
    ('1822b40a-8b13-44dc-8c37-106ae31bb447', 'https://www.newcastle.edu.au/__data/assets/pdf_file/0008/1160981/English-Language-Proficiency-Procedure.pdf', 7.5, 'CAE', 191, '{"reading": 191, "listening": 191, "speaking": 191, "writing": 191}', 'IELTS 7.5: Cambridge English Advanced (CAE) 191; section 191'),
    ('1822b40a-8b13-44dc-8c37-106ae31bb447', 'https://www.newcastle.edu.au/__data/assets/pdf_file/0008/1160981/English-Language-Proficiency-Procedure.pdf', 8.0, 'CAE', 200, '{"reading": 200, "listening": 200, "speaking": 200, "writing": 200}', 'IELTS 8.0: Cambridge English Advanced (CAE) 200; section 200')
  ) x(provider_id, url, ielts, test_code, overall, sections, quote)
  join pipeline.provider_fact_sources f on f.provider_id = x.provider_id and f.kind = 'english_policy' and f.url = x.url
on conflict (provider_id, ielts, test_code) do nothing;

CREATE OR REPLACE FUNCTION security.provider_english_concordance_apply_v1(p_provider uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_src uuid; v_ev uuid; v_ids uuid[]; v_by jsonb;
begin
  select c.fact_source_id, f.evidence_id into v_src, v_ev
    from pipeline.english_concordance c join pipeline.provider_fact_sources f on f.id = c.fact_source_id
   where c.provider_id = p_provider limit 1;
  if v_src is null then return jsonb_build_object('skipped', 'no published equivalence table for this provider'); end if;
  if v_ev is null then return jsonb_build_object('skipped', 'the table''s page is not stored yet', 'fact_source_id', v_src); end if;
  with ielts as (
    select r.course_id, r.overall_score ov, (select min(v::numeric) from jsonb_each_text(r.component_scores) e(k, v) where k in ('listening', 'reading', 'writing', 'speaking')) band, r.confidence
      from catalogue.course_english_requirements r
      join ref.english_tests ti on ti.id = r.english_test_id and ti.code = 'IELTS'
      join catalogue.courses co on co.id = r.course_id and co.provider_id = p_provider and co.lifecycle_status = 'active'
     where r.status = 'active'
       and (select count(*) from jsonb_each_text(coalesce(r.component_scores, '{}'::jsonb)) e(k, v) where k in ('listening', 'reading', 'writing', 'speaking')) = 4
       and (select count(distinct v::numeric) from jsonb_each_text(r.component_scores) e(k, v) where k in ('listening', 'reading', 'writing', 'speaking')) = 1
       -- regulated disciplines: the universities publish their own tables for these, so the general table is not applied
       and co.canonical_title !~* '(nurs|midwi|medic|pharm|physio|dent|health|clinical|psycholog|speech|occupational|dietet|paramed|radiograph|optom|teach|education|law|juris|legal|social work)'),
  ins as (
    insert into catalogue.course_english_requirements(course_id, english_test_id, overall_score, component_scores, notes, source_id, evidence_id,
                                                      confidence, source_requirement_key, status, last_verified_at)
    select i.course_id, t.id, co.overall_score,
           case when co.test_code = 'TOEFL_IBT' then cs.section_scores else jsonb_build_object('listening', cs.overall_score, 'reading', cs.overall_score, 'writing', cs.overall_score, 'speaking', cs.overall_score) end,
           format('%s equivalent to this course''s IELTS %s (each band %s) in the university''s published table (%s; %s). CF-247 s1053.', t.name, i.ov, i.band, f.url, co.quote),
           null, v_ev, least(coalesce(i.confidence, 0.9), 0.9), 'concordance:' || v_src || ':' || lower(co.test_code), 'active', now()
      from ielts i
      join pipeline.english_concordance co on co.provider_id = p_provider and co.ielts = i.ov
      join pipeline.english_concordance cs on cs.provider_id = p_provider and cs.ielts = i.band and cs.test_code = co.test_code
      join ref.english_tests t on t.code = co.test_code
      join pipeline.provider_fact_sources f on f.id = co.fact_source_id
     where not exists (select 1 from catalogue.course_english_requirements o where o.course_id = i.course_id and o.english_test_id = t.id and o.status = 'active')
    on conflict (course_id, english_test_id) do nothing
    returning course_id, english_test_id)
  select array_agg(distinct ins.course_id), (select jsonb_object_agg(code, n) from (select t2.code, count(*) n from ins i2 join ref.english_tests t2 on t2.id = i2.english_test_id group by 1) z)
    into v_ids, v_by from ins;
  if coalesce(cardinality(v_ids), 0) > 0 then
    perform search.course_refresh_request_v1(v_ids, 'CF-247 s1053 English equivalence');  -- queued: the search writer refreshes them on its own run
  end if;
  insert into pipeline.admin_control_events(area, action, target, detail, actor)
  values ('policies', 'concordance_apply', p_provider::text, jsonb_build_object('fact_source_id', v_src, 'evidence_id', v_ev, 'courses', coalesce(cardinality(v_ids), 0), 'rows', coalesce(v_by, '{}'::jsonb),
          'approved_by', 'Platform Admin (chat, 24 Nov 2026 17:14 AEDT)', 'via', 'CF-247 s1053'), null);
  return jsonb_build_object('courses', coalesce(cardinality(v_ids), 0), 'rows', coalesce(v_by, '{}'::jsonb), 'evidence_id', v_ev);
end $function$;
comment on function security.provider_english_concordance_apply_v1(uuid) is 'CF-247 s1053: adds the PTE, TOEFL iBT and CAE rows a university''s published IELTS equivalence table gives a course whose active IELTS row has an overall score and four equal band scores the table lists. Insert only; not for regulated disciplines; only from the table page''s stored copy. Logged.';
revoke all on function security.provider_english_concordance_apply_v1(uuid) from public, anon, authenticated;

-- the moment a table's page is stored by the governed fetch, its equivalences are applied: no waiting for a person or a later change
CREATE OR REPLACE FUNCTION security.english_concordance_on_store_tg()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  if new.status = 'stored' and old.status is distinct from 'stored'
     and exists (select 1 from pipeline.english_concordance c where c.fact_source_id = new.fact_source_id) then
    begin
      perform security.provider_english_concordance_apply_v1(new.provider_id);
    exception when others then
      insert into pipeline.admin_control_events(area, action, target, detail, actor)
      values ('policies', 'concordance_apply_failed', new.provider_id::text, jsonb_build_object('fact_source_id', new.fact_source_id, 'error', left(sqlerrm, 300), 'via', 'CF-247 s1053'), null);
    end;
  end if;
  return new;
end $function$;
comment on function security.english_concordance_on_store_tg() is 'CF-247 s1053: when the governed fetch stores the page of a published English equivalence table (pipeline.elr_central_fetches status stored), applies the table to that university''s courses (security.provider_english_concordance_apply_v1). A failure is logged and never stops the fetch record.';
revoke all on function security.english_concordance_on_store_tg() from public, anon, authenticated;
create or replace trigger english_concordance_on_store after update of status on pipeline.elr_central_fetches
  for each row execute function security.english_concordance_on_store_tg();

-- 4. Newcastle's Vice-Chancellor's International Academic Merit Scholarship: the postgraduate entry GPA its 2027 conditions state (clause 3.1.2)
insert into scholarship.criteria(scholarship_id, criterion_type, operator, value_text, value_number, value_json, human_text, is_mandatory, machine_evaluable, status, source_id, confidence)
select s.id, 'academic_minimum', '>=', 'GPA 4.5', 4.5,
       jsonb_build_object('scale', 7, 'scale_set_by', 'stated_text', 'applies_to', 'postgraduate',
                          'source_url', 'https://www.newcastle.edu.au/__data/assets/pdf_file/0015/1136301/UNI_059-Vice-Chancellors-International-Academic-Merit-Scholarship-2027-conditions-07072026.pdf',
                          'approved_by', 'Platform Admin (chat, 24 Nov 2026 17:14 AEDT)', 'via', 'CF-247 s1053'),
       'Vice-Chancellor''s International Academic Merit Scholarship 2027 conditions, clause 3.1.2: "4.5 / 7 GPA in an eligible qualification (for postgraduate students)"',
       true, true, 'active', s.source_id, 0.95
  from scholarship.scholarships s
 where s.provider_id = '1822b40a-8b13-44dc-8c37-106ae31bb447' and s.name = 'Vice-Chancellor''s International Academic Merit Scholarship' and s.lifecycle_status = 'active'
   and not exists (select 1 from scholarship.criteria c where c.scholarship_id = s.id and c.status = 'active' and c.criterion_type = 'academic_minimum' and coalesce(c.value_text, '') ~* '^GPA');

create temp table s1053_out on commit drop as
select p provider_id, security.provider_english_concordance_apply_v1(p) result
  from unnest(array['de2201a1-69ee-40ff-b6aa-0e54e535e6c0', '1822b40a-8b13-44dc-8c37-106ae31bb447']::uuid[]) p;

do $c$
declare v_api jsonb;
begin
  if (select count(*) from pipeline.english_concordance) <> 30 then raise exception 'post-check: the equivalence tables did not load (30 rows expected)'; end if;
  if exists (select 1 from catalogue.course_english_requirements r where r.source_requirement_key like 'concordance:%' and r.status = 'active'
               and (select count(*) from jsonb_object_keys(coalesce(r.component_scores, '{}'::jsonb)) k where k in ('listening', 'reading', 'writing', 'speaking')) <> 4) then
    raise exception 'post-check: a row was added without its four section scores';
  end if;
  if security.gpa_scale_of_v1(null, 'A minimum overall Grade Point Average (GPA) of 4.5 (on a 7.0 scale)') is distinct from 7.0 then raise exception 'post-check: the stated scale is not read'; end if;
  if security.gpa_scale_of_v1(null, 'a cumulative GPA of 4.5 or above') is not null then raise exception 'post-check: a scale was read where none is stated'; end if;
  if exists (select 1 from pipeline.gpa_scale_reviews g join scholarship.criteria c on c.id = g.criterion_id
              where g.decision = 'stated_on_page' and g.threshold > g.decided_scale) then raise exception 'post-check: a threshold above its scale was admitted'; end if;
  if (select count(*) from pipeline.elr_central_fetches f join pipeline.on_demand_requests r on r.id = f.on_demand_id and r.state = 'open' where f.status = 'queued') < 5 then
    raise exception 'post-check: the official pages are not queued under an open on-demand request';
  end if;
  if (select count(*) from cron.job where active) <> (select n from s1053_cron) then raise exception 'post-check: the number of active cron jobs changed'; end if;
  if (select count(*) from pipeline.manual_locks) <> (select n from s1053_locks) then raise exception 'post-check: manual locks changed'; end if;
  v_api := security.consumer_api_check_v1();
  if jsonb_array_length(coalesce(v_api->'drift', '[]'::jsonb)) <> 0 or (v_api->>'functions')::int <> 75 or (v_api->>'relations')::int <> 48 then
    raise exception 'post-check: the consumer API moved: %', v_api;
  end if;
  raise notice 's1053: %', (select jsonb_agg(jsonb_build_object('provider', provider_id, 'result', result)) from s1053_out);
end $c$;
