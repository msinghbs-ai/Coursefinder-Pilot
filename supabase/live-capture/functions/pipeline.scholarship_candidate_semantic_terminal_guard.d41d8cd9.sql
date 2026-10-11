CREATE OR REPLACE FUNCTION pipeline.scholarship_candidate_semantic_terminal_guard()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'pipeline'
AS $function$
declare
  v_title text:=lower(trim(replace(replace(replace(coalesce(new.observed_title,''),'&amp;','&'),'&#x2019;','’'),'&#x27;','''')));
  v_url text:=lower(coalesce(nullif(new.detail_target_url,''),nullif(new.scholarship_url,''),''));
begin
  if v_title ~ '(terms? and conditions|terms? & conditions|conditions of award|scholarship conditions|award conditions)'
     or v_url ~ '(terms[-_% ]?and[-_% ]?conditions|term[-_% ]?conditions|conditions[-_% ]?of[-_% ]?award|scholarship[-_% ]?conditions)'
     or (v_url ~ '\.pdf([?#].*)?$' and v_title ~ '(terms?|conditions|policy|guidelines?)') then
    new.classification:='support_or_navigation';
    new.classification_reason:='CF-220 supporting terms/conditions document retained as Evidence; not an individual Scholarship detail';
    new.classified_at:=now();
  elsif v_title ~ '^(search|about us|learn more|scholarships? & grants|academic scholarships|external scholarships|scholarships and fees|financial aid for international students|domestic student scholarships|prestigious.*scholarships|home country sponsored scholarships)$'
     or v_url ~ '/search\.html([?#].*)?$'
     or v_url ~ '/about-us(\.html)?([?#].*)?$'
     or v_url ~ '/scholarships/domestic/?([?#].*)?$'
     or v_url ~ '/home-country-sponsored-scholarships/?([?#].*)?$' then
    new.classification:='support_or_navigation';
    new.classification_reason:='CF-191 semantic terminal guard: navigation, collection, domestic or support page is not an individual international Scholarship';
    new.classified_at:=now();
  elsif v_title ~ '^(scholarships?|scholarships? & grants|scholarships? for international students|international scholarships?)$'
        or v_url ~ '/scholarships/?([?#].*)?$' then
    new.classification:='catalogue_or_filter';
    new.classification_reason:='CF-191 semantic terminal guard: Scholarship catalogue root retained as Evidence only';
    new.classified_at:=now();
  end if;
  return new;
end
$function$
