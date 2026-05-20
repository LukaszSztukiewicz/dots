# shellcheck shell=bash
# Color helpers for dots install scripts. Source me, don't execute.
#
# Auto-disables colors when stdout is not a TTY or when NO_COLOR is set
# (https://no-color.org). DOTS_NO_COLOR=1 also forces plain output.

# Guard against double-sourcing.
if [ "${_DOTS_COLORS_SH:-0}" = "1" ]; then
    return 0 2>/dev/null || true
fi
_DOTS_COLORS_SH=1

if [ -t 1 ] && [ -z "${NO_COLOR:-}" ] && [ -z "${DOTS_NO_COLOR:-}" ]; then
    _c_reset=$'\033[0m'
    _c_bold=$'\033[1m'
    _c_red=$'\033[31m'
    _c_grn=$'\033[32m'
    _c_ylw=$'\033[33m'
    _c_blu=$'\033[34m'
    _c_cyn=$'\033[36m'
    _c_gry=$'\033[90m'
else
    _c_reset=
    _c_bold=
    _c_red=
    _c_grn=
    _c_ylw=
    _c_blu=
    _c_cyn=
    _c_gry=
fi

c_step() { printf '%s==>%s %s%s%s\n' "$_c_cyn" "$_c_reset" "$_c_bold" "$*" "$_c_reset"; }
c_info() { printf '%s[dots]%s %s\n' "$_c_blu" "$_c_reset" "$*"; }
c_ok()   { printf '%s[ ok ]%s %s\n' "$_c_grn" "$_c_reset" "$*"; }
c_warn() { printf '%s[warn]%s %s\n' "$_c_ylw" "$_c_reset" "$*" >&2; }
c_err()  { printf '%s[ERR ]%s %s\n' "$_c_red" "$_c_reset" "$*" >&2; }
error()  { c_err "$*"; exit 1; }
