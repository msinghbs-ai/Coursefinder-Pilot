-- CF-247 F-INT (S2-Intakes mandate, Platform Admin 13 Nov 2026 11:02: "Fix genuine technical blockers at their source: ... timeouts ... and stranded jobs").
-- Found (13 Nov 2026 11:26 AEDT): the hourly job intake-dates-apply failed at 23:26 and 00:26 UTC on the 2-minute statement time-out, the second time
--   after its batch was lowered from 200 to 120. The batch size is not the cause. A 6-row plan took 88 s: 67 s of it is
--   security.intake_wording_fp_v1, called 14,653 times while the planner checks which decided rows have changed inputs. Each call cost about 4.3 ms,
--   because the two SQL functions (security definer, so never inlined) are planned again on every call and evaluate the page-address variants inside an
--   OR. The same lookup written out inline takes about 0.5 ms.
-- What: security.intake_page_wording_v1 and security.intake_wording_fp_v1 are rewritten in PL/pgSQL with the same signatures, owner, grants and results.
--   coverage_course_pages has one row a course (its primary key is course_id), so the page row is read once; the exact address and final address are
--   compared first and the variants helper is called only when neither matches; the filled intake quotes are added after the page wording as before.
--   Measured on live data before release: 2,000 calls 8.6 s -> 0.8 s; identical wording text for 6,000 random intakes and identical fingerprints
--   for 8,035 intakes (a quarter of the planner's candidates, chosen by hash), so no decided row is re-planned because of this change.
-- Guards: G1 (no job), G2 (no operational value; no setting changes), G3 (no consumer API object), G4 (cf-247-s540).
-- Replaces: security.intake_page_wording_v1 and security.intake_wording_fp_v1 (same names, guarded by the md5 of the live bodies).
-- Retires: nothing.
-- Reversal: re-run the bodies eb380f591dc17bf536c94d999f4f1b26 (20261113182000) and 1433922c14f8b545cc3a09bb557dd9fb (LANGUAGE sql).

do $pre$ begin
  if md5((select p.prosrc from pg_proc p where p.oid = 'security.intake_page_wording_v1(uuid,uuid,text)'::regprocedure)) not in ('eb380f591dc17bf536c94d999f4f1b26')
     and (select p.prolang from pg_proc p where p.oid = 'security.intake_page_wording_v1(uuid,uuid,text)'::regprocedure) <> (select oid from pg_language where lanname = 'plpgsql') then
    raise exception 'live security.intake_page_wording_v1 differs from the definition this change replaces'; end if;
  if md5((select p.prosrc from pg_proc p where p.oid = 'security.intake_wording_fp_v1(uuid,uuid)'::regprocedure)) not in ('1433922c14f8b545cc3a09bb557dd9fb')
     and (select p.prolang from pg_proc p where p.oid = 'security.intake_wording_fp_v1(uuid,uuid)'::regprocedure) <> (select oid from pg_language where lanname = 'plpgsql') then
    raise exception 'live security.intake_wording_fp_v1 differs from the definition this change replaces'; end if;
end $pre$;

create or replace function security.intake_page_wording_v1(p_course uuid, p_evidence uuid, p_url text)
 returns text
 language plpgsql
 stable security definer
 set search_path to ''
as $function$
declare
  v_gurl text; v_final text; v_ctx jsonb; v_match boolean := false; v_page text; v_fill text;
begin
  -- the course's stored page (one row a course)
  select g.url, g.candidates->>'final_url', g.candidates->'intake_context' into v_gurl, v_final, v_ctx
    from pipeline.coverage_course_pages g where g.course_id = p_course;
  if found then
    if v_gurl = p_url or v_final = p_url then v_match := true;
    -- 12 Nov 2026 (F-INT): the same page with or without its trailing slash, or on another of the provider's own hosts (looked up only when needed)
    elsif v_gurl = any ((select security.course_page_url_variants_v1(co.provider_id, p_url) from catalogue.courses co where co.id = p_course)::text[]) then v_match := true;
    end if;
  end if;
  if v_match then
    v_page := (select string_agg(x, ' | ') from jsonb_array_elements_text(case when jsonb_typeof(v_ctx) = 'array' then v_ctx else '[]'::jsonb end) x);
  end if;
  v_fill := (select string_agg(f.quote, ' | ') from pipeline.field_enrich_items f
              where f.course_id = p_course and f.field = 'intakes' and f.state = 'filled' and f.evidence_id = p_evidence and nullif(btrim(f.quote), '') is not null);
  return case when v_page is null then v_fill when v_fill is null then v_page else v_page || ' | ' || v_fill end;
end
$function$;

create or replace function security.intake_wording_fp_v1(p_course uuid, p_evidence uuid)
 returns text
 language plpgsql
 stable security definer
 set search_path to ''
as $function$
begin
  return md5(coalesce((select string_agg(s, '|' order by s)
                         from (select distinct s from unnest(string_to_array(
                                 security.intake_page_wording_v1(p_course, p_evidence, (select e.source_url from pipeline.evidence_artifacts e where e.id = p_evidence)), ' | ')) s) z), ''));
end
$function$;

revoke all on function security.intake_page_wording_v1(uuid, uuid, text) from public, anon, authenticated;
revoke all on function security.intake_wording_fp_v1(uuid, uuid) from public, anon, authenticated;

do $post$ begin
  if (select p.prolang from pg_proc p where p.oid = 'security.intake_page_wording_v1(uuid,uuid,text)'::regprocedure) <> (select oid from pg_language where lanname = 'plpgsql')
     or (select p.prolang from pg_proc p where p.oid = 'security.intake_wording_fp_v1(uuid,uuid)'::regprocedure) <> (select oid from pg_language where lanname = 'plpgsql') then
    raise exception 'post-check: the intake wording functions are not the PL/pgSQL versions'; end if;
end $post$;
