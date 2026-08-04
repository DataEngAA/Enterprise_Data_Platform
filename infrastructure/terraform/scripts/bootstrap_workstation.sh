#!/usr/bin/env bash
#
# bootstrap_workstation.sh
#
# EC2 user_data / manual-run bootstrap script for the enterprise-data-platform
# dev workstation (Amazon Linux 2023, x86_64). Installs workstation
# PREREQUISITE TOOLING ONLY -- see Dev_Environment_Terraform_Implementation_
# Plan.md Section 29 for the originally approved scope this script stays
# within in spirit; Terraform installation was added in v1.1.0 (see revision
# note below) because this workstation is intended for Terraform
# development -- Section 29 should be reviewed/updated to reflect this
# addition explicitly.
#
# v1.1.1: Amazon Linux 2023 ships `curl-minimal` by default, which conflicts
# with the full `curl` package at the RPM level (dnf refuses to install
# `curl` over `curl-minimal`). The core-tooling step below no longer requests
# `curl` at all; a separate availability check installs `curl-minimal` only
# if no `curl` command is present under any name.
#
# This script has NOT been run against any real instance. It is version-
# controlled source only.
#
# ---------------------------------------------------------------------------
# WHAT THIS SCRIPT MAY DO (Section 29.1, extended in v1.1.0):
#   - system package updates
#   - install: git, GitHub CLI (gh), jq, unzip, common shell utilities
#   - install Terraform (pinned version, checksum-verified, official
#     HashiCorp release archive -- NOT a curl-pipe-shell installer)
#   - install Python tooling prerequisites and uv, as the intended
#     non-root workstation user, not as root
#   - create empty project working directories under that user's home
#   - write a bootstrap version marker and execution log
#
# WHAT THIS SCRIPT MUST NEVER DO (Section 29.2), and does not do below:
#   1. Contain any credential or token.
#   2. Perform GitHub authentication (`gh auth login` stays manual/interactive).
#   3. Clone any repository, private or public.
#   4. Write AWS credentials anywhere.
#   5. Assume the deployment role, or any IAM role.
#   6. Deploy application code.
#   7. Run any Terraform command that operates against real infrastructure
#      (`init`, `plan`, `apply`, etc.) -- installing the `terraform` binary
#      itself (v1.1.0) is tooling installation, not Terraform execution,
#      and is not in tension with this constraint.
#   8. Contain any AWS account ID or ARN.
#   9. Depend on interactive input -- every command below is non-interactive.
#  10. Fail destructively when safely rerun -- see idempotency notes below.
#
# Requirements satisfied: Bash, non-interactive, idempotent, `set -euo
# pipefail`, meaningful progress logging, a bootstrap version marker, safe
# reruns (Section 29.3-29.6).
#
# Revision note (v1.1.0): the workstation user is no longer hardcoded as
# `ec2-user` -- this environment's interactive access is through AWS Systems
# Manager Session Manager as `ssm-user`, not the AL2023 default user. The
# intended workstation user is now resolved from WORKSTATION_USER (default
# `ssm-user`), validated against the system user database, and used for both
# the projects directory ownership and the uv install context. Terraform
# installation was added (pinned version, checksum-verified official
# release, installed to /usr/local/bin). uv is now explicitly installed in
# the workstation user's own context (not root's), so it lands in that
# user's home rather than root's.
# ---------------------------------------------------------------------------

set -euo pipefail

# ---------------------------------------------------------------------------
# Root-execution guard. This script installs system packages (dnf), writes
# to /etc and /var/log, and installs Terraform to /usr/local/bin -- all of
# which require elevated privileges. Failing fast with a clear message here
# is preferable to a confusing permission-denied error partway through.
# ---------------------------------------------------------------------------
if [[ "${EUID}" -ne 0 ]]; then
  echo "Run this script with sudo."
  exit 1
fi

# ---------------------------------------------------------------------------
# Intended non-root workstation user (v1.1.0). Accepted via an environment
# variable with a sensible default rather than hardcoded, since the active
# interactive user depends on the connection method (Session Manager's
# `ssm-user` here, not AL2023's default `ec2-user`). The user's home
# directory is resolved from the system user database (getent), never
# blindly constructed as `/home/<name>` -- this also doubles as validation
# that the user actually exists before any file ownership is attempted.
# ---------------------------------------------------------------------------
readonly WORKSTATION_USER="${WORKSTATION_USER:-ssm-user}"

