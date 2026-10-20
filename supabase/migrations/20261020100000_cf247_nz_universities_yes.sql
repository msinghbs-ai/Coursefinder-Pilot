-- CF-247 (20 Oct 2026). The NZQA re-read (coverage-sweep v0.34.1) found that the NZQA pages of all eight New Zealand universities (and two of
-- the three wānanga) say nothing about international students: neither the signatory sentence nor a "not a signatory" one. Platform Admin,
-- 20 Oct 2026, choice "Universities Yes (Recommended)": the eight universities are set Yes with the basis that a New Zealand university must be
-- a signatory to the Code to enrol international students; a person can still change it; the two wānanga stay blank.
-- Replaces: security.nz_cop_apply_v1() (universities by NZQA type UNI; nothing else changes)
-- Retires: nothing
-- Nothing dropped or deleted. Consumer API not touched (Decision 266): only values of enrols_international change.

create or replace function pg_temp.edit_once(p_sig text, p_md5 text, p_edits text[][]) returns void language plpgsql as $f$
declare v_def text := pg_get_functiondef(p_sig::regprocedure); i int;
begin
  if md5(v_def) <> p_md5 then raise exception 'live % differs from the definition this change edits', p_sig; end if;
  for i in 1 .. array_length(p_edits, 1) loop
    if (length(v_def) - length(replace(v_def, p_edits[i][1], ''))) / length(p_edits[i][1]) <> 1 then raise exception '%: edit % must apply exactly once', p_sig, i; end if;
    v_def := replace(v_def, p_edits[i][1], p_edits[i][2]);
  end loop;
  execute v_def;
end $f$;

select pg_temp.edit_once('security.nz_cop_apply_v1()', '2cf6736293aebe4548702e0ad9f58491', array[
  array[$o$case when s.signatory then true when s.explicit_no then false end val,$o$,
        $n$case when s.signatory then true when s.explicit_no then false when s.nzqa_type = 'UNI' then true end val,$n$],
  array[$o$case when s.signatory then 'NZQA Code of Practice signatory' when s.explicit_no then 'NZQA Code of Practice: not a signatory' end basis$o$,
        $n$case when s.signatory then 'NZQA Code of Practice signatory' when s.explicit_no then 'NZQA Code of Practice: not a signatory'
                when s.nzqa_type = 'UNI' then 'NZQA Code of Practice: NZ university (must be a signatory to enrol international students; Platform Admin 20 Oct 2026)' end basis$n$]
]);

select security.nz_cop_apply_v1();
