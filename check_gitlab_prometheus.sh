#!/bin/bash

###############################################################################
#
# A simple Nagios/Icinga check of the alerts of the GitLab bundled Prometheus
#
# (c) Jan ' Kozo ' Vajda <Jan.Vajda@gmail.com>
#
# Omnibus GitLab ships Prometheus with alerting rules (ServiceDown,
# PostgresDown, PumaQueueing, FilesystemFullIn1Day, ...), but the bundled
# alertmanager sends them nowhere. This plugin reports the firing alerts
# (ALERTS{alertstate="firing"}, the "for" of a rule already applied):
#   firing alert from the critical list -> CRITICAL, any other -> WARNING,
#   Prometheus unreachable or without alerting rules -> UNKNOWN
# Perfdata: Puma utilization and queue, Rails 5xx ratio and p95 latency,
# Gitaly errors, PostgreSQL connections.
#
# Prometheus listens on localhost:9090 by default, so the plugin usually runs
# on the GitLab host (e.g. as an SNMP extend or via NRPE).
#
###############################################################################

me="$(basename "$0")"

usage () {
cat <<EOF
Usage: ${me} [options]

	Gitlab Naemon/Icinga/Nagios plugin which reports the firing alerts
	of the Prometheus bundled with Omnibus GitLab

Options:
    -U, --URL ADDRESS                Prometheus address (default ${URL})
    -c, --critical "NAMES"           Alerts reported as CRITICAL, the others are WARNING
                                     (default "${CRIT_ALERTS}")
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

URL="http://127.0.0.1:9090"
CRIT_ALERTS="ServiceDown RedisDown PostgresDown FilesystemAlmostFull"
NOPROXY=0

while [ $# -gt 0 ]; do
    case "$1" in
        --URL|-U)       URL="$2"; shift;;
        --critical|-c)  CRIT_ALERTS="$2"; shift;;
        --insecure|-k)  EXTRA_OPTS="-k";;
        --noproxy|-x)   NOPROXY=1;;
        --help|-h)      usage; exit 0 ;;
        *)              usage; exit ${UNKNOWN} ;;
    esac
    shift
done

for c in curl jq awk; do
  if ! type "$c" >/dev/null 2>&1; then
    echo "UNKNOWN - required command '$c' not found"
    exit ${UNKNOWN}
  fi
done

if [ ${NOPROXY} -gt 0 ]; then
  REMOTE=$(echo "${URL}" | awk -F[/:] '{print $4}')
  PROXY_OPTS="--noproxy ${REMOTE}"
fi

api () {
  # shellcheck disable=SC2086
  curl -s --max-time 5 ${PROXY_OPTS} ${EXTRA_OPTS} "${URL}/api/v1/$1" "${@:2}" 2>/dev/null
}

## one value of a PromQL query (empty result or NaN = 0), empty string on error;
## LC_ALL=C: with a decimal comma locale awk would read 0.48 as 0
q () {
  api query --data-urlencode "query=$1" \
    | jq -r 'select(.status == "success") | .data.result[0].value[1] // "0"' 2>/dev/null \
    | LC_ALL=C awk '{ v = ($1 ~ /^[-+]?[0-9.eE+-]+$/) ? $1 + 0 : 0; printf "%g\n", int(v * 1000 + 0.5) / 1000 }'
}

## alerting rules loaded
RULES=$(api "rules?type=alert" | jq -r '[.data.groups[].rules[]] | length' 2>/dev/null)
if [ -z "${RULES}" ]; then
  echo "UNKNOWN - Prometheus (${URL}) unreachable"
  exit ${UNKNOWN}
fi
if [ "${RULES}" -eq 0 ]; then
  echo "UNKNOWN - Prometheus has no alerting rules loaded"
  exit ${UNKNOWN}
fi

## firing alerts: "name<TAB>name{distinguishing labels}", each once
ALERTS=$(api query --data-urlencode 'query=ALERTS{alertstate="firing"}' | jq -r '
  .data.result[].metric | . as $m
  | [["job", "name", "route", "mountpoint", "datname"][] | select(($m[.] // "") != "") | "\(.)=\($m[.])"]
  | join(",") as $lab
  | "\($m.alertname)\t\($m.alertname)\(if $lab != "" then "{" + $lab + "}" else "" end)"' 2>/dev/null | sort -u)

PUMA_UTIL=$(q 'max(instance:puma_utilization:ratio) * 100')
PUMA_QUEUE=$(q 'max(puma_queued_connections)')
ERR5XX=$(q '100 * sum(rate(http_requests_total{job="gitlab-rails",status="5xx"}[15m])) / sum(rate(http_requests_total{job="gitlab-rails"}[15m]))')
P95=$(q 'histogram_quantile(0.95, sum by (le) (rate(http_request_duration_seconds_bucket{job="gitlab-rails"}[15m])))')
GITALY_ERR=$(q 'sum(rate(grpc_server_handled_total{job="gitaly",grpc_code=~"Internal|Unavailable|ResourceExhausted|DeadlineExceeded|Unknown"}[15m]))')
PG_CONN=$(q 'sum(pg_stat_activity_count)')
PG_MAX=$(q 'max(pg_settings_max_connections)')

PERF="puma_util=${PUMA_UTIL}% puma_queue=${PUMA_QUEUE} rails_5xx=${ERR5XX}% rails_p95=${P95}s gitaly_errors=${GITALY_ERR} pg_connections=${PG_CONN};;;0;${PG_MAX}"
INFO="${RULES} rules, Puma ${PUMA_UTIL}% (queue ${PUMA_QUEUE}), 5xx ${ERR5XX}%, p95 ${P95}s, PostgreSQL ${PG_CONN}/${PG_MAX} connections"

if [ -z "${ALERTS}" ]; then
  echo "OK - no firing alert: ${INFO} | ${PERF}"
  exit ${OK}
fi

LIST=$(echo "${ALERTS}" | cut -f2 | paste -sd ' ')
for a in $(echo "${ALERTS}" | cut -f1); do
  case " ${CRIT_ALERTS} " in
    *" ${a} "*)
      echo "CRITICAL - ${LIST}: ${INFO} | ${PERF}"
      exit ${CRITICAL} ;;
  esac
done
echo "WARNING - ${LIST}: ${INFO} | ${PERF}"
exit ${WARNING}
