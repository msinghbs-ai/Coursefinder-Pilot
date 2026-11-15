// Canonical browser-visible release and recovery authority.
// New releases must change this file rather than defining competing current-version literals elsewhere.
export const UI_VERSION='2.16.3'
export const PACKAGE_VERSION='0.1.425'
export const RELEASE_STATE='candidate'
export const RELEASE={
  version:UI_VERSION,
  packageVersion:PACKAGE_VERSION,
  date:'15 Nov 2026',
  title:'Pipeline maintenance: pause every job before a database change, then resume exactly those jobs',
  changes:[
    'Scheduled jobs › Automations: a new card at the top, Pipeline maintenance. Pause & Drain for Migration (Platform Admin) switches off every active scheduled job after a confirmation with an optional reason, and keeps a copy of every job and setting. Jobs that were already off stay off.',
    'While paused the card refreshes every 2 seconds and shows what is still under way: running cron jobs, active database queries, edge worker calls, worker leases, catalogue locks, and any job switched on again during the pause.',
    'When all of these reach 0 the card turns green: SAFE TO APPLY DB CHANGES. The time paused counts up and turns red after Maintenance pause: warn after (Settings › Pipeline settings, 15 minutes).',
    'Resume Pipeline switches on exactly the jobs the pause switched off (never a retiring job). It changes no setting; settings changed during the pause are listed.',
    'While paused, nothing switches a job back on by itself: the idle-job and flag controllers stand down, releasing a held job is refused, and Automations allows Pause only. The website and Zoho APIs keep answering; their data is not refreshed until resume.',
    'Everyone with an admin role sees the state; only the Platform Admin pauses and resumes.'
  ],
  bugFixes:[
    'Worker v1.0.0 to v1.0.4 (no screen change, released since v2.16.2): Layer 4 self-healing drain and its verdicts; markdown page input; model order kept by AI health; defects found in admitted records fixed (the scholarship coverage classifier failed on every run); an OpenRouter key-limit refusal stops AI work for the account instead of failing each item; course description prompt v2 with one quality retry on the next model.',
    'API v3 additive schema (migration 20261115190000): new columns and tables beside v2; the v2 website and Zoho APIs are unchanged.'
  ]
}

// Ordered accepted releases. The first item is the only recovery baseline for a new candidate.
// Historical releases before this central manifest remain retained by the legacy release-history source.
export const ACCEPTED_RELEASES=[
  {
    version:'2.15.79',
    packageVersion:'0.1.6',
    date:'14 Sep 2026',
    pilotMain:'32be4e96a8df342deba3011f9740dc1230a672b2',
    title:'Dispatcher tuning & run metrics',
    changes:[
      'Administration > Scraper Config now separates vendor controls from governed Layer 2 dispatcher tuning.',
      'Admins can compare recent runs using throughput, response/extraction latency, retries, Evidence, field resolution and Layer 2/Layer 3/blocked outcomes.',
      'PIM/Data Admins can tune batch size, run concurrency, stale recovery and paid-attempt limits for subsequent runs with an auditable governance reason.',
      'Running batches retain their immutable policy snapshot; tuning never rewrites work already in flight.',
      'Hourly CourseFinder metrics track dispatcher continuations, provider performance, Evidence and policy snapshots for evidence-based tuning.'
    ],
    bugFixes:[
      'Retains the Layer 2 runner transport safety cap introduced by PR #84: ordinary invocations remain capped at four items and scraper-first invocations at two.',
      'Dispatcher metrics are sanitized and do not expose raw payloads, result/error text, target URLs, Storage paths or provider credentials.',
      'Preserves Layer 1 authority, Layer 3 Evidence/profile/model governance, Layer 4 human authority and separate Search/Publication admission.'
    ]
  }
]

export const RECOVERY_RELEASE=ACCEPTED_RELEASES[0]
