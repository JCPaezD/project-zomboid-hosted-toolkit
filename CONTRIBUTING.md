# Contributing

PZ Hosted Toolkit is intentionally conservative. Contributions should preserve three rules:

- read-only tools should stay read-only;
- write-capable tools need clear previews, confirmations, and/or backups;
- examples and tests must not contain personal save data, Steam IDs, or private logs.

## Development workflow

Run smoke tests before proposing changes:

```powershell
.\tests\run-smoke-tests.ps1
```

Keep scripts compatible with Windows PowerShell 5.1 unless there is a strong reason not to.

## Documentation

Document user-facing behavior in `README.md` or `docs/`. Avoid assuming the reader followed the original troubleshooting session that inspired the toolkit.

## Safety

Do not add automatic save/chunk repair as a default behavior. Any future repair tool should operate on copied profiles first and explain data-loss risk clearly.

