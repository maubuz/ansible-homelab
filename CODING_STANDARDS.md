# Coding standards

Judgement calls for review. Anything mechanical is enforced by `scripts/check.sh` (lint, syntax, the `become` rules), which the pre-commit hook runs; it is not repeated here. The execution rules are in `AGENTS.md`.

- **One place per check.** A role's early assertions live in one task file; another entry point (a preflight, a verify) imports that file with `import_tasks` instead of copying its regexes or conditions.
- **Use the role's variables.** Paths, unit names and file lists that a role already defines (`server_laptop_grub_dropin_dir`, `server_laptop_sleep_targets`) are referenced, never retyped in another task or doc.
- **Document every tunable.** A variable in a role's `defaults/main.yml` that an operator may set appears in that role's doc table with its default and meaning.
- **Cut checks that name no failure.** A check, assertion or report row earns its place by naming the failure of the apply it prevents. A number chosen without a reason (a size floor, a count) is a guess; drop it or justify it in a comment.
- **Comment the why.** Where code works around an Ansible or host behaviour, one comment says which (see "Ansible and host gotchas" in `docs/testing.md`); the gotcha list holds the general ones.
