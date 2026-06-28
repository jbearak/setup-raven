# setup-raven

A GitHub Action that installs the [Raven](https://github.com/jbearak/raven) CLI
from prebuilt release binaries.

**Raven** is a static analyzer for the R programming language. It reads R
projects without running them, follows `source()` chains, and flags issues such
as undefined symbols, used-before-defined references, cross-file problems, and
style issues. In CI, `raven check` gives R projects the kind of fast,
side-effect-free pre-merge check that other language ecosystems take for
granted.

Raven also powers editor features through the Language Server Protocol:
diagnostics, completion, hover, go-to-definition, and other code intelligence
use the same static scope model that `raven check` runs headlessly.

Raven's sibling project [Sight](https://github.com/jbearak/sight) provides the
same static-analysis and language-server model for Stata. Together, Raven and
Sight bring cross-file navigation, error detection, and code intelligence to two
languages widely used in social science research; `setup-raven` and
[`setup-sight`](https://github.com/jbearak/setup-sight) make their headless CLI
checks easy to install in CI.

## Why this action exists

The released way to get Raven is a prebuilt binary from
[GitHub Releases](https://github.com/jbearak/raven/releases). Installing it in CI
by hand means detecting the runner's OS and architecture, downloading the right
asset, verifying its checksum, and adding it to `PATH`. The other option —
`cargo install --git https://github.com/jbearak/raven raven` — builds Raven from
source, which needs Rust and Cargo and costs minutes of CI time on every run.

This action does the binary install for you: it detects the platform, downloads
the matching release asset, verifies its published SHA-256 checksum, adds `raven`
to `PATH`, and runs `raven --version` as a smoke test. No Rust, no compile.

It **installs only**. Beyond the `--version` smoke test it runs no `raven`
subcommand — `packages update`/`fetch`/`freeze`, `check`, and `lint` are each an
explicit `run:` step your workflow controls, so you keep full control over paths,
flags, and severity thresholds.

## Usage

```yaml
- uses: actions/checkout@v4
- uses: jbearak/setup-raven@v1
  with:
    version: latest
- run: raven packages update   # broad R-free CRAN/Bioconductor coverage
- run: raven check
```

## Inputs

- `version` — `latest` (default) or a Raven release tag. Pin a tag for fully
  reproducible CLI versions.

## Supported runners

macOS, Windows, and Linux runners.

## Package metadata

Provisioning the package-symbol database is left to your workflow:

- `raven packages update` downloads Raven's broad CRAN/Bioconductor database.
- `raven packages fetch` creates an ephemeral project-scoped `.raven/packages.json`
  from r-universe.
- A committed `.raven/packages.json` from `raven packages freeze` is the
  reproducible, project-specific option.

See the [Raven CLI docs](https://github.com/jbearak/raven/blob/main/docs/cli.md)
for details.

## License

[GPL-3.0](LICENSE), the same license as Raven.
