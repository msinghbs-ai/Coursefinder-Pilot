CREATE OR REPLACE FUNCTION security.boost_study_load_review_feed_trg_v1()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  perform security.boost_study_load_review_feed_v1();
  return null;
end $function$
