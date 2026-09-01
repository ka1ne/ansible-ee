# Testing against a Windows VM

There is no provisioning here. You point the tests at a Windows machine you
already have — by IP address or by hostname — and they run against it.

```bash
make test-vm HOST=10.0.0.5
make test-vm HOST=winlab01 SUITE=iis
```

## What you need

- A Windows VM reachable over WinRM from wherever you run this.
- An account on it with local administrator rights.
- For the `mssql` suite, SQL Server already installed on that VM.

Set credentials in `.env` at the repository root:

```bash
cp dev/.env.example .env    # fill in TEST_HOST, TEST_USER, TEST_PASSWORD
```

Passing `--password` on the command line works, but anyone who can run `ps` on
your machine can read it. `.env` is gitignored; prefer it.

## The suites

| Suite | What it proves | Needs |
|---|---|---|
| `connectivity` | WinRM works, facts gather, commands run and return output | Any Windows host |
| `iis` | `roles/iis_deploy` creates a working site that serves content | Any Windows host |
| `mssql` | `roles/sqlserver_deploy` creates a database with the requested settings | SQL Server on the host |

`SUITE=all` (the default) runs all three, in that order.

Start with `connectivity`. It is fast, changes nothing, and separates "I cannot
reach the machine" from "the role is broken" — which is most of the diagnostic
value on a first run.

## What a run does

Each suite runs three phases:

1. **converge** — run the content, then assert the result is what was asked
   for. Not "the play went green": the IIS suite fetches the page over HTTP and
   checks the body, the MSSQL suite reads the database back out of
   `sys.databases` and checks the recovery model and compatibility level.
2. **idempotence** — run it again and require that *nothing* changed. This
   catches the most common defect in Ansible content: a task that reports
   `changed` every time, which makes `changed` meaningless to anyone watching a
   real run. Skipped for `connectivity`, which changes nothing by design.
3. **cleanup** — remove everything the test created.

Everything a test creates is named with a per-run id, so two people can run
against the same VM without colliding, and anything left behind by a failed run
is identifiable. Use `--keep` to skip cleanup when you want to inspect the
result; the summary prints the run id.

## Options

```
-H, --host ADDR        IP address or hostname (required)
-u, --user NAME        Account to authenticate as (default: ansible)
-s, --suite NAME       connectivity | iis | mssql | all
    --transport NAME   ntlm | credssp | kerberos | basic (default: ntlm)
    --scheme NAME      http | https (default: http)
    --port N           WinRM port (default: 5985)
    --local            Use the local ansible instead of the EE image
    --keep             Leave artifacts on the VM
    --no-idempotence   Skip the second run
-v, --verbose          Pass -vvv through
```

Run `bash dev/scripts/run-tests.sh --help` for the full list.

### Domain-joined targets

The default is NTLM over HTTP on 5985, which suits a workgroup lab box. For a
domain-joined VM:

```bash
make test-vm HOST=win01.corp.example.com \
  ARGS="--transport credssp --scheme https --port 5986"
```

Kerberos additionally needs the Python packages uncommented in
`ee/requirements.txt` and the image rebuilt — see
[execution-environment.md](execution-environment.md).

## Where it runs

By default the tests run **inside the Execution Environment image**, because
that is what AWX and Tekton actually execute. A test that only passes against
the Ansible on your laptop has not tested the thing you ship.

`--local` runs them with your local Ansible instead. That is faster to iterate
with, but confirm through the EE before opening a pull request.

## Why this is not in CI

These tests need a Windows host, and GitHub-hosted runners cannot reach a VM on
a private network. CI covers what can be checked without a target — linting,
syntax, and building the EE image and inspecting its contents.

That leaves a real gap: nothing automated exercises WinRM, IIS or SQL Server.
Until that is closed, changes to `pywinrm`, the WinRM transports, or the roles
need a manual run against a VM before merging. The Dependabot PR bumping
`pywinrm` is exactly the case to be careful with — that library is on the path
of every connection this project makes.

If you want this automated later, the options are a self-hosted runner inside
the network, or running the same `make test-vm` target from the Tekton pipeline
on OpenShift, which already sits on the right side of the firewall.

## Known gaps in the content these tests exercise

The IIS suite creates the site's physical directory itself, because
`roles/iis_deploy` points a site at `C:\inetpub\wwwroot\<name>` without creating
it, and IIS will not start a site whose path is missing. That is a real gap in
the role rather than a property of the test — tracked in
[#13](https://github.com/ka1ne/ansible-ee/issues/13).

The Molecule scenarios under `molecule/` and `roles/sqlserver_deploy/molecule/`
predate this harness. Some spin up Windows VMs with `dockur/windows`, which is
the provisioning this deliberately avoids. They are not wired into anything and
are candidates for removal.
