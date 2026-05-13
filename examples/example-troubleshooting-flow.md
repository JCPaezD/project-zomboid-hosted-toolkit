# Example Troubleshooting Flow

Symptom: hosted server terminates during Workshop download/update.

1. Close Project Zomboid.
2. Audit:

```powershell
.\tools\pz-audit.ps1
```

3. Check latest server log:

```powershell
.\tools\pz-find-latest-error.ps1 -ServerOnly
```

4. If client global mods are active:

```powershell
.\tools\pz-clear-client-mods.ps1 -WhatIf
.\tools\pz-clear-client-mods.ps1
```

5. If logs specifically show `Installed|NeedsUpdate`, `result=33`, and a locked `.jar`:

```powershell
.\tools\pz-repair-workshop-redownload.ps1 -WhatIf
.\tools\pz-repair-workshop-redownload.ps1
```

Do not delete saves to fix Workshop errors.
