-- CF-247 Decision 254 (5 Oct 2026, 19:18 run). exit_awards_apply_v2 failed for a university that admits exit awards
-- but not fees (Canberra: "record v_fee is not assigned yet"), because a record variable set to null is still unset.
-- The record now starts with empty columns. Snippet patch, md5-guarded, found exactly once. No semicolon in any text
-- value in this file.
do $p$
declare v_def text; v_pair text[]; v_pairs text[][];
begin
  if (select md5(prosrc) from pg_proc where oid = 'security.exit_awards_apply_v2(uuid)'::regprocedure) is distinct from 'da94c52172aef30ec5a62a2e87bea5f4' then
    raise exception 'exit_awards_apply_v2 changed, not patching'; end if;
  v_def := pg_get_functiondef('security.exit_awards_apply_v2(uuid)'::regprocedure);
  v_pairs := array[
    array[$s$      v_fee := null{sc}$s$,
          $s$      select null::numeric amount, null::int fee_year, null::text currency_code into v_fee{sc}$s$]];
  foreach v_pair slice 1 in array v_pairs loop
    v_pair[1] := replace(v_pair[1], '{sc}', chr(59));
    v_pair[2] := replace(v_pair[2], '{sc}', chr(59));
    if (length(v_def) - length(replace(v_def, v_pair[1], ''))) / length(v_pair[1]) <> 1 then raise exception 'snippet not found exactly once: %', v_pair[1]; end if;
    v_def := replace(v_def, v_pair[1], v_pair[2]);
  end loop;
  execute v_def;
end $p$;
