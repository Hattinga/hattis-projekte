import assert from "node:assert/strict";
import { existsSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { after, beforeEach, test } from "node:test";
import { branchExists, excludeHivemindDir, git, hasUncommittedChanges, Workspace } from "../src/git.js";

const dirs: string[] = [];
let repo: string;

function newRepo(): string {
  const dir = mkdtempSync(join(tmpdir(), "hivemind-test-"));
  dirs.push(dir);
  git(dir, "init", "-q", "-b", "main");
  git(dir, "config", "user.name", "Test");
  git(dir, "config", "user.email", "test@example.com");
  git(dir, "config", "core.autocrlf", "false");
  writeFileSync(join(dir, "a.txt"), "eins\n");
  git(dir, "add", "-A");
  git(dir, "commit", "-qm", "init");
  return git(dir, "rev-parse", "--show-toplevel");
}

beforeEach(() => {
  repo = newRepo();
});

after(() => {
  for (const dir of dirs) rmSync(dir, { recursive: true, force: true });
});

test("tasks run in their own worktrees and merge into the run's branch, the checkout stays untouched", () => {
  excludeHivemindDir(repo);
  const ws = new Workspace(repo, "run1");
  ws.open();

  const t1 = ws.taskWorktree("t1");
  writeFileSync(join(t1.dir, "b.txt"), "von t1\n");
  ws.commitLeftovers(t1.dir, "t1");
  assert.equal(ws.merge(t1.branch, "merge t1"), true);
  ws.removeTaskWorktree(t1.dir, t1.branch);

  assert.equal(readFileSync(join(ws.integration, "b.txt"), "utf8"), "von t1\n");
  assert.equal(existsSync(join(repo, "b.txt")), false);
  assert.equal(git(repo, "branch", "--show-current"), "main");
  assert.equal(hasUncommittedChanges(repo), false, ".hivemind/ must not show up in git status");
});

test("a later task starts from what is already merged", () => {
  const ws = new Workspace(repo, "run2");
  ws.open();
  const t1 = ws.taskWorktree("t1");
  writeFileSync(join(t1.dir, "b.txt"), "b\n");
  ws.commitLeftovers(t1.dir, "t1");
  ws.merge(t1.branch, "merge t1");

  const t2 = ws.taskWorktree("t2");
  assert.equal(readFileSync(join(t2.dir, "b.txt"), "utf8"), "b\n");
  assert.equal(t2.base, git(repo, "rev-parse", ws.branch));
});

test("conflicting tasks are detected and the merge can be rolled back", () => {
  const ws = new Workspace(repo, "run3");
  ws.open();
  const t1 = ws.taskWorktree("t1");
  const t2 = ws.taskWorktree("t2");
  writeFileSync(join(t1.dir, "a.txt"), "t1 sagt so\n");
  writeFileSync(join(t2.dir, "a.txt"), "t2 sagt anders\n");
  ws.commitLeftovers(t1.dir, "t1");
  ws.commitLeftovers(t2.dir, "t2");

  assert.equal(ws.merge(t1.branch, "merge t1"), true);
  assert.equal(ws.merge(t2.branch, "merge t2"), false);
  assert.equal(ws.mergeInProgress(), true);
  ws.abortMerge();
  assert.equal(ws.mergeInProgress(), false);
  assert.equal(readFileSync(join(ws.integration, "a.txt"), "utf8"), "t1 sagt so\n");
});

test("cleanup removes worktrees and task branches but keeps the result, and the run can be reopened", () => {
  const ws = new Workspace(repo, "run4");
  ws.open();
  const t1 = ws.taskWorktree("t1");
  writeFileSync(join(t1.dir, "b.txt"), "b\n");
  ws.commitLeftovers(t1.dir, "t1");
  ws.merge(t1.branch, "merge t1");
  ws.taskWorktree("t2"); // interrupted, never merged

  ws.cleanup();
  assert.equal(existsSync(ws.integration), false);
  assert.equal(existsSync(join(ws.root, "t2")), false);
  assert.equal(branchExists(repo, ws.branch), true);
  assert.equal(branchExists(repo, `${ws.branch}-t1`), false);
  assert.equal(branchExists(repo, `${ws.branch}-t2`), false);

  // --resume
  ws.open();
  assert.equal(readFileSync(join(ws.integration, "b.txt"), "utf8"), "b\n");
  ws.cleanup();
});

test("a task interrupted last time starts over cleanly", () => {
  const ws = new Workspace(repo, "run5");
  ws.open();
  const first = ws.taskWorktree("t1");
  writeFileSync(join(first.dir, "halb.txt"), "halb fertig\n");
  const again = ws.taskWorktree("t1");
  assert.equal(existsSync(join(again.dir, "halb.txt")), false);
});

test("merging into the checkout works when clean and refuses when dirty", () => {
  const ws = new Workspace(repo, "run6");
  ws.open();
  writeFileSync(join(ws.integration, "neu.txt"), "neu\n");
  ws.commitLeftovers(ws.integration, "neu");

  writeFileSync(join(repo, "a.txt"), "lokal geändert\n");
  assert.equal(ws.mergeIntoCheckout().ok, false);
  git(repo, "checkout", "--", "a.txt");

  assert.equal(ws.mergeIntoCheckout().ok, true);
  assert.equal(readFileSync(join(repo, "neu.txt"), "utf8"), "neu\n");
  ws.cleanup();
});

test("the exclude entry is added only once", () => {
  excludeHivemindDir(repo);
  excludeHivemindDir(repo);
  const exclude = readFileSync(join(repo, ".git", "info", "exclude"), "utf8");
  assert.equal(exclude.split("\n").filter((l) => l.trim() === ".hivemind/").length, 1);
});
