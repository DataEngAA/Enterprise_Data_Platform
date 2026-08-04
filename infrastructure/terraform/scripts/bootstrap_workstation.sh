#!/usr/bin/env bash
#
# bootstrap_workstation.sh
#
# EC2 user_data bootstrap script for the enterprise-data-platform dev
# workstation (Amazon Linux 2023, x86_64). Installs workstation
# PREREQUISITE TOOLING ONLY -- see Dev_Environment_Terraform_Implementation_
# Plan.md Section 29 for the full, approved scope this script must stay
# within.
#
# This script has NOT been run against any real instance. It is version-
# controlled source only.
#
# ---------------------------------------------------------------------------
# WHAT THIS SCRIPT MAY DO (Section 29.1):
#   - system package updates
#   - install: git, GitHub CLI (gh), jq, unzip, common shell utilities
#   - install Python tooling prerequisites and uv
#   - create empty project working directories
#   - write a bootstrap version marker and execution log
#
# WHAT THIS SCRIPT MUST NEVER DO (Section 29.2), and does not do below:
#   1. Contain any credential or token.
#   2. Perform GitHub authentication (`gh auth login` stays manual/interactive).
#   3. Clone any repository, private or public.
#   4. Write AWS credentials anywhere.
#   5. Assume the deployment role, or any IAM role.
#   6. Deploy application code.
#   7. Run `terraform apply`, or any Terraform command at all.
#   8. Contain any AWS account ID or ARN.
#   9. Depend on interactive input -- every command below is non-interactive.
#  10. Fail destructively when safely rerun -- see idempotency notes below.
#
# Requirements satisfied: Bash, non-interactive, idempotent, `set -euo
# pipefail`, meaningful progress logging, a bootstrap version marker, safe
# reruns (Section 29.3-29.6).
# ---------------------------------------------------------------------------

set -euo pipefail

# ---------------------------------------------------------------------------
# Versioning (Section 29.6) -- identifies which version of this script ran
# on a given instance, independent of the repository's own git history.
# Bump this value deliberately whenever the script's behavior changes.
# ---------------------------------------------------------------------------
readonly BOOTSTRAP_SCRIPT_VERSION="1.0.0"
readonly VERSION_MARKER_FILE="/etc/bootstrap_workstation_version"

# ---------------------------------------------------------------------------
# Logging (Section 29.4) -- a predictable, discoverable log location, plus
# whatever cloud-init/user_data logging AL2023 already captures by default.
# ---------------------------------------------------------------------------
readonly LOG_FILE="/var/log/bootstrap_workstation.log"

log() {
  # Timestamped, single-line progress marker. Appends, so reruns keep a
  # full history rather than overwriting prior runs' evidence.
  echo "$(date -u '+%Y-%m-%dT%H:%M:%SZ') [bootstrap_workstation v${BOOTSTRAP_SCRIPT_VERSION}] $*" | tee -a "${LOG_FILE}"
}

log "START bootstrap_workstation.sh version ${BOOTSTRAP_SCRIPT_VERSION}"

# ---------------------------------------------------------------------------
# 1. System package updates -- non-interactive.
# ---------------------------------------------------------------------------
log "STEP system package update: starting"
dnf update -y
log "STEP system package update: complete"

# ---------------------------------------------------------------------------
# 2. Core tooling: git, jq, unzip, common shell utilities.
#    dnf install is naturally idempotent -- an already-installed package is
#    a no-op, not an error, so no extra guard is needed here (Section 29.3).
# ---------------------------------------------------------------------------
log "STEP core tooling install: starting (git, jq, unzip, curl, tar, less)"
dnf install -y git jq unzip curl tar less
log "STEP core tooling install: complete"

# ---------------------------------------------------------------------------
# 3. GitHub CLI -- installed only. Never authenticated by this script
#    (Section 29.2 item 2). `gh auth login` remains a manual, interactive,
#    per-developer step performed after first connecting to the instance.
# ---------------------------------------------------------------------------
if ! command -v gh >/dev/null 2>&1; then
  log "STEP GitHub CLI install: starting"
  dnf install -y 'dnf-command(config-manager)'
  dnf config-manager --add-repo https://cli.github.com/packages/rpm/gh-cli.repo
  dnf install -y gh --repo gh-cli
  log "STEP GitHub CLI install: complete"
else
  log "STEP GitHub CLI install: skipped, already present (idempotent rerun)"
fi

# ---------------------------------------------------------------------------
# 4. uv (Python package/dependency manager) -- official installer, no
#    credential required. Idempotent: the installer itself safely
#    overwrites/upgrades an existing installation; the presence check below
#    keeps this step's log output accurate on rerun.
# ---------------------------------------------------------------------------
if ! command -v uv >/dev/null 2>&1; then
  log "STEP uv install: starting"
  curl -LsSf https://astral.sh/uv/install.sh | sh
  log "STEP uv install: complete"
else
  log "STEP uv install: skipped, already present (idempotent rerun)"
fi

# ---------------------------------------------------------------------------
# 5. Project working directories -- empty scaffolding only. This script
#    does NOT clone any repository (Section 29.2 item 3); the developer
#    performs `git clone` manually after `gh auth login`.
# ---------------------------------------------------------------------------
readonly PROJECTS_DIR="/home/ec2-user/projects"
if [ ! -d "${PROJECTS_DIR}" ]; then
  log "STEP project working directory: creating ${PROJECTS_DIR}"
  mkdir -p "${PROJECTS_DIR}"
  chown ec2-user:ec2-user "${PROJECTS_DIR}"
else
  log "STEP project working directory: already exists, skipped (idempotent rerun)"
fi

# ---------------------------------------------------------------------------
# 6. Bootstrap version marker (Section 29.6).
# ---------------------------------------------------------------------------
echo "${BOOTSTRAP_SCRIPT_VERSION}" > "${VERSION_MARKER_FILE}"
log "STEP version marker: wrote ${BOOTSTRAP_SCRIPT_VERSION} to ${VERSION_MARKER_FILE}"

log "COMPLETE bootstrap_workstation.sh version ${BOOTSTRAP_SCRIPT_VERSION}"
