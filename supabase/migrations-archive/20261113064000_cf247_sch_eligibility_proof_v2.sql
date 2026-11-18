-- CF-247 F-SCH.01 post-activation review (12 Nov 2026 16:55 AEDT): the eligibility proof is tightened before the reader may act again. Worker v0.78.0
-- (eligibility.ts eligibilityProof) refuses course titles with "(International)", programme-wide banners, fee or entry instructions, menu tags and
-- search controls; here the rule refuses a sentence read from a government site (an NZQA page was attributed to a provider whose recorded website is
-- NZQA's). Every international or both proof is read again by v0.78.0, in shadow (sch_elig.apply_on stays 0; going live is its own recorded step).
-- Replaces: nothing (the proof rule is extended). Retires: nothing.

create or replace function security.scholarship_government_host_v1(p_url text)
returns boolean language sql immutable set search_path to '' as $function$
  select coalesce(lower(substring(p_url from '^[a-z]+://([^/:?#]+)')) ~ '(^|\.)(gov|govt)(\.[a-z]{2})?$|\.gc\.ca$|(^|\.)gov\.[a-z]{2}$', false)
$function$;
comment on function security.scholarship_government_host_v1(text) is 'F-SCH.01 (12 Nov 2026): true for a government or regulator site (gov, govt, gc.ca); a scholarship eligibility sentence read there is not a provider''s own page.';

create or replace function pg_temp.edit_n(p_sig text, p_md5 text, p_edits text[][], p_times int[]) returns void language plpgsql as $f$
declare v_def text := pg_get_functiondef(p_sig::regprocedure); i int; v_c int;
begin
  if md5(v_def) <> p_md5 then raise exception 'live % differs from the definition this change edits (md5 %)', p_sig, md5(v_def); end if;
  for i in 1 .. array_length(p_edits, 1) loop
    v_c := (length(v_def) - length(replace(v_def, p_edits[i][1], ''))) / length(p_edits[i][1]);
    if v_c <> p_times[i] then raise exception '%: edit % must apply exactly % times (found %)', p_sig, i, p_times[i], v_c; end if;
    v_def := replace(v_def, p_edits[i][1], p_edits[i][2]);
  end loop;
  execute v_def;
end $f$;

select pg_temp.edit_n('security.scholarship_eligibility_apply_v1(integer)', '5b684e8b755092672641c7d113c3800e', array[
  array[$o$        case when not coalesce(security.url_on_provider_sites(v_url, r.provider_id), false) or security.third_party_host_v1(coalesce(v_url, '')) then 'sentence_off_provider_site'$o$,
        $n$        case when not coalesce(security.url_on_provider_sites(v_url, r.provider_id), false) or security.third_party_host_v1(coalesce(v_url, ''))
                  or security.scholarship_government_host_v1(v_url) then 'sentence_off_provider_site'$n$]
], array[1]);

do $r$
declare v_n int;
begin
  update pipeline.scholarship_eligibility_reads
     set state = 'queued', outcome = null, result = null, applied = null, tries = 0, queued_at = now(), updated_at = now(),
         next_try_at = now() + interval '20 minutes'  -- fixed: after deploy-on-merge has deployed worker v0.78.0, so the new proof reads them
   where outcome = 'proven' and result->>'audience' in ('international', 'both');
  get diagnostics v_n = row_count;
  raise notice 'international proofs queued to be read again: %', v_n;
  if security.pipeline_num_v1('sch_elig.apply_on', -1) <> 0 then raise exception 'post-check: the reader stays in shadow'; end if;
end $r$;

insert into pipeline.component_register(kind, name, layer, area, purpose, status, replaces, introduced_in) values
 ('function', 'security.scholarship_government_host_v1', 'Layer 2', 'Scholarships', 'Government or regulator site test for scholarship eligibility sentences', 'active', '{}', '20261113064000')
on conflict do nothing;
