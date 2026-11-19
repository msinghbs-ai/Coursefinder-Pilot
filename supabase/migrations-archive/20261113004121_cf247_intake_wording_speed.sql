-- CF-247 F-INT (S2-Intakes mandate, Platform Admin 13 Nov 2026 11:02: "Fix genuine technical blockers at their source: ... timeouts ... and stranded jobs").
-- See supabase/migrations/20261113290000_cf247_intake_wording_speed.sql for the full header.
-- Replaces: security.intake_page_wording_v1 and security.intake_wording_fp_v1 (same names, guarded by the md5 of the live bodies).
-- Retires: nothing.

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
