# check_gitlab

[![Security](https://github.com/kozliatko/check_gitlab/actions/workflows/security.yml/badge.svg)](https://github.com/kozliatko/check_gitlab/actions/workflows/security.yml)
[![ShellCheck](https://github.com/kozliatko/check_gitlab/actions/workflows/shellcheck.yml/badge.svg)](https://github.com/kozliatko/check_gitlab/actions/workflows/shellcheck.yml)
![Bash](https://img.shields.io/badge/Bash-4EAA25?logo=gnubash&logoColor=white)
![Nagios/Icinga](https://img.shields.io/badge/Nagios%2FIcinga-plugin-004357)
![License](https://img.shields.io/github/license/kozliatko/check_gitlab)
![Last commit](https://img.shields.io/github/last-commit/kozliatko/check_gitlab)

Pure bash/curl/jq/awk plugins for _nagios/icinga_ to check a self-managed GitLab:

- `check_gitlab.sh` - health of GitLab components (readiness endpoint)
- `check_gitlab_version.sh` - whether the installed GitLab version is up to date
- `check_gitlab_prometheus.sh` - firing alerts of the Prometheus bundled with Omnibus GitLab

`check_gitlab.sh` and `check_gitlab_version.sh` use the GitLab **health check access token**
(Admin area -> Monitoring -> Health check), or work without it when the
monitoring host is in the GitLab monitoring IP allowlist.
`check_gitlab_prometheus.sh` needs no token, it reads the Prometheus API.

--------------

## check_gitlab.sh

__Usage: check_gitlab.sh [options]__

	Gitlab Naemon/Icinga/Nagios plugin which checks various stuff via Gitlab API(v4)

Options:

  **-U, --URL ADDRESS**                Gitlab address

  **-t, --token TOKEN**                Access token

  **-s, --service NAME**               Service name ("cache_check" "db_check" "gitaly_check" "master_check" "queues_check" "shared_state_check" "rate_limiting_check" "sessions_check" "trace_chunks_check" ...)

  **-k, --insecure**                   No ssl verification

  **-x, --noproxy**                    No connect over proxy

  **-h, --help**                       Show this help message

The plugin reads `/-/readiness?all=1`. Without `-s` it checks the overall
status and all sub-checks, with `-s` only the given sub-check. The available
sub-check names depend on the GitLab version, see the output without `-s`.

| result | state |
|---|---|
| all checked statuses are `ok` | OK |
| a checked status is not `ok` | WARNING |
| `-s` names a sub-check that GitLab does not report | CRITICAL |
| GitLab unreachable, or the response is not readiness JSON (e.g. HTTP 502 during restart) | CRITICAL |

Example:

```
$ check_gitlab.sh -U https://gitlab.example.com -k -x -t <token> -s db_check
OK - "db_check": "ok",
```

## check_gitlab_version.sh

__Usage: check_gitlab_version.sh [options]__

	Gitlab Naemon/Icinga/Nagios plugin which checks whether the installed
	GitLab version is up to date (via version.gitlab.com)

Options:

  **-U, --URL ADDRESS**                Gitlab address

  **-t, --token TOKEN**                Health check access token

  **-k, --insecure**                   No ssl verification

  **-x, --noproxy**                    No connect over proxy

  **-h, --help**                       Show this help message

The installed version is read from `/-/metrics` (metric `deployments`), no API
token is needed. The version is then evaluated by `https://version.gitlab.com/check.json`,
the same service the GitLab admin area uses for its version check. The monitoring
host therefore needs outgoing HTTPS access to version.gitlab.com.

| version.gitlab.com | state | meaning |
|---|---|---|
| `success` | OK | installed version is up to date |
| `warning` | WARNING | a newer version is available |
| `danger` | CRITICAL | security update required |
| no answer / no version | UNKNOWN | `/-/metrics` or version.gitlab.com unreachable |

Example:

```
$ check_gitlab_version.sh -U https://gitlab.example.com -k -x -t <token>
OK - GitLab 19.5.1-ee is up to date (latest 19.5.1)
```

Running it once a day is enough.

## check_gitlab_prometheus.sh

__Usage: check_gitlab_prometheus.sh [options]__

	Gitlab Naemon/Icinga/Nagios plugin which reports the firing alerts
	of the Prometheus bundled with Omnibus GitLab

Options:

  **-U, --URL ADDRESS**                Prometheus address (default `http://127.0.0.1:9090`)

  **-c, --critical "NAMES"**           Alerts reported as CRITICAL, the others are WARNING
                                     (default `"ServiceDown RedisDown PostgresDown FilesystemAlmostFull"`)

  **-k, --insecure**                   No ssl verification

  **-x, --noproxy**                    No connect over proxy

  **-h, --help**                       Show this help message

Omnibus GitLab ships Prometheus with alerting rules (`ServiceDown`, `RedisDown`,
`PostgresDown`, `PumaQueueing`, `HighPumaUtilization`, `SidekiqJobsQueuing`,
`HighgRPCResourceExhaustedRate`, `PostgresDatabaseDeadlocks`, `WorkhorseHighErrorRate`,
`FilesystemAlmostFull`, `FilesystemFullIn1Day`, ...), but the bundled alertmanager
sends them nowhere. The plugin reads the firing alerts
(`ALERTS{alertstate="firing"}`, so the `for` duration of a rule is already applied)
and reports them with the labels that tell them apart (`job`, `name`, `route`,
`mountpoint`, `datname`).

| result | state |
|---|---|
| no firing alert | OK |
| a firing alert, none of them in the `-c` list | WARNING |
| a firing alert from the `-c` list | CRITICAL |
| Prometheus unreachable, or no alerting rules loaded | UNKNOWN |

Perfdata (also in the OK output): Puma utilization and queued connections,
Rails 5xx ratio and p95 latency over 15 minutes, Gitaly gRPC errors per second
(`Internal`, `Unavailable`, `ResourceExhausted`, `DeadlineExceeded`, `Unknown`),
PostgreSQL connections and `max_connections`.

Example:

```
$ check_gitlab_prometheus.sh
OK - no firing alert: 13 rules, Puma 0% (queue 0), 5xx 0%, p95 0.496s, PostgreSQL 28/400 connections | puma_util=0% puma_queue=0 rails_5xx=0% rails_p95=0.496s gitaly_errors=0 pg_connections=28;;;0;400
```

The bundled Prometheus listens on `localhost:9090` only, so the plugin runs on the
GitLab host and Nagios gets the result e.g. via NRPE or an SNMP extend:

```
# /etc/snmp/snmpd.conf on the GitLab host
extend gitlabprom /usr/local/bin/check_gitlab_prometheus.sh
```

`WorkhorseHighErrorRate` has no `for` duration and fires on short bursts of errors
(e.g. on `/info/refs` or `/-/cable`); a service with `max_check_attempts 3` usually
keeps such bursts in a SOFT state.

## Nagios configuration

```
define command {
	command_name		check_gitlab
	command_line		$USER1$/check_gitlab.sh -U https://$HOSTADDRESS$ -k -x -t $_HOSTGITLABTOKEN$ -s "$ARG1$"
}

define command {
	command_name		check_gitlab_version
	command_line		$USER1$/check_gitlab_version.sh -U https://$HOSTADDRESS$ -k -x -t $_HOSTGITLABTOKEN$
}

define service {
	use			generic-service
	host_name		gitlab
	service_description	gitlab-db
	check_command		check_gitlab!db_check
}

define service {
	use			generic-service
	host_name		gitlab
	service_description	gitlab-version
	check_command		check_gitlab_version
	check_interval		1440
	retry_interval		60
}
```

The token is kept as the custom host variable `_GITLABTOKEN`.

`check_gitlab_prometheus.sh` through an SNMP extend (see above), with the
`check_snmp_extend` plugin that maps the `OK`/`WARNING`/`CRITICAL`/`UNKNOWN`
prefix of the first line to the state:

```
define service {
	use			generic-service
	host_name		gitlab
	service_description	gitlab-prometheus-alerts
	check_command		check_snmp_extend!gitlabprom
}
```

Requirements: bash, curl, jq, awk, base64 (`check_gitlab_prometheus.sh`: curl, jq, awk).

--------------

_If the plugin doesn't work, you have patches or want to suggest improvements
you are [welcome](https://github.com/kozliatko/check_gitlab/issues).
Please include version information with all correspondence_
