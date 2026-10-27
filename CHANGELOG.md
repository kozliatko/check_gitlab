# Changelog

All notable changes to this project are documented in this file.
The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).
The project has no version numbers, entries are grouped by date.

## 2026-10-27

### Added
- `check_gitlab_prometheus.sh`: reports the firing alerts of the Prometheus
  bundled with Omnibus GitLab (`ALERTS{alertstate="firing"}`), whose alertmanager
  sends them nowhere. Alerts from the `-c` list (default `ServiceDown`,
  `RedisDown`, `PostgresDown`, `FilesystemAlmostFull`) are CRITICAL, the others
  WARNING; Prometheus unreachable or without alerting rules is UNKNOWN. Perfdata:
  Puma utilization and queue, Rails 5xx ratio and p95 latency, Gitaly errors,
  PostgreSQL connections.
- README: documentation of `check_gitlab_prometheus.sh` and an SNMP extend
  example.

## 2026-10-22

### Added
- `check_gitlab_version.sh`: checks whether the installed GitLab version is up
  to date. The version is read from `/-/metrics` (metric `deployments`) with the
  health check token and evaluated by version.gitlab.com like the GitLab admin
  area: `success` OK, `warning` WARNING (newer version available), `danger`
  CRITICAL (security update required), no answer UNKNOWN.
- README: documentation of both plugins, state tables and a Nagios
  configuration example.

### Fixed
- `check_gitlab.sh`: a failed sub-check was reported as OK. The plugin printed
  `WARN - ...` but exited with the undefined `${WARN}`, i.e. exit code 0; it now
  exits with WARNING (1).
- `check_gitlab.sh`: an unreachable GitLab (curl error, HTTP 502 page during
  restart, empty response) is reported as `CRITICAL - GitLab unreachable`
  instead of the misleading `CRITICAL - There is no service ...`. A readiness
  response with HTTP 503 and valid JSON (failed sub-check) is still evaluated
  per sub-check.
- `check_gitlab.sh`: curl has a 10 s timeout, the previous version could hang
  until Nagios killed the check.

### Changed
- `check_gitlab.sh`: help lists the current readiness sub-check names
  (`rate_limiting_check`, `sessions_check`, `trace_chunks_check`, ...),
  `redis_check` was removed from the list.

## 2026-08-31

### Changed
- CI: `actions/checkout` bumped from 4 to 7 in the ShellCheck workflow
  (Dependabot, #3).

## 2026-08-20

### Changed
- CI: `actions/checkout` bumped from 4 to 7 in the security workflow
  (Dependabot, #2).

## 2026-08-09

### Added
- CI: ShellCheck workflow (errors only) and README badge.
- CI: Dependabot configuration for GitHub Actions.

## 2026-08-07

### Added
- CI: security workflow with gitleaks secret scanning, configuration and
  README badge.

## 2026-08-06

### Added
- MIT license.
- README: status badges.

## 2020-03-24

### Added
- `check_gitlab.sh`: `-s, --service` option to check a single readiness
  sub-check, so every GitLab component can be a separate Nagios service.
- `check_gitlab.sh`: `-x, --noproxy` option to bypass the proxy for the GitLab
  host.

### Changed
- README: formatted usage.

## 2020-02-28

### Added
- `check_gitlab.sh`: first working version. Checks GitLab health via
  `/-/readiness?all=1`, options `-U`, `-t`, `-k`.
