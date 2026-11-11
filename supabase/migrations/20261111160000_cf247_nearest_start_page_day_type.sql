-- CF-247 F-INT Rule B hotfix (Decision 271; found validating the Monash switch-on, Platform Admin 11 Nov 2026 12:21 "settings saved, validate").
-- Evidence (production, 11 Nov 2026 12:4x AEDT): a bounded intake apply for Monash's courses failed: "operator does not exist: integer = date ... v_pd is not
--   null and not (extract(day from v_cand)::int = all (v_pd)) ... security.intake_nearest_start_v1 line 54". The helper declares v_pd date[] but fills it with the
--   day numbers printed on the course page (regexp_matches ... m[1]::int). The 20261111130000 dry run used a transcribed copy that declared int[], so it did not
--   show. Any listed provider's row whose page prints a day and month errors the whole intake apply (every provider) until this is fixed. Nothing was written: the
--   failed call rolled back.
-- What: md5-guarded text edit of security.intake_nearest_start_v1 (body 517f2986... -> a99b42c7...): v_pd date[] -> v_pd int[]. Verified on production in a
--   rolled-back transaction with the exact edit applied to the live definition: a bounded apply of 150 Monash rows gave 111 filled (91 by Rule B: Semester 1
--   = 1 Mar 2027 for 50, Semester 2 = 26 Jul 2027 for 41).
-- Guards: G1, G2, G3 unchanged; G4 (cf-247-s531, assertion added).
-- Replaces: security.intake_nearest_start_v1 (same name; md5-guarded text edit, resulting md5 checked).
-- Retires: nothing.
-- Reversal: none needed (type correction).

create or replace function pg_temp.edit_all(p_sig text, p_before text, p_after text, p_olds text[], p_news text[]) returns text language plpgsql as $f$
declare v_def text := pg_get_functiondef(p_sig::regprocedure); v_src text := (select p.prosrc from pg_proc p where p.oid = p_sig::regprocedure); v_c int; i int;
begin
  -- the guard is the md5 of the function body (pg_proc.prosrc), the same text on PostgreSQL 16 and 17
  if md5(v_src) = p_after then raise notice '%: already applied', p_sig; return p_sig || ': already applied'; end if;
  if md5(v_src) <> p_before then raise exception 'live % differs from the definition this change edits (body md5 %)', p_sig, md5(v_src); end if;
  v_def := replace(v_def, chr(13), '');
  for i in 1 .. array_length(p_olds, 1) loop
    v_c := (length(v_def) - length(replace(v_def, p_olds[i], ''))) / length(p_olds[i]);
    if v_c <> 1 then raise exception '%: edit % must apply exactly once (found %)', p_sig, i, v_c; end if;
    v_def := replace(v_def, p_olds[i], p_news[i]);
  end loop;
  execute v_def;
  v_src := (select p.prosrc from pg_proc p where p.oid = p_sig::regprocedure);
  if md5(v_src) <> p_after then raise exception '% after the edit has body md5 %, expected %', p_sig, md5(v_src), p_after; end if;
  raise notice '%: applied', p_sig;
  return p_sig || ': applied';
end $f$;

select pg_temp.edit_all('security.intake_nearest_start_v1(uuid,uuid,integer,integer,text,jsonb,date,integer,integer)', '517f2986c5142c5d075f243fb8b0fc22', 'a99b42c7007436a78860a386652f81a9',
  array[$o$v_pd date[];$o$], array[$n$v_pd int[];$n$]);

do $post$ begin
  if md5((select p.prosrc from pg_proc p where p.oid = 'security.intake_nearest_start_v1(uuid,uuid,integer,integer,text,jsonb,date,integer,integer)'::regprocedure)) <> 'a99b42c7007436a78860a386652f81a9' then
    raise exception 'post-check: security.intake_nearest_start_v1 does not have the recorded body'; end if;
end $post$;
