CREATE OR REPLACE FUNCTION security.cdesc_block_info_v1(p_key text)
 RETURNS jsonb
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO ''
AS $function$
  select case p_key
    when 'not_active' then jsonb_build_object('label', 'Not an active course', 'next', 'Nothing to do.')
    when 'already_has_description' then jsonb_build_object('label', 'Already has a description', 'next', 'Nothing to fill.')
    when 'locked' then jsonb_build_object('label', 'Locked by hand', 'next', 'A person removes the lock first; a read never overwrites a hand-held value.')
    when 'provider_hidden' then jsonb_build_object('label', 'The university is unpublished', 'next', 'Publish the university again, then run this.')
    when 'no_source' then jsonb_build_object('label', 'No stored course page that is proved to be this course', 'next', 'Wait for the course page to be found and read, or add a course link. Nothing is read from a generic page.')
    when 'waiting_for_person' then jsonb_build_object('label', 'A reading is waiting for a person in Layer 4', 'next', 'Decide it in Layer 4.')
    when 'in_flight' then jsonb_build_object('label', 'Already in an open task', 'next', 'Wait for that task to finish.')
    when 'rejected_same_evidence' then jsonb_build_object('label', 'A person rejected the reading of this same page copy', 'next', 'It is read again when the page is read again.')
    when 'held_for_person' then jsonb_build_object('label', 'Held for a person (flag raised or manual hold)', 'next', 'Release the flag in Flags, or wait for the page to be read again.')
    when 'held_first_admission' then jsonb_build_object('label', 'Read and checked; waits for the university''s first descriptions to be decided', 'next', 'Decide the waiting readings in Layer 4; no new read is needed.')
    when 'same_page_not_stated' then jsonb_build_object('label', 'This same page copy was read and does not state it', 'next', 'It is read again when the page is read again.')
    when 'recent_attempt' then jsonb_build_object('label', 'Tried recently', 'next', 'The standing queue tries again on its own date; use Recheck description to read it now.')
    when 'nothing_to_recheck' then jsonb_build_object('label', 'Not tried yet', 'next', 'Use Fill description.')
    when 'review_backlog' then jsonb_build_object('label', 'Too many descriptions already wait for a person in Layer 4', 'next', 'Decide the waiting readings in Layer 4; the limit is Pipeline settings > Course description: most waiting for a person before new readings pause.')
    when 'daily_capacity' then jsonb_build_object('label', 'Over today''s limit for description readings', 'next', 'The limit is Pipeline settings > Enrich fields > items per day; it frees as the day moves on.')
    when null then null
    else jsonb_build_object('label', p_key, 'next', '') end
$function$
