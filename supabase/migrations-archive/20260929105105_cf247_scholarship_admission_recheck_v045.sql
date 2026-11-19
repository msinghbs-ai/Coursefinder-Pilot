-- CF-247 scholarship discovery, second step-2 hand-check (29 Sep 2026): admitted titles still included page furniture
-- (Charles Sturt "--> Scholarships <!--"), listings ("Global Curtin scholarships", "UNSW scholarships for international
-- students", UniSC "International Scholarships | UniSC | ..."), student stories (UWA "... Premiers University Scholarship
-- Shruti"), a recap (UC "End of Year Recap: 2024 UC Student Awards") and application/information pages. Extractor
-- scholarship-sweep-v0.4.5 admits only a scholarship's own name; every admitted page is read again and withdrawn when
-- it no longer meets the rules (security.scholarship_admission_withdraw_v1, logged; nothing is published).
update pipeline.scholarship_pages set next_read_at=now(), attempts=0, leased_until=null where url_source='admitted';
