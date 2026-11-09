-- Consumer API change approved: Platform Admin (Mandeep Singh), 9 Nov 2026, in chat: G3 change approved for R23 and R24 on condition of API compatibility tests, developer guide and versioned handover
-- G3 approval recorded above (Platform Admin, 9 Nov 2026: "G3 change is approved in principle. Complete the required API compatibility tests,
-- developer guide, versioned handover and record the formal G3 approval before merging. Do not release an unvalidated consumer contract
-- change."). The conditions are met in this change and its admin counterpart: the compatibility evidence (isolated PostgreSQL fixture and the
-- live rolled-back comparison, admin docs/platform/approvals/2026-11-06-g3-r23-r24-approval-package.md section 11), developer guide Issue 8 and
-- its versioned handover note. Nothing here has been applied to any database by the author.
--
-- CF-247 Website API v2, developer requests R23 and R24 (developer feedback of 5 Nov 2026; Platform Admin decision 5 Nov 2026 19:14 §5;
-- mandate 3 Nov 2026 11:46 §2-§3; design: admin docs/platform/nz-enrichment-brief/2026-11-03-website-api-v2-change-proposal.md §2-§3).
-- Why (live, read-only, 5 Nov 2026 AEDT; figures in the approval package §3):
--   R23 The provider campus list merges every campus that shares a city, postcode, state and regional class into one item and carries no
--       campus name, identity or course count (University of Auckland: 8 campuses returned as 1 item "Auckland").
--   R24 citizenship_eligibility is empty for most published scholarships; an empty list does not mean "open to every nationality", but
--       nothing in the response says which it is.
-- What (additive only; no existing key, value, filter, edge function or caller changes):
--   R23 api.website_v2_provider_campuses (whole replacement, md5-guarded): one item per campus by its stable identity
--       (catalogue.campuses.stable_key), never merged by city or postcode. Each item keeps city, postcode, subdivision_code, metro_area,
--       regional_category and regional_category_name, with the same values, and gains
--         campus_id     text     the campus's stable key;
--         campus_name   text     the stored campus name (null when blank: null means not held);
--         course_count  integer  distinct courses the API returns linked to this campus: in search.course_documents, of this provider, and
--                                not held back by security.layer4_search_blocked_courses (Layer 4 search blocks, providers whose Published
--                                switch is off or which are not active, and courses that are not active). The same rule as the
--                                provider's course_count, restricted to the campus. One grouped read per provider, never one per campus.
--       The campuses included are as before (a city held, campus not inactive). Items are ordered by campus name (blank last), then
--       campus_id. The provider list itself (and so the Published switch on providers) is decided by the unchanged callers.
--   R24 api.website_v2_scholarship_item (one md5-guarded edit): adds nationality_eligibility_status, the first that applies of
--         under_review  a pending Layer 4 item on who the scholarship is for (field nationalities, nationality, citizenship_eligibility,
--                       audience or student_type), or a pending scholarship AI review whose reason is who it is for;
--         restricted    the list the API returns (citizenship_eligibility) names at least one country or region code; or an active
--                       extracted nationality / citizenship_and_residency criterion names codes (its quote is held) although the list is
--                       still empty; or the API's student_type is domestic (domestic students only);
--         unrestricted  no code is held and the nationality reading holds an explicit "any nationality" phrase (key ANY);
--         unknown       otherwise: nothing on nationality is held. An empty list is never read as unrestricted.
--       citizenship_eligibility and eligible_countries_list are unchanged (codes as held; region codes R-* keep their region meaning).
-- Not changed: course search and detail campuses[] (also read by Zoho through the same item builder; decision P3), the nationality_codes
-- filter, rankings, entry, tuition, every public.website_v2_* wrapper, every edge function (the edge baseline hashes are unchanged).
-- Zoho (corrected 9 Nov 2026 after independent QA): public.zoho_v2_providers passes the website campuses[] items through (count, order and the three
-- new keys change) and public.zoho_v2_passthrough 'scholarships' / 'scholarship' return the new nationality_eligibility_status key; zoho_v2_provider
-- (detail), the Zoho sync items and zoho_edge_* are unaffected. Additive for Zoho; the Zoho developer is told before the release.
-- Replaces: api.website_v2_provider_campuses(uuid), api.website_v2_scholarship_item(uuid) (same names and signatures; md5-guarded);
--   supersedes the unmerged prepared migration 20261103180000_cf247_website_api_v2_campus_nationality.sql (branch
--   cf247-website-api-v2-campus-nationality, never applied)
-- Retires: nothing
-- Nothing dropped, deleted or renamed. No table, job, status or setting is created here. The approval setting is created by the Platform
-- Admin's approval paste (approval package §9), not by this migration. The migration does read that setting (step 0) and re-takes the
-- consumer API baseline (step 4).
--
-- Release order (approval package §9): 1. the Platform Admin's approval paste creates pipeline setting api.v2_r23_r24_approved = 1 (reason
--   quoting the 9 Nov 2026 approval); 2. this migration applies (it refuses without the setting and changes nothing); 3. security.consumer_api_check_v1()
--   must report no drift; 4. developer guide Issue 8 is sent with the release date. If the setting is missing the migration stops at step 0,
--   so it must exist before the release applies migrations.

