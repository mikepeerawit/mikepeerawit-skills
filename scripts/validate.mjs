#!/usr/bin/env node
// Validates the skills in this repo. No dependencies — Node built-ins only.
//
//   node scripts/validate.mjs
//
// Exits non-zero if anything is wrong, so CI fails loudly rather than shipping
// a skill that Claude Code will silently refuse to load.

import { readFileSync, readdirSync, existsSync, statSync } from "node:fs";
import { join, dirname, resolve, relative } from "node:path";
import { fileURLToPath } from "node:url";

const ROOT = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const SKILLS_DIR = join(ROOT, "skills");

// Claude Code's own limits on skill frontmatter.
const MAX_NAME_LEN = 64;
const MAX_DESC_LEN = 1024;
const NAME_RE = /^[a-z0-9]+(-[a-z0-9]+)*$/;

const errors = [];
const fail = (file, msg) => errors.push(`${relative(ROOT, file)}: ${msg}`);

/** Split a markdown file into its YAML frontmatter block and body. */
function splitFrontmatter(text) {
  const lines = text.split("\n");
  if (lines[0] !== "---") return null;
  const end = lines.indexOf("---", 1);
  if (end === -1) return null;
  return { fm: lines.slice(1, end), body: lines.slice(end + 1).join("\n") };
}

/** Parse the flat `key: value` pairs we actually use. Not a general YAML parser. */
function parseFrontmatter(fmLines) {
  const out = {};
  for (const line of fmLines) {
    if (!line.trim() || line.trimStart().startsWith("#")) continue;
    const idx = line.indexOf(":");
    if (idx === -1 || /^\s/.test(line)) {
      out.__malformed = (out.__malformed ?? []).concat(line);
      continue;
    }
    out[line.slice(0, idx).trim()] = line.slice(idx + 1).trim();
  }
  return out;
}

