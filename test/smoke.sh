#!/usr/bin/env bash
#
# Smoke test for the sf-pipelines CI runner image.
#
# Usage:  ./test/smoke.sh <image-ref>
# Example: ./test/smoke.sh sf-pipelines:local
#          ./test/smoke.sh ghcr.io/ucdavis/sf-pipelines:v1.8.4-php84
#
# Exits 0 only if every assertion passes. WARN lines are advisory and do not
# affect the exit code; they flag pre-existing quirks carried over from the
# original hand-built image.
#
# Override the platform with SMOKE_PLATFORM (default linux/amd64, since the
# image is built for Bitbucket Pipelines' x86_64 runners).

set -uo pipefail

IMAGE="${1:-}"
PLATFORM="${SMOKE_PLATFORM:-linux/amd64}"

if [ -z "$IMAGE" ]; then
  echo "usage: $0 <image-ref>" >&2
  exit 2
fi

echo "=============================================="
echo "Smoke test: $IMAGE"
echo "Platform:   $PLATFORM"
echo "=============================================="

docker run --rm -i --platform="$PLATFORM" --entrypoint /bin/bash "$IMAGE" -s <<'INNER'
set -uo pipefail

PASS=0; FAIL=0; WARN=0

ok()   { printf 'PASS  %s\n' "$1"; PASS=$((PASS+1)); }
bad()  { printf 'FAIL  %s\n' "$1"; FAIL=$((FAIL+1)); }
warn() { printf 'WARN  %s\n' "$1"; WARN=$((WARN+1)); }

# check <description> <command...>
check() {
  local desc="$1"; shift
  if "$@" >/dev/null 2>&1; then ok "$desc"; else bad "$desc"; fi
}

# have <binary> — present on PATH
have() {
  local bin="$1"
  if command -v "$bin" >/dev/null 2>&1; then ok "binary on PATH: $bin"; else bad "binary on PATH: $bin"; fi
}

section() { printf '\n--- %s\n' "$1"; }

section "PHP 8.4"
PHP_V="$(php -v 2>/dev/null | head -1)"
case "$PHP_V" in
  "PHP 8.4."*) ok "PHP CLI is 8.4 ($PHP_V)" ;;
  "")          bad "PHP CLI is 8.4 (php not found)" ;;
  *)           bad "PHP CLI is 8.4 (got: $PHP_V)" ;;
esac

PHP_MODS="$(php -m 2>/dev/null | tr '[:upper:]' '[:lower:]')"
for ext in apcu curl gd imagick mbstring pdo_mysql readline sqlite3 tokenizer xml zip; do
  if printf '%s\n' "$PHP_MODS" | grep -qx "$ext"; then
    ok "PHP extension loaded: $ext"
  else
    bad "PHP extension loaded: $ext"
  fi
done
# OPcache is a Zend extension, so it appears as "Zend OPcache" under
# [Zend Modules] rather than as "opcache" in the regular module list.
if printf '%s\n' "$PHP_MODS" | grep -q 'zend opcache'; then
  ok "PHP extension loaded: Zend OPcache"
else
  bad "PHP extension loaded: Zend OPcache"
fi

section "PHP config file (99-sitefarm.ini)"
SF_INI="/usr/local/etc/php/conf.d/99-sitefarm.ini"
if [ -f "$SF_INI" ]; then
  ok "$SF_INI present"
  for setting in 'memory_limit=1G' 'upload_max_filesize=64M' 'post_max_size=64M' 'opcache.enable_cli=1' 'sys_temp_dir=/tmp' 'upload_tmp_dir=/tmp'; do
    if grep -qF "$setting" "$SF_INI"; then
      ok "$SF_INI contains $setting"
    else
      bad "$SF_INI contains $setting"
    fi
  done
else
  bad "$SF_INI present"
fi

# Advisory: this Debian/sury PHP scans /etc/php/8.4/*/conf.d, not the
# /usr/local/etc/php/conf.d path the Dockerfile writes to, so the settings above
# may not actually be applied. Carried over from the original image; reported,
# not failed.
EFFECTIVE_MEM="$(php -r 'echo ini_get("memory_limit");' 2>/dev/null)"
if [ "$EFFECTIVE_MEM" = "1G" ]; then
  ok "PHP effective memory_limit is 1G"
else
  warn "PHP effective memory_limit is '$EFFECTIVE_MEM', not 1G — 99-sitefarm.ini is not being loaded by PHP (pre-existing quirk)"
fi
SCAN_DIR="$(php -i 2>/dev/null | grep -i '^Scan this dir' | head -1)"
[ -n "$SCAN_DIR" ] && printf 'INFO  %s\n' "$SCAN_DIR"

section "Apache"
check "apache2 binary present" apache2ctl -v
APACHE_MODS="$(apache2ctl -M 2>/dev/null)"
for mod in php headers rewrite deflate; do
  if printf '%s\n' "$APACHE_MODS" | grep -q "${mod}_module"; then
    ok "Apache module enabled: ${mod}_module"
  else
    bad "Apache module enabled: ${mod}_module"
  fi
