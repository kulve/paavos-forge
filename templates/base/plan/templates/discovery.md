# Discovery: [short title]

## Found By

- Agent: [agent role]
- Story: [story ID and path, or N/A]
- Phase: [req|arch|test|impl|support|fixer]
- Review: [path to the review this came out of, or N/A]
- Date: [YYYY-MM-DD HH:MM]

## Classification

- Category: [bug|gap|stub|design flaw|risk|advisory]
- Severity: [high|medium|low]

Use `advisory` with `low` or `medium` severity for review findings that are real but not
blocking: the work is correct and meets its requirements, and you would have done it
differently. Anything incorrect, unsafe, unmet, or diverging from the architecture is a
blocking review finding, not a discovery.

## Finding

[One short paragraph describing the discovery precisely. A review advisory may hold several
related findings in one file -- one file per review, not one per finding.]

## Evidence

[Relevant file paths, symptoms, or observations. Keep this brief.]

## Why It Matters

[The meaningful functionality, correctness, security, or performance impact.]

## Suggested Follow-Up

[A concise proposed next step. Do not solve it here.]
