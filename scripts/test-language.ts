#!/usr/bin/env bun
/**
 * Test runner for zlx implementation-agnostic language tests in tests/.
 *
 * Follows Crafting Interpreters conventions and zlx modifiers:
 *   // expect: output
 *   // @success: output
 *   // expect runtime error: message
 *   // [line N] Error ...
 *   // @failure[: expected error message] (asserts exit code != 0 and optional error message)
 *   // @timeout: seconds (limits a test that may otherwise hang)
 */

import * as fs from "fs";
import * as path from "path";

interface TestExpectations {
  expectedOutput: string[];
  runtimeErrors: string[];
  compileErrors: string[];
  hasFailure: boolean;
  failureErrors: string[];
  timeoutSeconds: number | null;
}

interface TestRunResult {
  displayPath: string;
  result: "PASS" | "FAIL";
  duration: number;
  exitCode: number;
  reason: string;
  expected: string;
  actual: string;
  rawOutput: string;
}

const rootDir = path.resolve(import.meta.dir, "..");
const testDir = path.join(rootDir, "tests");
const resultsDir = path.join(rootDir, ".test-results");
const lastRunFile = path.join(resultsDir, "last-run.json");
const prevRunFile = path.join(resultsDir, "prev-run.json");

const isTTY = Boolean(process.stdout.isTTY && !process.env.NO_COLOR);
const colors = {
  reset: isTTY ? "\x1b[0m" : "",
  bold: isTTY ? "\x1b[1m" : "",
  dim: isTTY ? "\x1b[2m" : "",
  red: isTTY ? "\x1b[31m" : "",
  green: isTTY ? "\x1b[32m" : "",
  yellow: isTTY ? "\x1b[33m" : "",
  cyan: isTTY ? "\x1b[36m" : "",
  boldRed: isTTY ? "\x1b[1;31m" : "",
  boldGreen: isTTY ? "\x1b[1;32m" : "",
};

function usage() {
  console.log(`Usage: scripts/test-language.ts [command] [options] [test-file-or-directory ...]

Commands:
  run               Run tests and output table of passed/failed with names (default).
  diff, compare     Run tests and compare results against previous run, highlighting differences.
  detailed          Run tests with full failure details (expected/actual/raw output).

Options:
  --mode MODE       Zig optimization mode: Debug (default), ReleaseFast, ReleaseSafe,
                    or ReleaseSmall.
  --release-fast    Shorthand for --mode ReleaseFast.
  --time            Include elapsed time for every test in the table.
  --no-build        Reuse zig-out/bin/zlx instead of building first.
  -d, --detailed    Include full failure details in output (default in 'detailed' command).
  --diff            Compare results against previous run (same as 'diff' command).
  --no-save         Do not save run results to .test-results/.
  --no-run, --cached
                    In 'diff' command, compare existing last-run and prev-run without running tests.
  -h, --help        Show this help.

With no paths, every .lx file below tests/ is run. Paths may be absolute or
relative to the repository root. A non-zero exit status means at least one
test failed.`);
}

function die(msg: string): never {
  console.error(`error: ${msg}`);
  process.exit(2);
}

function parseExpectations(content: string): TestExpectations {
  const expectedOutput: string[] = [];
  const runtimeErrors: string[] = [];
  const compileErrors: string[] = [];
  const failureErrors: string[] = [];
  let hasFailure = false;
  let timeoutSeconds: number | null = null;

  const lines = content.split("\n");
  for (let i = 0; i < lines.length; i++) {
    const lineNum = i + 1;
    const line = lines[i];

    // // expect: ... or // @success: ...
    const expMatch = line.match(/\/\/\s*(?:expect|@success):\s?(.*)$/);
    if (expMatch) {
      expectedOutput.push(expMatch[1]);
    }

    // // expect runtime error: ...
    const rtMatch = line.match(/\/\/\s*expect runtime error:\s?(.*)$/);
    if (rtMatch) {
      runtimeErrors.push(rtMatch[1]);
    }

    // // [line N] Error... or // Error...
    const compLineMatch = line.match(/\/\/\s*(\[line\s+\d+\]\s+Error.*)/);
    if (compLineMatch) {
      compileErrors.push(compLineMatch[1]);
    } else {
      const compErrMatch = line.match(/\/\/\s*(Error.*)/);
      if (compErrMatch) {
        compileErrors.push(`[line ${lineNum}] ${compErrMatch[1]}`);
      }
    }

    // // @failure[: expected message]
    if (/\/\/\s*@failure/.test(line)) {
      hasFailure = true;
      const failMatch = line.match(/\/\/\s*@failure:?\s*(.*)$/);
      if (failMatch && failMatch[1].trim()) {
        failureErrors.push(failMatch[1].trim());
      }
    }

    // // @timeout: N
    const timeoutMatch = line.match(/^\s*\/\/\s*@timeout:\s*(\d+)\s*$/);
    if (timeoutMatch && timeoutSeconds === null) {
      timeoutSeconds = parseInt(timeoutMatch[1], 10);
    }
  }

  return {
    expectedOutput,
    runtimeErrors,
    compileErrors,
    hasFailure,
    failureErrors,
    timeoutSeconds,
  };
}

