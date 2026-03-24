# patch-review

A Claude Code plugin for reviewing mailing list patches with dual-reviewer (Claude + Codex) cross-reference.

Designed for open source projects that use mailing list workflows (QEMU, Linux kernel, etc.). Downloads, applies, and performs multi-stage code review with external context from Patchwork and lore.kernel.org.

## Features

- **Multiple input sources**: lore.kernel.org URLs, Message-Ids, subject keyword search, local commits, commit ranges
- **Automatic patch download**: Uses `b4` with graduated fallback to direct lore download
- **Prerequisite detection**: Automatically finds and applies dependency patches
- **Multi-stage review**: Five-stage analysis covering correctness, security, resource management, and more
- **Dual-reviewer cross-reference**: Parallel Codex review with [Claude+Codex] confidence tagging
- **External context**: Queries Patchwork and lore for prior reviews, version history, and CI status
- **Inline review generation**: Produces mailing-list-ready review replies with bilingual comments (English + Chinese)

## Installation

### Claude Code Plugin (recommended)

```bash
claude plugin add github:zevorn/patch-review
```

After installation, use in Claude Code:

```
/patch-review <lore-url-or-msgid-or-commit> [base_branch]
```

### Codex

```bash
git clone git@github.com:zevorn/patch-review.git
cd patch-review
./install.sh --codex
```

### Manual Installation

**Claude Code** (without plugin system):

```bash
git clone git@github.com:zevorn/patch-review.git
cd patch-review
./install.sh --claude
```

### Uninstall

```bash
# Plugin
claude plugin remove patch-review

# Manual
./install.sh --uninstall
```

## Usage

### Input Formats

| Format | Example |
|--------|---------|
| lore URL | `https://lore.kernel.org/qemu-devel/<msgid>/t.mbox.gz` |
| Message-Id | `<msgid@domain>` or `msgid@domain` |
| Subject search | `virtio-net fix`, `riscv vector` |
| Local commit | `HEAD`, `abc1234` |
| Commit range | `master..HEAD`, `abc1234..def5678` |

### Examples

```
/patch-review https://lore.kernel.org/qemu-devel/20240101120000.12345-1-author@example.com/t.mbox.gz
/patch-review master..HEAD
/patch-review abc1234
/patch-review virtio-net RSC fix
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
10. **Launch** parallel Codex review (if available)
11. **Review** in five stages (conceptual, correctness, resources, security, verification)
12. **Cross-reference** Claude and Codex findings
13. **Summarize** findings by severity with source attribution
14. **Generate** inline review reply for mailing list

## Dependencies

- `git` (required)
- `b4` (recommended, falls back to `curl` if unavailable)
- `curl` (fallback patch download)
- `codex` (optional, enables dual-reviewer mode)
- QEMU source tree with `scripts/checkpatch.pl` (for style checking)

## Project Structure

```
patch-review/
├── .claude-plugin/
│   └── plugin.json         # Plugin manifest
├── commands/
│   └── patch-review.md     # Slash command / skill file
├── install.sh              # Manual install script
├── LICENSE
└── README.md
```

## License

MIT License. See [LICENSE](LICENSE) for details.
