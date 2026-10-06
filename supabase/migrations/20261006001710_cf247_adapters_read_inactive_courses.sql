-- CF-247 Decision 254 (6 Oct 2026, Platform Admin decision D1 at 10:56: "Read inactive courses too; activation stays a
-- separate catalogue step"). Nearly every Canadian course is inactive (for example 205 of 213 at Camosun), and the
-- adapter builder, preview and apply only visited pages of active courses, so a rebound page gave no adapter reading.
-- Now the builder samples, the preview reads and the apply reads pages of inactive courses too. Admission is not
-- changed: security.adapter_overwrite_v1 still writes values for active courses only, so an inactive course gets its
-- adapter readings (visible in Coverage, measurable) but no admitted value until it is activated through the catalogue.
-- Snippet patches, md5-guarded, each snippet found exactly once. No text value in this file contains a semicolon.

do $p$
declare v_fn text; v_md5 text; v_def text; v_old text; v_new text; v_pairs text[][];
begin
  v_pairs := array[
    array['public.admin_adapter_builder(text,jsonb)', 'e9755f95fc7e92a638e51e1ca7a4c306',
          $s$join catalogue.courses c on c.id = pg.course_id and c.lifecycle_status = 'active'$s$,
          $s$join catalogue.courses c on c.id = pg.course_id and c.lifecycle_status in ('active', 'inactive')$s$],
    array['public.svc_adapter_apply_next(uuid,uuid,integer)', '166cf8ca8af1ea0c3bde227df96c9ac8',
          $s$and e.storage_path is not null and c.lifecycle_status = 'active'$s$,
          $s$and e.storage_path is not null and c.lifecycle_status in ('active', 'inactive')$s$],
    array['public.svc_adapter_preview_next(uuid)', '460eb3f55ac4061c41ffe074f7c955d9',
          $s$and e.storage_path is not null and c.lifecycle_status = 'active'$s$,
          $s$and e.storage_path is not null and c.lifecycle_status in ('active', 'inactive')$s$]];
  for i in 1 .. array_length(v_pairs, 1) loop
    v_fn := v_pairs[i][1]; v_md5 := v_pairs[i][2]; v_old := v_pairs[i][3]; v_new := v_pairs[i][4];
    if (select md5(prosrc) from pg_proc where oid = v_fn::regprocedure) is distinct from v_md5 then
      raise exception '% changed, not patching', v_fn; end if;
    v_def := pg_get_functiondef(v_fn::regprocedure);
    if (length(v_def) - length(replace(v_def, v_old, ''))) / length(v_old) <> 1 then raise exception 'snippet not found exactly once in %: %', v_fn, v_old; end if;
    execute replace(v_def, v_old, v_new);
  end loop;
end $p$;