function normalizeDebugOutput(raw: string): string {
  // Debug builds dump bytecode and VM state through stderr.
  // Remove trace records; regular language output remains intact.
  return raw
    .replace(/\r/g, "")
    .split("\n")
    .filter((line) => {
      if (/^== .* ==$/.test(line)) return false;
      if (/^\s*[0-9]{4}\s/.test(line)) return false;
      if (/^ {8}\[/.test(line)) return false;
      if (/^error: /.test(line)) return false;
      if (/^\/.* in .* \(zlx\)$/.test(line)) return false;
      if (/^\s*\^$/.test(line)) return false;
      if (/^\s*$/.test(line)) return false;
      return true;
    })
    .join("\n");
}

function findLxFiles(dir: string): string[] {
  const results: string[] = [];
  const entries = fs.readdirSync(dir, { withFileTypes: true });
  for (const entry of entries) {
    const full = path.join(dir, entry.name);
    if (entry.isDirectory()) {
      results.push(...findLxFiles(full));
    } else if (entry.isFile() && entry.name.endsWith(".lx")) {
      results.push(full);
    }
  }
  return results.sort();
}

function formatResult(res: "PASS" | "FAIL"): string {
  if (res === "PASS") {
    return `${colors.green}PASS    ${colors.reset}`;
  }
  return `${colors.red}FAIL    ${colors.reset}`;
}

function formatDiff(label: string): string {
  switch (label) {
    case "REGRESSION":
      return `${colors.boldRed}REGRESSION  ${colors.reset}`;
    case "FIXED":
      return `${colors.boldGreen}FIXED       ${colors.reset}`;
    case "NEW":
      return `${colors.cyan}NEW         ${colors.reset}`;
    case "CHANGED":
      return `${colors.bold}CHANGED     ${colors.reset}`;
    default:
      return `${colors.dim}UNCHANGED   ${colors.reset}`;
  }
}

function showCachedDiff() {
  if (!fs.existsSync(lastRunFile)) {
    console.error("error: no previous run found in .test-results/last-run.json");
    process.exit(1);
  }
  if (!fs.existsSync(prevRunFile)) {
    console.error("error: no second previous run found in .test-results/prev-run.json to compare against");
    process.exit(1);
  }

  const prevData = JSON.parse(fs.readFileSync(prevRunFile, "utf8"));
  const lastData = JSON.parse(fs.readFileSync(lastRunFile, "utf8"));
  const prevTests = prevData.tests || {};
  const lastTests = lastData.tests || {};

  const regressions: Array<{ path: string; reason: string }> = [];
  const fixes: string[] = [];
  const changed: Array<{ path: string; oldReason: string; newReason: string }> = [];
  const newTests: Array<{ path: string; result: string }> = [];
  const removedTests: Array<{ path: string; result: string }> = [];

  for (const [p, curr] of Object.entries(lastTests) as [string, any][]) {
    if (p in prevTests) {
      const prev = prevTests[p];
      if (prev.result === "PASS" && curr.result === "FAIL") {
        regressions.push({ path: p, reason: curr.reason });
      } else if (prev.result === "FAIL" && curr.result === "PASS") {
        fixes.push(p);
      } else if (prev.result === "FAIL" && curr.result === "FAIL") {
        if (prev.reason && curr.reason !== prev.reason) {
          changed.push({ path: p, oldReason: prev.reason, newReason: curr.reason });
        }
      }
    } else {
      newTests.push({ path: p, result: curr.result });
    }
  }

  for (const [p, prev] of Object.entries(prevTests) as [string, any][]) {
    if (!(p in lastTests)) {
      removedTests.push({ path: p, result: prev.result });
    }
  }

  const totalDiffs =
    regressions.length +
    fixes.length +
    changed.length +
    newTests.length +
    removedTests.length;

  console.log("Differences between prev-run.json and last-run.json:");
  console.log("----------------------------------------------------------------------");
  if (totalDiffs === 0) {
    console.log(`  No differences found (all ${Object.keys(lastTests).length} test results match).`);
  } else {
    for (const r of regressions) {
      const reasonStr = r.reason ? ` (${r.reason})` : "";
      console.log(`  ${colors.boldRed}[REGRESSION]${colors.reset} ${r.path}: PASS -> FAIL${reasonStr}`);
    }
    for (const f of fixes) {
      console.log(`  ${colors.boldGreen}[FIXED]${colors.reset}      ${f}: FAIL -> PASS`);
    }
    for (const ch of changed) {
      console.log(`  ${colors.bold}[CHANGED]${colors.reset}    ${ch.path}: FAIL -> FAIL (reason changed: ${ch.newReason})`);
    }
    for (const n of newTests) {
      console.log(`  ${colors.cyan}[NEW]${colors.reset}        ${n.path}: ${n.result}`);
    }
    for (const rm of removedTests) {
      console.log(`  ${colors.yellow}[REMOVED]${colors.reset}    ${rm.path} (was ${rm.result})`);
    }

    const diffParts: string[] = [];
    if (regressions.length) diffParts.push(`${regressions.length} regression${regressions.length > 1 ? "s" : ""}`);
    if (fixes.length) diffParts.push(`${fixes.length} fix${fixes.length > 1 ? "es" : ""}`);
    if (changed.length) diffParts.push(`${changed.length} changed`);
    if (newTests.length) diffParts.push(`${newTests.length} new`);
    if (removedTests.length) diffParts.push(`${removedTests.length} removed`);

    console.log(`\nTotal differences: ${totalDiffs} (${diffParts.join(", ")}).`);
  }
}

async function main() {
  const rawArgs = process.argv.slice(2);
  let command = "";
  let mode = "Debug";
  let showTime = false;
  let build = true;
  let detailedExplicit: boolean | null = null;
  let diffExplicit = false;
  let noSave = false;
  let noRun = false;
  const testPathArgs: string[] = [];

  let i = 0;
  while (i < rawArgs.length) {
    const arg = rawArgs[i];
    switch (arg) {
      case "run":
      case "table":
      case "summary":
        command = "run";
        i++;
        break;
      case "diff":
      case "compare":
        command = "diff";
        i++;
        break;
      case "detailed":
      case "detail":
      case "verbose":
        command = "detailed";
        i++;
        break;
      case "--mode":
        if (i + 1 >= rawArgs.length) die("--mode requires a value");
        mode = rawArgs[i + 1];
        i += 2;
        break;
      case "--release-fast":
        mode = "ReleaseFast";
        i++;
        break;
      case "--time":
        showTime = true;
        i++;
        break;
      case "--no-build":
        build = false;
        i++;
        break;
      case "-d":
      case "--detailed":
        detailedExplicit = true;
        i++;
        break;
      case "--no-detailed":
      case "--table-only":
        detailedExplicit = false;
        i++;
        break;
      case "--diff":
        diffExplicit = true;
        i++;
        break;
      case "--no-save":
        noSave = true;
        i++;
        break;
      case "--no-run":
      case "--cached":
        noRun = true;
        i++;
        break;
      case "-h":
      case "--help":
        usage();
        process.exit(0);
      case "--":
        i++;
        while (i < rawArgs.length) {
          testPathArgs.push(rawArgs[i]);
          i++;
        }
        break;
      default:
        if (arg.startsWith("--")) {
          die(`unknown option: ${arg}`);
        }
        testPathArgs.push(arg);
        i++;
        break;
    }
  }

  if (diffExplicit) {
    command = "diff";
  }

  if (!command) {
    command = detailedExplicit ? "detailed" : "run";
  }

  const isDetailed = command === "detailed" || detailedExplicit === true;

  if (command === "diff" && noRun) {
    showCachedDiff();
    process.exit(0);
  }

  if (!["Debug", "ReleaseFast", "ReleaseSafe", "ReleaseSmall"].includes(mode)) {
    die(`unsupported mode '${mode}'`);
  }

  if (build) {
    console.log(`Building zlx (${mode})...`);
    const buildProc = Bun.spawn(["zig", "build", `-Doptimize=${mode}`], {
      cwd: rootDir,
      stdout: "inherit",
      stderr: "inherit",
    });
    const exitCode = await buildProc.exited;
    if (exitCode !== 0) {
      process.exit(exitCode);
    }
  }

  const binary = path.join(rootDir, "zig-out", "bin", "zlx");
  if (!fs.existsSync(binary)) {
    die(`executable not found: ${binary} (omit --no-build or build it first)`);
  }

  // Load baseline test results
  let baselineTests: Record<string, any> = {};
  let hadBaseline = false;
  if (fs.existsSync(lastRunFile)) {
    try {
      const data = JSON.parse(fs.readFileSync(lastRunFile, "utf8"));
      baselineTests = data.tests || {};
      hadBaseline = true;
    } catch {}
  }

  // Resolve tests to run
  let testFiles: string[] = [];
  let isSubset = false;

  if (testPathArgs.length === 0) {
    isSubset = false;
    testFiles = findLxFiles(testDir);
  } else {
    isSubset = true;
    for (const p of testPathArgs) {
      const absPath = path.isAbsolute(p) ? p : path.join(rootDir, p);
      if (!fs.existsSync(absPath)) {
        die(`test path not found: ${absPath}`);
      }
      const stat = fs.statSync(absPath);
      if (stat.isDirectory()) {
        testFiles.push(...findLxFiles(absPath));
      } else if (stat.isFile()) {
        testFiles.push(absPath);
      }
    }
  }

  if (testFiles.length === 0) {
    die("no .lx tests found");
  }

  // Print table header
  let header = `\n${"No.".padEnd(5)} ${"Result".padEnd(8)}`;
  let separator = `${"----".padEnd(5)} ${"--------".padEnd(8)}`;
  if (command === "diff") {
    header += ` ${"Diff".padEnd(12)}`;
    separator += ` ${"------------".padEnd(12)}`;
  }
  header += ` ${"Test".padEnd(54)}`;
  separator += ` ${"------------------------------------------------------".padEnd(54)}`;
  if (showTime) {
    header += ` ${"Time".padStart(10)}`;
    separator += ` ${"----------".padStart(10)}`;
  }

  console.log(header);
  console.log(separator);

  let passed = 0;
  let failed = 0;
  let testNumber = 0;
  const currentTests: Record<string, TestRunResult> = {};
  const failureDetails: TestRunResult[] = [];

  for (const testFile of testFiles) {
    testNumber++;
    const displayPath = path.relative(rootDir, testFile);
    const content = fs.readFileSync(testFile, "utf8");
    const expectations = parseExpectations(content);

    const startTime = performance.now();
    let timedOut = false;
    let timeoutTimer: ReturnType<typeof setTimeout> | undefined;

    const proc = Bun.spawn([binary, testFile], {
      stdout: "pipe",
      stderr: "pipe",
    });

    if (expectations.timeoutSeconds !== null && expectations.timeoutSeconds > 0) {
      timeoutTimer = setTimeout(() => {
        timedOut = true;
        proc.kill();
      }, expectations.timeoutSeconds * 1000);
    }

    const [stdout, stderr] = await Promise.all([
      new Response(proc.stdout).text(),
      new Response(proc.stderr).text(),
    ]);

    await proc.exited;
    if (timeoutTimer) clearTimeout(timeoutTimer);

    const duration = (performance.now() - startTime) / 1000;
    const exitCode = timedOut ? 124 : proc.exitCode ?? 1;

    // Combine stdout and stderr; normalize trace and debug info
    const rawClean = (stdout + stderr).replace(/\r/g, "");
    const actual = normalizeDebugOutput(rawClean);
    const expected = expectations.expectedOutput.join("\n");

    let reason = "";

    if (timedOut) {
      reason = `timed out after ${expectations.timeoutSeconds} seconds`;
    } else if (expectations.hasFailure) {
      if (exitCode === 0) {
        reason = "expected execution to fail (exit non-zero), but it succeeded";
      } else {
        for (const exp of expectations.failureErrors) {
          if (!rawClean.includes(exp)) {
            reason = `missing expected error message: ${exp}`;
            break;
          }
        }
      }
    } else if (expectations.compileErrors.length > 0) {
      if (exitCode === 0) {
        reason = "expected a compile error, but execution succeeded";
      } else {
        const rawLines = rawClean.split("\n");
        for (const exp of expectations.compileErrors) {
          if (!rawLines.includes(exp)) {
            reason = `missing compiler error: ${exp}`;
            break;
          }
        }
      }
    } else if (expectations.runtimeErrors.length > 0) {
      if (exitCode === 0) {
        reason = "expected a runtime error, but execution succeeded";
      } else {
        for (const exp of expectations.runtimeErrors) {
          if (!rawClean.includes(exp)) {
            reason = `missing runtime error: ${exp}`;
            break;
          }
        }
      }
      const firstRuntimeError = expectations.runtimeErrors[0];
      const actualBeforeError = actual.split(firstRuntimeError)[0];
      if (!reason && actualBeforeError !== expected) {
        reason = "output before the runtime error differs";
      }
    } else {
      if (exitCode !== 0) {
        reason = `unexpected exit status ${exitCode}`;
      } else if (actual !== expected) {
        reason = "output differs from // expect: comments";
      }
    }

    const result: "PASS" | "FAIL" = reason ? "FAIL" : "PASS";
    if (result === "PASS") {
      passed++;
    } else {
      failed++;
    }

    // Determine diff status compared to baseline
    let diffLabel = "UNCHANGED";
    if (displayPath in baselineTests) {
      const prev = baselineTests[displayPath];
      const prevRes = prev.result;
      const prevReason = prev.reason || "";
      if (prevRes === "PASS" && result === "FAIL") {
        diffLabel = "REGRESSION";
      } else if (prevRes === "FAIL" && result === "PASS") {
        diffLabel = "FIXED";
      } else if (prevRes === "FAIL" && result === "FAIL") {
        if (prevReason && reason !== prevReason) {
          diffLabel = "CHANGED";
        } else {
          diffLabel = "UNCHANGED";
        }
      } else {
        diffLabel = "UNCHANGED";
      }
    } else {
      diffLabel = "NEW";
    }

    // Print test line
    let lineStr = `${testNumber.toString().padEnd(5)} ${formatResult(result)}`;
    if (command === "diff") {
      lineStr += ` ${formatDiff(diffLabel)}`;
    }
    lineStr += ` ${displayPath.padEnd(54)}`;
    if (showTime) {
      lineStr += ` ${duration.toFixed(3).padStart(8)} s`;
    }
    console.log(lineStr);

    const runResult: TestRunResult = {
      displayPath,
      result,
      duration,
      exitCode,
      reason,
      expected,
      actual,
      rawOutput: rawClean.split("\n").slice(0, 160).join("\n"),
    };

    currentTests[displayPath] = runResult;
    if (result === "FAIL") {
      failureDetails.push(runResult);
    }
  }

  console.log(`\nSummary: ${passed} passed, ${failed} failed, ${testNumber} total (${mode}).`);

  // Differences section for diff command
  if (command === "diff") {
    const regressions: Array<{ path: string; reason: string }> = [];
    const fixes: string[] = [];
    const changed: Array<{ path: string; oldReason: string; newReason: string }> = [];
    const newTests: Array<{ path: string; result: string }> = [];
    const removedTests: Array<{ path: string; result: string }> = [];

    if (!hadBaseline) {
      console.log("\nDifferences compared to previous run:");
      console.log("----------------------------------------------------------------------");
      console.log("  No previous run recorded in .test-results/. Baseline established.");
    } else {
      for (const [p, curr] of Object.entries(currentTests)) {
        if (p in baselineTests) {
          const prev = baselineTests[p];
          if (prev.result === "PASS" && curr.result === "FAIL") {
            regressions.push({ path: p, reason: curr.reason });
          } else if (prev.result === "FAIL" && curr.result === "PASS") {
            fixes.push(p);
          } else if (prev.result === "FAIL" && curr.result === "FAIL") {
            if (prev.reason && curr.reason !== prev.reason) {
              changed.push({ path: p, oldReason: prev.reason, newReason: curr.reason });
            }
          }
        } else {
          newTests.push({ path: p, result: curr.result });
        }
      }

      if (!isSubset) {
        for (const [p, prev] of Object.entries(baselineTests)) {
          if (!(p in currentTests)) {
            removedTests.push({ path: p, result: prev.result });
          }
        }
      }

      const totalDiffs =
        regressions.length +
        fixes.length +
        changed.length +
        newTests.length +
        removedTests.length;

      console.log("\nDifferences compared to previous run:");
      console.log("----------------------------------------------------------------------");
      if (totalDiffs === 0) {
        console.log(`  No differences found (all ${Object.keys(currentTests).length} test results match previous run).`);
      } else {
        for (const r of regressions) {
          const reasonStr = r.reason ? ` (${r.reason})` : "";
          console.log(`  ${colors.boldRed}[REGRESSION]${colors.reset} ${r.path}: PASS -> FAIL${reasonStr}`);
        }
        for (const f of fixes) {
          console.log(`  ${colors.boldGreen}[FIXED]${colors.reset}      ${f}: FAIL -> PASS`);
        }
        for (const ch of changed) {
          console.log(`  ${colors.bold}[CHANGED]${colors.reset}    ${ch.path}: FAIL -> FAIL (reason changed: ${ch.newReason})`);
        }
        for (const n of newTests) {
          console.log(`  ${colors.cyan}[NEW]${colors.reset}        ${n.path}: ${n.result}`);
        }
        for (const rm of removedTests) {
          console.log(`  ${colors.yellow}[REMOVED]${colors.reset}    ${rm.path} (was ${rm.result})`);
        }

        const diffParts: string[] = [];
        if (regressions.length) diffParts.push(`${regressions.length} regression${regressions.length > 1 ? "s" : ""}`);
        if (fixes.length) diffParts.push(`${fixes.length} fix${fixes.length > 1 ? "es" : ""}`);
        if (changed.length) diffParts.push(`${changed.length} changed`);
        if (newTests.length) diffParts.push(`${newTests.length} new`);
        if (removedTests.length) diffParts.push(`${removedTests.length} removed`);

        console.log(`\nTotal differences: ${totalDiffs} (${diffParts.join(", ")}).`);
      }
    }
  }

  // Save results to .test-results/last-run.json
  if (!noSave && Object.keys(currentTests).length > 0) {
    fs.mkdirSync(resultsDir, { recursive: true });

    const allTests = isSubset && hadBaseline ? { ...baselineTests, ...currentTests } : currentTests;
    const passedCnt = Object.values(allTests).filter((t: any) => t.result === "PASS").length;
    const failedCnt = Object.values(allTests).filter((t: any) => t.result === "FAIL").length;

    const newRunData = {
      timestamp: new Date().toISOString(),
      mode,
      total: Object.keys(allTests).length,
      passed: passedCnt,
      failed: failedCnt,
      tests: allTests,
    };

    if (fs.existsSync(lastRunFile)) {
      try {
        fs.copyFileSync(lastRunFile, prevRunFile);
      } catch {}
    }

    const tmpSave = `${lastRunFile}.tmp`;
    fs.writeFileSync(tmpSave, JSON.stringify(newRunData, null, 2), "utf8");
    fs.renameSync(tmpSave, lastRunFile);
  }

  // Detailed failure logs
  if (failed > 0) {
    if (isDetailed) {
      console.log("\nFailure details:\n");
      for (const detail of failureDetails) {
        console.log("----------------------------------------------------------------------");
        console.log(`${detail.displayPath}: ${detail.reason}`);
        console.log("Expected output:");
        console.log(detail.expected || "<empty>");
        console.log("Actual output:");
        console.log(detail.actual || "<empty>");
        console.log("Raw interpreter output:");
        console.log(detail.rawOutput);
      }
    } else {
      console.log("\nTip: Run with 'detailed' (or -d) to view failure details, or 'diff' to compare with previous run.");
    }
    process.exit(1);
  }

  process.exit(0);
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
