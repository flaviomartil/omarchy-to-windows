#!/usr/bin/env node
// Compares qmllint's warnings with scripts/qmllint-baseline.txt and fails on
// any warning the baseline doesn't list. qmllint can't see Quickshell's or
// the Omarchy shell's types, so the QML files carry hundreds of standing
// "unqualified access" warnings; what matters is a *new* one, which is how a
// misspelt id or a property that no longer exists shows up before the shell
// is restarted. An entry is the file, the warning's category and, for an
// unqualified access, the name itself, so using a known name again adds
// nothing and a new name fails.
//
//   node scripts/qmllint-check.js            check
//   node scripts/qmllint-check.js --update   rewrite the baseline
const { execFileSync } = require("node:child_process");
const fs = require("node:fs");
const path = require("node:path");

const root = path.join(__dirname, "..");
const baselinePath = path.join(__dirname, "qmllint-baseline.txt");
const files = fs.readdirSync(root).filter((name) => name.endsWith(".qml")).sort();

function findQmllint() {
  const candidates = ["qmllint", "qmllint6", "/usr/lib/qt6/bin/qmllint"];
  for (const candidate of candidates) {
    try {
      execFileSync(candidate, ["--version"], { stdio: "ignore" });
      return candidate;
    } catch (error) {
      // try the next one
    }
  }
  return null;
}

function currentEntries(qmllint) {
  let output;
  try {
    output = execFileSync(qmllint, ["--json", "-", ...files], { cwd: root, encoding: "utf8", stdio: ["ignore", "pipe", "ignore"], maxBuffer: 64 * 1024 * 1024 });
  } catch (error) {
    // qmllint exits non-zero when it has warnings; the report is still on stdout.
    output = error.stdout;
  }
  const report = JSON.parse(output);
  const entries = new Set();
  for (const file of report.files) {
    const name = path.basename(file.filename);
    const source = fs.readFileSync(path.join(root, name), "utf8");
    for (const warning of file.warnings) {
      const detail = warning.id === "unqualified"
        ? source.slice(warning.charOffset, warning.charOffset + warning.length)
        : warning.message;
      entries.add([name, warning.id, detail.replace(/\s+/g, " ")].join("\t"));
    }
  }
  return [...entries].sort();
}

const qmllint = findQmllint();
if (!qmllint) {
  console.log("qmllint-check: SKIPPED, qmllint not found (install qt6-declarative to run it)");
  process.exit(0);
}

const current = currentEntries(qmllint);

if (process.argv.includes("--update")) {
  fs.writeFileSync(baselinePath, current.join("\n") + "\n");
  console.log(`qmllint-check: baseline rewritten with ${current.length} entries`);
  process.exit(0);
}

const baseline = new Set(fs.readFileSync(baselinePath, "utf8").split("\n").filter(Boolean));
const added = current.filter((entry) => !baseline.has(entry));
const gone = [...baseline].filter((entry) => !current.includes(entry));

if (added.length > 0) {
  console.error("qmllint-check: new warnings (file, category, name or message):");
  for (const entry of added) console.error("  " + entry.split("\t").join("  |  "));
  console.error("\nA new unqualified name is usually a misspelt or removed id or property.");
  console.error("If it is a real name from the shell (Color, Style, ...), accept it with:");
  console.error("  npm run lint:qml -- --update");
  process.exit(1);
}

console.log(`qmllint-check: ok, ${current.length} known warnings, none new` + (gone.length ? `; ${gone.length} baseline entries no longer occur (npm run lint:qml -- --update to drop them)` : ""));
