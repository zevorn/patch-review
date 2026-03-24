---
name: patch-review
description: Download, apply, and review mailing list patches from lore.kernel.org or local commits. Use when the user asks to review a patch, review a mailing list submission, apply patches from lore, review a patch series, check a QEMU/Linux kernel patch, or analyze commit quality. Supports lore URLs, Message-Ids, subject keyword search, local commits, and commit ranges as input.
---

# patch-review: Download, apply, and review mailing list patches

## Arguments

$ARGUMENTS

Format: `<source> [base_branch]`

- `source` (required): One of the following input forms:
  - **lore URL**: `https://lore.kernel.org/qemu-devel/<msgid>/t.mbox.gz`
  - **Message-Id**: `<msgid@domain>` or bare `msgid@domain`
  - **Subject search**: Keywords from patch subject (e.g., `virtio-net fix`,
    `riscv vector`). Triggers interactive search on Patchwork and lore.
  - **Local commit**: A single git SHA or ref (e.g., `HEAD`, `abc1234`)
  - **Local commit range**: `<base>..<tip>` (e.g., `master..HEAD`,
    `abc1234..def5678`)
- `base_branch` (optional): Branch to base on. Default: `master`.
  Ignored when source is a local commit range (base is derived from range).

## Workflow

### Step 1: Parse arguments and detect input mode

Extract from `$ARGUMENTS`:
- source (first arg, required)
- base branch (second arg, default: `master`)

Detect the input mode:

1. **lore URL**: Starts with `https://lore.kernel.org/`. Extract Message-Id
   from the URL path.
   Example: `https://lore.kernel.org/qemu-devel/<msgid>/t.mbox.gz` → `<msgid>`
2. **Message-Id**: Contains `@` but is not a URL. Strip angle brackets if
   present.
3. **Local commit range**: Contains `..` (e.g., `master..HEAD`). Split into
   base and tip refs.
4. **Local commit**: A single SHA or ref. Verify with `git rev-parse <ref>`.
   If `git rev-parse` fails, this is NOT a local commit — fall through to
   mode 5.
5. **Subject search**: Any input that does not match modes 1–4. Treat the
   entire source string as search keywords.

If no arguments provided, ask the user for the source.

Set `$INPUT_MODE` to one of: `lore`, `msgid`, `range`, `commit`, `search`.
For modes `lore` and `msgid`, proceed to Step 2 (remote fetch).
For modes `commit` and `range`, skip to Step 2b (local export).
For mode `search`, proceed to Step 1.5 (subject search).

### Step 1.5: Subject search (mode: `search`)

Search for patches by subject keywords on Patchwork and lore, present results
to the user, and extract the Message-Id for the selected patch.

#### 1.5a: Search Patchwork API

Query the Patchwork REST API with the keywords:

```
WebFetch: https://patchwork.ozlabs.org/api/patches/?project=qemu-devel&q=<keywords>&order=-date&per_page=20
```

URL-encode the keywords (spaces → `%20` or `+`).

From the JSON response, extract for each result:
- `name` — patch subject line
- `msgid` — Message-Id
- `date` — submission date
- `submitter.name` — author name
- `state` — patch status (New / Under Review / Accepted / …)
- `series[0].name` — series name (if part of a series)
- `series[0].id` — series ID

#### 1.5b: Fallback — search lore

If Patchwork returns no results or is unreachable, fall back to lore search:

```
WebFetch: https://lore.kernel.org/qemu-devel/?q=<keywords>&x=A
```

Parse the HTML response to extract matching threads:
- Subject lines
- Message-Ids (from `href` attributes linking to messages)
- Dates and authors

#### 1.5c: Present results to user

Display the search results as a numbered list:

```
Search results for "<keywords>":

  #  | Date       | Subject                                    | Author         | Status
  ---+------------+--------------------------------------------+----------------+-----------
  1  | 2026-03-20 | [PATCH v3 0/5] virtio-net: Fix RSC ...     | Alice Smith    | Under Review
  2  | 2026-03-18 | [PATCH v2 0/5] virtio-net: Fix RSC ...     | Alice Smith    | Superseded
  3  | 2026-03-15 | [PATCH 1/2] virtio-net: Add feature X      | Bob Jones      | New
  ...
```

