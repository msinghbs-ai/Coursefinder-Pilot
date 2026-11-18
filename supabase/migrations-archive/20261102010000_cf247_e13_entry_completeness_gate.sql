-- CF-247 E13 (Platform Admin 2 Nov 2026 05:18 AEDT, "E13 — Entry-requirement completeness. Decision: APPROVE development of the whole-read
-- completeness gate"): a course entry-requirement read is proposed whole or held whole, and an incomplete read never reaches approval.
-- Record: admin docs/platform/nz-enrichment-brief/2026-11-01-layer4-exception-decision-pack.md (E13, E14) and
-- 2026-11-02-morning-execution-mandate-and-decisions.md (E13).
-- Why: the reader (security.enrich_entry_record_v1) proposed at most entry.max_rows_per_course (6) rows and recorded the rest as dropped
--   (over_row_limit). Measured 1 Nov: 225 of 1,117 reads dropped 3,189 rows; 53 of the 59 capped approvals dropped 287 rows. E14 found two
--   faults in approved reads: a sibling programme variant's rows on a combined page (EIT: "The academic entry requirement for the MIT (240)"
--   on the Postgraduate Certificate), and a joined condition cut by the cap (Monash Master of Clinical Research kept "An Australian bachelor
--   degree (or equivalent)" and dropped "plus a minimum of two years of relevant work experience").
-- What:
--   1. Reader (security.enrich_entry_record_v1, whole definition replaced, md5-guarded): rows are checked first and inserted only after the
--      whole read is known. A read with more admissible rows than the course's limit is held whole: no row is proposed, no Layer 4 item
--      opens, the item is skipped with reason "held_partial: over_row_limit ..." and keeps every row it read (value.rows_read), so a later,
--      separately authorised step can use it without another AI call. The rows past the limit are still recorded as dropped over_row_limit.
--      A row whose quote names another programme (security.course_entry_variant_v1) is dropped as other_programme and does not count
--      towards the limit. The limit is entry.max_rows_per_course, or the provider's own value in entry.max_rows_by_provider.
--   2. Approval (security.course_entry_review_apply_v1, md5-guarded edit): Approve and Approve except are refused, with nothing changed,
--      while security.course_entry_gate_v1 finds the read incomplete: any row dropped over_row_limit (a joined condition among them is
--      named), a waiting row that names another programme and is not left out, or a stored page that is also the page of a differently
--      named programme (entry.shared_page_hold; E14: 14 EIT approvals carried sibling-variant rows, 4 of them with no label in the quote).
--      Reject, and the other non-approve outcomes, are unchanged.
--   3. Review screen (security.aer_review_read_v1, md5-guarded edit): a course entry item carries its gate result (completeness_gate), so the
--      reviewer sees why it is held and which rows name another programme.
-- Settings (G2; Settings > Pipeline settings, section Entry requirements): entry.max_rows_by_provider, entry.joined_condition_words,
--   entry.joined_condition_kinds, entry.variant_check, entry.shared_page_hold, entry.variant_check_off_providers, entry.award_abbreviations.
-- Measured on the stored reads (read only, 2 Nov 2026), with the default settings: of 499 pending course entry items the gate holds 215:
--   162 cut by the row limit (2,842 rows; 2 with a joined condition), 98 from a page shared with a differently named programme (53 of them
--   not cut), and 2 waiting rows about another programme (both on shared EIT pages). The other 284 are unaffected. On the 18 E14 items:
--   the 14 EIT items are all on shared pages (10 also named by their quotes) and the 4 joined-condition items are exactly those the joined
--   check names among approved reads.
-- Not changed: entry.max_rows_per_course stays 6 (no global raise). No course is re-read, no AI or page fetch is started, and nothing is
--   approved, withdrawn or re-opened: the 59 approved capped reads stay as they are (decision E13: retained unless independently found
--   incorrect). Pending items are not changed; the gate is checked when a person decides. A passing test switches nothing on.
-- Before (live, 2 Nov 2026): security.enrich_entry_record_v1 857102dc182426a841a41e7244f7a088; security.course_entry_review_apply_v1
--   ce8d0bad9717034342f165b1876fb632; security.aer_review_read_v1 62793b3544874e91a1e2aa26b80e8a14.
-- After: enrich_entry_record_v1 9757abeeb3700c5cd2e02385def05869; course_entry_review_apply_v1 4be9267d8419dee7d9f80cb96ff4098b;
--   aer_review_read_v1 50c31fc4df16b7bbbb39dab03aa9f9b2. Computed read-only on 2 Nov 2026 (the edited live definition hashed in a SELECT;
--   the reader's header and the header+source rule checked against live), because a rolled-back DDL dry run was refused at confirmation.
--   Each helper checks the after md5 once it has applied, and raises (rolling the migration back) on any difference.
-- Rollback: re-apply the three before definitions (enrich_entry_record_v1 from 20261029130000 as live; the two edits reversed). The new
--   functions and settings are then unused and go by a paste file after hygiene.retire_after_days.
-- Replaces: security.enrich_entry_record_v1 (same name; the row cap now holds the whole read instead of proposing the first rows);
--   security.course_entry_review_apply_v1 and security.aer_review_read_v1 (same names; md5-guarded edits)
-- Retires: nothing (no table, function, job or edge function is left unused)
-- Nothing dropped or deleted. No new table, job or status. The consumer API is not touched (G3, Decision 266): no website_*, zoho_*, api.*
--   object or edge function changes; active entry rows are not changed.

create or replace function pg_temp.edit_once(p_sig text, p_before text, p_after text, p_edits text[][], p_times int[]) returns text language plpgsql as $f$
declare v_def text := pg_get_functiondef(p_sig::regprocedure); i int; v_c int; v_old text; v_new text;
begin
  if md5(v_def) = p_after then return p_sig || ': already applied'; end if;
  if md5(v_def) <> p_before then raise exception 'live % differs from the definition this change edits (md5 %)', p_sig, md5(v_def); end if;
  for i in 1 .. array_length(p_edits, 1) loop
    -- fixed: line endings are normalised, so the edit applies the same however the text arrives
    v_old := replace(p_edits[i][1], chr(13), ''); v_new := replace(p_edits[i][2], chr(13), '');
    v_c := (length(v_def) - length(replace(v_def, v_old, ''))) / length(v_old);
    if v_c <> p_times[i] then raise exception '%: edit % must apply exactly % times (found %)', p_sig, i, p_times[i], v_c; end if;
    v_def := replace(v_def, v_old, v_new);
  end loop;
  execute v_def;
  if md5(pg_get_functiondef(p_sig::regprocedure)) <> p_after then
    raise exception '% after the edit has md5 %, expected %', p_sig, md5(pg_get_functiondef(p_sig::regprocedure)), p_after;
  end if;
  return p_sig || ': applied';
end $f$;

-- a whole definition replaced, guarded the same way: the live definition must be the one this change was written against
create or replace function pg_temp.replace_once(p_sig text, p_before text, p_after text, p_def text) returns text language plpgsql as $f$
declare v_md5 text := md5(pg_get_functiondef(p_sig::regprocedure));
begin
  if v_md5 = p_after then return p_sig || ': already applied'; end if;
  if v_md5 <> p_before then raise exception 'live % differs from the definition this change replaces (md5 %)', p_sig, v_md5; end if;
  execute replace(p_def, chr(13), '');
  if md5(pg_get_functiondef(p_sig::regprocedure)) <> p_after then
    raise exception '% after the change has md5 %, expected %', p_sig, md5(pg_get_functiondef(p_sig::regprocedure)), p_after;
  end if;
  return p_sig || ': applied';
end $f$;

-- ---------------------------------------------------------------- settings (G2)
insert into pipeline.platform_toolset_settings(toolset_key, key, label, help, kind, value, min_value, max_value, unit, sort, section, used_by, reason) values
 ('pipeline', 'entry.max_rows_by_provider', 'Course entry requirements: rows a course, by provider',
  'A provider''s own row limit for a course read, as provider id=rows (for example 1719c3ba-…=10). It must lie within the range of "rows a course"; otherwise "rows a course" applies. A read with more rows than its limit is held whole, never proposed in part.',
  'list', '[]'::jsonb, null, null, 'provider=rows', 925, 'Entry requirements',
  'security.course_entry_max_rows_v1, security.enrich_entry_record_v1', 'CF-247 E13 (Platform Admin 2 Nov 2026 05:18): the cap is raised only per provider, with a reason'),
 ('pipeline', 'entry.joined_condition_words', 'Course entry requirements: words that join a condition',
  'A row cut by the row limit whose quote starts with one of these words belongs to a requirement that was kept (for example "plus two years of work experience"). The review names it.',
  'list', '["and", "plus", "together with", "as well as", "in addition"]'::jsonb, null, null, 'words', 926, 'Entry requirements',
  'security.course_entry_joined_v1, security.course_entry_gate_v1', 'CF-247 E13 (Platform Admin 2 Nov 2026 05:18): detect joined requirements separated by the cap'),
 ('pipeline', 'entry.joined_condition_kinds', 'Course entry requirements: kinds that join a condition',
  'A row of one of these kinds cut by the row limit is treated as joined to a requirement that was kept (work experience is usually a condition of a degree route).',
  'list', '["work_experience"]'::jsonb, null, null, 'kinds', 927, 'Entry requirements',
  'security.course_entry_joined_v1, security.course_entry_gate_v1', 'CF-247 E13 (Platform Admin 2 Nov 2026 05:18): detect joined requirements separated by the cap'),
 ('pipeline', 'entry.variant_check', 'Course entry requirements: other-programme check on',
  'Rows whose quote names another programme (a sibling variant on a combined page, for example "the MIT (240)" on a Postgraduate Certificate) are not proposed, and a waiting row that names one holds approval.',
  'number', '1'::jsonb, 0, 1, 'on/off', 928, 'Entry requirements',
  'security.course_entry_variant_v1', 'CF-247 E13 (Platform Admin 2 Nov 2026 05:18): detect requirements belonging to sibling programme variants'),
 ('pipeline', 'entry.shared_page_hold', 'Course entry requirements: hold reads of a shared page',
  'A course whose stored page is also the page of a differently named programme (one page for a master, its 180 and 240 point versions, diploma and certificate) cannot have its rows told apart by programme, so approval of its read is held.',
  'number', '1'::jsonb, 0, 1, 'on/off', 929, 'Entry requirements',
  'security.course_entry_gate_v1', 'CF-247 E13 (Platform Admin 2 Nov 2026 05:18): E14 found sibling-variant rows approved from one shared page (EIT, 14 items)'),
 ('pipeline', 'entry.variant_check_off_providers', 'Course entry requirements: providers without the other-programme checks',
  'Providers whose course reads are not checked for another programme (neither the quotes nor a shared page). Leave empty unless a provider''s page names other programmes as genuine requirements.',
  'list', '[]'::jsonb, null, null, 'providers', 930, 'Entry requirements',
  'security.course_entry_variant_v1, security.course_entry_gate_v1', 'CF-247 E13 (Platform Admin 2 Nov 2026 05:18): provider-specific applicability'),
 ('pipeline', 'entry.award_abbreviations', 'Course entry requirements: award abbreviations',
  'Short form=award name pairs used to recognise a programme named in a quote (for example PGCert=Postgraduate Certificate, so "PGCertIT" is a Postgraduate Certificate in Information Technology). Longer short forms are tried first.',
  'list', '["PGCert=Postgraduate Certificate", "PGDip=Postgraduate Diploma", "GradCert=Graduate Certificate", "GradDip=Graduate Diploma", "M=Master", "B=Bachelor"]'::jsonb,
  null, null, 'pairs', 931, 'Entry requirements',
  'security.course_entry_variant_v1', 'CF-247 E13 (Platform Admin 2 Nov 2026 05:18): detect requirements belonging to sibling programme variants')
on conflict (toolset_key, key) do nothing;

-- ---------------------------------------------------------------- the course's row limit (provider-specific, within the global range)
create or replace function security.course_entry_max_rows_v1(p_provider uuid) returns int
language sql stable security definer set search_path to '' as $$
  select coalesce(
    (select split_part(e, '=', 2)::int
       from jsonb_array_elements_text(coalesce(security.toolset_setting('pipeline', 'entry.max_rows_by_provider'), '[]'::jsonb)) e
       join pipeline.platform_toolset_settings s on s.toolset_key = 'pipeline' and s.key = 'entry.max_rows_per_course'
      where btrim(split_part(e, '=', 1)) = p_provider::text and btrim(split_part(e, '=', 2)) ~ '^[0-9]+$'
        and split_part(e, '=', 2)::numeric between coalesce(s.min_value, split_part(e, '=', 2)::numeric) and coalesce(s.max_value, split_part(e, '=', 2)::numeric)
      limit 1),
    security.pipeline_num_v1('entry.max_rows_per_course', 6)::int)
$$;
revoke all on function security.course_entry_max_rows_v1(uuid) from public, anon, authenticated;
comment on function security.course_entry_max_rows_v1(uuid) is 'CF-247 E13: the row limit of a course entry read: the provider''s value in entry.max_rows_by_provider when it lies within the range of entry.max_rows_per_course, otherwise entry.max_rows_per_course.';

-- ---------------------------------------------------------------- joined condition: a cut row that belongs to a kept one
create or replace function security.course_entry_joined_v1(p_quote text, p_kind text) returns boolean
language sql stable security definer set search_path to '' as $$
  select coalesce(security.toolset_setting('pipeline', 'entry.joined_condition_kinds'), '[]'::jsonb) ? coalesce(p_kind, '')
      or exists (select 1 from jsonb_array_elements_text(coalesce(security.toolset_setting('pipeline', 'entry.joined_condition_words'), '[]'::jsonb)) w
                  where btrim(w) <> ''
                    and lower(regexp_replace(btrim(coalesce(p_quote, '')), '^[^[:alnum:]]+', '')) ~ ('^' || regexp_replace(lower(btrim(w)), '([^[:alnum:] ])', '\\\1', 'g') || '\M'))
$$;
revoke all on function security.course_entry_joined_v1(text, text) from public, anon, authenticated;
comment on function security.course_entry_joined_v1(text, text) is 'CF-247 E13: true when a course entry row''s quote starts with a joining word (entry.joined_condition_words) or its kind is in entry.joined_condition_kinds.';

-- ---------------------------------------------------------------- sibling programme variant named in a quote
-- Returns the other programme a quote is about, or null when it is this course's own (or the check does not apply). The programme is read from
--   * the subject of "entry (or admission) requirement(s) for/of (the) X", or of "A X applicant ...";
--   * the start of the quote used as a heading: "Postgraduate Diploma in Applied Management An undergraduate degree ..." or
--     "PGDipDigiBus and PGCertDigiBus A NZQF listed undergraduate degree ..." (the name, an optional credit in brackets, then a new sentence).
-- X is an abbreviation (award short form from entry.award_abbreviations, then the capitals of the field, then the credit, for example
-- "MIT (240)" or "PGCertIT"), or a programme title of the same provider (the longest that fits). It is another programme when its award, field
-- or credit differs from the course's own. Naming a programme as a qualification to hold ("Completion of the Postgraduate Diploma in IT with
-- a B average", "completed the requirements for the Bachelor of Arts") is none of these forms.
create or replace function security.course_entry_variant_v1(p_course uuid, p_quote text) returns text
language sql stable security definer set search_path to '' as $$
  with aw as (select btrim(split_part(e, '=', 1)) abbr, btrim(split_part(e, '=', 2)) long
                from jsonb_array_elements_text(coalesce(security.toolset_setting('pipeline', 'entry.award_abbreviations'), '[]'::jsonb)) e
               where btrim(split_part(e, '=', 1)) <> '' and btrim(split_part(e, '=', 2)) <> ''),
  -- the course's own programme: title without bracketed parts, its credit value in brackets, its award and the capitals of its field
  c as (select x.provider_id, btrim(coalesce(p_quote, '')) q, btrim(regexp_replace(x.canonical_title, '\s*\([^)]*\)', '', 'g')) base,
               substring(x.canonical_title from '\(([0-9]{2,3})(?:\s*(?:[Cc]redits?|[Pp]oints?))?\)') credit
          from catalogue.courses x
         where x.id = p_course and btrim(coalesce(p_quote, '')) <> '' and security.pipeline_num_v1('entry.variant_check', 1) >= 1
           and not (coalesce(security.toolset_setting('pipeline', 'entry.variant_check_off_providers'), '[]'::jsonb) ? x.provider_id::text)),
  own as (select c.*, a.abbr award, (select string_agg(upper(left(w, 1)), '' order by n) from regexp_split_to_table(coalesce(a.field, ''), '\s+') with ordinality t(w, n)
                                     where w <> '' and lower(w) not in ('of', 'in', 'and', '&', 'the', 'with', 'for')) init
            from c left join lateral (select aw.abbr, btrim(regexp_replace(substr(c.base, length(aw.long) + 1), '^\s*(of|in)\s+', '', 'i')) field
                                        from aw where lower(c.base) like lower(aw.long) || ' %' order by length(aw.long) desc limit 1) a on true),
  -- where a quote names the programme it is about
  cand as (select 1 k, 'subject' mode, btrim((regexp_match(own.q, '(?:entry|admission)\s+requirements?\s+(?:for|of)\s+(?:the\s+)?(.*)$', 'i'))[1]) t from own
           union all select 2, 'subject', btrim((regexp_match(own.q, '^an?\s+(.*)\s+applicants?\M', 'i'))[1]) from own
           union all select 3, 'heading', own.q from own),
  -- 1. an abbreviation: award short form, then the capitals of the field, then the credit
  r1 as (select cand.k, nm.name || coalesce(' (' || nm.credit || ')', '') v
           from own cross join cand
           cross join lateral (select substring(cand.t from '^([A-Z][A-Za-z]*[A-Z][A-Za-z]*)') name,
                                      substring(cand.t from '^[A-Za-z]+\s*\(([0-9]{2,3})(?:\s*(?:[Cc]redits?|[Pp]oints?))?\)') credit) nm
           join lateral (select aw.abbr, regexp_replace(substr(nm.name, length(aw.abbr) + 1), '[^A-Z]', '', 'g') rest
                           from aw where left(nm.name, length(aw.abbr)) = aw.abbr and length(nm.name) > length(aw.abbr) order by length(aw.abbr) desc limit 1) ab on true
          where cand.t is not null and own.award is not null
            and (cand.mode <> 'heading' or cand.t ~ '^[A-Z][A-Za-z]*[A-Z][A-Za-z]*(\s*\([^)]*\))?(\s*(,|and|&)\s*[A-Z][A-Za-z]*[A-Z][A-Za-z]*(\s*\([^)]*\))?)*\s+[A-Z]')
            and (ab.abbr <> own.award or (own.init is not null and ab.rest <> '' and ab.rest <> own.init)
                 or (nm.credit is not null and own.credit is not null and nm.credit <> own.credit))),
  -- 2. a programme title of the same provider (the longest that fits decides; the course's own title with the same credit is not another)
  r2 as (select cand.k, (select z.t || coalesce(' (' || z.credit || ')', '')
                           from (select y.t, substring(substr(cand.t, length(y.t) + 1) from '^\s*\(([0-9]{2,3})(?:\s*(?:[Cc]redits?|[Pp]oints?))?\)') credit
                                   from (select distinct btrim(regexp_replace(s.canonical_title, '\s*\([^)]*\)', '', 'g')) t
                                           from catalogue.courses s where s.provider_id = own.provider_id) y
                                  where y.t <> '' and left(lower(cand.t), length(y.t)) = lower(y.t)
                                    and exists (select 1 from aw where lower(y.t) like lower(aw.long) || ' %')
                                    and (cand.mode <> 'heading' or substr(cand.t, length(y.t) + 1) ~ '^\s*(\([^)]*\))?\s+[A-Z]')
                                    and (cand.mode <> 'subject' or substr(cand.t, length(y.t) + 1) ~ '^(\s*\([^)]*\))?([^[:alnum:]]|$)')
                                  order by length(y.t) desc, y.t limit 1) z
                          where lower(z.t) <> lower(own.base) or (z.credit is not null and own.credit is not null and z.credit <> own.credit)) v
           from cand cross join own where cand.t is not null)
  select coalesce((select v from r1 order by k limit 1), (select v from r2 where v is not null order by k limit 1))
$$;
revoke all on function security.course_entry_variant_v1(uuid, text) from public, anon, authenticated;
comment on function security.course_entry_variant_v1(uuid, text) is 'CF-247 E13: the other programme (sibling variant) a course entry quote is about, or null when it is the course''s own or the check does not apply (entry.variant_check, entry.variant_check_off_providers, entry.award_abbreviations).';

-- ---------------------------------------------------------------- the whole-read completeness gate of one Layer 4 course entry item
create or replace function security.course_entry_gate_v1(p_item uuid, p_exclude uuid[] default '{}') returns jsonb
language plpgsql stable security definer set search_path to '' as $$
declare r pipeline.layer4_review_items%rowtype; v_drop jsonb; v_cut int; v_joined jsonb; v_other jsonb; v_shared jsonb; v_why text[] := '{}';
begin
  select * into r from pipeline.layer4_review_items where id = p_item;
  if r.id is null or r.field_code <> 'course_entry_first_read' then return null; end if;
  v_drop := coalesce(r.proposed_value->'dropped',
                     (select f.value->'dropped' from pipeline.field_enrich_items f where f.id = nullif(r.proposed_value->>'item_id', '')::bigint), '[]'::jsonb);
  select count(*) into v_cut from jsonb_array_elements(v_drop) d where d->>'reason' = 'over_row_limit';
  select coalesce(jsonb_agg(jsonb_build_object('kind', d->>'kind', 'quote', d->>'quote')), '[]'::jsonb) into v_joined
    from jsonb_array_elements(v_drop) d where d->>'reason' = 'over_row_limit' and security.course_entry_joined_v1(d->>'quote', d->>'kind');
  select coalesce(jsonb_agg(jsonb_build_object('id', x.id, 'names', n.v, 'quote', x.quote) order by x.kind, x.id), '[]'::jsonb) into v_other
    from catalogue.course_entry_requirements x cross join lateral (select security.course_entry_variant_v1(x.course_id, x.quote) v) n
   where x.provenance->>'review_item_id' = p_item::text and x.status = 'proposed' and not (x.id = any (coalesce(p_exclude, '{}'::uuid[]))) and n.v is not null;
  -- the course's stored page is also the page of a differently named programme (a combined page): its rows cannot be told apart by programme
  select coalesce(jsonb_agg(distinct c2.canonical_title), '[]'::jsonb) into v_shared
    from pipeline.coverage_course_pages g1
    join catalogue.courses c1 on c1.id = g1.course_id
    join pipeline.coverage_course_pages g2 on g2.url = g1.url and g2.course_id <> g1.course_id
    join catalogue.courses c2 on c2.id = g2.course_id
   where g1.course_id = r.entity_id  -- titles compared without "(Level n)", spacing and punctuation, so a duplicate record of the same programme is not another
     and lower(regexp_replace(regexp_replace(c2.canonical_title, '\(Level [0-9]+\)', '', 'gi'), '[^[:alnum:]]', '', 'g'))
         <> lower(regexp_replace(regexp_replace(c1.canonical_title, '\(Level [0-9]+\)', '', 'gi'), '[^[:alnum:]]', '', 'g'))
     and security.pipeline_num_v1('entry.shared_page_hold', 1) >= 1 and security.pipeline_num_v1('entry.variant_check', 1) >= 1
     and not (coalesce(security.toolset_setting('pipeline', 'entry.variant_check_off_providers'), '[]'::jsonb) ? c1.provider_id::text);
  if v_cut > 0 then
    v_why := v_why || format('the reader cut %s requirement(s) on this page at its row limit, so the read is incomplete: reject it', v_cut);
  end if;
  if jsonb_array_length(v_joined) > 0 then
    v_why := v_why || format('%s of the cut requirement(s) belong to a requirement that was kept (for example "%s")', jsonb_array_length(v_joined), left(v_joined->0->>'quote', 80));
  end if;
  if jsonb_array_length(v_other) > 0 then
    v_why := v_why || format('%s waiting row(s) are about another programme (%s): leave them out with Approve except, or reject the read',
                             jsonb_array_length(v_other), (select string_agg(distinct o->>'names', ', ') from jsonb_array_elements(v_other) o));
  end if;
  if jsonb_array_length(v_shared) > 0 then
    v_why := v_why || format('the stored page is also the page of %s other programme(s) (%s), so its rows cannot be told apart by programme: reject the read',
                             jsonb_array_length(v_shared), (select string_agg(t, ', ') from (select jsonb_array_elements_text(v_shared) t limit 3) z)
                             || case when jsonb_array_length(v_shared) > 3 then ', …' else '' end);
  end if;
  return jsonb_build_object('rule', 'E13', 'complete', cardinality(v_why) = 0, 'rows_cut', v_cut, 'joined', v_joined, 'other_programme', v_other,
                            'shared_page', v_shared, 'reasons', to_jsonb(v_why));
end $$;
revoke all on function security.course_entry_gate_v1(uuid, uuid[]) from public, anon, authenticated;
comment on function security.course_entry_gate_v1(uuid, uuid[]) is 'CF-247 E13: whole-read completeness of a Layer 4 course entry item: rows cut by the row limit (joined conditions named), waiting rows about another programme (less the rows left out), and a stored page shared with a differently named programme (entry.shared_page_hold). complete=false holds approval.';

-- ---------------------------------------------------------------- 1. the reader: whole read or held whole
select pg_temp.replace_once('security.enrich_entry_record_v1(bigint,jsonb)', '857102dc182426a841a41e7244f7a088', '9757abeeb3700c5cd2e02385def05869', $def$
create or replace function security.enrich_entry_record_v1(p_item bigint, p_r jsonb) returns text
language plpgsql security definer set search_path to '' as $$
declare i pipeline.field_enrich_items%rowtype; g record; x jsonb; v_in int := 0; v_drop jsonb := coalesce(p_r->'value'->'dropped', '[]'::jsonb);
        v_notes jsonb := '[]'::jsonb; v_max int; v_conf numeric := security.pipeline_num_v1('entry.min_confidence', 0.8); v_kind text; v_q text; v_d text;
        v_score numeric; v_basis text; v_band text; v_aud text; v_c numeric; v_review uuid; v_ids uuid[] := '{}'; v_id uuid; v_other text;
        v_keep jsonb := '[]'::jsonb; v_n int; v_joined int;
begin
  select * into i from pipeline.field_enrich_items where id = p_item for update;
  if i.id is null or i.course_id is null then return 'nothing'; end if;
  select pg.provider_id, pg.identity_basis, pg.url, pg.evidence_id, e.captured_at, security.coverage_country(pg.provider_id) cc into g
    from pipeline.coverage_course_pages pg left join pipeline.evidence_artifacts e on e.id = pg.evidence_id where pg.course_id = i.course_id;
  if g.provider_id is null or not security.coverage_identity_allowed(g.provider_id, g.identity_basis, 'entry_requirements') then
    update pipeline.field_enrich_items set state = 'skipped', reason = 'the page''s proof (' || coalesce(g.identity_basis, 'none') || ') does not admit entry requirements for this country', updated_at = now() where id = i.id;
    return 'not_admitted';
  end if;
  if jsonb_array_length(coalesce(p_r->'value'->'rows', '[]'::jsonb)) = 0 then
    update pipeline.field_enrich_items set state = 'skipped', reason = coalesce(nullif(p_r->>'reason', ''), 'the page does not state it'), value = jsonb_build_object('dropped', v_drop, 'coverage', p_r->'value'->'coverage'), updated_at = now() where id = i.id;
    return 'not_stated';
  end if;
  -- an earlier read of this course still waits for a person: nothing is proposed twice
  if exists (select 1 from pipeline.layer4_review_items r where r.entity_type = 'course' and r.entity_id = i.course_id and r.field_code = 'course_entry_first_read' and r.status = 'pending') then
    update pipeline.field_enrich_items set state = 'skipped', reason = 'an earlier read of this course waits in Layer 4', updated_at = now() where id = i.id;
    return 'already';
  end if;
  -- E13: the course's row limit (entry.max_rows_per_course, or the provider's own value in entry.max_rows_by_provider)
  v_max := security.course_entry_max_rows_v1(g.provider_id);
  for x in select * from jsonb_array_elements(p_r->'value'->'rows') loop
    v_kind := x->>'kind'; v_q := left(btrim(coalesce(x->>'quote', '')), 300); v_d := left(btrim(coalesce(x->>'description', '')), 500);
    v_c := case when x->>'confidence' ~ '^[0-9.]+$' then (x->>'confidence')::numeric end;
    v_score := case when x->>'min_entry_score' ~ '^[0-9]+(\.[0-9]+)?$' then (x->>'min_entry_score')::numeric end;
    v_basis := nullif(btrim(coalesce(x->>'min_entry_score_basis', '')), '');
    v_band := nullif(btrim(coalesce(x->>'benchmark_band', '')), '');
    if v_kind is null or v_kind not in ('prior_qualification', 'minimum_grade', 'subject_prerequisite', 'portfolio_interview', 'work_experience', 'override', 'general_note') then
      v_drop := v_drop || jsonb_build_object('reason', 'kind_unknown', 'kind', v_kind, 'quote', v_q); continue;
    end if;
    if length(v_q) < 4 then v_drop := v_drop || jsonb_build_object('reason', 'no_quote', 'kind', v_kind); continue; end if;
    if coalesce(v_c, 0) < v_conf then v_drop := v_drop || jsonb_build_object('reason', 'low_confidence', 'kind', v_kind, 'quote', v_q); continue; end if;
    -- the English requirement is its own field: a row about an English test or English proficiency is never stored here (B1 rule)
    if (v_q || ' ' || v_d) ~* '(\mielts\M|\mtoefl\M|\mpte\M|\mduolingo\M|cambridge english|\moet\M|english language (requirement|proficiency|test)|english proficiency)' then
      v_drop := v_drop || jsonb_build_object('reason', 'english_duplicate', 'kind', v_kind, 'quote', v_q); continue;
    end if;
    -- no numeric score without its basis: both the number and the basis words are printed in the quote (B1 rule)
    if v_score is not null and (v_basis is null or strpos(lower(regexp_replace(v_q, '\s+', ' ', 'g')), lower(regexp_replace(v_basis, '\s+', ' ', 'g'))) = 0
                                or not exists (select 1 from regexp_matches(v_q, '([0-9]+(\.[0-9]+)?)', 'g') m where m[1]::numeric = v_score)) then
      v_drop := v_drop || jsonb_build_object('reason', 'score_without_basis', 'kind', v_kind, 'quote', v_q); continue;
    end if;
    if v_score is null then v_basis := null; end if;
    -- a band only when the quote prints it exactly; never derived (Platform Admin 28 Oct 2026: no ATAR-to-band mapping)
    if v_band is not null and strpos(lower(v_q), lower(v_band)) = 0 then
      v_notes := v_notes || jsonb_build_object('note', 'band_not_printed', 'band', v_band, 'quote', v_q); v_band := null;
    end if;
    -- audience from the quote's own words; international applicability is never inferred
    v_aud := case when v_q ~* '\m(international|overseas)\M' then 'international'
                  when v_q ~* '(\mVCE\M|\mATAR\M|\mVTAC\M|\mSTAT\M|Australian Year 12)' then 'domestic'
                  -- CF-247 AER NZ (Platform Admin mandate 29 Oct 2026 12:23 B4): NZ school-leaver routes, never inferred to apply internationally
                  when g.cc = 'NZ' and v_q ~* '(\mNCEA\M|University Entrance|\mUE\M)' then 'domestic' else 'all' end;
    -- E13: a row about another programme (a sibling variant on a combined page) is not this course's and does not count towards the limit
    v_other := security.course_entry_variant_v1(i.course_id, v_q);
    if v_other is not null then v_drop := v_drop || jsonb_build_object('reason', 'other_programme', 'kind', v_kind, 'quote', v_q, 'names', v_other); continue; end if;
    v_keep := v_keep || jsonb_build_object('kind', v_kind, 'audience', v_aud, 'description', coalesce(nullif(v_d, ''), v_q), 'min_grade', nullif(btrim(coalesce(x->>'min_grade', '')), ''),
                                           'min_entry_score', v_score, 'min_entry_score_basis', v_basis, 'benchmark_band', v_band, 'quote', v_q, 'confidence', v_c);
  end loop;
  v_n := jsonb_array_length(v_keep);
  -- E13 (Platform Admin 2 Nov 2026 05:18): a read with more rows than its limit is held whole, never proposed in part (the rule the reader
  -- already applies to cut answers and unread slices). Every row read is kept on the item; the rows past the limit are recorded as dropped.
  if v_n > v_max then
    select count(*) filter (where security.course_entry_joined_v1(k->>'quote', k->>'kind')) into v_joined from jsonb_array_elements(v_keep) with ordinality t(k, o) where o > v_max;
    select v_drop || coalesce(jsonb_agg(jsonb_build_object('reason', 'over_row_limit', 'kind', k->>'kind', 'quote', k->>'quote') order by o), '[]'::jsonb) into v_drop
      from jsonb_array_elements(v_keep) with ordinality t(k, o) where o > v_max;
    update pipeline.field_enrich_items set state = 'skipped',
           reason = left(format('held_partial: over_row_limit: the page has %s requirements and the limit is %s%s; nothing proposed (E13)', v_n, v_max,
                                case when v_joined > 0 then format(', %s of those past the limit joined to an earlier requirement', v_joined) else '' end), 300),
           value = jsonb_build_object('held', 'over_row_limit', 'limit', v_max, 'rows_read', v_keep, 'dropped', v_drop, 'notes', v_notes, 'coverage', p_r->'value'->'coverage'),
           updated_at = now() where id = i.id;
    return 'held_partial';
  end if;
  for x in select * from jsonb_array_elements(v_keep) loop
    insert into catalogue.course_entry_requirements(course_id, kind, audience, description, min_grade, min_entry_score, min_entry_score_basis, benchmark_band,
                                                    quote, source_url, evidence_id, confidence, as_at, status, provenance)
    values (i.course_id, x->>'kind', x->>'audience', x->>'description', x->>'min_grade', (x->>'min_entry_score')::numeric, x->>'min_entry_score_basis', x->>'benchmark_band',
            x->>'quote', g.url, coalesce(i.evidence_id, g.evidence_id), (x->>'confidence')::numeric, coalesce(g.captured_at::date, current_date), 'proposed',
            jsonb_build_object('reader', 'enrich_ai', 'field', 'entry_requirements', 'item_id', i.id, 'job_id', i.job_id, 'model', p_r->>'model',
                               'worker', p_r->>'worker', 'prompt', p_r->>'prompt_version'))
    returning id into v_id;
    v_ids := v_ids || v_id; v_in := v_in + 1;
  end loop;
  if v_in = 0 then
    update pipeline.field_enrich_items set state = 'skipped', reason = 'no row met the admission rules', value = jsonb_build_object('dropped', v_drop, 'notes', v_notes, 'coverage', p_r->'value'->'coverage'), updated_at = now() where id = i.id;
    return 'not_admitted';
  end if;
  insert into pipeline.layer4_review_items(entity_type, entity_id, field_code, evidence_id, before_value, proposed_value, layer2_state, layer3_state,
                                           status, escalation_reason, change_control_ref)
  values ('course', i.course_id, 'course_entry_first_read', coalesce(i.evidence_id, g.evidence_id),
          jsonb_build_object('active_rows', (select count(*) from catalogue.course_entry_requirements r where r.course_id = i.course_id and r.status = 'active')),
          jsonb_build_object('item_id', i.id, 'url', g.url, 'rows', v_in, 'limit', v_max, 'dropped', v_drop, 'notes', v_notes,
            'sample', (select jsonb_agg(jsonb_build_object('id', r.id, 'kind', r.kind, 'audience', r.audience, 'description', r.description, 'min_entry_score', r.min_entry_score,
                                         'min_entry_score_basis', r.min_entry_score_basis, 'benchmark_band', r.benchmark_band, 'quote', r.quote) order by r.kind)
                         from catalogue.course_entry_requirements r where r.id = any (v_ids))),
          jsonb_build_object('source', 'course entry reader', 'page', g.url, 'identity_basis', g.identity_basis),
          jsonb_build_object('item_id', i.id, 'model', p_r->>'model'),
          'pending', 'Course entry requirements first read: a person admits the rows before any is active (Track C Step B)', 'CF-CHG-20260915-247')
  returning id into v_review;
  update catalogue.course_entry_requirements set provenance = provenance || jsonb_build_object('review_item_id', v_review) where id = any (v_ids);
  update pipeline.field_enrich_items set state = 'review', reason = null, quote = left((select r.quote from catalogue.course_entry_requirements r where r.id = v_ids[1]), 300),
         value = jsonb_build_object('rows', v_in, 'limit', v_max, 'review_item_id', v_review, 'dropped', v_drop, 'notes', v_notes, 'coverage', p_r->'value'->'coverage'), updated_at = now() where id = i.id;
  return 'review';
end $$
$def$);

-- ---------------------------------------------------------------- 2. approval: an incomplete read never reaches approval
select pg_temp.edit_once('security.course_entry_review_apply_v1(uuid,text,jsonb,text)', 'ce8d0bad9717034342f165b1876fb632', '4be9267d8419dee7d9f80cb96ff4098b', array[
 array[$o$declare r pipeline.layer4_review_items%rowtype; v_ex uuid[]; v_on int := 0; v_off int := 0; v_sup int := 0; v_enrich bigint;$o$,
       $n$declare r pipeline.layer4_review_items%rowtype; v_ex uuid[]; v_on int := 0; v_off int := 0; v_sup int := 0; v_enrich bigint; v_gate jsonb;$n$],
 array[$o$    v_ex := coalesce(array(select jsonb_array_elements_text(coalesce(p_final->'exclude_row_ids', '[]'::jsonb))::uuid), '{}');
$o$,
       $n$    v_ex := coalesce(array(select jsonb_array_elements_text(coalesce(p_final->'exclude_row_ids', '[]'::jsonb))::uuid), '{}');
    -- E13 (Platform Admin 2 Nov 2026 05:18): an incomplete read never reaches approval. Rows cut by the row limit (a joined condition among
    -- them named), a waiting row about another programme that is not left out, or a page shared with another programme hold the whole
    -- decision; nothing is changed
    v_gate := security.course_entry_gate_v1(p_item, v_ex);
    if v_gate is not null and not coalesce((v_gate->>'complete')::boolean, true) then
      raise exception 'Held (E13, incomplete read): %. Nothing was changed',
        (select string_agg(w, '; ') from jsonb_array_elements_text(v_gate->'reasons') w) using errcode = '55000';
    end if;
$n$]],
 array[1, 1]);

-- ---------------------------------------------------------------- 3. the review screen shows the gate
select pg_temp.edit_once('security.aer_review_read_v1(uuid)', '62793b3544874e91a1e2aa26b80e8a14', '50c31fc4df16b7bbbb39dab03aa9f9b2', array[
 array[$o$    'lineage', security.aer_review_lineage_v1(p_item), 'rows', v_rows,$o$,
       $n$    'lineage', security.aer_review_lineage_v1(p_item), 'rows', v_rows,
    -- E13: a course entry read's completeness (rows cut by the row limit, rows about another programme, a shared page); approval is held while incomplete
    'completeness_gate', case when i.field_code = 'course_entry_first_read' then security.course_entry_gate_v1(i.id) end,$n$]],
 array[1]);
