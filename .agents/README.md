# `.agents/`

| File                | Contents                                                          | Tense      |
| ------------------- | ----------------------------------------------------------------- | ---------- |
| `PRINCIPLES.md`     | the charter, the sensor, the thesis, what Ping owes its user      | present    |
| `IMPLEMENTATION.md` | module layout, the pure core, the effects, the config machinery   | present    |
| `changes/<id>.md`   | what one change did and why                                       | past       |
| `DOCS.md`           | how the rest are written; the pass that ends a change             | imperative |

## Ground truth

`PRINCIPLES.md` and `IMPLEMENTATION.md` describe Ping as it is now. No dated entries, no "corrected
on", no description of prior behaviour. A superseded decision has its text replaced; the previous
reading stays in git and in the change that replaced it.

**These two are the only design documents, and there is no third.** A comment that wants to point
somewhere points at one of them by name and section — `IMPLEMENTATION.md §4`, never a bare `§4`,
because a section number with no document attached is a reference to whatever the reader assumes.

## Changes

Feature work has a change id: the Unix epoch second it was made. The id names a file,
`.agents/changes/1787000000.md`.

How a comment, a change, or an edit to the two documents is written — and the pass that ends feature
work — is `DOCS.md`.