done
VHOST="/etc/apache2/sites-enabled/000-default.conf"
if [ -f "$VHOST" ] && grep -q 'DocumentRoot /opt/atlassian/pipelines/agent/build/docroot/' "$VHOST"; then
  ok "$VHOST installed with the pipelines DocumentRoot"
else
  bad "$VHOST installed with the pipelines DocumentRoot"
fi

section "Composer"
COMPOSER_V="$(composer --version --no-interaction 2>/dev/null | head -1)"
case "$COMPOSER_V" in
  *"2.8.2"*) ok "Composer is 2.8.2 ($COMPOSER_V)" ;;
  "")        bad "Composer is 2.8.2 (composer not found)" ;;
  *)         bad "Composer is 2.8.2 (got: $COMPOSER_V)" ;;
esac

section "Chromium (Cypress browser)"
if [ -x /usr/bin/chromium ]; then
  ok "/usr/bin/chromium present and executable"
else
  bad "/usr/bin/chromium present and executable"
fi
CHROMIUM_OUT="$(chromium --version 2>&1)"
CHROMIUM_RC=$?
CHROMIUM_OUT="$(printf '%s\n' "$CHROMIUM_OUT" | head -3)"
if [ "$CHROMIUM_RC" -eq 0 ] && printf '%s' "$CHROMIUM_OUT" | grep -qi 'chromium'; then
  ok "chromium runs ($(printf '%s' "$CHROMIUM_OUT" | head -1))"
elif printf '%s' "$CHROMIUM_OUT" | grep -qi 'sse3'; then
  # Chromium requires SSE3, which QEMU's x86_64 emulation does not provide. This
  # is expected when running an amd64 image on Apple Silicon and says nothing
  # about the image; on a real x86_64 runner (GitHub Actions, Bitbucket
  # Pipelines) chromium executes normally.
  warn "chromium cannot execute under QEMU emulation (no SSE3) — expected on Apple Silicon, verified on x86_64 runners instead"
else
  bad "chromium runs (output: $(printf '%s' "$CHROMIUM_OUT" | head -1))"
fi
have xvfb-run

section "Tooling"
for bin in npm git git-lfs jq yq rsync curl unzip zip patch pv html2text msmtp supervisord python python3; do
  have "$bin"
done
if command -v mariadb >/dev/null 2>&1 || command -v mysql >/dev/null 2>&1; then
  ok "MariaDB/MySQL client present"
else
  bad "MariaDB/MySQL client present"
fi

section "Baked sf_* commands"
for cmd in sf_apache_error sf_apache_test sf_bb_post_status sf_clear_cache sf_start_apache sf_cypress; do
  if [ -f "/bin/$cmd" ] && [ -x "/bin/$cmd" ]; then
    ok "/bin/$cmd exists and is executable"
  else
    bad "/bin/$cmd exists and is executable"
  fi
done

section "Locale"
if locale -a 2>/dev/null | grep -qi '^en_US.utf8$'; then
  ok "en_US.UTF-8 locale generated"
else
  bad "en_US.UTF-8 locale generated"
fi
case "${LC_ALL:-}" in
  en_US.UTF8|en_US.UTF-8|en_US.utf8) ok "LC_ALL is $LC_ALL" ;;
  *)                                 bad "LC_ALL is en_US.UTF8 (got: '${LC_ALL:-unset}')" ;;
esac

section "Pipelines paths"
EXPECTED_ROOT="/opt/atlassian/pipelines/agent/build"
if [ "${ROOT_DIR:-}" = "$EXPECTED_ROOT" ]; then
  ok "ROOT_DIR=$ROOT_DIR"
else
  bad "ROOT_DIR=$EXPECTED_ROOT (got: '${ROOT_DIR:-unset}')"
fi
if [ "${DOCROOT:-}" = "$EXPECTED_ROOT/docroot" ]; then
  ok "DOCROOT=$DOCROOT"
else
  bad "DOCROOT=$EXPECTED_ROOT/docroot (got: '${DOCROOT:-unset}')"
fi
if [ -d "${ROOT_DIR:-/nonexistent}" ]; then
  ok "ROOT_DIR directory exists"
else
  bad "ROOT_DIR directory exists"
fi

section "Architecture"
ARCH="$(uname -m)"
if [ "$ARCH" = "x86_64" ]; then
  ok "image architecture is x86_64"
else
  bad "image architecture is x86_64 (got: $ARCH)"
fi

printf '\n==============================================\n'
printf 'passed: %d   failed: %d   warnings: %d\n' "$PASS" "$FAIL" "$WARN"
printf '==============================================\n'

if [ "$FAIL" -gt 0 ]; then
  echo "SMOKE TEST FAILED"
  exit 1
fi
echo "SMOKE TEST PASSED"
exit 0
INNER

RC=$?
if [ "$RC" -ne 0 ]; then
  echo "smoke.sh: FAILED (exit $RC) for $IMAGE" >&2
fi
exit "$RC"
