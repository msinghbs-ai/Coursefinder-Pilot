// Canonical browser-visible release and recovery authority.
// New releases must change this file rather than defining competing current-version literals elsewhere.
export const UI_VERSION='2.16.20'
export const PACKAGE_VERSION='0.1.442'
export const RELEASE_STATE='candidate'
export const RELEASE={
  version:UI_VERSION,
  packageVersion:PACKAGE_VERSION,
  date:'17 Nov 2026',
  title:'Users & roles: Links & Email Templates',
  changes:[
    'Administration › Users & roles now has two tabs: Users & roles (the directory, as before) and Links & Email Templates (Platform Admin).',
    'Links & Email Templates: set the Admin Site URL and the Admin Guide Link, and edit the Invite User and Reset Password emails (subject and HTML body) with a live preview. Variable chips insert {{link}}, {{guide_link}}, {{user_email}}, {{user_name}} and {{role}} at the cursor. The emails start from the branded StudySearch PIM Admin template.',
    'Save & Sync needs a reason, which is kept in the control log. The saved emails are copied to Supabase Auth only when a management token is set for the edge function; the screen says whether the copy happened.',
    'Send Test Email sends the Reset Password email to your own account or another existing user. An invitation is tested by inviting a new address from Create user.',
    'A password reset email now carries the person\'s current role and the saved guide link.'
  ],
  bugFixes:[
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
