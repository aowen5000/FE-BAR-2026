# Conversation IDs in commit messages

Moved from BUILD.md in Step 10. Steps 8 to 11 are added at the end.

In Step 7, every merge commit on main was matched to the transcript in `~/.conversations` that contains its `git merge` command. This is the same method `logs/commit_metadata_corrections.md` used. Three groups of commits carry a conversation ID that differs from the transcript holding the merge command:

| Commits | ID in commit message | Transcript with the merge command | Why |
| --- | --- | --- | --- |
| 69c7546, 563f534 (non-merge commits a0d1a81, 81b9d37, 0e7b667 and ba0518f fall in the same session window; matched by time only) | 2172058462486781 | 1915570766916222 ("Creating UC User Groups for PII and Non-PII", 2026-10-15 02:08 to 03:40 UTC) | Follow-up work in a second session; the message reused the Step 2 ID |
| e6e20bc, 1b646df, 63aa15f (non-merge commits 6f2f6dc, 8237f17 and b7b8d78 fall in the same session window; matched by time only) | 2172058462486781 | 2606072674702393 ("Confirming Access to Installed Genie Skills", 2026-10-16) | Gold layer built in a new session; the message reused the Step 2 ID |
| cca7f02, d960100, df950c1, f905a98 | 1835980093459154 | 2460977471802157 ("Restoring Notebook Outputs for GitHub", 2026-10-23 to 2026-10-24) | That session flagged the mismatch and asked which ID to use; 1835980093459154 was used |

History was not rewritten. Each transcript's opening prompt is in `prompts/`.

## Steps 7 to 11 (from `git log --merges --first-parent main`, read 2026-11-06; Step 11 added 2026-11-10)

| Merge | Branch | Conversation ID in message | Note |
| --- | --- | --- | --- |
| 2181f41 | `step7/2026-11-01_fevm-workshop-guy_conv-245211859776391` | 245211859776391 | |
| 549fac2 | `step7-followup/2026-11-01_fevm-workshop-guy_conv-1125672163420859` | 1125672163420859 | No prompt file for this conversation in `prompts/` |
| 8c5da6d | `step8/2026-11-03_fevm-workshop-guy_conv-2326365276521178` | 2326365276521178 | |
| a14d8c0 | `step8b/2026-11-04_fevm-workshop-guy_conv-2326365276521178` | 2326365276521178 | |
| 346289b | `step8c/2026-11-04_fevm-workshop-guy_conv-2326365276521178` | 2326365276521178 | The message says "Merges step8b". Its second parent 2bbfac7 is the tip of step8c ("narrow account users grants to least privilege on fe_bar_a0"). Not rewritten |
| 894e41a | `step8d/2026-11-04_fevm-workshop-guy_conv-2326365276521178` | 2326365276521178 | |
| e54d5c8 | `step8e/2026-11-05_fevm-workshop-guy_conv-2326365276521178` | 2326365276521178 | |
| d54f358 | `step9/2026-11-04_fevm-workshop-guy_conv-1085628541759563` | 1085628541759563 | Merged 2026-11-06 UTC |
| f6d6fd4 | `docs/2026-11-06_fevm-workshop-guy_conv-1883459888084279` | 1883459888084279 | No prompt file for this conversation in `prompts/` |
| Step 10 merge | `step10/2026-11-06_fevm-workshop-guy_conv-1883459888084300` | 1883459888084300 | Hash recorded in `logs/final_verification_2026-11-06.md` |
| Step 11 merge | `step11/2026-11-09_fevm-workshop-guy_conv-4443667514456316` | 4443667514456316 | Merge hash in `git log --merges --first-parent main`; branch commits in `logs/high_value_triage_2026-11-09.md` |
