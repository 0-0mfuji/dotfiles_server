# Repository Guidelines

## Project Structure & Module Organization

This repository configures a Mac thin client, a Debian development server, and a Raspberry Pi Wake-on-LAN gateway. `macos/bin/dev` orchestrates remote development through helpers in `scripts/`; shared Bash functions live in `scripts/lib.sh`. Host-specific installers and settings belong in `macos/`, `server/`, or `raspi/`. `config/projects.conf` defines development targets, and `config/local.env.example` documents local variables. Setup and operational instructions live in `docs/`, with an overview in `README.md`. There is no application asset directory or dedicated test suite.

The ignored `dotfile_infra/` checkout is a separate repository. Keep host infrastructure provisioning and Incus instance creation, updates, and deletion there; this repository handles status checks, startup, and connection workflows.

## Build, Test, and Development Commands

There is no build step or package manager configuration. Run commands from the repository root:

- `bash -n scripts/lib.sh macos/bin/dev`: check Bash syntax without executing scripts; include other changed Bash files as needed.
- `bash macos/bin/dev --help`: inspect launcher options without connecting to a host.
- `./install.sh macos` or `./install.sh server`: apply configuration on the corresponding machine.
- `./install.sh raspi <host>`: install the Wake gateway on the specified Pi.
- `dev os sota`: exercise a configured remote development workflow after installation.

Installers and development workflows can change local or remote state; use them only on the intended machines.

## Coding Style & Naming Conventions

Follow existing Bash conventions: two-space indentation, quoted variable expansions, `snake_case` functions and variables, and uppercase configuration variables. Executable Bash entry points use `#!/usr/bin/env bash` and generally `set -euo pipefail`. Use descriptive hyphenated command names such as `server-wake`. Reuse shared logging and configuration helpers. Preserve executable permissions. No formatter or linter is configured; existing ShellCheck source annotations should remain accurate.

## Testing Guidelines

No automated test framework or coverage threshold is defined. Syntax-check changed scripts, then verify affected behavior on the appropriate host. For target-resolution changes, cover exact targets, grouped targets, and unknown names. Record commands and outcomes in the pull request. Tests described for projects in `docs/web.md` belong to those external projects.

## Commit & Pull Request Guidelines

Recent commits use short, descriptive subjects, including imperative messages and `docs:` prefixes. Follow that pattern. Pull requests should explain the affected host, behavior change, validation performed, and configuration prerequisites. Update relevant `docs/` instructions when workflows change; link related issues when applicable.

## Security & Configuration

Keep secrets and machine-specific IP/MAC addresses outside Git, in `~/.ssh/config.local` and `~/.config/dev/local.env`. Add placeholders to examples rather than credentials. Long-running server jobs should use `systemd-inhibit` to prevent automatic suspend.

## Server Update Workflow

Publish Mac changes to the repository remote, then update the Development Server with
`git pull --ff-only` in `~/dotfiles_server` or `~/dotfile_infra`. Do not deploy repository
changes by editing server checkouts directly or copying files over SSH. Before pulling,
preserve and reconcile any server-side worktree changes; never discard them to make a pull
succeed. After pulling, run the installer or provisioning command for the changed component.
For suspend changes, run `sudo ./server/install-suspend.sh` from `~/dotfiles_server`.
