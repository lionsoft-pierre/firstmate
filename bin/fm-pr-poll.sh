#!/usr/bin/env bash
# Static watcher program for a validated PR/MR poll sidecar.
# It emits exactly one terminal-outcome line for a PR or MR that has reached one
# and stays silent otherwise, including on every error, so a failed lookup can
# never be read as a merge.
# The provider-tagged identity is data in the sidecar and is never interpolated
# into this source: these bytes are identical for every task.
# Each provider is read through its own standard CLI, gh for GitHub and glab
# for GitLab, so an upstream checkout needs no extra tooling to follow either.
# Bitbucket Cloud has no such CLI and is read over REST 2.0 with curl. Its
# credentials are resolved here rather than stored in the sidecar, and the API
# token is handed to curl on stdin so it never appears in any argument list.
# This program is copied verbatim into every task's check, so it sources
# nothing: the validation and the credential read below are deliberately
# self-contained rather than shared with bin/fm-pr-lib.sh.
#
# Output is one terminal word or nothing: "merged" for a landed change, and
# "declined" or "superseded" for Bitbucket's terminal non-merge outcomes, which
# firstmate retires rather than polling forever. Silence means "not terminal
# yet", which is also what every error produces.
set -u
LC_ALL=C
export LC_ALL

if [ "$#" -eq 6 ] && [ "$1" = --validated ]; then
  provider=$2
  url=$3
  host=$4
  path=$5
  number=$6
elif [ "$#" -eq 0 ]; then
  case "$0" in
    *.check.sh) data=${0%.check.sh}.pr-poll ;;
    *) exit 0 ;;
  esac

  [ -f "$data" ] && [ ! -L "$data" ] || exit 0
  { exec 3< "$data"; } 2>/dev/null || exit 0
  IFS= read -r provider <&3 || exit 0
  IFS= read -r url <&3 || exit 0
  IFS= read -r host <&3 || exit 0
  IFS= read -r path <&3 || exit 0
  IFS= read -r number <&3 || exit 0
  if IFS= read -r _extra <&3; then
    exit 0
  fi
  exec 3<&-
else
  exit 0
fi

case "$number" in
  [1-9]*) ;;
  *) exit 0 ;;
esac
case "$number" in
  *[!0-9]*) exit 0 ;;
esac

