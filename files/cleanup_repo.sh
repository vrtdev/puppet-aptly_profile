#!/bin/bash
## File managed by puppet
# * module: aptly_profile
# * file: repo_cleanup.sh

#
# Removes old packages in the received repo
#
# $1: Repository
# $2: Amount of packages to keep
# $3: How many days of package history to keep

set -o errexit # exit on command failure
set -o pipefail # pipes fail when any command fails, not just the last one
set -o nounset # exit on use of undeclared var
#set -o xtrace

## Presets
PACKAGE=all
KEEP=15
DAYS=3650
FILE_PATH="/data/aptly/public"
PRECMD=""

## Functions
_help() {
	cat - <<EOHELP
USAGE:
$0 <options>

OPTIONS:
-r, --repository    Repository to clean up (Required)

-p, --package       Name of the package to cleanup, (default: all)
-k, --keep          Number of versions of a package to keep (default: ${KEEP})
-d, --days          Cleanup packages older than this amount of days (default: ${DAYS})
-n, --noop          Do a dry run with verbose output

-h, --help          This help message.
EOHELP
}

## Cleanup repo
cleanup() {
  local REPO=$1
  local PKG_NAME=$2
  local PKG_VERSION=$3

  ${PRECMD} aptly repo remove ${REPO} "Name (${PKG_NAME}), Version (<= ${PKG_VERSION})"
  DELETED='yes'
}

## Helper function to output stuff to stderr and exit with a non-zero status.
syserr() {
  echo $* 1>&2
  exit 1;
}

## show help if no arguments are given
[ $# -eq 0 ] && _help && exit 0;

## getopt parsing
if `getopt -T >/dev/null 2>&1` ; [ $? = 4 ] ; then
  true; # Enhanced getopt.
else
  syserr "You are using an old getopt version $(getopt -V)";
fi;

if GETOPT_TEMP=$( getopt -o -r:p:k:d:n:h --long repository:,package:,keep:,days:,noop -n "$0":,help -n "$0" -- "$@" ); then
  eval set -- "${GETOPT_TEMP}"
else
  _help
  exit 64
fi

if [[ $? != 0 ]]; then
  syserr "Error parsing arguments"
fi;

while [ $# -gt 0 ]; do
  case "$1" in
    -r|--repository)    REPO="$2"; shift;;

    -p|--package)       PACKAGE="$2"; shift;;
    -k|--keep)          KEEP="$2"; shift;;
    -d|--days)          DAYS="$2"; shift;;
    -n|--noop)          PRECMD="/bin/echo"; shift;;

    -h|--help)    _help; exit 0;;
    --)           shift; break;;
    -*)           echo "Unknown option: '$1'" 1>&2; _help; exit 1;;
    *)            break;;
  esac;
  shift;
done;

CUR_PKG=""

if [ "${PACKAGE}" == "all" ]; then
  ## empty filter
  PKG_FILTER="Name, !\$Architecture (=source)"
else
  ## filter on package name
  PKG_FILTER="Name (${PACKAGE}), !\$Architecture (=source)"
fi


## Search repo for all packages and sort by reverse version (newest on top)"
for PKG in $(aptly repo search ${REPO} "${PKG_FILTER}" | grep -v "ERROR: no results" | sort -rV); do
  PKG_NAME=$(echo ${PKG} | cut -d_ -f1)
  if [ "${PKG_NAME}" != "${CUR_PKG}" ]; then
    COUNT=0
    DELETED=""
    CUR_PKG="${PKG_NAME}"
  fi
  ## if DELETED is set, no use in checking old versions of that same package since they were already cleaned
  test -n "$DELETED" && continue
  let COUNT+=1
  ## Check if there's over $KEEP versions for 1 package in repo
  if [ ${COUNT} -gt ${KEEP} ]; then
    PKG_VERSION=$(echo $PKG | cut -d_ -f2)
    echo "Cleaning package ${PKG_NAME}, Version (<= ${PKG_VERSION})\", since it has ${COUNT} or more versions"
    cleanup ${REPO} ${PKG_NAME} ${PKG_VERSION}
    # exit from this loop, no need to verify by age if package is already removed
    break
  fi
  ## Check if file is older then $DAYS, but only if we have more then 1 version of a package!!!
  if [ ${COUNT} -gt 1 ]; then
    FILE=$(find ${FILE_PATH} -name "${PKG}.deb" -mtime +$DAYS)
    ## If a file matched, we want to clean it
    if [ "${FILE}" != "" ]; then
      PKG_VERSION=$(echo $PKG | cut -d_ -f2)
      ## file found, needs cleaning because age is over $DAYS
      echo "Cleaning package ${PKG_NAME}, Version (<= ${PKG_VERSION})\", because it is over ${DAYS} days old"
      cleanup ${REPO} ${PKG_NAME} ${PKG_VERSION}
    fi
  fi
done
