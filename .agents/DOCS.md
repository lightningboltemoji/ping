# Writing it down

## Where an explanation goes

A comment says what a reader needs to understand the code in front of them. Everything else — the
investigation, the rejected alternatives, the bug that motivated a line, the numbers that proved it —
belongs in the change, and `git blame` reaches it. A comment carrying that weight is unparseable at
the moment someone actually needs it: it is read while chasing something else.

- **Three lines is the working ceiling** for a declaration, and most need one. If it wants more, the
  surplus is history and the change file is where it goes.
- **Say the constraint, not the derivation.** "A tile this far off-screen is clamped back into view by
  macOS" is the fact; how it was found is not.
- **Never date, attribute, or narrate.** No "previously", no "we changed this because", no bug ids.
  `PRINCIPLES.md` and `IMPLEMENTATION.md` are present-tense for the same reason.
- The two documents are the exception that proves it: prose _is_ their code, and an argument that
  belongs to the design as a whole lives there rather than above the line that happens to implement it.

## The change file

Three sections, normally a paragraph each:

```markdown
# <title>

> Change `<id>` — <date>

## Goal

The problem this addresses.

## Implementation

Pull-request altitude: what a reviewer needs to read the diff. Decisions and the reasons for them,
rejected alternatives and their failure modes. Not a restatement of the code.

## Observations

Known limits, untested areas, follow-up work.
```

## The pass

The change file is the last thing written, and writing it is the cue to run this. Not an appraisal of
whether the rules were followed — that question answers itself "yes" from inside the frame that broke
them. It is four steps over the diff, each with an output.

1. **Enumerate** every comment on a declaration that the diff added or touched and that runs past three
   lines. For each, cut it to the constraint or move the surplus into the change file. The list comes
   first: a block is easy to defend one at a time and hard to defend in a column.
2. **Grep** the diff's comments for `previously`, `used to`, `we changed`, `the bug`, dates, and issue
   ids. Delete what they introduce.
3. **Reconcile** the diff against `PRINCIPLES.md` and `IMPLEMENTATION.md`. Behaviour either of them now
   describes wrongly is edited in place, present tense — the change file is what holds the prior
   reading. Writing the change is half the job; this is the other half.
4. **Report** what the pass changed. "Nothing" is a valid result and worth saying out loud, because a
   silent pass and a skipped pass look identical.