If results span multiple series, group by series where possible (use
`series[0].id` to group). Show the cover letter (`0/N`) entry when available,
otherwise show the first patch of the series.

#### 1.5d: User selection

Ask the user to select one result by number. If the user wants to refine the
search, allow them to provide new keywords and repeat from 1.5a.

#### 1.5e: Extract Message-Id and continue

From the selected result, extract the `msgid` field. Set `$INPUT_MODE` to
`msgid` and proceed to Step 2 (remote fetch) with this Message-Id.

If the selected result is part of a series (has `series[0].id`), prefer to
use the cover letter's Message-Id so that b4 fetches the entire series. Query
the series endpoint to find the cover letter:

```
WebFetch: https://patchwork.ozlabs.org/api/series/<series_id>/
```

Extract `cover_letter.msgid` from the response. If available, use it as the
Message-Id; otherwise fall back to the selected patch's `msgid`.

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

If b4 fails (not installed, network error, series not found), apply a
graduated fallback strategy instead of immediately asking the user:

**Fallback 1 — Direct lore mbox download**:
```bash
# Download the entire thread as mbox
curl -sL "https://lore.kernel.org/qemu-devel/<message_id>/t.mbox.gz" \
    | gunzip > /tmp/qemu-review-<timestamp>/thread.mbox

# If the above fails (e.g., message-id encoding), try URL-encoded form
curl -sL "https://lore.kernel.org/qemu-devel/<url_encoded_msgid>/t.mbox.gz" \
    | gunzip > /tmp/qemu-review-<timestamp>/thread.mbox
```

When using the raw mbox fallback, additional processing is needed:
- The mbox contains the entire thread (including replies, not just patches)
- Filter to keep only messages whose Subject matches `[PATCH` or `[RFC`
- Sort by subject index (`[PATCH n/m]`) to ensure correct ordering
- The cover letter is the message with index `0/m` or the one without a
  diff body

**Fallback 2 — Single patch via lore raw endpoint**:
```bash
# For a single patch (not a series)
curl -sL "https://lore.kernel.org/qemu-devel/<message_id>/raw" \
    > /tmp/qemu-review-<timestamp>/patch.mbox
```

**Fallback 3 — Ask user**: If all automated approaches fail, show the
errors and ask for guidance. Suggest the user manually download the mbox
or provide a local file path.

### Step 2b: Export local commits as patches (modes: `commit`, `range`)

For local commit input, export patches using `git format-patch`:

```bash
mkdir -p /tmp/qemu-review-<timestamp>

# For a commit range (e.g., master..HEAD):
git format-patch <base>..<tip> -o /tmp/qemu-review-<timestamp>/

# For a single commit:
git format-patch -1 <sha> -o /tmp/qemu-review-<timestamp>/
```

This produces numbered `.patch` files ready for review. There is no `.mbx`
or `.cover` file in this mode — extract series info directly from the
patch files and commit messages.

After export, skip Step 3.5 (prerequisite detection) and Step 4 (branch
creation) — the commits are already in the local repo. Proceed directly
to Step 6 (intent summary), using `<base>` as the base branch for diff
and review commands.

### Step 3: Analyze the patch series (version-aware)

Read the `.cover` file (if present) and the `.mbx` file to get:
- Series title, purpose, patch count, author

#### 3a: Extract version information

Parse the series subject line to extract version metadata:

- **Version number**: Extract `vN` from `[PATCH vN ...]` or `[RFC vN ...]`.
  If no version tag, assume v1.
- **Subject stem**: Strip version tag, index (`n/m`), and prefixes
  (`PATCH`, `RFC`, `RESEND`) to get the base subject. This is used later
  for finding prior versions (Step 7d).
  Example: `[PATCH v3 2/5] hw/i386: Add foo support` → stem: `hw/i386: Add foo support`
- **Changelog**: If the cover letter or individual patches contain a
  changelog section (text between `---` and the diffstat, or after
  `Changes in vN:`), extract it. This shows what changed from the
  prior version.

Record: `$SERIES_VERSION`, `$SUBJECT_STEM`, `$CHANGELOG` (if any).

#### 3b: Derive branch name

Derive branch name: `review/<short-description>` from series title.

### Step 3.5: Detect and apply prerequisite patches

**IMPORTANT**: Before applying the current series, check for prerequisite dependencies.

