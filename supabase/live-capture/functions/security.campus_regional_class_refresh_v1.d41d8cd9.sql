CREATE OR REPLACE FUNCTION security.campus_regional_class_refresh_v1()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'catalogue', 'pipeline', 'ref', 'security'
AS $function$
declare n int;
begin
  insert into pipeline.campus_regional_class(campus_id,state_code,postcode,category,category_name,metro_area,computed_at)
  select k.id, s.code, k.postcode, (c->>'category')::smallint,
         case (c->>'category')::int when 1 then 'Major city' when 2 then 'City or major regional centre' when 3 then 'Regional centre or other regional area' end,
         c->>'metro_area', now()
    from catalogue.campuses k left join ref.subdivisions s on s.id=k.subdivision_id
    cross join lateral (select security.au_regional_class(s.code,k.postcode) c) z
  on conflict (campus_id) do update set state_code=excluded.state_code, postcode=excluded.postcode, category=excluded.category,
         category_name=excluded.category_name, metro_area=excluded.metro_area, computed_at=now()
   where pipeline.campus_regional_class.postcode is distinct from excluded.postcode or pipeline.campus_regional_class.state_code is distinct from excluded.state_code
      or pipeline.campus_regional_class.category is distinct from excluded.category;
  get diagnostics n=row_count;
  return jsonb_build_object('changed',n);
end $function$
