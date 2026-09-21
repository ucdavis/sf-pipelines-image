# sf-pipelines-image

> **POC — not yet used by any pipeline.** The Bitbucket Pipelines runner image in
> active use is still `jjpost/sf-pipelines:v1.8.3` on Docker Hub, built by hand on
> a developer laptop. Nothing in `sitefarm-acquia` or `sitefarm` points here yet.

Standalone build for the SiteFarm CI runner image, published to
`ghcr.io/ucdavis/sf-pipelines` by GitHub Actions.

## What this image is

It is the **CI runner environment** for SiteFarm's Bitbucket Pipelines — not an
application image, and not something deployed to a server. `bitbucket-pipelines.yml`
sets it as the top-level `image:`, so every pipeline step (Drupal Installation,
Stage Environment, Cypress Tests) runs inside it. One image, one tag, no per-env
variants. The `sitefarm` repo pins the same tag.

Contents: Debian bookworm-slim, PHP 8.4 (packages.sury.org), Apache 2, Chromium +
Xvfb for Cypress, MariaDB client, Composer 2.8.2, npm, Python 3, and assorted CLI
tools. The `sf_*` helper commands are baked into `/bin`.

Roughly 1.5 GB uncompressed, ~512 MiB compressed in the registry. A clean build on
a GitHub-hosted runner takes about 3.5 minutes.

## Publishing a new version

Push a `v*` git tag. That is the whole release process:

```bash
git tag v1.8.4-php84
git push origin v1.8.4-php84
```

The [Build and push image](.github/workflows/build-push.yml) workflow builds for
`linux/amd64`, runs `test/smoke.sh` against the built image, and only then pushes
the exact version tag and `ghcr.io/ucdavis/sf-pipelines:latest`. A failing smoke
test means nothing is published.

The git tag is used verbatim as the versioned image tag. The same tested image is
also published as `:latest`; consumers that need a stable reference should
continue to pin an exact version tag.

You can also build a one-off from the Actions tab via **Run workflow**, supplying
the tag as an input. Useful for POC or scratch builds without creating a git tag.

## Pulling the image

The package is **private**, so you must authenticate. GHCR needs a **classic**
personal access token with `read:packages` — fine-grained tokens are unreliable
here. Create one at <https://github.com/settings/tokens>, then:

```bash
echo "$GHCR_PAT" | docker login ghcr.io -u <your-github-username> --password-stdin
docker pull --platform=linux/amd64 ghcr.io/ucdavis/sf-pipelines:v1.8.4-php84
```

If you already use the `gh` CLI with a token carrying `read:packages`, this works
too:

```bash
gh auth token | docker login ghcr.io -u <your-github-username> --password-stdin
```

### Apple Silicon

The image is amd64-only, because Bitbucket Pipelines runs x86_64. It still runs on
Apple Silicon under emulation — just slowly, and `--platform=linux/amd64` is
required on both `build` and `pull`.

One caveat: **Chromium will not start under emulation.** It requires the SSE3
instruction set, which QEMU's x86_64 emulation does not provide
(<http://crbug.com/1123353>). Cypress therefore cannot run locally on an Apple
Silicon machine with this image. Chromium works normally on real x86_64 hardware,
including GitHub-hosted runners and Bitbucket Pipelines, and the CI smoke test
asserts that it does.

## Working on the image locally

Build from the repo root — the Dockerfile's `COPY` paths are repo-root-relative:

```bash
docker build --platform=linux/amd64 -t sf-pipelines:local . -f .ci/docker-image/Dockerfile
./test/smoke.sh sf-pipelines:local
```

Expect roughly 12 minutes on Apple Silicon (emulated), versus ~3.5 minutes native
on a runner.

To poke around inside, using the same resource limits Bitbucket Pipelines applies
(4 CPUs, 3 GB memory, 1 GB of which goes to the MariaDB service container):

```bash
docker run -p 8080:80 -it --memory=3g --memory-swap=4g --cpus=4 \
  --platform=linux/amd64 --entrypoint=/bin/bash \
  ghcr.io/ucdavis/sf-pipelines:v1.8.4-php84
```

### `test/smoke.sh`

Takes an image reference and exits non-zero if any assertion fails. It checks PHP
8.4 and its extensions, Apache modules and the vhost, Composer 2.8.2, Chromium,
the expected CLI tooling, the baked `sf_*` commands, locale, the pipelines paths
(`ROOT_DIR`/`DOCROOT`), and that the architecture is x86_64.

`WARN` lines are advisory and do not fail the run. They flag environment
limitations and pre-existing quirks inherited from the hand-built image — see
below.

## Known issues inherited from the original image

- **`99-sitefarm.ini` is dead config.** The Dockerfile copies `conf/php.ini` to
  `/usr/local/etc/php/conf.d/99-sitefarm.ini`, which is the path convention of the
  official `php` Docker images. This image installs Debian/sury PHP, which scans
  `/etc/php/8.4/cli/conf.d` instead. Inside the container, `memory_limit` is `-1`
  and `opcache.enable_cli` is `Off` — not the `1G` and `1` the file specifies. The
  same is true of the image currently in production. Composer is unaffected
  because it gets `COMPOSER_MEMORY_LIMIT=4G` from an env var. Fixing this changes
  runtime behavior, so it is deliberately not part of Phase 1.
- **A MariaDB password is baked into the image** as `ENV MYSQL_PASS`, matching the
  `mariadb` service in `bitbucket-pipelines.yml`. This is why the package must not
  be made public: `docker inspect` would expose it.
- **Dockerfile build warning** `UndefinedVar: '$HOME'` on line 4, from
  `ENV NVM_DIR="$HOME/.nvm"` — `$HOME` is not defined at that point. Harmless,
  since nvm is not actually used.

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

The `.ci/` layout is preserved deliberately: the Dockerfile's `COPY` instructions
are repo-root-relative, so keeping the layout means the Dockerfile needs **no
modifications** and stays byte-for-byte diffable against upstream.

Note that `sitefarm-acquia`'s Cypress step invokes its own `.ci/run/cypress`, not
the baked `/bin/sf_cypress`. De-duplicating that is a Phase 2 concern.

## Phase 1 status and what's next

Phase 1 is complete: the workflow builds, smoke tests, and publishes to GHCR on a
tag push, and the result can be pulled and verified locally.

Deliberately **out of scope** so far, and the agenda for Phase 2:

- Point `sitefarm-acquia` and `sitefarm` at the GHCR image (`image:` block plus
  new Bitbucket repository variables) and prove it with a real PR pipeline run.
- A bot/machine account holding a long-lived `read:packages` token for Bitbucket
  to authenticate with, instead of an individual's PAT.
- **Storage and transfer quota.** On its current plan the org gets roughly 500 MB
  of packages storage and 1 GB/month of data transfer for private packages, and a
  single version of this image is already ~512 MiB. Every retained tag adds
  another ~512 MiB, and in Phase 2 every pipeline pull draws on the transfer
  allowance. This needs a conversation with whoever owns UCDavisIET billing, plus
  a version-retention policy.
- Switching the package from private to internal, if org-wide visibility is
  wanted. There is no REST API for this; it is a manual toggle in package
  settings.
- Retiring the Docker Hub image, de-duplicating `.ci/run/cypress`, and
  parameterizing `MYSQL_PASS`.
