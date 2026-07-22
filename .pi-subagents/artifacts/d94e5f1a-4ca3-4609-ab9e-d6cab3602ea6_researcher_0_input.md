# Task for researcher

Research open-source fonts and icon fonts specifically suitable for smooth frame-by-frame terminal loading animations. Prioritize fonts with long coherent glyph sequences (8+ frames), especially centered pulse/orbit/circle/loading animations. Distinguish actual animation-ready glyph families from ordinary spinner libraries. Provide exact font/project, frame count, codepoints/names, visual behavior, licensing, terminal compatibility, and stable primary-source links or GitHub permalinks. Do not edit files.

---
**Output:**
Write your findings to exactly this path: /home/ian/.config/nixos/.pi-subagents/artifacts/outputs/d94e5f1a-4ca3-4609-ab9e-d6cab3602ea6/research/external-spinner-fonts.md
This path is authoritative for this run.
Ignore any other output filename or output path mentioned elsewhere, including output destinations in the base agent prompt, system prompt, or task instructions.

## Acceptance Contract
Acceptance level: attested
Completion is not accepted from prose alone. End with a structured acceptance report.

Criteria:
- criterion-1: Return concrete findings with file paths and severity when applicable

Required evidence: review-findings, residual-risks

Finish with a fenced JSON block tagged `acceptance-report` in this shape:
Use empty arrays when no items apply; array fields contain strings unless object entries are shown.
`criteriaSatisfied[].status` must be exactly one of: satisfied, not-satisfied, not-applicable.
`commandsRun[].result` must be exactly one of: passed, failed, not-run.
`manualNotes` and `notes` are optional strings; an empty string means no note and does not satisfy `manual-notes` evidence.
```acceptance-report
{
  "criteriaSatisfied": [
    {
      "id": "criterion-1",
      "status": "satisfied",
      "evidence": "specific proof"
    }
  ],
  "changedFiles": [
    "src/file.ts"
  ],
  "testsAddedOrUpdated": [
    "test/file.test.ts"
  ],
  "commandsRun": [
    {
      "command": "command",
      "result": "passed",
      "summary": "short result"
    }
  ],
  "validationOutput": [
    "validation output or concise summary"
  ],
  "residualRisks": [
    "none"
  ],
  "noStagedFiles": true,
  "diffSummary": "short description of the diff",
  "reviewFindings": [
    "blocker: file.ts:12 - issue found, or no blockers"
  ],
  "manualNotes": "anything else the parent should know"
}
```