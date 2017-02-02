#!/bin/bash

set -o errexit # exit on any command failure; use `whatever || true` to accept failures
set -o pipefail # pipes fail when any command fails, not just the last one (see above for workaround)
set -o nounset # exit on use of undeclared var, use `${possibly_undefined-}` to substitute the empty string in that case
#set -o xtrace

HELLO_PACKAGE="hello"

declare -a on_exit_items=()
on_exit() {
  for i in "${on_exit_items[@]}"; do
    eval $i
  done
}
add_on_exit() {
  local n=${#on_exit_items[*]}
  on_exit_items[$n]="$*"
  if [[ $n -eq 0 ]]; then
    trap on_exit EXIT
  fi
}

CWD="$( pwd )"
function cwd_reset() {
  cd $CWD;
}
add_on_exit cwd_reset;

_help() {
  cat - <<EOHELP
USAGE:
    $0 <options>

DESCRIPTION:
    Adds the hello world package from upstream (repositories configured on this
    system) to a specific repository (\`--repo\`) or all repositories with no
    packages in them.

OPTIONS:
    -r, --repo          Only add the hello package to this repository.
    -a, --arch          Use this architecture (amd64, i386, ...) !!!NOT IMPLEMENTED!!!
    -c, --cachedir      Download (and cache) the latest version here.
                        When running in temp mode, the cache dir is not used.
    -t, --temp          Cleanup the package after adding it to the repo(s).
    -f, --force         With a single repo, add the package even if the
                        repository is not empty.
    -n, --dry-run       Show to which repos it would be added but not actually
                        add it. This does not prevent the package to be
                        downloaded.
    -h, --help          This help message.

EOHELP
}

## Helper function to output stuff to stderr and exit with a non-zero status.
syserr() {
  echo $* 1>&2
  exit 1;
}

## getopt parsing
if `getopt -T >/dev/null 2>&1` ; [ $? = 4 ] ; then
  true; # Enhanced getopt.
else
  syserr "You are using an old getopt version $(getopt -V)";
fi;

if ! APT_CACHE="$( which apt-cache )"; then
  echo "ERROR: Could not find required binary apt-cache" 1>&2;
  exit 69;
fi;
if ! APT_GET="$( which apt-get )"; then
  echo "ERROR: Could not find required binary apt-get" 1>&2;
  exit 69;
fi
if ! APTLY="$( which aptly )"; then
  echo "ERROR: Could not find required binary apt-get" 1>&2;
  exit 69;
fi

if GETOPT_TEMP="$(
  getopt \
    -o -r:a:c:tfnh \
    --long repo:,arch:,cachedir:,temp,force,help,dry-run \
    -n "$0" -- "$@"
  )"; then
    eval set -- "${GETOPT_TEMP}"
else
    _help
    exit 64
fi

while [ $# -gt 0 ]; do
  case "$1" in
    -r|--repo)      REPO="$2"; shift;;
    -a|--arch)      ARCHITECTURE="$2"; shift;;
    -c|--cachedir)  CACHE_DIR="$2"; shift;;
    -t|--temp)      USE_TEMP=1;;
    -n|--dry-run)   DRY_RUN=1;;
    -f|--force)     FORCE=1;;
    -h|--help)      _help; exit 0;;
    --)             shift; break;;
    *)              break;;
  esac;
  shift;
done;

CACHE_DIR="${CACHE_DIR-/var/cache/aptly}"
ARCHITECTURE="${ARCHITECTURE-amd64}"
USE_TEMP=${USE_TEMP-0}
DRY_RUN=${DRY_RUN-0}
FORCE=${FORCE-0}

if [ $USE_TEMP -eq 1 ]; then
  CACHE_DIR="$( mktemp -d 2>/dev/null || mktemp -d -t 'hello_repo' )"
  function cleanup_temp() {
    if [ $DRY_RUN -eq 1 ]; then
      echo "WARN: Skip cleanup ${CACHE_DIR} (dry-run)" 1>&2
    else
      rm -rf "${CACHE_DIR}";
    fi;
  }
  add_on_exit cleanup_temp;
fi;

if [ ! -d "${CACHE_DIR}" ]; then
  echo "ERROR: Cache dir ${CACHE_DIR} does not exist" 1>&2
  exit 65;
fi;

function fetch_cached_hello() {
  local cwd="$( pwd )"
  cd "${CACHE_DIR}"
  if ! "${APT_GET}" download "${HELLO_PACKAGE}"; then
    echo "Unable to fetch hello package '${HELLO_PACKAGE}'" 1>&2;
    exit 69
  fi
  cd "$cwd"
}

function get_cached_hello() {
  # prefetch cached hello if needed
  [ -f "${CACHED_HELLO}" ] || fetch_cached_hello
  # check if prefetch worked
  if [ ! -f "${CACHED_HELLO}" ]; then
    echo "Could not retrieve the correct package. Expected filename: '${HELLO_DEB}'" 1>&2
    exit 69
  fi
}

function do_insert() {
  local repo="$1";
  get_cached_hello
  if [ $DRY_RUN -eq 1 ]; then
    echo "DRYRUN: $APTLY repo add '${repo}' '${CACHED_HELLO}'"
  else
    $APTLY repo add "${repo}" "${CACHED_HELLO}" || exit 1;
  fi
}

function insert_package() {
  local repo="$1";
  local package_count;
  if ! package_count=$( "${APTLY}" repo show "${repo}" 2>/dev/null | grep '^Number of packages' | awk -F': ' '{print $2}' ); then
    echo "ERROR: Repository ${repo} not found" 1>&2;
    exit 65
  fi
  if [ $package_count -eq 0 ]; then
    do_insert "${repo}"
  elif [ $FORCE -eq 1 ]; then
    do_insert "${repo}"
  else
    echo "WARN: Repo ${repo} already has packages ($package_count). Skipping" 1>&2
  fi
}

if ! HELLO_VERSION="$( $APT_CACHE policy ${HELLO_PACKAGE} | grep '^[ ]\+Candidate:' | awk '{print $2}' )"; then
  echo "Could not find the hello package in any upstream repos" 1>&2
  exit 69
fi

HELLO_DEB="${HELLO_PACKAGE}_${HELLO_VERSION}_${ARCHITECTURE}.deb"
CACHED_HELLO="${CACHE_DIR}/${HELLO_DEB}"

if [ "${REPO-}x" == "x" ]; then
  # No specific repo defined.
  FORCE=0; #never force if looping all repos.
  while read repo; do
    [ "${repo}x" == "x" ] && continue
    insert_package "${repo}"
  done < <( $APTLY repo list | grep '(packages: 0)$' | sed -e 's@^[ ]\+\*[ ]\+\[\([^]]\+\)\].*@\1@' )
else
  insert_package "${REPO}"
fi;
