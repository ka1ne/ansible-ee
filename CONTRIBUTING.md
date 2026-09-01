# Contributing

Thanks for taking an interest. This is a small project and contributions of
any size are welcome, including documentation fixes and bug reports.

## Getting set up

You need Python 3.11 or newer, git, and a container runtime. Docker is the
default; export `CONTAINER_RT=podman` if you prefer Podman.

```bash
git clone https://github.com/ka1ne/ansible-ee.git
cd ansible-ee
make bootstrap        # checks prerequisites, then creates .venv
source .venv/bin/activate
make deps             # installs the Ansible collections
```

`make` on its own lists every target with a one-line description. That list is
the fastest way to find your way around.

## The one rule about build commands

**Build logic lives in the Makefile, nowhere else.**

The project runs in three places — your laptop, GitHub Actions, and Tekton on
OpenShift — and each one calls the same make targets. When a command is copied
into a workflow file instead, the three drift apart and CI stops telling the
truth about what you will get locally.

If you need a new build step, add a target and call it from the workflow.

## Before opening a pull request

```bash
make lint          # yamllint and ansible-lint
make test-syntax   # syntax-check the playbooks
make ee-build      # build the Execution Environment
```

`make ee-build` needs to reach `galaxy.ansible.com` and the base image
registry. If your network blocks either, `make ee-context` still validates the
EE definition and generates the Containerfile without building, and CI will do
the real build on your pull request.

Testing anything that touches a Windows host needs an actual Windows host —
see [docs/windows-host-prep.md](docs/windows-host-prep.md). There is no way
around this and it is fine to open a pull request saying you could not run it;
say so and someone with a lab can check.

## Conventions

**Branches.** Cut from `main`, named `<type>/<short-description>` — for example
`feat/iis-bindings` or `fix/probe-timeout`.

**Commits.** Explain why the change is needed, not what the diff shows. The
diff already shows what changed.

**Linting.** Fix findings rather than adding to `skip_list` in `.ansible-lint`.
If a rule genuinely does not apply, say why in the pull request so the
exception gets discussed rather than quietly absorbed. Entries currently in
`warn_list` are deferred on purpose and each names the issue tracking it.

**Secrets.** Never commit credentials. Playbooks read them from the
environment; AWX injects them through credential types. If you add a variable
that carries a secret, add it to `dev/.env.example` with an empty value.

## Issues

Bug reports are most useful with the exact command you ran, what you expected,
and what happened instead. For anything involving a Windows target, include the
Windows version and whether the host is domain-joined — that distinction
changes which WinRM transport applies and is behind a good share of connection
problems.

Issues labelled `good-first-issue` are scoped to be approachable without
knowing the whole codebase.

## Code of Conduct

This project follows the [Contributor Covenant](CODE_OF_CONDUCT.md).
