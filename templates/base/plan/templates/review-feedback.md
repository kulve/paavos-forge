# Review Feedback: [Phase] for Story XXXXX

## Verdict

REJECTED

A review is REJECTED only when it has at least one blocking finding. Advisories do not
belong in this file at all -- they go to a single discovery file under `plan/discoveries/`
and the review is APPROVED. If every finding is advisory, do not write this file.

## Blocking Issues

A finding is blocking when the work is incorrect, unsafe, fails to meet a requirement, or
diverges from the architecture. Every entry needs an **anchor**: the artifact element the
work contradicts. Valid anchors are listed in your agent prompt. An issue you cannot
anchor is not blocking.

Each entry carries one line of justification for why it is blocking rather than advisory.

1. **[File:line or artifact]** -- Anchor: [requirement ID, ARCHITECTURE.md rule, interface element, test name, quoted gate output, or project-profile entry]. Problem: [Exact contradiction]. Why blocking: [incorrect / unsafe / requirement unmet / diverges from architecture]. Fix: [Concrete instruction].
2. **[File:line or artifact]** -- Anchor: [...]. Problem: [...]. Why blocking: [...]. Fix: [...].

## Missed Requirements

- [Requirement ID]: [What was missed and what should be added]

## Advisories Filed

- [Path to the single discovery file holding this review's advisory findings, or "none"]

## Approved Aspects

[What was good -- helps the Write agent know what NOT to change]
