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

Both plugins use the GitLab **health check access token**
(Admin area -> Monitoring -> Health check), or work without it when the
monitoring host is in the GitLab monitoring IP allowlist.

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

Requirements: bash, curl, jq, awk, base64.

--------------

_If the plugin doesn't work, you have patches or want to suggest improvements
you are [welcome](https://github.com/kozliatko/check_gitlab/issues).
Please include version information with all correspondence_
