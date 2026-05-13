# Example Profile Export

Run:

```powershell
.\tools\pz-export-profile.ps1 -ProfileName "MyHostedServer" -OutputDir ".\exports\MyHostedServer"
```

Expected output:

```text
exports\MyHostedServer\MyHostedServer-mods.txt
exports\MyHostedServer\MyHostedServer-workshopitems.txt
exports\MyHostedServer\MyHostedServer-map.txt
exports\MyHostedServer\MyHostedServer-workshop-checklist.csv
exports\MyHostedServer\MyHostedServer-summary.md
```

Use `workshop-checklist.csv` to build or verify a Steam Workshop collection.
