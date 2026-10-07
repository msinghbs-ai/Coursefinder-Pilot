// Canonical browser-visible release and recovery authority.
// New releases must change this file rather than defining competing current-version literals elsewhere.
export const UI_VERSION='2.15.216'
export const PACKAGE_VERSION='0.1.143'
export const RELEASE_STATE='candidate'
export const RELEASE={
  version:UI_VERSION,
  packageVersion:PACKAGE_VERSION,
  date:'7 Oct 2026',
  title:'Guided adapter build; Adapters visible to Pipeline Operators',
  changes:[
    'Providers list: Platform Admins see an Adapter column beside the provider name. Open adapter or Create adapter opens Layer 2 \u203a Adapter builder with that provider loaded.',
    'Adapter builder: a guided build in six steps, one button each (find course pages, capture samples, the pinned model proposes settings, save in testing and apply, qualify, admit). Admit these is offered only for fields that pass the admit rule and agree with values already held; nothing runs on a schedule and a passing check never admits by itself.',
    'Layer 2 \u203a Adapters is visible again to Pipeline Operators, read only, as the server allows.'
  ],
  bugFixes:['v2.15.211 hid Layer 2 \u203a Adapters from Pipeline Operators by mistake; restored.','v2.15.215 showed the previous release notes; corrected.','Seven contract checks written against screens redesigned since late September now check the current screens.']
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
