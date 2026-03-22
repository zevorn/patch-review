#!/usr/bin/env bash
# install.sh - Install patch-review skill for Claude Code and/or Codex
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

CLAUDE_CMD_DIR="${HOME}/.claude/commands"
CODEX_SKILL_DIR="${CODEX_HOME:-${HOME}/.codex}/skills/patch-review"

usage() {
    cat <<EOF
Usage: $0 [OPTIONS]

Install patch-review skill for AI coding assistants.

Options:
    --claude        Install for Claude Code
    --codex         Install for Codex
    --all           Install for all supported platforms
    --uninstall     Remove installed skill files
    -h, --help      Show this help

If no option is given, installs for all platforms.

Examples:
    $0 --claude
    $0 --codex
    $0 --all
    $0 --uninstall
EOF
}

install_claude() {
    echo "Installing for Claude Code..."
    mkdir -p "${CLAUDE_CMD_DIR}"
    cp "${SCRIPT_DIR}/patch-review.md" "${CLAUDE_CMD_DIR}/patch-review.md"
    echo "  -> ${CLAUDE_CMD_DIR}/patch-review.md"
    echo "Done. Restart Claude Code to pick up the new command."
}

install_codex() {
    echo "Installing for Codex..."
    mkdir -p "${CODEX_SKILL_DIR}"
    cp "${SCRIPT_DIR}/codex/SKILL.md" "${CODEX_SKILL_DIR}/SKILL.md"
    echo "  -> ${CODEX_SKILL_DIR}/SKILL.md"
    echo "Done. Restart Codex to pick up the new skill."
}

uninstall() {
    echo "Uninstalling patch-review..."
    if [ -f "${CLAUDE_CMD_DIR}/patch-review.md" ]; then
        rm "${CLAUDE_CMD_DIR}/patch-review.md"
        echo "  Removed ${CLAUDE_CMD_DIR}/patch-review.md"
    fi
    if [ -d "${CODEX_SKILL_DIR}" ]; then
        rm -rf "${CODEX_SKILL_DIR}"
        echo "  Removed ${CODEX_SKILL_DIR}"
    fi
    echo "Done."
}

do_claude=false
do_codex=false
do_uninstall=false

if [ $# -eq 0 ]; then
    do_claude=true
    do_codex=true
fi

while [ $# -gt 0 ]; do
    case "$1" in
        --claude)   do_claude=true ;;
        --codex)    do_codex=true ;;
        --all)      do_claude=true; do_codex=true ;;
        --uninstall) do_uninstall=true ;;
        -h|--help)  usage; exit 0 ;;
        *)          echo "Unknown option: $1"; usage; exit 1 ;;
    esac
    shift
done

if $do_uninstall; then
    uninstall
    exit 0
fi

$do_claude && install_claude
$do_codex && install_codex
