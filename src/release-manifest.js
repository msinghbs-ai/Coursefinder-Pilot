// Canonical browser-visible release and recovery authority.
// New releases must change this file rather than defining competing current-version literals elsewhere.
export const UI_VERSION='2.15.284'
export const PACKAGE_VERSION='0.1.211'
export const RELEASE_STATE='candidate'
export const RELEASE={
  version:UI_VERSION,
  packageVersion:PACKAGE_VERSION,
  date:'16 Oct 2026',
  title:'Platform health that matches reality; scholarship reading restarted; dashboard icons; delete users',
  changes:[
    'Users & roles: a Platform Admin can delete a user (type the email to confirm). A Platform Admin, your own account and the system automation account cannot be deleted. Deleted users are listed with who deleted them and when.',
    'Dashboard: each queue in Waiting for you has its icon.',
    'Platform health shows work held on purpose (a university past its scholarship cap, small Australian providers) as held, not stalled.'
  ],
  bugFixes:[
    'Scholarship pages asked to be read again were held by the per-university cap and nothing was read from 14 Oct; they are read again now.',
    'Platform health no longer reports the retired tuition hand-off, a job back from a trial-run pause as overdue, the scholarship Firecrawl allowance as 3,000 credits, or the database against the old Micro plan (it is Medium, 120 connections; size levels follow the 8 GB disk).'
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
