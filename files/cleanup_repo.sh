#!/bin/bash -x
## File managed by puppet
# * module: 
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

if [ $# -gt 3 ]; then
  echo "Usage: $0 <repo> [<keep>] [<day>]"
  echo "  repo is required"
  echo "  keep versions amount, defaults to \`15\`"
  echo "  days to keep packages, defaults to \'3650'\ (10 years)"
  exit 64 # EX_USAGE
fi

REPO="${1}"
KEEP="${2:-15}"
DAYS="${3:-3650}"

CUR_PKG=""
FILE_PATH="/data/aptly/public"

# Search repo for all packages and sort by reverse version (newest on top)"
for PKG in $(aptly repo search ${REPO} "Architecture" | grep -v "ERROR: no results" | sort -rV); do
  PKG_NAME=$(echo ${PKG} | cut -d_ -f1)
  if [ "${PKG_NAME}" != "${CUR_PKG}" ]; then
    COUNT=0
    DELETED=""
    CUR_PKG="${PKG_NAME}"
  fi
  test -n "$DELETED" && continue
  let COUNT+=1
  # Check if there's over $KEEP versions for 1 package in repo
  if [ ${COUNT} -gt ${KEEP} ]; then
    PKG_VERSION=$(echo $PKG | cut -d_ -f2)
    echo "Cleaning package ${PKG_NAME}, Version (<= ${PKG_VERSION})\", since it has ${COUNT} or more versions"
    echo "WOULD DO: aptly repo remove ${REPO} \"Name (${PKG_NAME}), Version (<= ${PKG_VERSION})\""
    DELETED='yes'
  fi
  # Check if file is older then $DAYS, but only if we have more then 1 version of a package!!!
  if [ ${COUNT} -gt 1 ]; then
    FILE=$(find ${FILE_PATH} -name "${PKG}.deb" -mtime +$DAYS)
    # If a file matched, we want to clean it
    if [ "${FILE}" != "" ]; then
      PKG_VERSION=$(echo $PKG | cut -d_ -f2)
      # file found, needs cleaning because age is over $DAYS
      echo "Cleaning package ${PKG_NAME}, Version (<= ${PKG_VERSION})\", because it is over ${DAYS} days old"
      echo "WOULD DO: aptly repo remove ${REPO} \"Name (${PKG_NAME}), Version (= ${PKG_VERSION})\""
    fi
  fi
done