if ! getent passwd "${WORKSTATION_USER}" >/dev/null 2>&1; then
  echo "User '${WORKSTATION_USER}' does not exist on this system. Set WORKSTATION_USER to a valid, existing user and rerun." >&2
  exit 1
fi

readonly WORKSTATION_HOME="$(getent passwd "${WORKSTATION_USER}" | cut -d: -f6)"

if [ -z "${WORKSTATION_HOME}" ] || [ ! -d "${WORKSTATION_HOME}" ]; then
  echo "Could not resolve a valid, existing home directory for '${WORKSTATION_USER}' from the system user database." >&2
  exit 1
fi

readonly WORKSTATION_GROUP="$(id -gn "${WORKSTATION_USER}")"

# ---------------------------------------------------------------------------
# Versioning (Section 29.6) -- identifies which version of this script ran
# on a given instance, independent of the repository's own git history.
# Bump this value deliberately whenever the script's behavior changes.
# v1.1.0: workstation-user handling made explicit and safe (see revision
# note above), Terraform installation added, uv installed in the workstation
# user's own context instead of root's.
# v1.1.1 (this revision): removed `curl` from the core-tooling dnf install
# (conflicts with AL2023's preinstalled `curl-minimal`); added a separate
# curl-availability check/fallback install of `curl-minimal` before the
# Terraform download step, which is the first step that needs `curl`.
# ---------------------------------------------------------------------------
readonly BOOTSTRAP_SCRIPT_VERSION="1.1.1"
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

log "START bootstrap_workstation.sh version ${BOOTSTRAP_SCRIPT_VERSION} (workstation user: ${WORKSTATION_USER}, home: ${WORKSTATION_HOME})"

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
#    unzip is required below by the Terraform install step.
#    `curl` is deliberately NOT requested here (v1.1.1): Amazon Linux 2023
#    preinstalls `curl-minimal`, and the full `curl` package conflicts with
#    it at the RPM level -- `dnf install -y curl` fails outright on a real
#    AL2023 instance rather than upgrading/coexisting. curl availability is
#    verified separately, below, immediately before the first step that
#    needs it.
# ---------------------------------------------------------------------------
log "STEP core tooling install: starting (git, jq, unzip, tar, less)"
dnf install -y git jq unzip tar less
log "STEP core tooling install: complete"

# ---------------------------------------------------------------------------
# 2a. curl availability (v1.1.1). AL2023 ships `curl-minimal` by default,
#     which already provides the `curl` command for the download steps
#     below (Terraform archive/checksum fetch, uv installer). Only install
#     `curl-minimal` explicitly if no `curl` command is present at all; the
#     full `curl` package is never installed, avoiding the curl-minimal
#     conflict entirely.
# ---------------------------------------------------------------------------
if ! command -v curl >/dev/null 2>&1; then
  log "STEP curl availability: curl command missing; installing curl-minimal"
  dnf install -y curl-minimal
else
  log "STEP curl availability: available"
fi

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
# 4. Terraform -- pinned version, official HashiCorp release archive,
#    checksum-verified against HashiCorp's published SHA256SUMS file before
#    install. Deliberately NOT a curl-pipe-shell installer. Installed to
#    /usr/local/bin, which is already ahead of /usr/bin on AL2023's default
#    PATH for both interactive and sudo sessions. (v1.1.0, new)
# ---------------------------------------------------------------------------
readonly TERRAFORM_VERSION="1.15.8"
readonly TERRAFORM_INSTALL_DIR="/usr/local/bin"
readonly TERRAFORM_ZIP="terraform_${TERRAFORM_VERSION}_linux_amd64.zip"
readonly TERRAFORM_DOWNLOAD_URL="https://releases.hashicorp.com/terraform/${TERRAFORM_VERSION}/${TERRAFORM_ZIP}"
readonly TERRAFORM_SHA256SUMS_URL="https://releases.hashicorp.com/terraform/${TERRAFORM_VERSION}/terraform_${TERRAFORM_VERSION}_SHA256SUMS"

if command -v terraform >/dev/null 2>&1 && terraform version | head -n1 | grep -q "v${TERRAFORM_VERSION}"; then
  log "STEP Terraform install: skipped, v${TERRAFORM_VERSION} already present (idempotent rerun)"