Search for dependency indicators in the `.cover` and `.mbx` files:
- `Based-on:` tag (usually contains message-id or lore URL)
- `Depends-on:` tag
- Text patterns: "depends on", "based on", "on top of", "prerequisite", "requires"
- `In-Reply-To:` or `References:` headers (may indicate parent series)

Common formats:
```
Based-on: <message-id@domain>
Based-on: https://lore.kernel.org/qemu-devel/<msgid>/
Depends-on: [PATCH v2 0/3] Add foo support
This series depends on the "Add bar" series posted earlier.
```

**If dependencies are found:**

1. Extract the dependency reference (message-id or URL)
2. Inform the user: "Found prerequisite: <description>"
3. Recursively apply prerequisites:
   ```bash
   # Download prerequisite
   mkdir -p /tmp/qemu-review-<timestamp>/prereq-<n>
   cd /tmp/qemu-review-<timestamp>/prereq-<n>
   b4 am <prerequisite-message-id>

   # Apply prerequisite patches
   cd <repo-root>
   git am /tmp/qemu-review-<timestamp>/prereq-<n>/*.mbx
   ```
4. If prerequisite application fails:
   - Try `--3way`
   - If still fails, inform user and ask whether to:
     - Skip prerequisite and try current series anyway
     - Abort review
     - Manually resolve conflicts
5. After all prerequisites are applied, proceed to apply current series

**If no dependencies found:**
- Proceed directly to Step 4

**Note**: Some implicit dependencies may not be declared. If patch application
fails in Step 5, suggest checking lore.kernel.org for recent related series
that might be prerequisites.

### Step 4: Create branch

```bash
git checkout <base_branch>
git checkout -b <branch_name>
```

If branch exists, ask user to delete/recreate or rename.

After creating the branch, update submodules to match the branch state:

```bash
git submodule update
```

This ensures submodules are synchronized with the current branch.

### Step 5: Apply patches

```bash
git am /tmp/qemu-review-<timestamp>/*.mbx
```

On failure: show error, `git am --abort`, retry with `--3way`.
Still failing: ask user.

### Step 6: Patch intent summary

**IMPORTANT**: Before diving into detailed code review, provide a clear summary
of what the patch series intends to do. This helps the user understand the
overall goal and context.

Present to the user:

1. **Series Overview**:
   - Title and author
   - Number of patches
   - Base branch and any prerequisites applied

2. **What Problem Does It Solve?**:
   - Extract from cover letter and commit messages
   - What bug is being fixed or feature being added?
   - Why is this change needed?

3. **How Does It Solve It?**:
   - High-level approach taken
   - Key architectural or design decisions
   - Which subsystems/files are affected

4. **Scope of Changes**:
   - Number of files modified
   - Which architectures/targets are affected
   - Is this a refactor, bug fix, new feature, or API change?

5. **Dependencies and Context**:
   - Any prerequisite patches that were applied
   - Related patch series or issues mentioned
   - Links to relevant documentation or specifications

**Format**: Present this as a clear, concise summary in Chinese, allowing the
user to understand the patch's intent before proceeding with detailed review.

After presenting the summary, ask the user if they want to proceed with the
detailed code review, or if they have any questions about the patch intent.

### Step 7: Patchwork & mailing list context collection

Before reviewing the code, gather external context from Patchwork and the
mailing list archive. This surfaces prior reviewer feedback, version history,
and related work that pure code reading cannot reveal.

Use the **WebFetch** tool for all API calls and page fetches below. If a
query fails or returns empty, skip it and move on — this step is best-effort.

#### 7a: Find the patch on Patchwork

Query the Patchwork REST API to locate the current series:

```
WebFetch: https://patchwork.ozlabs.org/api/patches/?project=qemu-devel&msgid=<message-id>
```

From the response, extract:
- `id` — needed for comment queries
- `state` — patch status (New / Under Review / Accepted / Rejected / …)
- `delegate` — assigned maintainer (if any)
- `series[0].id` — series ID for further queries
- `check` — CI check status

If the patch is not found on patchwork.ozlabs.org, try the alternative:
```
WebFetch: https://patchew.org/api/v1/projects/qemu/series/?message_id=<message-id>
```

#### 7b: Collect review comments from Patchwork

