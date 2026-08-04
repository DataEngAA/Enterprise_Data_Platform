# Coding Guidelines

Status: **Placeholder — not yet defined in detail.**

This file is referenced by `00_Project_Management/PROJECT_BLUEPRINT.md` (Pre-Phase Step 1, Section 7) and by `CLAUDE.md`, but detailed guidelines have not been written yet. High-level rules already exist in `03_Development/Rules.md` — this file is intended to expand on those with concrete, example-driven guidance once implementation begins (starting with Phase 1 ingestion code). Do not invent detailed guidelines here ahead of that work.

Expected scope, once defined:

- Project/module layout conventions for Python packages (src layout, package naming).
- Function and class design conventions beyond `Rules.md`'s summary (type hints, structured logging, Pydantic contracts).
- Error handling patterns and exception hierarchy.
- Logging format and required fields (correlation ID, pipeline run ID, etc. — see ingestion metadata envelope in `PROJECT_BLUEPRINT.md` Section 13).
- Testing conventions beyond `07_Testing/Testing.md` (test file layout, fixture conventions, mocking AWS services).
- Docstring style and required documentation per function/module.
- Linting/formatting configuration (Ruff rules enabled, line length, import ordering).
- Pre-commit hook expectations, if any.

## Related files

- `03_Development/Rules.md` — high-level AI/development rules (authoritative until this file is filled in).
- `01_Architecture/Standards.md` — engineering standards (Python, Terraform, data).
- `07_Testing/Testing.md` — testing strategy.

Last updated: 2026-07-24
