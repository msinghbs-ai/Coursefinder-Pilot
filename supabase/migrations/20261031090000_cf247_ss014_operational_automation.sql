-- CF-247 StudySearch SS-014 (31 Oct 2026): NOT APPLIED. Superseded by 20261031091000_cf247_ss014_operational_automation.sql.
-- Its md5 guard refused the health-check edit at deploy (expected md5 taken before the alert issue area was changed to 'scheduled jobs');
-- the transaction rolled back, so nothing in the database changed. Kept as a no-op so the migration history stays readable.
-- Replaces: nothing
-- Retires: nothing
select 1;
