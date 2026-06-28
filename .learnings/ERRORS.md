# Errors

Command failures and integration errors.

---


## [ERR-20260626-001] powershell_rg_search

**Logged**: 2026-06-26T00:00:00+08:00
**Priority**: low
**Status**: pending
**Area**: infra

### Summary
Initial repository search failed because rg is unavailable and one parallel PowerShell search hit a Windows sandbox CreateProcessWithLogonW 1056 error.

### Error
```nrg not recognized; windows sandbox: CreateProcessWithLogonW failed: 1056
```n
### Context
- Attempted file and text search before falling back to native PowerShell commands.

### Suggested Fix
Use Get-ChildItem and Select-String in this environment when rg is unavailable; avoid parallel shell search if the sandbox rejects it.

### Metadata
- Reproducible: unknown
- Related Files: none

---