/** Every relative markdown link must resolve to a file that exists. */
function checkLinks(file, text) {
  for (const [, , target] of text.matchAll(/\[([^\]]*)\]\(([^)\s]+)\)/g)) {
    if (/^(https?:|mailto:|#)/.test(target)) continue;
    const path = join(dirname(file), target.split("#")[0]);
    if (!existsSync(path)) fail(file, `broken relative link: ${target}`);
  }
}

if (!existsSync(SKILLS_DIR)) {
  console.error("no skills/ directory found");
  process.exit(1);
}

const skillDirs = readdirSync(SKILLS_DIR)
  .filter((n) => !n.startsWith(".") && statSync(join(SKILLS_DIR, n)).isDirectory())
  .sort();

if (skillDirs.length === 0) {
  console.error("skills/ contains no skill directories");
  process.exit(1);
}

for (const dir of skillDirs) {
  const file = join(SKILLS_DIR, dir, "SKILL.md");

  if (!existsSync(file)) {
    fail(join(SKILLS_DIR, dir), "missing SKILL.md");
    continue;
  }

  const text = readFileSync(file, "utf8");
  const split = splitFrontmatter(text);

  if (!split) {
    fail(file, "missing or unterminated YAML frontmatter (must open and close with ---)");
    continue;
  }

  const fm = parseFrontmatter(split.fm);

  for (const line of fm.__malformed ?? []) {
    fail(file, `frontmatter line is not a flat "key: value" pair: ${JSON.stringify(line)}`);
  }

  if (!fm.name) {
    fail(file, "frontmatter is missing `name`");
  } else {
    if (fm.name !== dir) fail(file, `frontmatter name "${fm.name}" does not match directory "${dir}"`);
    if (!NAME_RE.test(fm.name)) fail(file, `name "${fm.name}" must be lowercase kebab-case`);
    if (fm.name.length > MAX_NAME_LEN) fail(file, `name is ${fm.name.length} chars (max ${MAX_NAME_LEN})`);
  }

  if (!fm.description) {
    fail(file, "frontmatter is missing `description` — this is what Claude matches on, so it cannot be empty");
  } else if (fm.description.length > MAX_DESC_LEN) {
    fail(file, `description is ${fm.description.length} chars (max ${MAX_DESC_LEN})`);
  }

  if (!split.body.trim()) fail(file, "has frontmatter but no body");

  checkLinks(file, text);
}

// The README's skill list is hand-maintained; make drift a build failure rather
// than something a reader discovers. Any `[`name`](skills/…)` link counts —
// table row or prose heading — so the README stays free to explain each skill.
const readmePath = join(ROOT, "README.md");
if (existsSync(readmePath)) {
  const readme = readFileSync(readmePath, "utf8");
  checkLinks(readmePath, readme);

  const listed = [...readme.matchAll(/\[`([^`\/]+)`\]\(skills\/\1\//g)].map((m) => m[1]).sort();
  const missing = skillDirs.filter((s) => !listed.includes(s));
  const extra = listed.filter((s) => !skillDirs.includes(s));
  if (missing.length) fail(readmePath, `README does not link these skills: ${missing.join(", ")}`);
  if (extra.length) fail(readmePath, `README links non-existent skills: ${extra.join(", ")}`);
}

// Plugin manifests must parse and agree with each other. Every marketplace entry
// must point at a directory holding a plugin.json of the same name; if that
// plugin ships hooks or agents, those must be loadable too — a hook that points
// at a missing script fails silently inside Claude Code.
const marketplacePath = join(ROOT, ".claude-plugin", "marketplace.json");
const readJson = (p) => {
  try {
    return JSON.parse(readFileSync(p, "utf8"));
  } catch (e) {
    fail(p, `invalid JSON: ${e.message}`);
    return null;
  }
};

/** Agent files use the same frontmatter shape as skills, plus a required `model`. */
function checkAgents(agentsDir) {
  for (const name of readdirSync(agentsDir).filter((n) => n.endsWith(".md")).sort()) {
    const file = join(agentsDir, name);
    const split = splitFrontmatter(readFileSync(file, "utf8"));
    if (!split) {
      fail(file, "missing or unterminated YAML frontmatter");
      continue;
    }
    const fm = parseFrontmatter(split.fm);
    for (const line of fm.__malformed ?? []) fail(file, `frontmatter line is not a flat "key: value" pair: ${JSON.stringify(line)}`);
    const stem = name.slice(0, -3);
    if (!fm.name) fail(file, "frontmatter is missing `name`");
    else if (fm.name !== stem) fail(file, `frontmatter name "${fm.name}" does not match file "${stem}"`);
    if (!fm.description) fail(file, "frontmatter is missing `description`");
    else if (fm.description.length > MAX_DESC_LEN) fail(file, `description is ${fm.description.length} chars (max ${MAX_DESC_LEN})`);
    if (!fm.model) fail(file, "frontmatter is missing `model` — an orchestrator agent must pin its tier");
    if (!split.body.trim()) fail(file, "has frontmatter but no body");
  }
}

/** Every command hook that references ${CLAUDE_PLUGIN_ROOT}/… must name a file that exists. */
function checkHooks(pluginDir, hooksPath) {
  const hooks = readJson(hooksPath);
  if (!hooks) return;
  if (!hooks.hooks || typeof hooks.hooks !== "object") {
    fail(hooksPath, "must have a top-level `hooks` object keyed by event name");
    return;
  }
  for (const [event, groups] of Object.entries(hooks.hooks)) {
    if (!Array.isArray(groups)) {
      fail(hooksPath, `${event}: must be an array of matcher groups`);
      continue;
    }
    for (const group of groups) {
      for (const hook of group.hooks ?? []) {
        if (hook.type !== "command" || typeof hook.command !== "string") continue;
        for (const [, rel] of hook.command.matchAll(/\$\{CLAUDE_PLUGIN_ROOT\}\/([^"'\s]+)/g)) {
          if (!existsSync(join(pluginDir, rel))) fail(hooksPath, `${event}: hook script not found: ${rel}`);
        }
      }
    }
  }
}

if (existsSync(marketplacePath)) {
  const marketplace = readJson(marketplacePath);
  if (marketplace) {
    if (!Array.isArray(marketplace.plugins) || marketplace.plugins.length === 0) {
      fail(marketplacePath, "`plugins` must be a non-empty array");
    } else {
      for (const entry of marketplace.plugins) {
        if (typeof entry.source !== "string") {
          fail(marketplacePath, `plugin "${entry.name}": source must be a relative path string`);
          continue;
        }
        const pluginDir = resolve(ROOT, entry.source);
        const pluginPath = join(pluginDir, ".claude-plugin", "plugin.json");
        if (!existsSync(pluginPath)) {
          fail(marketplacePath, `plugin "${entry.name}": no plugin.json at ${relative(ROOT, pluginPath)}`);
          continue;
        }
        const plugin = readJson(pluginPath);
        if (plugin && plugin.name !== entry.name) {
          fail(pluginPath, `plugin.json name "${plugin.name}" does not match marketplace entry "${entry.name}"`);
        }
        const hooksPath = join(pluginDir, "hooks", "hooks.json");
        if (existsSync(hooksPath)) checkHooks(pluginDir, hooksPath);
        const agentsDir = join(pluginDir, "agents");
        if (existsSync(agentsDir)) checkAgents(agentsDir);
      }
    }
  }
}

if (errors.length) {
  console.error(`\n✗ ${errors.length} problem${errors.length === 1 ? "" : "s"} found:\n`);
  for (const e of errors) console.error(`  - ${e}`);
  console.error("");
  process.exit(1);
}

console.log(`✓ ${skillDirs.length} skills valid: ${skillDirs.join(", ")}`);
