`.agents/README.md` provides context on the project and how knowledge is managed.

House rules:

- Bias towards clean architecture. Ask yourself if this is the right solution or the easy one.
- Bias towards validating instead of guessing. Where Swift snippets won't do, running the daemon and moving windows is never an interruption.
- Before removing a mechanism, measure what it buys — a stale rationale is not a wrong decision, and the suite usually already prices it.
- Keep this file thin. It carries triggers; `.agents/` carries content.
- Feature work ends with the change file, and writing it starts the pass in `.agents/DOCS.md`. Run the pass
  before reporting the work done.

## Worktrees

Work happens in a worktree; `main` is where it lands. Never edit `main` directly, even for prototyping.

- **Start** with `EnterWorktree` — `.claude/worktrees/<name>` on `worktree-<name>`. Never `git worktree add` to a
  sibling directory.
- **Commit in the worktree**, freely and without asking. Landing needs those commits.
- **Land** from the main checkout, on `main`:

  ```
  git merge --squash worktree-<name>
  git worktree remove .claude/worktrees/<name> && git branch -D worktree-<name>
  ```

- It arrives **staged**, no commit created. Staged is what landed, unstaged was already there; never commit
  `main` yourself.
- Never `stash`, `reset`, or `checkout .` `main`'s dirty files to clear a merge. If it refuses, name the file and stop.
- `--squash` records no `MERGE_HEAD`. Back out with `git reset && git checkout -- <files>`, not `git merge --abort`.
