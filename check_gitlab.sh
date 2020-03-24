#!/bin/bash

###############################################################################
#
# A simple Nagios/Icinga check for gitlab
#
# (c) Jan ' Kozo ' Vajda <Jan.Vajda@gmail.com>
#
###############################################################################

me="$(basename $0)"


usage () {
cat <<EOF
Usage: ${me} [options]

	Gitlab Naemon/Icinga/Nagios plugin which checks various stuff via
	Gitlab API(v4)

Options:
    -U, --URL ADDRESS                Gitlab address
    -t, --token TOKEN                Access token
    -s, --service NAME               Service name ("cache_check" "db_check" "gitaly_check" "master_check" "queues_check" "redis_check" "shared_state_check")
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

#
NOPROXY=0

## helper functions
die () {
  rc="$1"
  shift
  (echo -n "${me}: ERROR: ";
      if [ $# -gt 0 ]; then echo "$@"; else cat; fi) 1>&2
  exit $rc
}

warn () {
  (echo -n "${me}: WARNING: ";
      if [ $# -gt 0 ]; then echo "$@"; else cat; fi) 1>&2
}

have_command () {
  type "$1" >/dev/null 2>/dev/null
}

require_command () {
  if ! have_command "$1"; then
    die 1 "Could not find required command '$1' in system PATH. Aborting."
  fi
}

is_absolute_path () {
    expr match "$1" '/' >/dev/null 2>/dev/null
}


## parse command-line

short_opts='U:t:s:kxh'
long_opts='URL:,token:,service:,insecure,noproxy,help'

# test which `getopt` version is available:
# - GNU `getopt` will generate no output and exit with status 4
# - POSIX `getopt` will output `--` and exit with status 0
getopt -T > /dev/null
rc=$?
if [ "${rc}" -eq 4 ]; then
    # GNU getopt
    args=$(getopt --name "${me}" --shell sh -l "${long_opts}" -o "${short_opts}" -- "$@")
    if [ $? -ne 0 ]; then
        die 1 "Type '${me} --help' to get usage information."
    fi
    # use 'eval' to remove getopt quoting
    eval set -- ${args}
else
    # old-style getopt, use compatibility syntax
    args=$(getopt "${short_opts}" "$@")
    if [ $? -ne 0 ]; then
        die 1 "Type '${me} --help' to get usage information."
    fi
    set -- ${args}
fi

while [ $# -gt 0 ]; do
    case "$1" in
    	--URL|-U)	URL="$2"; shift;;
        --token|-t) 	TOKEN="$2"; shift ;;
        --service|-s) 	SERVICE="$2"; shift ;;
        --insecure|-k)  EXTRA_OPTS="-k";;
        --noproxy|-x)	NOPROXY=1;;
        --help|-h)    	usage; exit 0 ;;
        --)           	shift; break ;;
    esac
    shift
done


## main
require_command curl
require_command jq
require_command awk


FULLPATH="${URL}/-/readiness?all=1&token=${TOKEN}"

if [ ${NOPROXY} -gt 0 ]; then
  REMOTE=$(echo ${URL}| awk -F[/:] '{print $4}')
  PROXY_OPTS="--noproxy ${REMOTE}"
fi

JSON=$(curl ${PROXY_OPTS} ${EXTRA_OPTS} "${FULLPATH}" 2>/dev/null)
retval=$?
if [ ${retval} -gt 0 ]; then 
  die 1 "incorrect curl return code: ${retval}"
  exit
fi

KEYS=$(echo $JSON | jq --sort-keys 'keys'| jq -c '.[]')

ERRCODE=0

OUT=""

### master status
STATUS=$(echo ${JSON} | jq ".status")

# if OK, then skip
if [ -z ${SERVICE} ]; then
  OUT="status: ${STATUS},"
  
  if ! [[ ${STATUS} =~ "ok" ]]; then
    ((ERRCODE++))
  fi
fi

for key in ${KEYS}; do 

  ### skip master status
  if [[ ${key} =~ "status" ]]; then
    continue
  fi

  ### skip unless match SERVICE
  if [ ! -z ${SERVICE} ] && [[ ! ${key} == "\"${SERVICE}\"" ]]; then
    continue
  else
    ((HAS_SERVICE++))
  fi

  
  STATUS=$(echo ${JSON} | jq ".${key}[].status")
  
  # if not OK, then increment ERRCODE
  OUT="${OUT}${key}: ${STATUS},"
  if [[ ! ${STATUS} =~ "ok" ]]; then
   ((ERRCODE++))
  fi

done


if [ -z ${HAS_SERVICE} ]; then
  echo "CRITICAL - There is no service ${SERVICE}"
  exit ${CRITICAL}
fi

#echo "${OUT}"
if [ ${ERRCODE} -gt 0 ]; then
  echo "WARN - ${OUT}"
  exit ${WARN}
else
  echo "OK - ${OUT}"
  exit ${OK}
fi