For each patch ID found in 7a:
```
WebFetch: https://patchwork.ozlabs.org/api/patches/<patch_id>/comments/
```

Extract:
- Reviewer name & email
- Comment content (inline review feedback)
- Any Reviewed-by / Acked-by / Tested-by tags
- Concerns or blockers raised

#### 7c: Fetch mailing list thread discussion from lore

Retrieve the full discussion thread from lore.kernel.org:
```
WebFetch: https://lore.kernel.org/qemu-devel/<message-id>/t/
```

Look for:
- Replies from maintainers (look for `@redhat.com`, `@linaro.org`, or
  known QEMU maintainers)
- Requests for changes or outstanding objections
- Positive signals (Reviewed-by, LGTM, "queued", "applied")

#### 7d: Version history — find prior versions

Use `$SERIES_VERSION` and `$SUBJECT_STEM` from Step 3a. If version > 1:

1. Use the subject stem (already cleaned in Step 3a) to search for earlier
   versions on Patchwork:
   ```
   WebFetch: https://patchwork.ozlabs.org/api/patches/?project=qemu-devel&q=<subject_stem>&order=-date&per_page=15
   ```

2. For each earlier version found, fetch its comments (7b) to understand:
   - What feedback was given on v1, v2, etc.
   - Whether the current version addresses those concerns
   - Recurring issues across versions

3. Cross-reference the `$CHANGELOG` (from Step 3a) against prior version
   feedback: does the changelog claim to address the issues reviewers
   raised? Are there concerns from prior versions that the changelog does
   not mention?

Also search lore for the earlier thread:
```
WebFetch: https://lore.kernel.org/qemu-devel/?q=<subject-stem-keywords>&o=-1
```

#### 7e: Related patches in the same subsystem

Identify the subsystem from modified file paths (e.g., `hw/i386/` →
`intel_iommu`, `hw/virtio/` → `virtio`).

Search Patchwork for recent activity in the same area:
```
WebFetch: https://patchwork.ozlabs.org/api/patches/?project=qemu-devel&q=<subsystem-keyword>&state=*&order=-date&per_page=10
```

Focus on:
- Patches touching the same files in the last 3 months
- Ongoing refactors or cleanup series that might conflict
- Recently accepted patches that establish new patterns

#### 7f: Context synthesis

Compile the collected context into a brief summary for reference in later
steps:

1. **Review status**: patch state, assigned maintainer, CI results
2. **Existing feedback**: key points from reviewer comments (both Patchwork
   and lore), any Reviewed-by/Acked-by tags already given
3. **Version evolution** (if applicable): what changed between versions, which
   prior concerns were addressed, which remain open
4. **Subsystem activity**: related recent patches, potential conflicts, new
   patterns to follow

Present this summary to the user in Chinese before proceeding to Git history
analysis.

### Step 8: Git history analysis

Before reviewing the code changes themselves, check the git history of each
modified file to gather context. This provides crucial review evidence that
pure code reading cannot:

```bash
# For each file touched by the series:
git log --oneline -20 <base_branch> -- <file_path>
```

Focus on:
- Recent refactors or bug fixes in the same area — does the patch conflict with
  or duplicate recent work?
- Original author and reviewers of the code being modified — are they CC'd?
- Patterns and conventions established by prior commits (naming, error handling
  style, memory management idioms).
- Whether the patch reverts or contradicts a previous intentional change.

Use `git log -p` or `git show <hash>` on specific historical commits when a
deeper look is needed (e.g., to understand why a particular API was chosen).

### Step 8.5: Code context prefetching

Before starting the multi-stage code review, gather deep context about the
code being modified. This step provides the reviewer with comprehensive
understanding beyond what the diff alone shows.

#### 8.5a: Read full modified files

For each file touched by the series, read the **complete file content** (not
just the diff hunks). This allows understanding:
- The surrounding code structure
- How the modified function fits into the file
- Existing patterns and conventions in the file
- Other related code that may be affected by the change

#### 8.5b: Identify and read related definitions

From the diff, extract key identifiers (struct names, function names, macros,
type definitions) and locate their definitions:

```bash
# For each important identifier in the diff:
grep -rn "typedef.*<type_name>" --include="*.h" --include="*.c"
grep -rn "struct <struct_name> {" --include="*.h"
grep -rn "<function_name>(" --include="*.h" --include="*.c" | head -10
```

