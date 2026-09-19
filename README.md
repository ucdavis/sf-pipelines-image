# sf-pipelines-image

> **POC — not yet used by any pipeline.** The Bitbucket Pipelines runner image in
> active use is still `jjpost/sf-pipelines:v1.8.3` on Docker Hub, built by hand.
> This repo is Phase 1 of moving that build to GitHub Actions + GHCR.

Standalone build for the SiteFarm CI runner image published to
`ghcr.io/ucdavisiet/sf-pipelines`.

## What this image is

It is the **CI runner environment** for SiteFarm's Bitbucket Pipelines — not an
application image and not something deployed to a server. `bitbucket-pipelines.yml`
sets it as the top-level `image:`, so every pipeline step (Drupal Installation,
Stage Environment, Cypress Tests) runs inside it. One image, one tag, no per-env
variants.

Contents: Debian bookworm-slim, PHP 8.3 (packages.sury.org), Apache 2, Chromium +
Xvfb for Cypress, MariaDB client, Composer 2.8.2, npm, Python 3, plus assorted CLI
tools. The `sf_*` helper commands are baked into `/bin`.

## Vendored files — drift risk

The image sources here are **verbatim copies** from the `sitefarm-acquia`
repository (`git@bitbucket.org:ietwebdev/sitefarm-acquia.git`). There is no
automated sync, so they can drift. Upstream paths:

| This repo | Upstream in `sitefarm-acquia` |
| --- | --- |
| `.ci/docker-image/Dockerfile` | `.ci/docker-image/Dockerfile` |
| `.ci/docker-image/conf/apache-vhost.conf` | same path |
| `.ci/docker-image/conf/php.ini` | same path |
| `.ci/docker-image/commands/sf_*` | same path |
| `.ci/run/cypress` | `.ci/run/cypress` (baked as `/bin/sf_cypress`) |

The `.ci/` directory layout is preserved deliberately: the Dockerfile's `COPY`
instructions are repo-root-relative, so keeping the layout means the Dockerfile
needs **no modifications** and stays diffable against upstream.

Note that `sitefarm-acquia`'s Cypress step invokes its own `.ci/run/cypress`, not
the baked `/bin/sf_cypress`. De-duplicating that is a Phase 2 concern.

## Building locally

Build from the repo root. The platform flag is required: Bitbucket Pipelines runs
x86_64, while most of us are on Apple Silicon. An amd64 image still runs on Apple
Silicon under emulation, just slowly.

```bash
docker build --platform=linux/amd64 -t sf-pipelines:local . -f .ci/docker-image/Dockerfile
```

Verify the result:

```bash
./test/smoke.sh sf-pipelines:local
```

## Phase 1 scope

Builds via GitHub Actions, pushes to GHCR as an internal package, and can be
pulled and smoke-tested locally. Deliberately **out of scope**: any change to
`sitefarm-acquia` or `sitefarm`, the Bitbucket credential cutover, retiring the
Docker Hub image, and parameterizing the baked `MYSQL_PASS`.
