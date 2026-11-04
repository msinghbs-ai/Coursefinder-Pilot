# Provider description governance records

The requested single draft PR is in `msinghbs-ai/Coursefinder-Pilot`. The canonical governance changes belong in `msinghbs-ai/coursefinder-admin` and are included in `provider-description-admin.patch` for the Integration Controller's review. They are also recorded on that repository's local `codex/provider-description-autonomy` branch.

From a reconciled admin checkout, inspect and apply with:

```sh
git apply --stat /path/to/provider-description-admin.patch
git apply --check /path/to/provider-description-admin.patch
git apply /path/to/provider-description-admin.patch
```

The patch contains the pre-implementation mandate, verified read-only baseline and aggregate JSON evidence, full dated response, updates to the existing UI catalogue, pipeline lineage and SS-018/SS-021 execution history, and regenerated canonical Test Register. It contains documentation only and introduces no runtime dependency. Its original governance base is `111bb17edcf4d9348be0c4be8a61cc47896dbd13`; reconcile any later canonical edits before applying. Do not overwrite other Controller changes.

No second PR, deployment, release assignment or production write is performed by this packaging. Runtime development acceptance and the Controller's production procedure are in [the feature document](../provider-description-autonomy.md).
