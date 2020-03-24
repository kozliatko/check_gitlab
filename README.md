# check_gitlab

This is a pure bash/curl/jq/awk plugin for _nagios/icinga_ to check health of gitlab

--------------

__Usage: check_gitlab.sh [options]

Gitlab Naemon/Icinga/Nagios plugin which checks various stuff via Gitlab API(v4)

Options:
  **-U, --URL ADDRESS**                Gitlab address
  **-t, --token TOKEN**                Access token
  **-s, --service NAME**               Service name ("cache_check" "db_check" "gitaly_check" "master_check" "queues_check" "redis_check" "shared_state_check")
  **-k, --insecure**                   No ssl verification
  **-x, --noproxy**                    No connect over proxy
  **-h, --help**                       Show this help message

--------------

_If the plugin doesn't work, you have patches or want to suggest improvements
you are [welcome](https://github.com/kozliatko/check_gitlab/issues).
Please include version information with all correspondence_

