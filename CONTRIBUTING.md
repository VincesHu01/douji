# Contributing

Thank you for helping improve Douji.

## Before opening an issue

- Confirm that Doubao desktop is signed in and current.
- Include the output of `doubao --version`, the Douji version, and macOS version.
- Use synthetic conversation text. Never publish a real conversation export, account identifier, access token, or local index.

## Development workflow

```bash
swift test --disable-sandbox
zsh scripts/build-app.sh
```

Keep changes lightweight and local-first. New network dependencies require a clear user benefit, explicit documentation, and a privacy review. Pull requests should include tests when applicable.
