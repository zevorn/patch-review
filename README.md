# patch-review

An AI-powered mailing list patch review skill for [Claude Code](https://docs.anthropic.com/en/docs/claude-code) and [Codex](https://github.com/openai/codex).

Designed for reviewing patches submitted to open source projects that use mailing list workflows (QEMU, Linux kernel, etc.). It downloads, applies, and performs multi-stage code review with external context from Patchwork and lore.kernel.org.

## Features

- **Multiple input sources**: lore.kernel.org URLs, Message-Ids, local commits, commit ranges
- **Automatic patch download**: Uses `b4` with graduated fallback to direct lore download
- **Prerequisite detection**: Automatically finds and applies dependency patches
- **Multi-stage review**: Five-stage analysis covering correctness, security, resource management, and more
- **External context**: Queries Patchwork and lore for prior reviews, version history, and CI status
- **Inline review generation**: Produces mailing-list-ready review replies with bilingual comments (English + Chinese)

## Installation

### Quick Install (all platforms)

```bash
git clone git@github.com:zevorn/patch-review.git
cd patch-review
./install.sh
```

### Claude Code only

```bash
./install.sh --claude
```

This copies `patch-review.md` to `~/.claude/commands/patch-review.md`.

After installation, use the skill in Claude Code with:

```
/patch-review <lore-url-or-msgid-or-commit> [base_branch]
```

### Codex only

```bash
./install.sh --codex
```

This copies the skill to `~/.codex/skills/patch-review/SKILL.md`.

After installation, restart Codex and ask it to review a patch:

```
Use patch-review to review https://lore.kernel.org/qemu-devel/<msgid>/t.mbox.gz
```

### Manual Installation

**Claude Code**:

```bash
mkdir -p ~/.claude/commands
cp patch-review.md ~/.claude/commands/
```

**Codex**:

```bash
mkdir -p ~/.codex/skills/patch-review
cp SKILL.md ~/.codex/skills/patch-review/
```

### Uninstall

```bash
./install.sh --uninstall
```

## Usage

### Input Formats

| Format | Example |
|--------|---------|
| lore URL | `https://lore.kernel.org/qemu-devel/<msgid>/t.mbox.gz` |
| Message-Id | `<msgid@domain>` or `msgid@domain` |
| Local commit | `HEAD`, `abc1234` |
| Commit range | `master..HEAD`, `abc1234..def5678` |

### Examples

Review a patch series from lore:

```
/patch-review https://lore.kernel.org/qemu-devel/20240101120000.12345-1-author@example.com/t.mbox.gz
```

Review local commits against a specific base:

```
/patch-review master..HEAD
```

Review a single commit:

```
/patch-review abc1234
```

## Review Workflow

1. **Parse** input and detect source type
2. **Download** patches via b4 (with fallback)
3. **Analyze** series metadata and version info
4. **Detect** and apply prerequisite patches
5. **Create** review branch and apply patches
6. **Summarize** patch intent
7. **Collect** Patchwork & mailing list context
8. **Analyze** git history of modified files
9. **Prefetch** code context (definitions, callers, callees)
10. **Review** in five stages (conceptual, correctness, resources, security, verification)
11. **Summarize** findings by severity
12. **Generate** inline review reply for mailing list

## Dependencies

- `git` (required)
- `b4` (recommended, falls back to `curl` if unavailable)
- `curl` (fallback patch download)
- QEMU source tree with `scripts/checkpatch.pl` (for style checking)

## Project Structure

```
patch-review/
├── patch-review.md     # Claude Code command file
├── SKILL.md            # Codex skill file
├── install.sh          # Installation script
├── LICENSE
└── README.md
```

## License

MIT License. See [LICENSE](LICENSE) for details.
