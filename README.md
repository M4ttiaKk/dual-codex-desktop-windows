# Dual Codex Desktop for Windows

Small PowerShell toolkit for experimenting with a second local Codex Desktop
profile on Windows. It is designed around an existing OpenAI Codex/ChatGPT
Desktop installation and uses separate directories for the second profile.

## What this repository contains

- a launcher for the secondary profile;
- non-sensitive health and process/window observation scripts;
- a cautious anonymous qualification probe;
- an observation-only lifecycle monitor.

## What it does not promise

- complete isolation of every internal application write;
- a separate Windows taskbar identity;
- safe automatic termination of background processes;
- any workaround for product quotas, authentication, or account policies.

## Safety model

- Use two legitimate accounts only.
- Do not copy credentials, tokens, browser data, or profile folders.
- Do not modify WindowsApps, the registry, ACLs, package identity, or binaries.
- Do not use global process-name termination or the application tray Exit action
  as a way to close only the second profile.
- If process ownership is ambiguous or access is denied, stop.

## Setup outline

1. Create a dedicated root, for example `C:\CodexDual`.
2. Run the anonymous qualification probe before logging in to the secondary
   profile.
3. Use the launcher only after the B profile has been prepared.
4. Treat the lifecycle monitor as observation-only: it records a window close
   but never kills processes.

The scripts contain additional preconditions and limitations. Review them before
using them on a machine with active accounts.

## Privacy

This repository intentionally excludes profiles, browser data, credentials,
reports, process receipts, desktop shortcuts, icons, machine-specific paths and
personal project data.