Read the header files that define types, macros, and APIs used in the patch.

#### 8.5c: Trace callers and callees

For modified or newly added functions:
- Find call sites (who calls this function?)
- Find callees (what does this function call?)
- Identify the ownership and lifecycle patterns in the call chain

```bash
grep -rn "<function_name>" --include="*.c" --include="*.h" | head -20
```

#### 8.5d: Context budget

Keep total prefetched context reasonable:
- Read at most 10 files fully
- For large files (>500 lines), focus on the sections relevant to the diff
- Prioritize: modified files > header files > caller/callee files

### Step 8.6: Launch parallel Codex review

Before starting Claude's multi-stage review, launch a Codex code review in the
background so both reviews run in parallel. This provides an independent second
opinion from a different model.

**Prerequisites check**: First verify `codex` is installed:
```bash
command -v codex &>/dev/null
```

If codex is **not** installed, skip this step entirely and proceed with
Claude-only review. Print a note: "Codex not found, proceeding with Claude-only
review."

**Launch codex review in background**:
```bash
# Use Bash tool with run_in_background=true
cd <repo_root>
codex review --base <base_branch> \
    -c "model=gpt-5.4" \
    -c "review_model=gpt-5.4" \
    -c "model_reasoning_effort=high" \
    > /tmp/qemu-review-<timestamp>/codex-review.log 2>&1
```

Where `<base_branch>` is:
- For modes `lore`, `msgid`: the base branch (default: `master`)
- For mode `commit`: the base branch
- For mode `range`: the `<base>` ref from the range

The codex review runs in background while Claude proceeds with Step 9. Its
output will be collected in Step 9.5.

### Step 9: Multi-stage code review protocol

**IMPORTANT**: Instead of a single monolithic review pass, perform the review
in multiple focused stages. Each stage targets a specific category of issues.
This multi-stage approach (inspired by the sashiko kernel review system) reduces
blind spots and improves issue detection.

First, gather the basic diff information:

1. `git log --oneline <base_branch>..HEAD`
2. `git diff <base_branch>..HEAD --stat`
3. `git show <hash>` for each commit

Then execute the following review stages sequentially:

#### Stage A: Conceptual & Implementation Verification

Focus **only** on whether the patch does what it claims:

- Does the code change match the commit message description?
- Is the architectural approach sound for this problem?
- Are API contracts and interfaces respected?
- Does the implementation align with QEMU's design patterns for this subsystem?
- Are there simpler alternatives that achieve the same goal?

For each concern, cite the specific commit message claim and the code that
contradicts or insufficiently implements it.

#### Stage B: Correctness & Logic Analysis

Focus **only** on logic bugs and correctness issues:

- Trace execution flow through the modified code paths
- Off-by-one errors, boundary conditions, integer overflow/underflow
- Null pointer dereferences, uninitialized variables
- Error handling: are all error paths handled? Do they clean up properly?
- Edge cases: empty input, maximum values, concurrent access
- Type correctness: signedness, truncation, implicit conversions
- Return value checking: are error returns from called functions checked?

For each finding, provide the **exact execution path** that triggers the bug.

#### Stage C: Resource Management & Concurrency

Focus **only** on resource lifecycle and thread safety:

- Memory management: leaks, use-after-free, double-free
- Reference counting: `object_ref`/`object_unref` balance
- Lock ordering and potential deadlocks (BQL, per-device locks)
- Thread-safety of shared state across vCPU threads
- QEMU Object Model lifecycle: realize/unrealize, instance_init/finalize
- QOM property getters/setters during migration
- `Error **errp` propagation: is `error_propagate` used correctly?
  Are errors set before returning failure?

#### Stage D: Security & Device Emulation Review

Focus **only** on security boundaries and hardware emulation correctness:

- **Guest input validation**: All values from guest (MMIO reads/writes, PCI
  config, DMA descriptors) MUST be validated. QEMU is a security boundary
  between guest and host.
- Buffer overflows from guest-controlled sizes or indices
- Integer overflows in address calculations
- DMA: `dma_memory_read`/`dma_memory_write` with guest-controlled addresses
- MMIO handlers: proper range checking, alignment handling
- PCI BAR and config space access validation
- Side-channel considerations in crypto or security-relevant code
- Migration compatibility: field versioning, subsection guards

