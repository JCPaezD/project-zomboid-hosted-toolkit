# Security Policy

PZ Hosted Toolkit is a local PowerShell toolkit for Project Zomboid hosted/co-op profiles. It does not require a Steam login, does not upload files, and does not run a background service.

## Supported Versions

Security fixes are handled on the latest public alpha/beta release only until the project has stable releases.

## Reporting A Security Issue

Please open a private GitHub security advisory if available, or contact the maintainer through GitHub.

Do not post private saves, full logs, Steam IDs, or `players.db` files publicly unless you have reviewed and redacted them.

## Local Script Notes

The `.cmd` wrappers use PowerShell's `-ExecutionPolicy Bypass` for that single process so users can run local scripts without changing their global Windows policy. This does not grant administrator rights, does not download code, and does not persist a policy change.

If you prefer not to use the wrappers, open PowerShell in the repository folder and run:

```powershell
.\pz-toolkit.ps1
```
