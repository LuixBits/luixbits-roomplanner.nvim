# Security policy

RoomPlan reads and writes user-authored JSON and Norg sources inside Neovim.
Reports involving unintended file writes, source corruption, path handling,
code execution, unsafe parsing, or dependency/workflow compromise are treated
as security-sensitive.

## Supported versions

Before the first tagged release, security fixes are made on `main`. After
`v0.1.0`, the newest tagged minor release and `main` receive fixes. Older
pre-`1.0` minor lines are not guaranteed separate backports unless a security
advisory says otherwise.

Persisted schema compatibility is separate: supported old plan schemas remain
loadable through the documented migrations even when an old plugin release no
longer receives fixes.

## Reporting privately

Do not open a public issue for a suspected vulnerability. Use GitHub's
[private vulnerability report](https://github.com/LuixBits/luixbits-roomplanner.nvim/security/advisories/new)
to send:

- affected RoomPlan tag or commit and Neovim version;
- operating system and installation method;
- impact and required preconditions;
- minimal reproduction or proof of concept;
- whether source files, symlinks, Norg buffers, or write hooks are involved.

Remove unrelated personal plan data. The maintainer will acknowledge a usable
report as soon as practical, reproduce and assess it privately, coordinate a
fix and disclosure, and credit the reporter unless anonymity is requested. Do
not publish details before a fix or coordinated disclosure date.

If GitHub private reporting is unavailable, contact the maintainer through the
[GitHub profile](https://github.com/LuixBits) without including vulnerability
details in a public message and request a private channel.

## Scope

RoomPlan is a space-planning tool, not a construction, safety, or building-code
system. Incorrect design advice is a product correctness issue, not by itself
a security vulnerability. Data loss, unintended writes, or executing untrusted
plan content remain in scope.
