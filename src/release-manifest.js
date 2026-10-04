// Canonical browser-visible release and recovery authority.
// New releases must change this file rather than defining competing current-version literals elsewhere.
export const UI_VERSION='2.15.177'
export const PACKAGE_VERSION='0.1.104'
export const RELEASE_STATE='candidate'
export const RELEASE={
  version:UI_VERSION,
  packageVersion:PACKAGE_VERSION,
  date:'3 Oct 2026',
  title:'Toolsets and limits: notices on each layer, OpenRouter observed not capped, Serper and ScrapingBee trials',
  changes:[
    'Each Layer page (1 to 4) shows a notice when a toolset it depends on hits a limit or times out: OpenRouter refusals and balance, spend past a guard, Firecrawl balance and caps, scheduled jobs that hit the database time limit, edge function time-outs, and trials stopped by a limit. Notices can be acknowledged and come back if it happens again.',
    'OpenRouter is set to observe only: the daily spend guards and the credit floor are shown and raise notices but no longer stop Layer 3. One switch on Models & services returns it to stop at limits. The routing worker no longer has a fixed US$5 floor in its code.',
    'Models & services › Toolsets and limits: every limit, look-back and threshold is a setting the Platform Admin changes with a reason; OpenRouter balance, today’s spend by task and 14 days of spend are shown.',
    'Serper and ScrapingBee are registered switched off. Trials sample the real backlog in every country listed (AU, NZ and CA to start), record each call’s outcome and credits, and show results by country with a cost projection for the whole backlog. Nothing a trial finds is admitted.'
  ],
  bugFixes:[]
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
