#!/bin/bash
#
#
# A simple "hello world" Nagios/Icinga check, to be used as a
# template for writing other and more complex ones.
#

me="$(basename $0)"


usage () {
cat <<EOF
Usage: $me [options]

	Gitlab Naemon/Icinga/Nagios plugin which checks various stuff via
	Gitlab API(v4)

Options:
    -U, --URL ADDRESS                Gitlab address
    -t, --token TOKEN                Access token
    -k, --insecure                   No ssl verification
    -h, --help                       Show this help message

EOF
}


## exit statuses recognized by Nagios
OK=0
WARNING=1
CRITICAL=2
UNKNOWN=3


## helper functions
die () {
  rc="$1"
  shift
  (echo -n "$me: ERROR: ";
      if [ $# -gt 0 ]; then echo "$@"; else cat; fi) 1>&2
  exit $rc
}

warn () {
  (echo -n "$me: WARNING: ";
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

short_opts='U:t:kh'
long_opts='URL:,token:,insecure,help'

# test which `getopt` version is available:
# - GNU `getopt` will generate no output and exit with status 4
# - POSIX `getopt` will output `--` and exit with status 0
getopt -T > /dev/null
rc=$?
if [ "$rc" -eq 4 ]; then
    # GNU getopt
    args=$(getopt --name "$me" --shell sh -l "$long_opts" -o "$short_opts" -- "$@")
    if [ $? -ne 0 ]; then
        die 1 "Type '$me --help' to get usage information."
    fi
    # use 'eval' to remove getopt quoting
    eval set -- $args
else
    # old-style getopt, use compatibility syntax
    args=$(getopt "$short_opts" "$@")
    if [ $? -ne 0 ]; then
        die 1 "Type '$me --help' to get usage information."
    fi
    set -- $args
fi

while [ $# -gt 0 ]; do
    case "$1" in
    	--URL|-U)	URL="$2"; shift;;
        --token|-t) 	TOKEN="$2"; shift ;;
        --help|-h)    	usage; exit 0 ;;
        --insecure|-k)   EXTRA_OPTS="-k"; shift ;;
        --)           	shift; break ;;
    esac
    shift
done


## main
require_command curl
require_command jq

#TOKEN="N3BkyY_xNLiAhrJs_Wes"

FULLPATH="${URL}/-/readiness?all=1&token=${TOKEN}"
#curl ${CURLOPTS} ${FULLPATH} 2>/dev/null | jq

JSON=$(curl --noproxy "*" ${EXTRA_OPTS} "${FULLPATH}" 2>/dev/null)
retval=$?
if [ ${retval} -gt 0 ]; then 
  die 1 "incorrect curl return code: ${retval}"
  exit
fi

KEYS=$(echo $JSON | jq --sort-keys 'keys'| jq -c '.[]')
#echo ${JSON}
#echo ${KEYS}

ERRCODE=0

### master status
STATUS=$(echo ${JSON} | jq ".status")

# if OK, then skip
OUT="status: ${STATUS}"
if ! [[ ${STATUS} =~ "ok" ]]; then
 ((ERRCODE++))
fi

for key in ${KEYS}; do 

  ### skip master status
  if [[ ${key} =~ "status" ]]; then
    continue
  fi
  
  STATUS=$(echo ${JSON} | jq ".${key}[].status")
  
  # if OK, then skip
  OUT="${OUT},${key}: ${STATUS}"
  if [[ ${STATUS} =~ "ok" ]]; then
   continue
  else
   ((ERRCODE++))
  fi

done


#echo "${OUT}"
if [ ${ERRCODE} -gt 0 ]; then
  echo "WARN - ${OUT}"
  exit ${WARN}
else
  echo "OK - ${OUT}"
  exit ${OK}
fi