#### Stage E: Finding Verification & Deduplication

Review ALL findings from stages A–D and apply strict quality control:

1. **Eliminate duplicates**: Merge findings that describe the same root issue
2. **Require concrete evidence**: Each finding MUST include:
   - Exact file path and line number(s)
   - The problematic code snippet
   - A clear explanation of WHY it is wrong (reference to spec, convention,
     or demonstrable logic flaw)
   - A concrete scenario or execution path that triggers the issue
3. **Dismiss speculative findings**: If you cannot construct a specific scenario
   that triggers the issue, demote it to a "note" or remove it entirely.
   Speculation wastes reviewer and author time.
4. **Classify severity**:
   - **Critical**: Data corruption, security vulnerability, crash, or
     migration breakage
   - **Major**: Functional bug, resource leak, incorrect behavior
   - **Minor**: Suboptimal code, missing edge case handling, style violation
     with functional impact
   - **Nit**: Pure style, naming, or documentation issues
5. **Cross-reference Patchwork context** (from Step 7): check whether the
   patch addresses feedback from prior versions, follows patterns established
   by recent subsystem patches, and aligns with maintainer requests

#### Checkpatch

Run checkpatch on each patch:
```bash
git format-patch <base_branch>..HEAD -o /tmp/qemu-review-<timestamp>/checkpatch/
./scripts/checkpatch.pl /tmp/qemu-review-<timestamp>/checkpatch/*.patch
```

### Step 9.5: Collect and cross-reference Codex review

If Codex review was launched in Step 8.6, collect its results now.

#### 9.5a: Read Codex output

Read the codex review log file:
```
/tmp/qemu-review-<timestamp>/codex-review.log
```

If the background command has not finished yet, wait for it to complete (it was
launched with `run_in_background`).

If codex exited with non-zero or produced empty output, note the failure and
proceed with Claude-only findings. Do not block the review.

#### 9.5b: Parse Codex findings

Codex review outputs issues with `[P0-9]` severity markers:
```
- [P0] Critical issue description - /path/to/file.c:line-range
  Detailed explanation.
- [P1] High priority issue - /path/to/file.c:line-range
  Detailed explanation.
```

Extract all findings with their severity, file path, line range, and
description.

#### 9.5c: Cross-reference with Claude findings

Compare Codex findings against Claude's findings from Stages A–E:

1. **Both agree** (`[Claude+Codex]`): Same issue found by both reviewers.
   Match by file + line range + issue category. These have highest confidence.
2. **Claude only** (`[Claude]`): Found by Claude but not by Codex. Present
   as normal.
3. **Codex only** (`[Codex]`): Found by Codex but not by Claude. Claude MUST
   verify each Codex-only finding before including it:
   - Read the relevant code and trace the execution path
   - If the finding is valid, include it with `[Codex]` attribution
   - If the finding is a false positive, discard it with a brief note in
     the internal cross-reference log

Record the cross-reference results for use in Steps 10 and 11.

### Step 10: Summary

Provide structured review with severity breakdown:

1. **Series overview**: title, author, patch count
2. **Patchwork context**: review status, existing feedback from other
   reviewers, CI results, and version evolution (from Step 7)
3. **Findings by severity** (with source attribution):
   - Critical issues (must fix before merge)
   - Major issues (should fix)
   - Minor issues (consider fixing)
   - Nits (optional cleanup)
   Each finding is tagged with its source:
   - `[Claude+Codex]` — found by both (highest confidence)
   - `[Claude]` — found by Claude only
   - `[Codex]` — found by Codex only (verified by Claude)
4. **Per-patch breakdown**: map findings to specific patches
5. **checkpatch results**
6. **Codex review summary** (if codex was available):
   - Codex model and configuration used
   - Number of findings: total, agreed with Claude, unique to Codex
   - Codex findings that were dismissed as false positives (with reason)
7. **Overall assessment**:
   - Ready to merge / Needs revision / Has blockers
   - Confidence level in the review (based on how much context was available,
     and whether dual-reviewer cross-reference was performed)
   - Key risks or areas that need domain expert input

### Step 11: Generate inline review reply

Generate a review reply file in standard mailing list inline review format and
save it to `~/qemu-patch/reply/`. This is the universal convention for all
mailing-list-based open source projects (QEMU, Linux kernel, etc.).

