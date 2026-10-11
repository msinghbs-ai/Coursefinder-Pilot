CREATE OR REPLACE FUNCTION public.svc_scholarship_register_save(p_register text, p_run_id uuid, p_evidence_id uuid, p_listings jsonb, p_final boolean DEFAULT false)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_country char(2); v_created int := 0; v_updated int := 0; v_unchanged int := 0; v_departed int := 0; v_match jsonb;
begin
  if current_user <> 'postgres' and coalesce(auth.role(),'') <> 'service_role' then raise exception 'service_role required'; end if;
  select country_code into v_country from scholarship.registers where code = p_register;
  if v_country is null then raise exception 'unknown register %', p_register; end if;
  with src as (
    select x->>'id' listing_id, x->>'url' url, x->>'name' name, x->>'provider_ref' provider_ref, x->>'provider_name' provider_name,
           nullif(x->>'level','') level_text, nullif(x->>'award','') award_text, nullif(x->>'closing','') closing_text, nullif(x->>'nationality','') nationality_text,
           md5(concat_ws('|', x->>'name', x->>'provider_ref', x->>'provider_name', x->>'level', x->>'award', x->>'closing', x->>'nationality')) h
      from jsonb_array_elements(coalesce(p_listings,'[]'::jsonb)) x
     where coalesce(x->>'id','') <> '' and coalesce(x->>'name','') <> '' and coalesce(x->>'url','') <> ''
  ), up as (
    insert into scholarship.register_listings as l(register_code, listing_id, country_code, url, name, provider_ref, provider_name,
           level_text, award_text, closing_text, nationality_text, content_hash, evidence_id, last_run_id)
    select p_register, s.listing_id, v_country, s.url, s.name, s.provider_ref, s.provider_name, s.level_text, s.award_text, s.closing_text,
           s.nationality_text, s.h, p_evidence_id, p_run_id from src s
    on conflict (register_code, listing_id) do update
       set url = excluded.url, name = excluded.name, provider_ref = excluded.provider_ref, provider_name = excluded.provider_name,
           level_text = excluded.level_text, award_text = excluded.award_text, closing_text = excluded.closing_text, nationality_text = excluded.nationality_text,
           content_hash = excluded.content_hash, evidence_id = excluded.evidence_id, last_run_id = excluded.last_run_id,
           last_seen_at = now(), departed_at = null
    returning (xmax = 0) ins, (l.content_hash) h
  ) select count(*) filter (where ins), 0, count(*) filter (where not ins) into v_created, v_updated, v_unchanged from up;
  if p_final then
    update scholarship.register_listings set departed_at = now()
     where register_code = p_register and departed_at is null and last_run_id is distinct from p_run_id;
    get diagnostics v_departed = row_count;
    v_match := public.svc_scholarship_register_match(p_register);
  end if;
  return jsonb_build_object('created', v_created, 'seen_again', v_unchanged, 'departed', v_departed, 'match', v_match);
end $function$