else
  log "STEP Terraform install: starting (pinned version ${TERRAFORM_VERSION})"

  terraform_workdir="$(mktemp -d)"

  curl -fsSL -o "${terraform_workdir}/${TERRAFORM_ZIP}" "${TERRAFORM_DOWNLOAD_URL}"
  curl -fsSL -o "${terraform_workdir}/SHA256SUMS" "${TERRAFORM_SHA256SUMS_URL}"

  terraform_expected_sha256="$(grep " ${TERRAFORM_ZIP}\$" "${terraform_workdir}/SHA256SUMS" | awk '{print $1}')"

  if [ -z "${terraform_expected_sha256}" ]; then
    echo "Could not find an expected checksum for ${TERRAFORM_ZIP} in HashiCorp's published SHA256SUMS file. Aborting Terraform install." >&2
    rm -rf "${terraform_workdir}"
    exit 1
  fi

  terraform_actual_sha256="$(sha256sum "${terraform_workdir}/${TERRAFORM_ZIP}" | awk '{print $1}')"

  if [ "${terraform_expected_sha256}" != "${terraform_actual_sha256}" ]; then
    echo "Terraform archive checksum mismatch for ${TERRAFORM_ZIP}: expected ${terraform_expected_sha256}, got ${terraform_actual_sha256}. Aborting install -- the downloaded archive did not match HashiCorp's published checksum." >&2
    rm -rf "${terraform_workdir}"
    exit 1
  fi

  unzip -o "${terraform_workdir}/${TERRAFORM_ZIP}" -d "${terraform_workdir}" >/dev/null
  install -m 0755 "${terraform_workdir}/terraform" "${TERRAFORM_INSTALL_DIR}/terraform"
  rm -rf "${terraform_workdir}"

  log "STEP Terraform install: complete (v${TERRAFORM_VERSION} installed to ${TERRAFORM_INSTALL_DIR}/terraform, checksum verified)"
fi

# ---------------------------------------------------------------------------
# 5. uv (Python package/dependency manager) -- official installer, no
#    credential required. Installed explicitly in the intended workstation
#    user's own context (v1.1.0: `sudo -u ... env HOME=...`), not as root --
#    running the installer as root would install uv for root's home
#    directory rather than the developer's. Idempotent: the presence check
#    below (run in the same user context) keeps this step's log output
#    accurate on rerun, and the installer itself safely overwrites/upgrades
#    an existing installation.
# ---------------------------------------------------------------------------
if sudo -u "${WORKSTATION_USER}" env HOME="${WORKSTATION_HOME}" bash -c 'command -v uv' >/dev/null 2>&1; then
  log "STEP uv install: skipped, already present for ${WORKSTATION_USER} (idempotent rerun)"
else
  log "STEP uv install: starting (installing for ${WORKSTATION_USER}, not root)"
  sudo -u "${WORKSTATION_USER}" env HOME="${WORKSTATION_HOME}" bash -c 'curl -LsSf https://astral.sh/uv/install.sh | sh'
  log "STEP uv install: complete"
fi

# ---------------------------------------------------------------------------
# 6. Project working directory -- empty scaffolding only, under the
#    resolved workstation user's own home directory (v1.1.0: no longer
#    hardcoded to /home/ec2-user). This script does NOT clone any
#    repository (Section 29.2 item 3); the developer performs `git clone`
#    manually after `gh auth login`.
# ---------------------------------------------------------------------------
readonly PROJECTS_DIR="${WORKSTATION_HOME}/projects"
if [ ! -d "${PROJECTS_DIR}" ]; then
  log "STEP project working directory: creating ${PROJECTS_DIR}"
  mkdir -p "${PROJECTS_DIR}"
  chown "${WORKSTATION_USER}:${WORKSTATION_GROUP}" "${PROJECTS_DIR}"
else
  log "STEP project working directory: already exists, skipped (idempotent rerun)"
fi

# ---------------------------------------------------------------------------
# 7. Bootstrap version marker (Section 29.6).
# ---------------------------------------------------------------------------
echo "${BOOTSTRAP_SCRIPT_VERSION}" > "${VERSION_MARKER_FILE}"
log "STEP version marker: wrote ${BOOTSTRAP_SCRIPT_VERSION} to ${VERSION_MARKER_FILE}"

log "COMPLETE bootstrap_workstation.sh version ${BOOTSTRAP_SCRIPT_VERSION}"
