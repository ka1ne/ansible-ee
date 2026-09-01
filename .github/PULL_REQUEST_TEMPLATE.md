# What this changes

<!-- What the change does and why it is needed. Link the issue it closes. -->

Closes #

# How it was tested

<!--
Tick what you ran. Leaving boxes unticked is fine — say what you could not run
and why, especially if you do not have a Windows host to test against.
-->

- [ ] `make lint`
- [ ] `make test-syntax`
- [ ] `make ee-build`
- [ ] `make test-local` against a real Windows host
- [ ] Applied to AWX and ran the affected job template

<!-- If you tested against Windows, which version, and was it domain-joined? -->

# Anything reviewers should look at closely

<!--
Decisions you are unsure about, trade-offs you made, or parts you would like a
second opinion on. Say so plainly — it is more useful than a clean summary
that hides the uncertain bits.
-->

# Checklist

- [ ] Build logic went in the Makefile, not into a workflow file
- [ ] No credentials committed; new secret variables added to `dev/.env.example`
- [ ] Lint findings fixed rather than added to `skip_list`
- [ ] Documentation updated if behaviour or commands changed
