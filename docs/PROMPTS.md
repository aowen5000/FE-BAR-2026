# Prompts

Moved from BUILD.md in Step 10, with Steps 8 to 10 added.

`prompts/` holds one file per conversation, named `step<N>_<conversation_id>.md`. Each file contains the opening user prompt copied verbatim from that conversation's transcript. Where the first message was only a session name or the skills check, the build prompt that followed is included too. In Step 7 none of the transcripts contained tokens, passwords or credentialed connection strings, so nothing was redacted (token scan in `logs/evidence_pass_2026-11-01.md`). Steps 8 to 10 are covered by the Step 10 token scan in `logs/final_verification_2026-11-06.md`.

| File | Conversation |
| --- | --- |
| `prompts/step1_3458967129203277.md` | Step 1 data generator |
| `prompts/step2_2172058462486781.md` | Step 2 bronze/silver pipeline |
| `prompts/step2_1915570766916222.md` | Step 2 follow-up (groups, executable evidence notebook, merges) |
| `prompts/step2_2606072674702393.md` | Step 2 gold feature layer |
| `prompts/step3_3367633421784666.md` | Step 3 Lakebase read and write path |
| `prompts/step4_2565515039400048.md` | Step 4 ML batch scoring |
| `prompts/step5_1507503687185838.md` | Step 5 agent and Lakebase FGAC |
| `prompts/step6_1835980093459154.md` | Step 6 dashboard |
| `prompts/step6_2460977471802157.md` | Step 6 notebook outputs re-run |
| `prompts/step7_245211859776391.md` | Step 7 evidence pass |
| `prompts/step8_2326365276521178.md` | Step 8 Genie Agent, and the follow-ups 8b to 8e in the same conversation |
| `prompts/step9_1085628541759563.md` | Step 9 Databricks App |
| `prompts/step10_1883459888084300.md` | Step 10 business value and final evidence pass |

Gaps:

* **Transcript gap, Step 3:** the stored transcript of 3367633421784666 has visibly missing spans inside the opening prompt, including most of STEP 2 to STEP 4. The file reproduces the text as stored and marks the gaps. The original wording can be pasted in if a copy exists.
* **No prompt file:** conversation 1125672163420859 (Step 7 follow-up, merge 549fac2) and conversation 1883459888084279 (Commit identities note, merge f6d6fd4).
