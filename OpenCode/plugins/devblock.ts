import { type Plugin, tool } from "@opencode-ai/plugin"
import { readFileSync, writeFileSync, existsSync, mkdirSync, unlinkSync, rmSync, appendFileSync, renameSync } from "fs"
import { join, dirname, basename, isAbsolute, normalize, relative } from "path"

// ─── Types ──────────────────────────────────────────────────────────────────

interface ScopeFeature {
  name: string
  phase: "red" | "green"
  files: string[]
  tests: string[]
  started_at?: string
}

interface QueuedFeature {
  name: string
  files: string[]
  tests: string[]
}

interface CompletedFeature extends ScopeFeature {
  completed_at: string
}

interface ScopeJSON {
  session?: string
  current: ScopeFeature | null
  test_command: string
  queue: QueuedFeature[]
  completed: CompletedFeature[]
}

// ─── Helpers ────────────────────────────────────────────────────────────────

function scopePath(dir: string) {
  return join(dir, ".scope.json")
}

function devblockDir(dir: string) {
  return join(dir, ".devblock")
}

function normalizeScopeFilePath(filePath: string): string {
  return filePath.replace(/\\/g, "/").replace(/^\.\//, "")
}

function normalizeScope(scope: ScopeJSON): ScopeJSON {
  const normalizeFeature = <T extends ScopeFeature | QueuedFeature | CompletedFeature>(feature: T): T => ({
    ...feature,
    files: feature.files.map(normalizeScopeFilePath),
    tests: feature.tests.map(normalizeScopeFilePath),
  })

  return {
    ...scope,
    current: scope.current ? normalizeFeature(scope.current) : null,
    queue: scope.queue.map(normalizeFeature),
    completed: scope.completed.map(normalizeFeature),
  }
}

function isScopeMetadataPath(filePath: string): boolean {
  const normalized = normalizeScopeFilePath(filePath)
  return normalized === ".scope.json" || normalized.endsWith("/.scope.json")
}

function readScope(dir: string): ScopeJSON | null {
  const p = scopePath(dir)
  if (!existsSync(p)) return null
  try {
    return normalizeScope(JSON.parse(readFileSync(p, "utf-8")))
  } catch {
    return null
  }
}

function writeScope(dir: string, data: ScopeJSON) {
  const tmp = scopePath(dir) + ".tmp"
  writeFileSync(tmp, JSON.stringify(normalizeScope(data), null, 2) + "\n")
  renameSync(tmp, scopePath(dir))
}

function ensureDevblockDir(dir: string) {
  const d = devblockDir(dir)
  if (!existsSync(d)) mkdirSync(d, { recursive: true })

  const gitignore = join(dir, ".gitignore")
  if (existsSync(gitignore)) {
    const content = readFileSync(gitignore, "utf-8")
    let append = ""
    if (!content.includes(".scope.json")) append += ".scope.json\n"
    if (!content.includes(".devblock")) append += ".devblock/\n"
    if (append) appendFileSync(gitignore, append)
  } else {
    writeFileSync(gitignore, ".scope.json\n.devblock/\n")
  }
}

function resolveRelPath(filePath: string, dir: string): string {
  if (!filePath) return ""

  let rel = filePath
  if (isAbsolute(filePath)) {
    const absolutePath = normalize(filePath)
    const root = normalize(dir)
    const absolutePathCmp = normalizeScopeFilePath(absolutePath)
    const rootCmp = normalizeScopeFilePath(root)

    if (absolutePathCmp === rootCmp || absolutePathCmp.startsWith(rootCmp + "/")) {
      rel = relative(dir, absolutePath)
    } else {
      rel = absolutePath
    }
  }

  rel = normalizeScopeFilePath(rel)
  if (rel.startsWith("./")) rel = rel.slice(2)
  return rel
}

function isTestFile(filePath: string): boolean {
  const normalized = normalizeScopeFilePath(filePath)
  const lower = normalized.toLowerCase()
  if (/\.(test|spec)\.\w+$/.test(lower)) return true
  if (/\/(tests?|__tests__|spec)\//.test(lower)) return true
  if (/^test_/.test(basename(lower))) return true
  if (/_test\.\w+$/.test(lower)) return true
  return false
}

function nestedProjectExample(dirName: string) {
  return {
    bash: `cd ${dirName} && <test command>`,
    powershell: `Set-Location ${dirName}; <test command>`,
  }
}

function testCommandRunsFromNestedDir(testCmd: string): boolean {
  return /(?:^|[;&|])\s*(?:cd\s+[^;&|]+|set-location\s+[^;&|]+)/i.test(testCmd)
}

async function detectTestFramework(dir: string): Promise<{ command: string; framework: string } | null> {
  const pkg = join(dir, "package.json")
  if (existsSync(pkg)) {
    try {
      const p = JSON.parse(readFileSync(pkg, "utf-8"))
      const deps = { ...p.devDependencies, ...p.dependencies }
      if (deps?.vitest) return { command: "npx vitest run", framework: "vitest" }
      if (deps?.jest) return { command: "npx jest", framework: "jest" }
      if (deps?.mocha) return { command: "npx mocha", framework: "mocha" }
      if (p.scripts?.test && p.scripts.test !== 'echo "Error: no test specified" && exit 1') {
        return { command: "npm test", framework: "npm scripts" }
      }
    } catch { /* ignore */ }
  }

  const pyproject = join(dir, "pyproject.toml")
  if (existsSync(pyproject)) {
    const content = readFileSync(pyproject, "utf-8")
    if (content.includes("[tool.pytest") || content.includes("pytest")) {
      return { command: "pytest", framework: "pytest" }
    }
    return { command: "python -m pytest", framework: "pytest (default)" }
  }

  const cargo = join(dir, "Cargo.toml")
  if (existsSync(cargo)) return { command: "cargo test", framework: "cargo" }

  const makefile = join(dir, "Makefile")
  if (existsSync(makefile)) {
    const content = readFileSync(makefile, "utf-8")
    if (content.includes("test:")) return { command: "make test", framework: "make" }
  }

  const gomod = join(dir, "go.mod")
  if (existsSync(gomod)) return { command: "go test ./...", framework: "go test" }

  return null
}

function validateFiles(dir: string, files: string[]): string[] {
  const warnings: string[] = []
  for (const f of files) {
    const full = join(dir, f)
    if (!existsSync(full) && !existsSync(dirname(full))) {
      warnings.push(`'${f}' — file and parent directory do not exist`)
    }
  }
  return warnings
}

function validateTestCommand(dir: string, testCmd: string): string[] {
  const warnings: string[] = []
  const nestedExamples = nestedProjectExample("app")

  warnings.push(
    `test command runs from session root: '${dir}'. For nested projects, start DevBlock there or change directories explicitly (bash: '${nestedExamples.bash}', PowerShell: '${nestedExamples.powershell}')`
  )

  if (/\bflutter\s+test\b/i.test(testCmd) && !existsSync(join(dir, "pubspec.yaml")) && !testCommandRunsFromNestedDir(testCmd)) {
    warnings.push(
      "flutter test detected but no pubspec.yaml found in the session root; this will fail unless the command changes into the Flutter app directory"
    )
  }

  return warnings
}

function now() {
  return new Date().toISOString().replace(/\.\d{3}Z$/, "Z")
}

// ─── Plugin ─────────────────────────────────────────────────────────────────

export const DevBlockPlugin: Plugin = async ({ project, client, $, directory, worktree }) => {
  const dir = worktree || directory
  const isWindows = process.platform === "win32"

  async function toast(
    message: string,
    variant: "info" | "success" | "warning" | "error" = "info",
    title = "DevBlock",
    duration?: number,
  ) {
    try {
      await client.tui.showToast({
        body: { title, message, variant, ...(duration ? { duration } : {}) },
      })
    } catch {
      /* TUI may not be connected (headless/API mode) — ignore */
    }
  }

  async function runTests(d: string, testCmd: string): Promise<{ passed: boolean; output: string }> {
    try {
      const result = isWindows
        ? await $`powershell -NoProfile -Command ${testCmd}`.cwd(d).quiet()
        : await $`bash -lc ${testCmd}`.cwd(d).quiet()
      return { passed: true, output: result.stdout.toString() + result.stderr.toString() }
    } catch (e: any) {
      return { passed: false, output: (e.stdout?.toString() || "") + (e.stderr?.toString() || "") }
    }
  }

  async function autoCommit(d: string, scope: ScopeJSON): Promise<string> {
    if (!scope.current) return "No files to commit."

    const allFiles = [...scope.current.files, ...scope.current.tests]
    if (allFiles.length === 0) return "No files to commit."

    let staged = 0
    for (const f of allFiles) {
      const full = join(d, f)
      if (!existsSync(full)) continue
      try {
        const diff = await $`git diff --name-only -- ${f}`.cwd(d).quiet()
        const untracked = await $`git ls-files --others --exclude-standard -- ${f}`.cwd(d).quiet()
        if (diff.stdout.toString().trim() || untracked.stdout.toString().trim()) {
          await $`git add ${f}`.cwd(d).quiet()
          staged++
        }
      } catch { /* skip */ }
    }

    if (staged === 0) return "No changes to commit."

    const commitMsg = "feat: " + scope.current.name
    try {
      await $`git commit -m ${commitMsg}`.cwd(d).quiet()
      return `Auto-committed: ${commitMsg}`
    } catch {
      return "Nothing to commit (already clean)."
    }
  }

  function completeFeature(d: string, scope: ScopeJSON) {
    if (!scope.current) return

    const ts = now()
    scope.completed.push({
      ...scope.current,
      phase: "green",
      completed_at: ts,
    } as CompletedFeature)

    if (scope.queue.length > 0) {
      const next = scope.queue.shift()!
      scope.current = {
        name: next.name,
        phase: "red",
        files: next.files,
        tests: next.tests,
        started_at: ts,
      }
    } else {
      scope.current = null
    }

    writeScope(d, scope)
  }

  return {
    // ── Scope Guard ───────────────────────────────────────────────────────

    "tool.execute.before": async (input, output) => {
      const scope = readScope(dir)
      if (!scope) return

      const toolName = input.tool

      // --- Edit / Write ---
      if (toolName === "edit" || toolName === "write" || toolName === "patch" || toolName === "multiedit") {
        const filePath = resolveRelPath(
          output.args.filePath || output.args.file_path || output.args.path || "",
          dir
        )
        if (!filePath) return

        if (isScopeMetadataPath(filePath)) {
          throw new Error(
            "DEVBLOCK DENIED: Do not edit .scope.json directly.\n" +
            "Use devblock_next to advance phase, devblock_add to add files."
          )
        }

        if (isAbsolute(filePath)) return

        if (!scope.current) {
          throw new Error(
            "DEVBLOCK DENIED: No active feature.\n" +
            "Start a TDD session first with devblock_init."
          )
        }

        const { files, tests, phase, name } = scope.current
        const inFiles = files.includes(normalizeScopeFilePath(filePath))
        const inTests = tests.includes(normalizeScopeFilePath(filePath))

        if (!inFiles && !inTests) {
          const allScoped = [...files, ...tests].join(", ")
          throw new Error(
            `DEVBLOCK DENIED: '${filePath}' is not in scope.\n` +
            `Scoped files: ${allScoped}\n` +
            `Add it with devblock_add.`
          )
        }

        // Skip token — single-use bypass
        const skipTokenPath = join(devblockDir(dir), ".skip-token")
        if (existsSync(skipTokenPath)) {
          try { unlinkSync(skipTokenPath) } catch { /* ok */ }
          return
        }

        if (phase === "red" && inFiles && !inTests) {
          toast(`DENIED: RED phase — '${basename(filePath)}' is impl`, "error").catch(() => {})
          throw new Error(
            `DEVBLOCK DENIED: RED phase — cannot edit '${filePath}' (implementation file).\n\n` +
            `Feature: "${name}" | Phase: RED\n` +
            `Editable now: ${tests.join(", ")}\n\n` +
            `Options:\n` +
            `1. Edit a test file instead\n` +
            `2. Call devblock_next to advance to GREEN (tests must fail first)\n` +
            `3. Call devblock_skip with a reason to bypass once`
          )
        }

        if (phase === "green" && inTests && !inFiles) {
          toast(`DENIED: GREEN phase — '${basename(filePath)}' is test`, "error").catch(() => {})
          throw new Error(
            `DEVBLOCK DENIED: GREEN phase — cannot edit '${filePath}' (test file).\n\n` +
            `Feature: "${name}" | Phase: GREEN\n` +
            `Editable now: ${files.join(", ")}\n\n` +
            `Options:\n` +
            `1. Edit an implementation file instead\n` +
            `2. Call devblock_next to complete (tests must pass first)\n` +
            `3. Call devblock_back to return to RED phase\n` +
            `4. Call devblock_skip with a reason to bypass once`
          )
        }

        return
      }

      // --- Bash ---
      if (toolName === "bash") {
        if (!scope.current) return

        const command = output.args.command || ""

        if (/devblock_/.test(command)) return

        const readonlyPattern = /^\s*(ls|cat|echo|find|which|file|stat|du|df|wc|head|tail|pwd|date|env|tree|rg|grep)\s/
        if (readonlyPattern.test(command)) return

        const testRunnerPattern = /^\s*(git\s+|npm\s+test|npx\s+|yarn\s+test|pnpm\s+test|pytest|python\s+-m\s+pytest|cargo\s+test|go\s+test|make\s+test|bundle\s+exec\s+rspec|jest|vitest|mocha|bun\s+test)/
        if (testRunnerPattern.test(command)) return

        const modifyingPattern = /([^2]>\s*[^&/]|[^0-9]>>\s*[^/]|sed\s+-i|tee\s+|rm\s+|mv\s+|cp\s+)/
        if (modifyingPattern.test(command)) {
          if (testRunnerPattern.test(command)) return
          const pipeToReadonly = /\|\s*(grep|head|tail|less|wc|sort|cat|jq|awk|sed\s+[^-])/
          const redirectPattern = /([^2]>\s*[^&/]|[^0-9]>>\s*[^/])/
          if (pipeToReadonly.test(command) && !redirectPattern.test(command)) return

          throw new Error(
            "DEVBLOCK DENIED: Do not modify files via shell.\n" +
            "Use the edit/write tool instead — it is scope-checked by DevBlock."
          )
        }

        return
      }
    },

    // ── Compaction Hook ───────────────────────────────────────────────────

    "experimental.session.compacting": async (input, output) => {
      const scope = readScope(dir)
      if (!scope?.current) return

      const { name, phase, files, tests } = scope.current
      output.context.push(
        `DEVBLOCK TDD STATE (preserve this):\n` +
        `Feature: "${name}" | Phase: ${phase.toUpperCase()}\n` +
        `Impl files: [${files.join(", ")}]\n` +
        `Test files: [${tests.join(", ")}]\n` +
        `Queue: ${scope.queue.length} remaining\n` +
        `Completed: ${scope.completed.length}\n` +
        `Test command: ${scope.test_command}\n\n` +
        `Tools: devblock_next (advance), devblock_back (GREEN→RED), ` +
        `devblock_add (add file), devblock_skip (bypass once), devblock_stop (end session).`
      )
    },

    // ── Custom Tools ──────────────────────────────────────────────────────

    tool: {
      devblock_init: tool({
        description:
          "Initialize a DevBlock TDD session. Creates .scope.json with the feature details " +
          "and enters RED phase. The agent should ask the user for feature name, implementation " +
          "files, test files, and test command before calling this tool.",
        args: {
          name: tool.schema.string().describe("Feature name (short description)"),
          files: tool.schema.array(tool.schema.string()).describe("Implementation file paths"),
          tests: tool.schema.array(tool.schema.string()).describe("Test file paths"),
          test_command: tool.schema.string().optional().describe(
            "Command to run tests. If omitted, auto-detected from project config."
          ),
        },
        async execute(args, context) {
          const d = context.worktree || context.directory
          const existing = readScope(d)
          if (existing?.current) {
            return `ERROR: A session is already active (feature: "${existing.current.name}", phase: ${existing.current.phase}). Call devblock_stop first.`
          }

          let testCmd = args.test_command
          let detectedFramework = ""
          if (!testCmd) {
            const detected = await detectTestFramework(d)
            if (detected) {
              testCmd = detected.command
              detectedFramework = detected.framework
            } else {
              return "ERROR: Could not auto-detect test framework. Provide test_command explicitly."
            }
          }

          const warnings = [
            ...validateFiles(d, [...args.files, ...args.tests]),
            ...validateTestCommand(d, testCmd),
          ]

          ensureDevblockDir(d)

          const ts = now()
          const data: ScopeJSON = {
            session: ts,
            current: {
              name: args.name,
              phase: "red",
              files: args.files,
              tests: args.tests,
              started_at: ts,
            },
            test_command: testCmd,
            queue: [],
            completed: [],
          }
          writeScope(d, data)

          let msg = `## TDD Session Started\n`
          msg += `**Feature:** ${args.name} | **Phase:** RED\n\n`
          msg += `| Type | File |\n|------|------|\n`
          for (const f of args.files) msg += `| impl | \`${f}\` |\n`
          for (const t of args.tests) msg += `| test | \`${t}\` |\n`
          msg += `\n**Test command:** \`${testCmd}\``
          if (detectedFramework) msg += ` (auto-detected: ${detectedFramework})`
          msg += `\n`

          if (warnings.length > 0) {
            msg += `\n**Warnings:**\n`
            for (const w of warnings) msg += `- ${w}\n`
          }

          msg += `\n### Next steps\n`
          msg += `1. Write failing tests in: ${args.tests.map(t => `\`${t}\``).join(", ")}\n`
          msg += `2. Call \`devblock_next\` when tests are ready (they must fail)\n`
          msg += `\n### Todo sync\n`
          msg += `Update your todos NOW with todowrite:\n`
          msg += `- { content: "Write failing tests for '${args.name}'", status: "in_progress", priority: "high" }\n`
          msg += `- { content: "Implement '${args.name}' — make tests pass", status: "pending", priority: "high" }\n`

          await toast(`RED — Write failing tests for "${args.name}"`, "info")

          return msg
        },
      }),

      devblock_status: tool({
        description: "Show the current DevBlock TDD session status.",
        args: {},
        async execute(_args, context) {
          const d = context.worktree || context.directory
          const scope = readScope(d)
          if (!scope) return "No active DevBlock session."

          if (!scope.current) {
            if (scope.completed.length > 0) {
              return `No active feature. ${scope.completed.length} feature(s) completed. Session idle.`
            }
            return "Session exists but no active feature."
          }

          const { name, phase, files, tests } = scope.current
          let msg = `## DevBlock Status\n`
          msg += `**Feature:** ${name} | **Phase:** ${phase.toUpperCase()}\n\n`
          msg += `| Type | File |\n|------|------|\n`
          for (const f of files) msg += `| impl | \`${f}\` |\n`
          for (const t of tests) msg += `| test | \`${t}\` |\n`
          msg += `\n**Test command:** \`${scope.test_command}\`\n`
          msg += `**Queue:** ${scope.queue.length} | **Completed:** ${scope.completed.length}\n`

          if (phase === "red") {
            msg += `\n*Write failing tests, then call \`devblock_next\`.*`
          } else {
            msg += `\n*Make tests pass, then call \`devblock_next\`.*`
          }

          return msg
        },
      }),

      devblock_stop: tool({
        description:
          "Close the DevBlock TDD session. Only call when the user explicitly requests it.",
        args: {
          full: tool.schema.boolean().optional().describe(
            "If true, also removes .devblock/ directory"
          ),
        },
        async execute(args, context) {
          const d = context.worktree || context.directory
          const scope = readScope(d)
          if (!scope) return "No active session to stop."

          const currentName = scope.current?.name || "none"
          const phase = scope.current?.phase || "none"
          const queueLen = scope.queue.length

          try { unlinkSync(scopePath(d)) } catch { /* ok */ }

          let msg = `Session closed. Feature: ${currentName} (phase: ${phase}), queue: ${queueLen} remaining.`

          if (args.full) {
            try { rmSync(devblockDir(d), { recursive: true, force: true }) } catch { /* ok */ }
            msg += " Cleaned up .devblock/ directory."
          }

          msg += `\n\n### Todo sync\n`
          msg += `Update your todos NOW with todowrite:\n`
          msg += `- { content: "TDD session for '${currentName}'", status: "cancelled", priority: "low" }\n`

          await toast("Session closed", "warning")

          return msg
        },
      }),

      devblock_next: tool({
        description:
          "Advance to the next TDD phase. RED: validates tests fail, moves to GREEN. " +
          "GREEN: validates tests pass, auto-commits, moves to next feature or completes.",
        args: {},
        async execute(_args, context) {
          const d = context.worktree || context.directory
          const scope = readScope(d)
          if (!scope?.current) return "ERROR: No active feature. Start a session first."

          const { phase, name } = scope.current
          const testCmd = scope.test_command
          if (!testCmd) return "ERROR: No test_command configured."

          const { passed: testPassed, output: testOutput } = await runTests(d, testCmd)

          try {
            const dbDir = devblockDir(d)
            if (!existsSync(dbDir)) mkdirSync(dbDir, { recursive: true })
            writeFileSync(join(dbDir, "last-test-output.txt"), testOutput)
          } catch { /* non-critical */ }

          if (phase === "red") {
            if (testPassed) {
              const commitResult = await autoCommit(d, scope)
              completeFeature(d, scope)
              const newScope = readScope(d)
              let msg = `Tests already passing — fast-forwarded through GREEN.\n`
              msg += commitResult + "\n"
              if (newScope?.current) {
                msg += `\n## Next feature: ${newScope.current.name} (RED)\n`
                msg += `Write failing tests, then call \`devblock_next\`.\n`
                msg += `\n### Todo sync\n`
                msg += `Update your todos NOW with todowrite:\n`
                msg += `- { content: "Implement '${name}' — make tests pass", status: "completed", priority: "high" }\n`
                msg += `- { content: "Write failing tests for '${newScope.current.name}'", status: "in_progress", priority: "high" }\n`
                await toast(`"${name}" complete (fast-forward) — next: "${newScope.current.name}" RED`, "success")
              } else {
                msg += `\nAll features completed!\n`
                msg += `\n### Todo sync\n`
                msg += `Update your todos NOW with todowrite:\n`
                msg += `- { content: "Implement '${name}' — make tests pass", status: "completed", priority: "high" }\n`
                await toast(`All features completed!`, "success")
              }
              return msg
            }

            scope.current.phase = "green"
            writeScope(d, scope)

            let msg = `## RED → GREEN\n`
            msg += `Tests correctly failing. Moving to GREEN phase.\n\n`
            msg += `**Feature:** ${name}\n`
            msg += `**Editable now:** ${scope.current.files.map(f => `\`${f}\``).join(", ")}\n\n`
            msg += `Make tests pass, then call \`devblock_next\`.\n`
            msg += `\n### Todo sync\n`
            msg += `Update your todos NOW with todowrite:\n`
            msg += `- { content: "Write failing tests for '${name}'", status: "completed", priority: "high" }\n`
            msg += `- { content: "Implement '${name}' — make tests pass", status: "in_progress", priority: "high" }\n`

            await toast(`GREEN — Implement "${name}"`, "info")

            return msg
          }

          if (phase === "green") {
            if (!testPassed) {
              const truncated = testOutput.length > 2000
                ? testOutput.slice(-2000)
                : testOutput

              await toast(`Tests still failing for "${name}"`, "error")

              return (
                `## Tests still FAILING\n` +
                `Fix implementation, then call \`devblock_next\` again.\n\n` +
                `**Test output (last ${Math.min(testOutput.length, 2000)} chars):**\n` +
                "```\n" + truncated + "\n```"
              )
            }

            const commitResult = await autoCommit(d, scope)
            completeFeature(d, scope)
            const newScope = readScope(d)

            let msg = `## Feature Complete: ${name}\n`
            msg += `Tests passing. ${commitResult}\n`

            if (newScope?.current) {
              msg += `\n## Next feature: ${newScope.current.name} (RED)\n`
              msg += `Write failing tests in: ${newScope.current.tests.map(t => `\`${t}\``).join(", ")}\n`
              msg += `Then call \`devblock_next\`.\n`
              msg += `\n### Todo sync\n`
              msg += `Update your todos NOW with todowrite:\n`
              msg += `- { content: "Implement '${name}' — make tests pass", status: "completed", priority: "high" }\n`
              msg += `- { content: "Write failing tests for '${newScope.current.name}'", status: "in_progress", priority: "high" }\n`
              for (const q of (newScope.queue || [])) {
                msg += `- { content: "Feature: '${q.name}' (queued)", status: "pending", priority: "medium" }\n`
              }
              await toast(`"${name}" complete — next: "${newScope.current.name}" RED`, "success")
            } else {
              msg += `\nAll features completed!\n`
              msg += `\n### Todo sync\n`
              msg += `Update your todos NOW with todowrite:\n`
              msg += `- { content: "Implement '${name}' — make tests pass", status: "completed", priority: "high" }\n`
              await toast(`All features completed!`, "success")
            }
            return msg
          }

          return `ERROR: Unexpected phase '${phase}'.`
        },
      }),

      devblock_back: tool({
        description: "Go back from GREEN to RED phase (to fix tests).",
        args: {},
        async execute(_args, context) {
          const d = context.worktree || context.directory
          const scope = readScope(d)
          if (!scope?.current) return "ERROR: No active feature."

          if (scope.current.phase !== "green") {
            return `ERROR: Already in ${scope.current.phase} phase. 'back' only works from GREEN.`
          }

          scope.current.phase = "red"
          writeScope(d, scope)

          await toast(`RED — Fix tests for "${scope.current.name}"`, "warning")

          return (
            `## GREEN → RED\n` +
            `Back to RED phase for "${scope.current.name}".\n` +
            `Fix your tests, then call \`devblock_next\`.\n` +
            `\n### Todo sync\n` +
            `Update your todos NOW with todowrite:\n` +
            `- { content: "Fix tests for '${scope.current.name}'", status: "in_progress", priority: "high" }\n`
          )
        },
      }),

      devblock_skip: tool({
        description:
          "Create a single-use skip token to bypass TDD phase restrictions. " +
          "Requires a reason. The agent MUST ask user confirmation before calling this.",
        args: {
          reason: tool.schema.string().describe("Why this phase bypass is needed"),
        },
        async execute(args, context) {
          const d = context.worktree || context.directory
          const scope = readScope(d)
          if (!scope) return "ERROR: No active session."

          const dbDir = devblockDir(d)
          if (!existsSync(dbDir)) mkdirSync(dbDir, { recursive: true })

          const tokenData = JSON.stringify({
            reason: args.reason,
            created_at: now(),
          })
          writeFileSync(join(dbDir, ".skip-token"), tokenData)

          const phase = scope.current?.phase || "none"
          const feature = scope.current?.name || "none"
          const logLine = `${now()} | phase=${phase} | feature=${feature} | reason: ${args.reason}\n`
          appendFileSync(join(dbDir, "skips.log"), logLine)

          await toast(`Skip: ${args.reason}`, "warning")

          return (
            `Skip token created. You may now make **ONE** edit outside the current phase.\n` +
            `Reason logged: ${args.reason}`
          )
        },
      }),

      devblock_add: tool({
        description:
          "Add a file to the current TDD scope. File type (impl/test) is auto-detected " +
          "from naming conventions, but can be overridden.",
        args: {
          file: tool.schema.string().describe("File path to add to scope"),
          type: tool.schema.enum(["impl", "test"]).optional().describe(
            "Override auto-detection: 'impl' for implementation, 'test' for test file"
          ),
        },
        async execute(args, context) {
          const d = context.worktree || context.directory
          const scope = readScope(d)
          if (!scope?.current) return "ERROR: No active feature."

          const filePath = resolveRelPath(args.file, d)

          if (isScopeMetadataPath(filePath)) {
            return "ERROR: Cannot add .scope.json to scope."
          }

          const fileIsTest = args.type === "test" || (args.type !== "impl" && isTestFile(filePath))
          const targetArray = fileIsTest ? "tests" : "files"
          const arr = scope.current[targetArray]

          if (arr.includes(normalizeScopeFilePath(filePath))) {
            return `'${filePath}' is already in scope (${targetArray}).`
          }

          arr.push(normalizeScopeFilePath(filePath))
          writeScope(d, scope)

          return (
            `Added \`${filePath}\` to **${targetArray}** scope.\n` +
            `(auto-detected as ${fileIsTest ? "test" : "implementation"} file)`
          )
        },
      }),
    },
  }
}
