#!/bin/bash

###############################################################################
#
# A simple Nagios/Icinga check whether GitLab is up to date
#
# (c) Jan ' Kozo ' Vajda <Jan.Vajda@gmail.com>
#
# The installed version is read from /-/metrics (metric "deployments", same
# health check token as /-/readiness). The evaluation is done by
# version.gitlab.com, the same service the GitLab admin area uses:
#   success -> OK, warning -> WARNING (newer version available),
#   danger  -> CRITICAL (security update required)
#
###############################################################################

me="$(basename $0)"

usage () {
cat <<EOF
Usage: ${me} [options]

	Gitlab Naemon/Icinga/Nagios plugin which checks whether the installed
	GitLab version is up to date (via version.gitlab.com)

Options:
    -U, --URL ADDRESS                Gitlab address
    -t, --token TOKEN                Health check access token
    -k, --insecure                   No ssl verification
    -x, --noproxy                    No connect over proxy
    -h, --help                       Show this help message

EOF
}

## exit statuses recognized by Nagios
OK=0
WARNING=1
CRITICAL=2
UNKNOWN=3

NOPROXY=0
CHECK_URL="https://version.gitlab.com/check.json"

while [ $# -gt 0 ]; do
    case "$1" in
        --URL|-U)       URL="$2"; shift;;
        --token|-t)     TOKEN="$2"; shift ;;
        --insecure|-k)  EXTRA_OPTS="-k";;
        --noproxy|-x)   NOPROXY=1;;
        --help|-h)      usage; exit 0 ;;
        *)              usage; exit ${UNKNOWN} ;;
    esac
    shift
done

if [ -z "${URL}" ] || [ -z "${TOKEN}" ]; then
  usage
  exit ${UNKNOWN}
fi

for c in curl jq base64 awk; do
  if ! type "$c" >/dev/null 2>&1; then
    echo "UNKNOWN - required command '$c' not found"
    exit ${UNKNOWN}
  fi
done

if [ ${NOPROXY} -gt 0 ]; then
  REMOTE=$(echo ${URL}| awk -F[/:] '{print $4}')
  PROXY_OPTS="--noproxy ${REMOTE}"
fi

## installed version
METRICS=$(curl -s --max-time 30 ${PROXY_OPTS} ${EXTRA_OPTS} "${URL}/-/metrics?token=${TOKEN}" 2>/dev/null)
retval=$?
if [ ${retval} -gt 0 ]; then
  echo "UNKNOWN - GitLab /-/metrics unreachable (curl return code: ${retval})"
  exit ${UNKNOWN}
fi

# after an upgrade without restart there may be more lines, take the highest version
FULLVER=$(echo "${METRICS}" | sed -n 's/^deployments{.*version="\([^"]*\)".*/\1/p' | sort -V | tail -1)
VERSION=${FULLVER%%-*}
if ! [[ ${VERSION} =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "UNKNOWN - could not get GitLab version from /-/metrics"
  exit ${UNKNOWN}
fi

## evaluation by version.gitlab.com
INFO=$(printf '{"version":"%s"}' "${VERSION}" | base64 -w0)
JSON=$(curl -s --max-time 20 "${CHECK_URL}?gitlab_info=${INFO}" 2>/dev/null)
# jq 1.6 returns 0 on empty input, hence the explicit empty test
if [ -z "${JSON}" ] || ! echo "${JSON}" | jq -e 'type == "object" and has("severity")' >/dev/null 2>&1; then
  echo "UNKNOWN - GitLab ${FULLVER}, version.gitlab.com not responding"
  exit ${UNKNOWN}
fi

SEVERITY=$(echo "${JSON}" | jq -r '.severity')
LATEST=$(echo "${JSON}" | jq -r '.latest_version // "?"')
STABLE=$(echo "${JSON}" | jq -r '(.latest_stable_versions // []) | join(", ")')

case "${SEVERITY}" in
  success)
    echo "OK - GitLab ${FULLVER} is up to date (latest ${LATEST})"
    exit ${OK} ;;
  warning)
    echo "WARNING - GitLab ${FULLVER}, newer version ${LATEST} available (current releases: ${STABLE})"
    exit ${WARNING} ;;
  danger)
    echo "CRITICAL - GitLab ${FULLVER} requires a security update, latest ${LATEST} (current releases: ${STABLE})"
    exit ${CRITICAL} ;;
  *)
    echo "UNKNOWN - GitLab ${FULLVER}, unknown version check result: ${SEVERITY}"
    exit ${UNKNOWN} ;;
esac
