import { execFileSync } from "node:child_process";
import { existsSync, mkdirSync } from "node:fs";
import { join, resolve } from "node:path";

export function git(cwd: string, ...args: string[]): string {
  return execFileSync("git", args, { cwd, encoding: "utf8", stdio: ["ignore", "pipe", "pipe"] }).trim();
}

export function tryGit(cwd: string, ...args: string[]): { ok: boolean; output: string } {
  try {
    return { ok: true, output: git(cwd, ...args) };
  } catch (error) {
    const e = error as { stdout?: string; stderr?: string };
    return { ok: false, output: `${e.stdout ?? ""}${e.stderr ?? ""}`.trim() };
  }
}

/** Non-empty lines of git output, without Windows line endings. */
function lines(output: string): string[] {
  return output.split("\n").map((line) => line.trim()).filter(Boolean);
}

export function isGitRepo(cwd: string): boolean {
  return tryGit(cwd, "rev-parse", "--is-inside-work-tree").output === "true";
}

/** Changed or new files. With `trackedOnly`, new files that git does not know yet don't count. */
export function hasUncommittedChanges(cwd: string, trackedOnly = false): boolean {
  return git(cwd, "status", "--porcelain", ...(trackedOnly ? ["--untracked-files=no"] : [])).length > 0;
}

export function branchExists(repo: string, branch: string): boolean {
  return tryGit(repo, "rev-parse", "--verify", "--quiet", `refs/heads/${branch}`).ok;
}

export function hasCommits(repo: string): boolean {
  return tryGit(repo, "rev-parse", "--verify", "--quiet", "HEAD").ok;
}

/**
 * All of a run's work happens in `root` (outside the project): one integration
 * worktree on branch hivemind/<runId> plus one worktree per task. Your own
 * checkout and branch are never touched; you merge hivemind/<runId> when you like it.
 */
export class Workspace {
  readonly root: string;
  readonly branch: string;
  readonly integration: string;

  constructor(readonly repo: string, readonly runId: string, root: string) {
    this.root = root;
    this.branch = `hivemind/${runId}`;
    this.integration = join(this.root, "integration");
  }

  /** Creates the integration worktree, or reopens it when an interrupted run continues. */
  open() {
    mkdirSync(this.root, { recursive: true });
    tryGit(this.repo, "worktree", "prune");
    if (existsSync(join(this.integration, ".git"))) return;
    if (branchExists(this.repo, this.branch)) git(this.repo, "worktree", "add", this.integration, this.branch);
    else git(this.repo, "worktree", "add", "-b", this.branch, this.integration, "HEAD");
  }

  /** A fresh worktree for one task, branched from the current state of the integration branch. */
  taskWorktree(taskId: string): { dir: string; branch: string; base: string } {
    const branch = `${this.branch}-${taskId}`;
    const dir = join(this.root, taskId);
    // Leftovers of a task that was interrupted last time start over.
    this.removeTaskWorktree(dir, branch);
    const base = git(this.repo, "rev-parse", this.branch);
    git(this.repo, "worktree", "add", "-b", branch, dir, base);
    return { dir, branch, base };
  }

  /** Commits whatever an agent left uncommitted, so nothing gets lost on merge. */
  commitLeftovers(dir: string, message: string) {
    if (!hasUncommittedChanges(dir)) return;
    git(dir, "add", "-A");
    git(dir, "commit", "-m", message);
  }

  /** Merges a task branch into the integration branch. Returns false when there are conflicts to resolve. */
  merge(branch: string, message: string): boolean {
    return tryGit(this.integration, "merge", "--no-ff", "-m", message, branch).ok;
  }

  mergeInProgress(): boolean {
    return tryGit(this.integration, "rev-parse", "-q", "--verify", "MERGE_HEAD").ok;
  }

  abortMerge() {
    tryGit(this.integration, "merge", "--abort");
  }

  removeTaskWorktree(dir: string, branch: string) {
    tryGit(this.repo, "worktree", "remove", "--force", dir);
    tryGit(this.repo, "branch", "-D", branch);
  }

  /** Removes all worktrees and task branches of this run but keeps the hivemind/<runId> branch. */
  cleanup() {
    const root = resolve(this.root).toLowerCase();
    for (const line of lines(git(this.repo, "worktree", "list", "--porcelain"))) {
      if (!line.startsWith("worktree ")) continue;
      const dir = resolve(line.slice("worktree ".length));
      if (dir.toLowerCase().startsWith(root)) tryGit(this.repo, "worktree", "remove", "--force", dir);
    }
    tryGit(this.repo, "worktree", "prune");
    for (const branch of lines(git(this.repo, "branch", "--list", `${this.branch}-*`, "--format=%(refname:short)"))) {
      tryGit(this.repo, "branch", "-D", branch);
    }
  }

  /** Merges the run's branch into whatever you have checked out. Only on a clean checkout; conflicts are rolled back. */
  mergeIntoCheckout(): { ok: boolean; message: string } {
    if (hasUncommittedChanges(this.repo, true)) {
      return { ok: false, message: "Du hast uncommittete Änderungen. Committe oder stash sie und merge dann selbst." };
    }
    const result = tryGit(this.repo, "merge", "--no-ff", "-m", `Merge ${this.branch}`, this.branch);
    if (result.ok) return { ok: true, message: `${this.branch} ist in ${git(this.repo, "branch", "--show-current") || "HEAD"} gemergt.` };
    tryGit(this.repo, "merge", "--abort");
    return { ok: false, message: `Merge-Konflikt, nichts geändert. Merge selbst mit: git merge ${this.branch}` };
  }
}
