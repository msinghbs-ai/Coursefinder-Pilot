-- CF-247 Decision 254 (5 Oct 2026, night run wave 2). Applying an adapter skipped every page whose address was set by
-- hand ('entered_by_hand'), so a course re-bound to its own page tonight got no adapter readings until its next
-- scheduled read, months away. The page address set by hand is still never changed (the adapter only reads the
-- stored copy of that page): the adapter now confirms the page and adds its fields as for any other page. Field
-- exclusions and values entered by hand are untouched (admission checks its own locks).
-- Snippet patch, md5-guarded, found exactly once. No text value in this file contains a semicolon.

do $p$
declare v_def text; v_pair text[]; v_pairs text[][];
begin
  if (select md5(prosrc) from pg_proc where oid = 'public.svc_adapter_page_record(uuid,text,text,jsonb)'::regprocedure) is distinct from 'f32ab786207ca970b3aed9ea08658eb5' then
    raise exception 'svc_adapter_page_record changed, not patching'; end if;
  v_def := pg_get_functiondef('public.svc_adapter_page_record(uuid,text,text,jsonb)'::regprocedure);
  v_pairs := array[
    array[$s$  if exists (select 1 from pipeline.manual_locks k where k.entity = 'course' and k.entity_id = p_course_id and k.field = 'official_url') then return 'entered_by_hand'{sc} end if{sc}
$s$, $s$  -- night run: a page bound by hand is read like any other (its address stays as set by hand)
$s$]];
  foreach v_pair slice 1 in array v_pairs loop
    v_pair[1] := replace(v_pair[1], '{sc}', chr(59));
    v_pair[2] := replace(v_pair[2], '{sc}', chr(59));
    if (length(v_def) - length(replace(v_def, v_pair[1], ''))) / length(v_pair[1]) <> 1 then raise exception 'snippet not found exactly once: %', v_pair[1]; end if;
    v_def := replace(v_def, v_pair[1], v_pair[2]);
  end loop;
  execute v_def;
end $p$;
