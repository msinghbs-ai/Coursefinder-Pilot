-- CF-247 (11 Oct 2026, Platform Admin standing rule): every background job appears in Task manager with its controls.
-- B3: 22 scheduled jobs had no catalogue entry, so Task manager › Running now showed them by their internal name under
-- "Other". This adds a plain label, area and control rank for each. Rows are only added (existing ones are left as they are);
-- nothing is dropped or deleted, and no schedule changes.
insert into pipeline.automation_catalogue (jobname, area, sort, label, description, control_rank) values
  ('admin-jobs',                   'Platform upkeep',  60, 'Task manager tasks',                         'Moves every waiting or running task in Task manager on by one step each minute (adapters, page reads, Firecrawl runs, scholarship tasks).', 6),
  ('firecrawl-runs',               'Platform upkeep',  62, 'Firecrawl runs',                             'Moves each Firecrawl run on by one step each minute and closes it when its pages are done or its credit cap is reached.', 6),
  ('firecrawl-targets',            'Platform upkeep',  64, 'Firecrawl target lists',                     'Refreshes the lists of pages each Firecrawl use case can be run on.', 6),
  ('firecrawl-panel-figures',      'Reports',          95, 'Firecrawl panel figures',                    'Refreshes the credit and result figures shown on the Firecrawl panel.', 5),
  ('retention-worker',             'Platform upkeep',  66, 'Data retention',                             'Removes logs and copies older than their retention period, a small batch at a time.', 6),
  ('university-reread-requests',   'Layer 2 reading', 130, 'University read-again requests',             'Sends university pages a person asked to read again to the reader.', 5),
  ('coverage-ai-match',            'Layer 3 AI',       70, 'AI course page matching',                    'Asks the tested AI model whether each candidate page is the course''s own page.', 5),
  ('coverage-ai-match-prepare',    'Layer 3 AI',       72, 'Prepare AI course page matching',            'Picks the candidate pages that need an AI match next.', 5),
  ('coverage-reidentify',          'Course pages',     70, 'Identify course pages again',                'Checks saved course pages again against the course''s code and title.', 5),
  ('coverage-admit-intakes',       'Admission',        80, 'Admit intakes from course pages',            'Admits intakes read from accepted course pages.', 5),
  ('adapter-overwrite',            'Admission',        82, 'Adapter values replace older ones',          'Where a university adapter is admitted, its values replace older values from other sources.', 5),
  ('better-page-revert',           'Course pages',     72, 'Return to the better course page',           'Puts a course back on its better page when a newer page proved weaker.', 5),
  ('course-field-source-build',    'Reports',          97, 'Who supplied each course value',             'Rebuilds the record of which source supplied each course value, for the Attributes panel.', 5),
  ('exit-awards-apply',            'Admission',        84, 'Exit awards take parent values',             'Gives exit awards the values of their single-degree parent once the register check passes.', 5),
  ('host-pages-apply',             'Admission',        86, 'Hosted courses take host page values',       'Gives courses carried on a host page the values on that page once host pages are admitted.', 5),
  ('l4-rule-fee-year-align',       'Admission',        88, 'Review rule: fee year',                      'Sends fees whose year does not match the intake year to review.', 5),
  ('l4-rule-low-agreement',        'Admission',        90, 'Review rule: sources disagree',              'Sends values that sources disagree on to review.', 5),
  ('l4-rule-unofficial-source',    'Admission',        92, 'Review rule: unofficial source',             'Sends values that came only from an unofficial source to review.', 5),
  ('provider-fee-ranges-refresh',  'Reports',          99, 'University fee ranges',                      'Works out each university''s lowest and highest whole-course fee.', 5),
  ('scholarship-auto-publish',     'Scholarships',     80, 'Publish scholarships automatically',         'Publishes scholarships that pass every check, as one batch named auto-publish.', 5),
  ('scholarship-fee-alignment',    'Scholarships',     82, 'Scholarship fee alignment',                  'Recalculates savings for courses whose fee changed.', 5),
  ('scholarship-listing',          'Scholarships',     84, 'Read scholarship listing pages',             'Reads each provider''s scholarship listing page through the scraper for the coverage check.', 5)
on conflict (jobname) do nothing;

do $post$
declare v_missing text;
begin
  select string_agg(j.jobname, ', ') into v_missing from cron.job j left join pipeline.automation_catalogue c on c.jobname = j.jobname where c.jobname is null;
  if v_missing is not null then raise exception 'CF-247 post-check: scheduled jobs still without a label: %', v_missing; end if;
end $post$;
