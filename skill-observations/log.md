# Skill Observation Log

Observations captured during task-oriented work.

**Status key:** OPEN = not yet actioned | ACTIONED (YYYY-MM-DD) = skill updated/created | DECLINED (YYYY-MM-DD) = user decided not to pursue

---

2026-10-09: Installer diagnosis, fix, and regression verification completed; no new skill observations.

2026-10-09: Windows npm certificate-store fix verified with a real registry ping and both PowerShell regression runners; no new skill observations.

2026-10-13: PowerShell same-line brace formatting configured and verified through the existing LSP formatter; no new skill observations.

### Observation 1: Plugin installation can rewrite unrelated lockfile pins

**Status:** OPEN
**Date:** 2026-10-15
**Session context:** Adding a Neovim agent integration through lazy.nvim.
**Skill:** add-nvim-plugin
**Type:** open-source
**Phase/Area:** Installation and verification

**Issue:** A targeted lazy.nvim install recorded the current on-disk revisions of existing
plugins, changing unrelated lockfile pins even though those plugins were not requested.
The unrelated generated changes were removed, preserving only the new plugin entry.

**Suggested improvement:** In the verification section, require comparing the lockfile
against its pre-install state and preserving existing pins unless upgrades were requested.

**Principle:** A targeted package-manager operation can serialize unrelated local drift;
review generated manifests for scope rather than assuming the operation stayed isolated.

### Observation 2: Repository activity fields are not interchangeable

**Status:** OPEN
**Date:** 2026-10-16
**Session context:** Researching Bicep language support.
**Skill:** add-nvim-plugin
**Type:** open-source
**Phase/Area:** Candidate health checks

**Issue:** A research report inferred that a grammar was stale from GitHub's `updated_at`.
Checking the required `pushed_at` field instead showed a push within the last two months,
reversing the proposed exclusion.

**Suggested improvement:** Require research reports to quote the literal `pushed_at`
value when applying the one-year staleness cutoff; mark missing values unconfirmed
rather than substituting a different activity field.

**Principle:** Threshold decisions must use the exact metric specified by the policy,
not a similarly named timestamp or an inferred proxy.

### Observation 3: Verify version requirements before presenting compatibility

**Status:** OPEN
**Date:** 2026-11-17
**Session context:** Comparing project-wide find-and-replace plugins.
**Skill:** add-nvim-plugin
**Type:** open-source
**Phase/Area:** Feature research and dependency verification

**Issue:** A candidate's README required ripgrep without naming a minimum version.
The comparison initially stated that the installed ripgrep 14 met its requirements.
A subsequent source check found a runtime guard requiring version 15, so that
compatibility claim needed correcting after the user had already chosen an option.

**Suggested improvement:** Before step 4 presents compatibility or dependency costs,
check runtime version guards or health checks when the README omits a version floor.
Mark compatibility unconfirmed until those checks finish rather than publishing an
early assumption while deeper delegated research is still running.

**Principle:** Documentation omissions do not establish compatibility; finish checking
enforced constraints before presenting a decision that depends on them.
