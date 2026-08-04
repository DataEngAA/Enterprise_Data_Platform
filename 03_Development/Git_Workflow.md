# Git Workflow — Branch Strategy and Pull Request Process

Status: **Documentation only. No GitHub branch-protection rules, GitHub API changes, or GitHub Actions workflows have been created as part of this document.** This is the single authoritative source for how branches and pull requests work in this repository — do not duplicate this content elsewhere; cross-reference it instead.

This document closes the two remaining Pre-Phase Step 3 items (`00_Project_Management/PRE_PHASE_CHECKLIST.md`): branch strategy and pull request process. It deliberately stays simple — no GitFlow, no release branches, no multiple permanent branches — appropriate for a solo portfolio project at this stage. Revisit only if the project's collaboration model actually changes later.

## 1. Branch Strategy

- **`main`** is the only permanent branch. It is treated as protected and stable — it should always be in a working, demonstrable state.
- **No direct commits to `main`** once this workflow is adopted. All changes go through a feature branch and a pull request, including documentation-only changes.
- **All work happens on short-lived feature branches**, created off the latest `main` and deleted after merge (Section 3).
- No release branches, no long-lived `develop` branch, no GitFlow — a single protected `main` plus short-lived branches is sufficient for this project's current size and solo-contributor model.

### Branch naming

```text
feature/<short-description>
fix/<short-description>
docs/<short-description>
refactor/<short-description>
chore/<short-description>
```

Guidance on the prefix to use:

| Prefix | Use for |
|---|---|
| `feature/` | New functionality, new documentation sections that add new capability/coverage, new infrastructure design |
| `fix/` | Correcting a bug, a broken build, or an error in existing documentation/code |
| `docs/` | Documentation-only changes that aren't tied to a specific feature (e.g., cleanup, reorganizing existing content) |
| `refactor/` | Restructuring existing code/config without changing behavior |
| `chore/` | Routine maintenance — dependency bumps, tooling config, `.gitignore` changes, etc. |

Example: `feature/ec2-workstation-bootstrap-script`, `docs/naming-convention`, `fix/terraform-var-typo`.

Keep the `<short-description>` lowercase, hyphen-separated, and specific enough to identify the change without reading the diff.

## 2. Pull Request Process

- **Every change to `main` goes through a pull request** — no exceptions, including single-file documentation edits.
- **Keep commits small and meaningful.** Each commit should represent one coherent change with a clear message; avoid large, unrelated multi-topic commits.
- A pull request should be scoped to one logical change (one feature, one fix, one documentation update) rather than bundling unrelated work.

### Required PR description sections

Every pull request description must include:

1. **Purpose** — what this PR does and why, in a sentence or two.
2. **Files changed** — a short list of the files touched and, briefly, what changed in each.
3. **Tests or validation performed** — what was actually run or checked (e.g., `pytest` output, `terraform validate`, manual verification steps, or "documentation only, reviewed for accuracy" when there's no code to test). Do not claim testing that didn't happen.
4. **Documentation updates** — which docs were updated alongside the change (e.g., `Memory.md`, `PRE_PHASE_CHECKLIST.md`, relevant ADRs/runbooks), or "none required" if genuinely none apply.
5. **Risks or open issues** — anything left unresolved, known limitations, or follow-up work the PR doesn't cover.

A minimal PR template capturing these five sections may be added later under `.github/PULL_REQUEST_TEMPLATE.md` if useful; not created as part of this task (see Section 5).

### Merge strategy

- **Prefer squash merge.** Each feature branch collapses into a single commit on `main`, keeping `main`'s history clean and readable even if the feature branch itself had messy or exploratory commits.
- **Delete the feature branch after merge.** Don't let merged branches accumulate in the repository.

## 3. Summary Checklist (Per Change)

1. Create a branch off `main` using the appropriate prefix (Section 1).
2. Make small, focused commits.
3. Open a pull request with all five required sections (Section 2).
4. Review (self-review is acceptable for a solo project, but actually re-read the diff).
5. Squash-merge into `main`.
6. Delete the feature branch.

## 4. What This Repository Does Not Use (By Design, For Now)

- No GitFlow, no `develop` branch, no `release/*` branches, no `hotfix/*` branches.
- No enforced branch-protection rules yet — this document defines the intended process; actually configuring GitHub branch protection (required reviews, required status checks, etc.) is a separate action the user takes directly in GitHub, not something this documentation task performs.
- No CI-enforced merge gates yet — `.github/workflows/README.md` notes that initial GitHub Actions workflows (Markdown/Python/Terraform validation) come after Terraform Bootstrap; until they exist, "tests or validation performed" in a PR description is whatever was actually run locally.

## 5. Related Files

- `.github/workflows/README.md` — planned GitHub Actions validation, not yet implemented.
- `03_Development/Rules.md` — broader AI/development rules.
- `03_Development/Coding_Guidelines.md` — placeholder for detailed coding conventions (not yet written).
- `00_Project_Management/PRE_PHASE_CHECKLIST.md` — tracks this document's completion under Step 3.

Last updated: 2026-07-24