-- 0. G3 approval gate: refuse unless the Platform Admin has recorded approval as pipeline setting api.v2_r23_r24_approved = 1. The setting is
--    a Platform Admin write (never created by a migration, so a migration cannot approve itself); a missing setting reads as 0 and refuses.
do $approval$
begin
  -- fixed: approval gate value (1 = approved); a governance flag, not an operational value
  if coalesce(security.pipeline_num_v1('api.v2_r23_r24_approved', 0), 0) <> 1 then
    raise exception 'CF-247 Website API v2 R23/R24 consumer change: setting api.v2_r23_r24_approved is not 1 (no recorded Platform Admin approval): not applied'
      using hint = 'Record the approval (admin docs/platform/approvals/2026-11-06-g3-r23-r24-approval-package.md §9) before applying this migration.';
  end if;
end $approval$;

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

create or replace function pg_temp.replace_once(p_sig text, p_before text, p_after text, p_def text) returns text language plpgsql as $f$
begin
  if md5(pg_get_functiondef(p_sig::regprocedure)) = p_after then return p_sig || ': already applied'; end if;
  if md5(pg_get_functiondef(p_sig::regprocedure)) <> p_before then
    raise exception 'live % differs from the definition this change replaces (md5 %)', p_sig, md5(pg_get_functiondef(p_sig::regprocedure)); end if;
  execute p_def;
  if md5(pg_get_functiondef(p_sig::regprocedure)) <> p_after then
    raise exception '% after the replacement has md5 %, expected %', p_sig, md5(pg_get_functiondef(p_sig::regprocedure)), p_after; end if;
  return p_sig || ': applied';
end $f$;

-- 1. what the new code reads, and the consumer wrappers that embed it, are the live definitions this change was written and tested
--    against (live, 5 Nov 2026; none of them is changed here)
do $g$
declare r record;
begin
  for r in select * from (values
      ('security.place_presentable(text)', 'a7b720fc9b34203d0a23315376fd483a'),
      ('public.website_v2_providers(jsonb,integer,integer,text)', '73ba533ee2f4c20b840c4cf172c17912'),
      ('public.website_v2_scholarships(jsonb,integer,integer)', 'b3a616d8ec31a86ffa3e770cf24db0af'),
      ('public.website_v2_scholarship(text)', '79131c22331c7439438177517bd1ba12')) v(sig, m) loop
    if md5(pg_get_functiondef(r.sig::regprocedure)) <> r.m then
      raise exception 'live % differs from the definition this change was written against', r.sig; end if;
  end loop;
  for r in select * from (values
      ('security.layer4_search_blocked_courses', '35cdaa19a775ffaaf60fc2be302affec'),
      ('security.layer4_active_blocks', '300ac7ca5fe9b72b13e2647a861ea8c6'),
      ('security.provider_hidden_v1', 'c8e2c132cc6fa8a52dccdbb04317707b')) v(rel, m) loop
    if md5(pg_get_viewdef(r.rel::regclass)) <> r.m then
      raise exception 'live % differs from the definition this change was written against', r.rel; end if;
  end loop;
end $g$;

-- 2. R23: provider campuses, one item per campus with campus_id, campus_name and course_count
select pg_temp.replace_once('api.website_v2_provider_campuses(uuid)', '57115d3b8ddbc40729ec04078ee15d41', '698afad0bc236a314fb356632938c403', $def$
CREATE OR REPLACE FUNCTION api.website_v2_provider_campuses(p_provider_id uuid)
 RETURNS jsonb
 LANGUAGE sql
 STABLE
 SET search_path TO 'pg_catalog', 'catalogue', 'ref', 'pipeline', 'security'
AS $function$
  -- CF-247 Website API v2 developer request (Platform Admin mandate 3 Nov 2026 11:46 §2): one item per campus by its stable identity (never
  -- merged by city or postcode), with additive campus_id, campus_name and course_count. The existing keys and the campuses included are as
  -- before. course_count: distinct courses the API returns (search documents, not held back by Layer 4) linked to this campus; one grouped
  -- read per provider, never one read per campus.
  with k as (
    select k.id, k.stable_key, k.name, k.city, k.postcode, k.subdivision_id
      from catalogue.campuses k
     where k.provider_id = p_provider_id and nullif(btrim(k.city),'') is not null and coalesce(k.status,'active') <> 'inactive'),
  n as (
    -- the provider's returned courses, then their campus links; the Layer 4 check is made per course (an anti-join would build the whole
    -- view on every call)
    select cc.campus_id, count(distinct cc.course_id) n
      from search.course_documents d
      join catalogue.course_campuses cc on cc.course_id = d.course_id
     where d.provider_id = p_provider_id
       and (select count(*) from security.layer4_search_blocked_courses b where b.course_id = cc.course_id) = 0
     group by cc.campus_id)
  select coalesce(jsonb_agg(jsonb_build_object('city', security.place_presentable(k.city), 'postcode', k.postcode, 'subdivision_code', s.code,
           'metro_area', rc.metro_area, 'regional_category', rc.category, 'regional_category_name', rc.category_name,
           'campus_id', k.stable_key, 'campus_name', nullif(btrim(k.name),''), 'course_count', coalesce(n.n, 0))
           order by lower(nullif(btrim(k.name),'')) nulls last, k.stable_key), '[]'::jsonb)
  from k
  left join ref.subdivisions s on s.id = k.subdivision_id
  left join pipeline.campus_regional_class rc on rc.campus_id = k.id
  left join n on n.campus_id = k.id