Rules:
- One reply file per series, covering all patches.
- For each patch, start with the standard `On <date>, <author> wrote:` header.
- Quote the original patch content with `> ` prefix (commit message, diffstat,
  and diff hunks).
- Place review comments **directly below** the relevant quoted code block, not
  in a separate section. This is the key difference from a standalone summary.
- Only quote the lines that are relevant to a comment; use `[...]` to skip
  unrelated hunks.
- If a section has no issues, either skip it or add a brief positive note.
- **Source attribution**: When Codex review was available, tag each review
  comment with its source. Use a subtle inline tag at the start of the comment:
  - `[Claude+Codex]` — both reviewers found this issue (highest confidence)
  - `[Codex]` — originally found by Codex, verified by Claude
  - No tag needed for Claude-only findings (default reviewer)
  This attribution helps the patch author gauge confidence level.
- **CRITICAL - Line Width Limit**: English review comments MUST follow mailing
  list conventions:
  - Target 75 characters per line (recommended)
  - NEVER exceed 80 characters per line (hard limit)
  - Break long sentences into multiple lines
  - Use natural line breaks at punctuation or logical boundaries
  - Code snippets and quoted patches are exempt from this limit
  - Chinese translations are exempt from this limit
- **CRITICAL - English Style**: Write review comments in simple, clear, and direct
  English. Use natural, conversational language common in technical communities.
  Prefer short sentences and everyday words over complex or overly formal expressions.
  Use technical slang and idioms when appropriate (e.g., "this breaks", "bloats the
  binary", "looks good", "nit:", "LGTM"). Avoid academic or bureaucratic phrasing.
  Write like a fellow developer, not a formal document.
- **CRITICAL - Tone and Voice**:
  - Avoid first-person subjects ("I think", "I noticed"). Use impersonal
    constructions instead: "there seems to be...", "it looks like...",
    "this might need...", "worth checking whether...".
  - **For minor issues** (nits, style, suggestions): be inclusive and
    humble. Use "might", "seems", "could". Leave room for the author
    to explain their intent.
  - **For real bugs** (logic errors, correctness issues, spec violations):
    be direct and assertive. Use "should", "is wrong", "this breaks".
    Do NOT soften actual bugs -- clarity prevents confusion.
  - Stay concise -- no filler, no hedging beyond a single softener.
  - Examples (minor):
    - BAD:  "I suggest changing this to X."
    - GOOD: "It might be worth changing this to X."
  - Examples (bug):
    - BAD:  "There might be a possible issue with the NaN value."
    - GOOD: "This is wrong -- 0x7e00 is not a NaN in BF16, it should
             be 0x7fc0."
- **CRITICAL - Chinese Translation**: Each English comment MUST be followed by its
  Chinese translation. The Chinese translation must be a **direct, one-to-one
  translation** of the English text, preserving all technical details, suggestions,
  and tone. Do NOT summarize, paraphrase, or add extra information in Chinese.
  Translate sentence by sentence to maintain accuracy.
- End each per-patch reply with `Thanks,\nChao Liu`.
- Wrap the entire reply body in a markdown fenced code block (` ``` `) so it
  preserves the `> ` quoting when rendered.

Example structure:

```
## Reply to [PATCH n/m] <subject>

` ` `
On <date>, <author> wrote:
> <commit message>
>
> Signed-off-by: ...
> ---
> <diffstat>
>
> <diff hunk context>
> +    problematic_code();

[Claude+Codex] Review comment explaining the issue found by both
reviewers, with suggested fix if applicable.

[Claude+Codex] 中文翻译。

> <more diff context>
[...]
> +    another_section();

Another comment (Claude-only findings need no tag).

中文翻译。

> +    yet_another_line();

[Codex] Issue originally found by Codex review, verified valid
by Claude. Explanation here.

[Codex] 中文翻译。

Best regards,
Chao Liu
` ` `
```

**Note on Codex unavailability**: If Codex was not available (not installed or
failed), omit all source attribution tags and produce the reply in the original
format. Add a brief note at the end of the review file:
`Note: This review was performed by Claude only (Codex unavailable).`

File naming: `~/qemu-patch/reply/<series-short-name>-<version>-reply.md`
