# Security

HeartBeat is a local developer tool that executes the checks you give it. It does not sandbox anything.
This file states the trust model plainly, in one place, so there are no surprises.

## A `dag.json` / executor is trusted input

A gate criterion is a shell command, and `.hb/gate.sh` runs it. Loading and running a HeartBeat project
— its `dag.json`, `.hb/executor.json`, `HB_NOTIFY_CMD`, and executor backends — is therefore
**equivalent to running a shell script from that source**. Treat a `dag.json` (or an executor config, or
a project's `.hb/`) from an untrusted party exactly as you would treat any untrusted shell script: read
it before you run it. HeartBeat neither sandboxes nor confirms gate commands before executing them.

## The MCP server is loopback-only and unauthenticated by design

`hb mcp-serve --http` binds `127.0.0.1` only, validates the `Origin` header (guarding against
DNS-rebinding), and refuses a non-loopback bind unless you explicitly pass `--allow-remote`. Within that
boundary the transport is **unauthenticated**: anything that can reach the port can drive the tools —
and the tools run gate shell-commands. Do not expose it beyond loopback without putting your own
authentication and network controls in front of it. Details and the hardening rationale:
[secure-the-mcp-server.md](docs/howto/secure-the-mcp-server.md).

## Auto-committed, never auto-pushed

HeartBeat commits the working tree on each gate pass (disable with `HB_GIT_AUTOCOMMIT=0`) but **never
pushes**. Nothing leaves your machine unless you push it. The installed pre-push guard re-verifies gates
before a manual push and is bypassable with `git push --no-verify`.

## Reporting

This is a local-only, single-maintainer project with no published release and no formal disclosure
process or support SLA. If you find a security issue, open a GitHub issue or contact the maintainer.