# Every component is revalidated here rather than trusted from the sidecar, and
# the stored URL must then be exactly reconstructible from those components, so
# a doctored sidecar cannot redirect this poll at another host or project.
case "$provider" in
  github)
    [ "$host" = github.com ] || exit 0
    owner=${path%%/*}
    repo=${path#*/}
    [ "${#owner}" -ge 1 ] && [ "${#owner}" -le 39 ] || exit 0
    case "$owner" in
      *[!A-Za-z0-9-]*|-*|*-|*--*) exit 0 ;;
    esac
    [ "${#repo}" -ge 1 ] && [ "${#repo}" -le 100 ] || exit 0
    case "$repo" in
      .|..|*[!A-Za-z0-9._-]*) exit 0 ;;
    esac
    [ "$url" = "https://github.com/$owner/$repo/pull/$number" ] || exit 0
    state=$(gh pr view "$url" --json state -q .state 2>/dev/null) || exit 0
    [ "$state" = MERGED ] && printf '%s\n' merged
    ;;
  gitlab)
    [ "${#host}" -ge 1 ] && [ "${#host}" -le 253 ] || exit 0
    [ "$host" != github.com ] || exit 0
    case "$host" in
      .*|*.|*..*|*[!a-z0-9.-]*) exit 0 ;;
    esac
    [ "${#path}" -ge 3 ] && [ "${#path}" -le 1024 ] || exit 0
    case "$path" in
      /*|*/|*//*) exit 0 ;;
    esac
    # A GitLab project sits under at least one group at no fixed depth, and
    # GitLab reserves the "-" segment as its route separator.
    rest=$path
    segments=0
    while [ -n "$rest" ]; do
      case "$rest" in
        */*) segment=${rest%%/*}; rest=${rest#*/} ;;
        *) segment=$rest; rest= ;;
      esac
      segments=$((segments + 1))
      [ "$segments" -le 20 ] || exit 0
      [ "${#segment}" -ge 1 ] && [ "${#segment}" -le 255 ] || exit 0
      case "$segment" in
        .|..|-*|*.git|*.atom|*[!A-Za-z0-9._-]*) exit 0 ;;
      esac
    done
    [ "$segments" -ge 2 ] || exit 0
    [ "$url" = "https://$host/$path/-/merge_requests/$number" ] || exit 0
    # glab resolves the instance from the project URL passed to -R, so the host
    # comes from the validated record rather than glab's configured default.
    # It cannot take a merge request URL the way gh does: that form shells out
    # to git for the current repository, and the watcher runs in no repository.
    # The state is read from glab's own field output rather than its JSON,
    # because plain glab has no field selector and firstmate does not require a
    # JSON processor; only an exact "merged" wakes, so a changed format or an
    # unreadable merge request stays silent instead of reporting a merge.
    raw=$(glab mr view "$number" -R "https://$host/$path" 2>/dev/null) || exit 0
    state=$(printf '%s\n' "$raw" | sed -n 's/^state:[[:space:]]*//p' | head -1) || exit 0
    [ "$state" = merged ] && printf '%s\n' merged
    ;;
  bitbucket)
    [ "$host" = bitbucket.org ] || exit 0
    workspace=${path%%/*}
    repo=${path#*/}
    case "$path" in
      */*/*) exit 0 ;;
    esac
    for slug in "$workspace" "$repo"; do
      [ "${#slug}" -ge 1 ] && [ "${#slug}" -le 100 ] || exit 0
      case "$slug" in
        .|..|*[!A-Za-z0-9._-]*) exit 0 ;;
      esac
    done
    [ "$url" = "https://bitbucket.org/$workspace/$repo/pull-requests/$number" ] || exit 0
    command -v curl >/dev/null 2>&1 || exit 0

    # Credentials: the environment first, then the file named by
    # FM_BITBUCKET_CREDENTIALS, then config/bitbucket-credentials in the home
    # this check was published into. docs/configuration.md owns the setting.
    email=${BITBUCKET_EMAIL:-}
    token=${BITBUCKET_API_TOKEN:-}
    if [ -z "$email" ] || [ -z "$token" ]; then
      credfile=${FM_BITBUCKET_CREDENTIALS:-}
      if [ -z "$credfile" ]; then
        if [ -n "${FM_CONFIG_OVERRIDE:-}" ]; then
          setting="$FM_CONFIG_OVERRIDE/bitbucket-credentials"
        elif [ -n "${FM_HOME:-}" ]; then
          setting="$FM_HOME/config/bitbucket-credentials"
        else
          case "$0" in
            */*.check.sh) setting="$(dirname "$(dirname "$0")")/config/bitbucket-credentials" ;;
            *) setting= ;;
          esac
        fi
        [ -n "$setting" ] && [ -f "$setting" ] && [ ! -L "$setting" ] || exit 0
        IFS= read -r credfile < "$setting" || exit 0
        credfile=${credfile%$'\r'}
        credfile=${credfile#"${credfile%%[![:space:]]*}"}
        credfile=${credfile%"${credfile##*[![:space:]]}"}
        # A leading "~/" in the setting is the literal path prefix a captain writes,
        # expanded here because no shell expanded it on the way in.
        # shellcheck disable=SC2088
        if [ "${credfile:0:2}" = "~/" ]; then
          credfile="$HOME/${credfile:2}"
        fi
      fi
      [ -n "$credfile" ] && [ -f "$credfile" ] && [ ! -L "$credfile" ] || exit 0
      email=
      token=
      while IFS= read -r line || [ -n "$line" ]; do
        case "$line" in
          BITBUCKET_EMAIL=*) email=${line#BITBUCKET_EMAIL=} ;;
          BITBUCKET_API_TOKEN=*) token=${line#BITBUCKET_API_TOKEN=} ;;
        esac
      done < "$credfile"
      case "$email" in '"'*'"') email=${email#\"}; email=${email%\"} ;; esac
      case "$token" in '"'*'"') token=${token#\"}; token=${token%\"} ;; esac
    fi
    # A quote, a backslash, or a control character cannot appear in a real
    # email or API token and would change how curl reads its configuration, so
    # such a value is refused rather than escaped.
    for value in "$email" "$token"; do
      [ "${#value}" -ge 1 ] && [ "${#value}" -le 1024 ] || exit 0
      case "$value" in
        *'"'*|*\\*|*[[:cntrl:]]*) exit 0 ;;
      esac
    done

    # The partial-response selector keeps the body to the single field asked
    # for, so a nested object elsewhere in the resource cannot supply a second
    # reading of "state".
    # The API host is a constant here rather than a setting: this request
    # carries the credential, so nothing in the environment may redirect it.
    body=$(printf 'url = "https://api.bitbucket.org/2.0/repositories/%s/%s/pullrequests/%s?fields=state"\nuser = "%s:%s"\nsilent\nshow-error\nfail\nmax-time = 20\n' \
      "$workspace" "$repo" "$number" "$email" "$token" \
      | curl --config - 2>/dev/null) || exit 0
    [ "$(printf '%s' "$body" | grep -o '"state"[[:space:]]*:' | wc -l | tr -d '[:space:]')" = 1 ] || exit 0
    state=$(printf '%s' "$body" | sed -n 's/.*"state"[[:space:]]*:[[:space:]]*"\([A-Z]*\)".*/\1/p' | head -1)
    case "$state" in
      MERGED) printf '%s\n' merged ;;
      DECLINED) printf '%s\n' declined ;;
      SUPERSEDED) printf '%s\n' superseded ;;
    esac
    ;;
  *) exit 0 ;;
esac
exit 0
