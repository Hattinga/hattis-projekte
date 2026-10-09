import { execFileSync } from "node:child_process";
import { mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { git, tryGit } from "./git.js";

function hasGh(): boolean {
  try {
    execFileSync("gh", ["--version"], { stdio: "ignore" });
    return true;
  } catch {
    return false;
  }
}

/** A pull request is possible when the project has an origin remote and the GitHub CLI is installed. */
export function canOpenPullRequest(repo: string): boolean {
  return tryGit(repo, "remote", "get-url", "origin").ok && hasGh();
}

/**
 * Pushes the run's branch to origin and opens a pull request into the branch you have checked out.
 * Returns the PR's URL.
 */
export function openPullRequest(repo: string, branch: string, title: string, body: string): string {
  const base = git(repo, "branch", "--show-current");
  if (!base) throw new Error("Du bist auf keinem Branch (detached HEAD), da weiß ich nicht, wohin der Pull Request soll.");
  git(repo, "push", "-u", "origin", branch);
  // The body goes through a file: Windows command lines are short and mangle quotes.
  const dir = mkdtempSync(join(tmpdir(), "hivemind-pr-"));
  try {
    const bodyFile = join(dir, "body.md");
    writeFileSync(bodyFile, body);
    return execFileSync("gh", ["pr", "create", "--base", base, "--head", branch, "--title", title, "--body-file", bodyFile], {
      cwd: repo,
      encoding: "utf8",
      stdio: ["ignore", "pipe", "pipe"],
    }).trim();
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
}
