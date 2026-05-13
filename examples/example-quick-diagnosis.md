# Example Quick Diagnosis

Symptom: a hosted server failed to start, but the user is not sure whether the problem is mods, Workshop, profile files, or a save issue.

Run:

```powershell
.\pz-toolkit.ps1 quick-diagnosis
```

Example result shape:

```text
[pz-quick-diagnosis] Overall: Warning

=== Findings ===
Warning  Client global mods  3 active mod line(s) found in mods/default.txt...
Warning  Latest server log   5 relevant recent line(s) found...
OK       Processes           No PZ/ZombieBuddy/Java-related process detected.
```

Suggested next step:

- If `Client global mods` is warning, run `clear-client-mods -WhatIf`.
- If `Latest server log` is warning, run `errors -ServerOnly -IncludeMapLogs`.
- If `Problem chunks` is warning, run `inspect-blam` and test any repair only on a copied profile.

