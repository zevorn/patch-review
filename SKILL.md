---
name: patch-review
description: Download, apply, and review mailing list patches from lore.kernel.org or local commits. Use when the user asks to review a patch, review a mailing list submission, apply patches from lore, review a patch series, check a QEMU/Linux kernel patch, or analyze commit quality. Supports lore URLs, Message-Ids, local commits, and commit ranges as input.
---

# Patch Review

Review mailing list patches with multi-stage analysis. Supports input from
lore.kernel.org URLs, Message-Ids, local commits, and commit ranges.

## Arguments

The user provides: `<source> [base_branch]`

- `source` (required): One of the following input forms:
  - **lore URL**: `https://lore.kernel.org/qemu-devel/<msgid>/t.mbox.gz`
  - **Message-Id**: `<msgid@domain>` or bare `msgid@domain`
  - **Local commit**: A single git SHA or ref (e.g., `HEAD`, `abc1234`)
  - **Local commit range**: `<base>..<tip>` (e.g., `master..HEAD`,
    `abc1234..def5678`)
- `base_branch` (optional): Branch to base on. Default: `master`.
  Ignored when source is a local commit range (base is derived from range).

## Workflow

### Step 1: Parse arguments and detect input mode

Extract source and base branch from user input.

Detect the input mode:

1. **lore URL**: Starts with `https://lore.kernel.org/`. Extract Message-Id
   from the URL path.
2. **Message-Id**: Contains `@` but is not a URL. Strip angle brackets if
   present.
3. **Local commit range**: Contains `..` (e.g., `master..HEAD`). Split into
   base and tip refs.
4. **Local commit**: A single SHA or ref. Verify with `git rev-parse <ref>`.

Set `$INPUT_MODE` to one of: `lore`, `msgid`, `commit`, `range`.
For modes `lore` and `msgid`, proceed to Step 2 (remote fetch).
For modes `commit` and `range`, skip to Step 2b (local export).

### Step 2: Download patches with b4 (modes: `lore`, `msgid`)

```bash
mkdir -p /tmp/qemu-review-<timestamp>
cd /tmp/qemu-review-<timestamp>
b4 am <message_id>
```

b4 will produce:
- A `.mbx` file (mbox ready for `git am`)
- A `.cover` file (cover letter, if present)

#### b4 failure fallback

If b4 fails, apply graduated fallback:

**Fallback 1 -- Direct lore mbox download**:
```bash
curl -sL "https://lore.kernel.org/qemu-devel/<message_id>/t.mbox.gz" \
    | gunzip > /tmp/qemu-review-<timestamp>/thread.mbox
```

When using raw mbox fallback:
- Filter to keep only messages whose Subject matches `[PATCH` or `[RFC`
- Sort by subject index (`[PATCH n/m]`) to ensure correct ordering
- The cover letter is the message with index `0/m`

**Fallback 2 -- Single patch via lore raw endpoint**:
```bash
curl -sL "https://lore.kernel.org/qemu-devel/<message_id>/raw" \
    > /tmp/qemu-review-<timestamp>/patch.mbox
```

**Fallback 3 -- Ask user**: If all automated approaches fail, show the
errors and ask for guidance.

### Step 2b: Export local commits as patches (modes: `commit`, `range`)

```bash
mkdir -p /tmp/qemu-review-<timestamp>

# For a commit range (e.g., master..HEAD):
git format-patch <base>..<tip> -o /tmp/qemu-review-<timestamp>/

# For a single commit:
git format-patch -1 <sha> -o /tmp/qemu-review-<timestamp>/
```

After export, skip Step 3.5 and Step 4. Proceed directly to Step 6.

### Step 3: Analyze the patch series (version-aware)

Read the `.cover` file (if present) and the `.mbx` file to get:
- Series title, purpose, patch count, author

#### 3a: Extract version information

- **Version number**: Extract `vN` from `[PATCH vN ...]`. Default v1.
- **Subject stem**: Strip version tag, index, and prefixes to get base subject.
- **Changelog**: Extract text between `---` and diffstat or after `Changes in vN:`.

Record: `$SERIES_VERSION`, `$SUBJECT_STEM`, `$CHANGELOG`.

#### 3b: Derive branch name

Derive branch name: `review/<short-description>` from series title.

### Step 3.5: Detect and apply prerequisite patches

Check for dependency indicators: `Based-on:`, `Depends-on:`, text patterns
like "depends on", "based on", "on top of", "prerequisite", "requires".

If dependencies found, recursively download and apply prerequisites before
the current series.

### Step 4: Create branch

```bash
git checkout <base_branch>
git checkout -b <branch_name>
git submodule update
```

### Step 5: Apply patches

```bash
git am /tmp/qemu-review-<timestamp>/*.mbx
```

On failure: `git am --abort`, retry with `--3way`. Still failing: ask user.

### Step 6: Patch intent summary

Present a clear summary covering:
1. Series overview (title, author, patch count, base branch)
2. What problem it solves
3. How it solves it
4. Scope of changes
5. Dependencies and context

Present in Chinese, then ask if the user wants to proceed with detailed review.

### Step 7: Patchwork & mailing list context collection

Query external sources for review context:

- **7a**: Find patch on Patchwork (`patchwork.ozlabs.org/api/patches/`)
- **7b**: Collect review comments from Patchwork
- **7c**: Fetch mailing list thread from lore
- **7d**: Find prior versions if version > 1
- **7e**: Search related patches in the same subsystem
- **7f**: Compile context synthesis summary

### Step 8: Git history analysis

For each modified file:
```bash
git log --oneline -20 <base_branch> -- <file_path>
```

Focus on recent refactors, original authors, patterns, and conventions.

### Step 8.5: Code context prefetching

- Read full modified files (not just diff hunks)
- Identify and read related definitions (structs, functions, macros)
- Trace callers and callees
- Keep total prefetched context reasonable (max 10 files)

### Step 9: Multi-stage code review

Execute review stages sequentially:

- **Stage A**: Conceptual & implementation verification
- **Stage B**: Correctness & logic analysis
- **Stage C**: Resource management & concurrency
- **Stage D**: Security & device emulation review
- **Stage E**: Finding verification & deduplication

Run checkpatch:
```bash
git format-patch <base_branch>..HEAD -o /tmp/qemu-review-<timestamp>/checkpatch/
./scripts/checkpatch.pl /tmp/qemu-review-<timestamp>/checkpatch/*.patch
```

### Step 10: Summary

Provide structured review:
1. Series overview
2. Patchwork context
3. Findings by severity (Critical / Major / Minor / Nit)
4. Per-patch breakdown
5. checkpatch results
6. Overall assessment

### Step 11: Generate inline review reply

Generate a review reply in standard mailing list inline format, saved to
`~/qemu-patch/reply/`.

Rules:
- One reply file per series
- Use `On <date>, <author> wrote:` header
- Quote original with `> ` prefix
- Place comments directly below relevant quoted code
- English line width: target 75, max 80 characters
- Each English comment followed by Chinese translation
- End with `Thanks,\nChao Liu`
- Wrap in markdown fenced code block

File naming: `~/qemu-patch/reply/<series-short-name>-<version>-reply.md`
