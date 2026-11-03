-- Consumer API change approved: PENDING — Platform Admin approval required (mandate 3 Nov 2026 11:46 §7)
-- CF-247 Website API v2 developer request (Platform Admin mandate 3 Nov 2026 11:46; admin docs/platform/nz-enrichment-brief/
-- 2026-11-03-website-api-v2-change-proposal.md). PREPARED, NOT APPROVED: this migration refuses to apply (step 0) until the Platform Admin
-- records approval. Until then nothing here may be merged, deployed or re-baselined.
-- Why (live, read-only, 3 Nov 2026 11:48-12:10 AEDT):
--   Campuses: the provider campus list merges every campus that shares a city, postcode, state and regional class into one item and carries no
--     campus name or identity (University of Auckland: 8 campuses returned as 1 item "Auckland"; George Brown College: 4 as 1 "Toronto");
--     256 providers (AU 228, NZ 20, CA 8) lose campuses this way (3,296 items for 3,808 campuses). Nothing tells the website how many courses
--     each campus has.
--   Nationality: `citizenship_eligibility` is empty for 1,070 of 1,148 published scholarships; an empty list does not mean "open to every
--     nationality", but nothing in the response says which it is.
-- What (additive only; no existing key, value, order rule, filter or edge function changes):
--   C1 api.website_v2_provider_campuses (whole replacement, md5-guarded): one item per campus by its stable identity
--      (catalogue.campuses.stable_key), never merged by city or postcode. Each item keeps city, postcode, subdivision_code, metro_area,
--      regional_category and regional_category_name as before and gains campus_id (the stable key), campus_name (the stored campus name; null
--      when blank) and course_count (distinct courses the API returns linked to that campus: in the search documents, of this provider, not
--      held back by Layer 4). The campuses included are as before (a city held, not inactive). Counts come from one grouped read per provider,
--      never one read per campus. Items are ordered by campus name (a blank name last), then campus_id.
--   N1 api.website_v2_scholarship_item (one md5-guarded edit): adds nationality_eligibility_status, one of
--      under_review  an open Layer 4 item on who the scholarship is for (fields nationalities, nationality, citizenship_eligibility, audience,
--                    student_type) or a pending AI review whose reason is who it is for;
--      restricted    the list the API returns (citizenship_eligibility) names at least one country or region code, each read from the
--                    scholarship's own wording, or the scholarship is for domestic students only;
--      unrestricted  only when the nationality reading holds an explicit "any nationality" phrase (key ANY in its phrases) and no code; no
--                    reader writes it yet, so none on 3 Nov 2026;
--      unknown       otherwise: nothing on nationality is held. An empty list is never read as unrestricted.
--   citizenship_eligibility and eligible_countries_list are unchanged (codes as held; region codes R-* keep their region meaning).
-- Not changed (assessed, see the proposal): the course search and detail campuses[] (also read by Zoho through the same item builder), the
-- nationality_codes filter, rankings, entry, tuition. No edge function changes, so the edge baseline file keeps its hashes.
-- Replaces: api.website_v2_provider_campuses, api.website_v2_scholarship_item (same names; md5-guarded)
-- Retires: nothing
-- Nothing dropped, deleted or renamed. No table, job or status. No setting is created here: the approval setting is created by the Platform
-- Admin (proposal §9). On approval this file gets the approval line in place of PENDING and the baseline re-take below step 3.

-- 0. approval gate (G3): refuse unless the Platform Admin has recorded approval as pipeline setting api.v2_campus_nationality_approved = 1
do $approval$
begin
  -- fixed: approval gate value (1 = approved); not an operational value
  if coalesce(security.pipeline_num_v1('api.v2_campus_nationality_approved', 0), 0) <> 1 then
    raise exception 'CF-247 Website API v2 campus and nationality change is PENDING Platform Admin approval (mandate 3 Nov 2026 11:46 §7): not applied'
      using hint = 'Record the approval (admin 2026-11-03-website-api-v2-change-proposal.md §9) before applying this migration.';
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

-- 1. what the new code reads is what it was written against (not changed here)
do $g$
begin
  if md5(pg_get_functiondef('security.place_presentable(text)'::regprocedure)) <> 'a7b720fc9b34203d0a23315376fd483a' then
    raise exception 'live security.place_presentable(text) differs from the definition this change was written against'; end if;
  if md5(pg_get_viewdef('security.layer4_search_blocked_courses'::regclass)) <> '35cdaa19a775ffaaf60fc2be302affec' then
    raise exception 'live security.layer4_search_blocked_courses differs from the definition this change was written against'; end if;
end $g$;

-- 2. C1: provider campuses, one item per campus with campus_id, campus_name and course_count
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

-- 3. N1: scholarship nationality_eligibility_status, beside the unchanged lists
select pg_temp.edit_once('api.website_v2_scholarship_item(uuid)', 'd1792cc7161101ce8c22abad70ecbd36', '74fb94060500970a2b7dc8923afe04a7', array[
 array[$o$    'citizenship_eligibility', to_jsonb((select codes from nat)), 'eligible_countries_list', to_jsonb((select codes from nat)),
$o$, $n$    'citizenship_eligibility', to_jsonb((select codes from nat)), 'eligible_countries_list', to_jsonb((select codes from nat)),
    -- CF-247 Website API v2 developer request (mandate 3 Nov 2026 11:46 §3): additive; an empty list is never read as unrestricted
    'nationality_eligibility_status', case
       when exists (select 1 from pipeline.layer4_review_items r where r.entity_type = 'scholarship' and r.entity_id = s.id and r.status = 'pending'
                      and r.field_code in ('nationalities', 'nationality', 'citizenship_eligibility', 'audience', 'student_type'))
         or exists (select 1 from pipeline.scholarship_ai_reviews a where a.scholarship_id = s.id and a.status = 'pending' and a.reason ~* 'who it is for')
         then 'under_review'
       when coalesce(cardinality((select codes from nat)), 0) > 0 or (select v from st) = 'domestic' then 'restricted'
       when exists (select 1 from scholarship.nationality_readings nr where nr.scholarship_id = s.id and cardinality(nr.codes) = 0 and nr.phrases ? 'ANY')
         then 'unrestricted'
       else 'unknown' end,
$n$]],
 array[1]);

-- On approval, add here (G3): select security.consumer_api_rebaseline_v1('<decision>: additive campus_id, campus_name, course_count on provider
-- campuses[] and nationality_eligibility_status on scholarships; approved Platform Admin <date time>');