$function$
$def$);

-- 3. R24: scholarship nationality_eligibility_status, beside the unchanged lists
select pg_temp.edit_once('api.website_v2_scholarship_item(uuid)', 'd1792cc7161101ce8c22abad70ecbd36', '04532402307717c6dab17567551364e1', array[
 array[$o$    'citizenship_eligibility', to_jsonb((select codes from nat)), 'eligible_countries_list', to_jsonb((select codes from nat)),
$o$, $n$    'citizenship_eligibility', to_jsonb((select codes from nat)), 'eligible_countries_list', to_jsonb((select codes from nat)),
    -- CF-247 Website API v2 developer request (mandate 3 Nov 2026 11:46 §3): additive; an empty list is never read as unrestricted
    'nationality_eligibility_status', case
       when exists (select 1 from pipeline.layer4_review_items r where r.entity_type = 'scholarship' and r.entity_id = s.id and r.status = 'pending'
                      and r.field_code in ('nationalities', 'nationality', 'citizenship_eligibility', 'audience', 'student_type'))
         or exists (select 1 from pipeline.scholarship_ai_reviews a where a.scholarship_id = s.id and a.status = 'pending' and a.reason ~* 'who it is for')
         then 'under_review'
       when coalesce(cardinality((select codes from nat)), 0) > 0 or (select v from st) = 'domestic'
         or exists (select 1 from cr where cr.criterion_type in ('nationality', 'citizenship_and_residency') and cardinality(cr.value_codes) > 0)
         then 'restricted'
       when exists (select 1 from scholarship.nationality_readings nr where nr.scholarship_id = s.id and cardinality(nr.codes) = 0 and nr.phrases ? 'ANY')
         then 'unrestricted'
       else 'unknown' end,
$n$]],
 array[1]);

-- 4. G3 baseline. Re-taken last, so it records only this approved change: first refuse if any consumer API function other than the two this change
--    replaces differs from the baseline (the baseline would otherwise absorb an unrelated, unapproved change). Compared as the guard compares
--    (search_path empty, so type names print the same way).
create or replace function pg_temp.consumer_drift_v1() returns jsonb language sql stable set search_path = '' as $f$
  select coalesce(jsonb_agg(x.name order by x.name), '[]'::jsonb)
    from (select f.name from security.consumer_api_functions_v1() f
            left join pipeline.consumer_api_baseline b on b.kind = 'function' and b.name = f.name
           where b.name is null or b.md5 is distinct from pg_catalog.md5(pg_catalog.pg_get_functiondef(f.oid))
          union
          select b.name from pipeline.consumer_api_baseline b
           where b.kind = 'function' and not exists (select 1 from security.consumer_api_functions_v1() f where f.name = b.name)) x
$f$;
do $b$
declare v_other jsonb;
begin
  select coalesce(jsonb_agg(d), '[]'::jsonb) into v_other
    from jsonb_array_elements_text(pg_temp.consumer_drift_v1()) d
   where d not in ('api.website_v2_provider_campuses(uuid)', 'api.website_v2_scholarship_item(uuid)');
  if jsonb_array_length(v_other) > 0 then
    raise exception 'CF-247 R23/R24: consumer API objects other than the two approved functions differ from the baseline (%): not re-baselined', left(v_other::text, 600);
  end if;
end $b$;

select security.consumer_api_rebaseline_v1('R23/R24 (website developer requests; mandate 3 Nov 2026 11:46; decision 5 Nov 2026 19:14 section 5): additive campus_id, campus_name, course_count on provider campuses[] and nationality_eligibility_status on scholarships; approved Platform Admin (Mandeep Singh) 9 Nov 2026');
