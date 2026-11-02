CREATE OR REPLACE FUNCTION security.layer4_inbox_kinds_v1()
 RETURNS jsonb
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO ''
AS $function$
  select '{
   "course_link": {"label": "Course link", "order": 1, "choices": [
     {"key": "keep", "label": "Keep the page we hold", "returns": "Closed; the same pair of pages is not asked again"},
     {"key": "use", "label": "Use the new page", "returns": "The new page becomes the official page (a person''s value, never overwritten); it is read again and the adapter applies"},
     {"key": "enter", "label": "Enter another address", "input": "url", "returns": "That address becomes the official page; it is read again and the adapter applies"}]},
   "held_scholarship": {"label": "Held scholarship", "order": 2, "choices": [
     {"key": "publish", "label": "Publish", "returns": "Taken as for international students and offered; the hourly publish checks still apply"},
     {"key": "not_international", "label": "Not for international students", "reason": "The page does not say international students may apply", "returns": "Refused; the same page copy is not asked again"},
     {"key": "not_scholarship", "label": "Not a scholarship", "reason": "Not a scholarship page", "returns": "Refused; the same page copy is not asked again"}]},
   "website_needed": {"label": "Website needed", "order": 3, "choices": [
     {"key": "website", "label": "Enter the website", "input": "url", "returns": "Onboarding starts again from the website: its course pages are found and read, then the adapter is built"},
     {"key": "cricos_only", "label": "CRICOS data only", "returns": "No adapter and no credits; it keeps its register data"},
     {"key": "archive", "label": "Archive the university", "rank": 5, "returns": "Unpublished and hidden from the consumer API; reviewable on Archived"}]},
   "pages_not_found": {"label": "Course pages not found", "order": 4, "choices": [
     {"key": "website", "label": "Change the website", "input": "url", "returns": "The hold is released, the site is mapped again and onboarding starts again"},
     {"key": "pages", "label": "Add page addresses", "link": "builder", "returns": "Opens the Adapter builder (2.1); release the hold here once pages are added"},
     {"key": "release", "label": "Release and try again", "rank": 4, "returns": "The hold is released; the site is mapped again and onboarding starts again"},
     {"key": "cricos_only", "label": "CRICOS data only", "returns": "Stays held; labelled CRICOS data only"}]},
   "too_few_pages": {"label": "Too few course pages", "order": 5, "choices": [
     {"key": "pages", "label": "Add page addresses", "link": "builder", "returns": "Onboarding carries on by itself once 3 pages are read"},
     {"key": "cricos_only", "label": "CRICOS data only", "returns": "No adapter and no credits; it keeps its register data"}]},
   "nothing_ready": {"label": "Adapter has nothing ready", "order": 6, "choices": [
     {"key": "adapter", "label": "Open the adapter", "link": "builder", "returns": "Fix a pattern and qualify again; what passes is admitted"},
     {"key": "rebuild", "label": "Rebuild the adapter", "rank": 5, "returns": "Onboarding builds and qualifies the adapter again; what passes is admitted, then courses are enriched and scholarships found"},
     {"key": "cricos_only", "label": "CRICOS data only", "returns": "No more work on its adapter; it keeps its register data"}]},
   "central_to_approve": {"label": "Central pages to approve", "order": 7, "choices": [
     {"key": "open", "label": "Open the central pages", "link": "builder", "returns": "Approve or refuse each page; onboarding carries on by itself"}]},
   "onboarding_failed": {"label": "Adapter proposal failed", "order": 8, "choices": [
     {"key": "retry", "label": "Try again", "rank": 5, "returns": "Onboarding starts again from the step that stopped"},
     {"key": "builder", "label": "Build by hand", "link": "builder", "returns": "Opens the Adapter builder"}]},
   "site_down": {"label": "Website not answering", "order": 9, "choices": [
     {"key": "website", "label": "Change the website", "input": "url", "returns": "The hold is released and onboarding starts again from the website"},
     {"key": "archive", "label": "Archive the university", "rank": 5, "returns": "Unpublished and hidden from the consumer API; reviewable on Archived"},
     {"key": "wait", "label": "Keep waiting", "returns": "Checked every 10 minutes as before; asked again in 30 days"}]},
   "not_offered": {"label": "Course not offered", "order": 10, "choices": [
     {"key": "archive_course", "label": "Archive the course", "rank": 5, "returns": "Unpublished and hidden from the consumer API; reviewable on Archived"},
     {"key": "keep", "label": "Keep it", "returns": "The hold is released; the course stays as it is"}]},
   "fee_check": {"label": "Fee fails the check", "order": 11, "choices": [
     {"key": "course", "label": "Open the course", "link": "course", "returns": "Enter or confirm the fee on the course"},
     {"key": "keep", "label": "Keep the CRICOS total", "returns": "The hold is released; the page fee stays out"}]},
   "counsellor_report": {"label": "Counsellor report", "order": 12, "choices": [
     {"key": "report_fixed", "label": "Fixed", "returns": "Closed as fixed with your note; Zoho shows the outcome to the counsellor"},
     {"key": "report_not_changed", "label": "Not changed", "returns": "Closed as not changed with your reason; Zoho shows it to the counsellor"},
     {"key": "course", "label": "Open the course", "link": "course", "returns": "Correct the value on the course, then close the report here"}]},
   "not_on_site": {"label": "Course not on the university''s site", "order": 13, "choices": [
     {"key": "archive_course", "label": "Archive the course", "rank": 5, "returns": "Unpublished and hidden from the consumer API; reviewable on Archived"},
     {"key": "keep", "label": "Keep it", "returns": "The hold is released; CRICOS still lists it"},
     {"key": "course", "label": "Open the course", "link": "course", "returns": "Enter its page on the course"}]},
   "no_page_first_run": {"label": "No page published: first run", "order": 15, "choices": [
     {"key": "approve", "label": "Approve: none has its own page", "returns": "The sample is recorded as no page published; at the 60% rule the university is trusted and its later cases are recorded without a person; any page found later re-opens a course"},
     {"key": "has_page", "label": "Approve, except courses that have a page", "input": "courses", "returns": "The ticked courses keep looking for their page; the others are recorded; the university is trusted only at the 60% rule"},
     {"key": "reject", "label": "Reject", "returns": "Nothing is recorded and the university is not trusted; its courses keep looking for their pages"}]},
   "conjoint_first_run": {"label": "Conjoint or double degrees: first run", "order": 16, "choices": [
     {"key": "approve", "label": "Approve: no page of their own", "returns": "The conjoint degrees of this university leave the course search, recorded as conjoint; any page found later re-opens a course"},
     {"key": "parent", "label": "Approve with their shared page", "input": "url", "returns": "Recorded as conjoint, with this address as their shared conjoint page"},
     {"key": "reject", "label": "Reject", "returns": "Nothing is recorded; the conjoint degrees keep looking for their pages"}]},
   "aer_review": {"label": "Entry requirements (AER)", "order": 17, "choices": [
     {"key": "approve", "label": "Approve all rows", "rank": 6, "returns": "Every waiting row becomes active once the identity, completeness, scale and basis checks pass; the source''s earlier rows are superseded"},
     {"key": "approve_except", "label": "Approve except…", "rank": 6, "input": "rows", "returns": "The ticked rows stay unadmitted, marked excluded with your reason; every other row becomes active once the same checks pass. An earlier active row is replaced only by an approved row with its identity; one whose replacement you leave out stays active (D4)"},
     {"key": "reject", "label": "Reject the read", "rank": 6, "returns": "No row is admitted; every waiting row is withdrawn with your reason"}]},
   "provider_departure": {"label": "Provider left the register", "order": 14, "choices": [
     {"key": "closed", "label": "Closed: archive it", "rank": 6, "returns": "Archived through the clean-up workflow and hidden from the consumer API"},
     {"key": "merged", "label": "Merged into another provider", "rank": 6, "input": "provider", "returns": "Archived, and the merger recorded with its successor"},
     {"key": "reviewed", "label": "Still operating: keep it", "rank": 6, "returns": "Closed; the provider stays as it is"}]}
  }'::jsonb
$function$
;
