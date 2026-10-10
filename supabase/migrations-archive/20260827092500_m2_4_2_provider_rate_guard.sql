-- CF-CHG-20260827-044 / M2.4.2 A8
alter table pipeline.layer2_acquisition_providers drop constraint if exists layer2_acquisition_providers_rate_limit_check;
alter table pipeline.layer2_acquisition_providers add constraint layer2_acquisition_providers_rate_limit_check check (rate_limit_per_minute is null or (rate_limit_per_minute between 1 and 10000));