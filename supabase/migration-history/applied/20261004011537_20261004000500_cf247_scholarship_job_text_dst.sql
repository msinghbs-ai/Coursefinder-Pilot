-- CF-247 (4 Oct 2026). Melbourne moved to daylight saving today (AEDT, UTC+11); a fixed clock time in a job description
-- ("06:17") is now an hour out. Job times are shown from each job's schedule in Melbourne time, so the description
-- names no time.
update pipeline.scholarship_jobs set what = 'Withdraws a published scholarship that no longer passes a check (once a day; time shown from the schedule).' where jobname = 'scholarship-publication-review' and what = 'Withdraws a published scholarship that no longer passes a check (06:17).';
