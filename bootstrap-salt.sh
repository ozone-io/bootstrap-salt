#!/bin/sh

#   Copyright 2014 Werner Buck
#
#   Licensed under the Apache License, Version 2.0 (the "License");
#   you may not use this file except in compliance with the License.
#   You may obtain a copy of the License at
#
#       http://www.apache.org/licenses/LICENSE-2.0
#
#   Unless required by applicable law or agreed to in writing, software
#   distributed under the License is distributed on an "AS IS" BASIS,
#   WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
#   See the License for the specific language governing permissions and
#   limitations under the License.


###########################################################################################
#
# Ozone.io's provisioner for Salt
#
# Features:
# * Installs salt minion, downloads SLS tree, runs in different stages
# * Easily configurable due to the use of environment variables. * See test
# * Runs on every unix distro BSD/Unix alike due to POSIX and /bin/sh compatibility. 
#     A lot of distro's have been tested using vagrant.
#
# Credit:
# * Helper functions are from Chef Omnitruck installer at opscode!
# 
############################################################################################

#drop out at every error. //TODO: Use trap
set -e

#Default options
SALT_DEFAULT_ALWAYS_INSTALL_SALT="false"
SALT_DEFAULT_INSTALL_SCRIPT="http://bootstrap.saltstack.org"
SALT_DEFAULT_INSTALL_SCRIPT_ARGS=""

#set default variables
SALT_ALWAYS_INSTALL_SALT=${SALT_ALWAYS_INSTALL_SALT:-$SALT_DEFAULT_ALWAYS_INSTALL_SALT}
SALT_INSTALL_SCRIPT=${SALT_INSTALL_SCRIPT:-$SALT_DEFAULT_INSTALL_SCRIPT}
SALT_INSTALL_SCRIPT_ARGS=${SALT_INSTALL_SCRIPT_ARGS:-$SALT_DEFAULT_INSTALL_SCRIPT_ARGS}

###########################################################################################
# helper functions. Skip to end.
###########################################################################################

# Timestamp
now () {
    date +'%H:%M:%S %z'
}

# Logging functions instead of echo
log () {
    echo "`now` ${1}"
}

info () {
    log "INFO: ${1}"
}

warn () {
    log "WARN$: ${1}"
}

critical () {
    log "CRIT: ${1}"
}

# Check whether a command exists - returns 0 if it does, 1 if it does not
exists() {
  if command -v $1 >/dev/null 2>&1
  then
    return 0
  else
    return 1
  fi
}

# Retrieve Platform and Platform Version
if test -f "/etc/lsb-release" && grep -q DISTRIB_ID /etc/lsb-release; then
  platform=`grep DISTRIB_ID /etc/lsb-release | cut -d "=" -f 2 | tr '[A-Z]' '[a-z]'`
  platform_version=`grep DISTRIB_RELEASE /etc/lsb-release | cut -d "=" -f 2`
elif test -f "/etc/debian_version"; then
  platform="debian"
  platform_version=`cat /etc/debian_version`
elif test -f "/etc/redhat-release"; then
  platform=`sed 's/^\(.\+\) release.*/\1/' /etc/redhat-release | tr '[A-Z]' '[a-z]'`
  platform_version=`sed 's/^.\+ release \([.0-9]\+\).*/\1/' /etc/redhat-release`

  # If /etc/redhat-release exists, we act like RHEL by default
  if test "$platform" = "fedora"; then
    # Change platform version for use below.
    platform_version="6.0"
  fi
  platform="el"
elif test -f "/etc/system-release"; then
  platform=`sed 's/^\(.\+\) release.\+/\1/' /etc/system-release | tr '[A-Z]' '[a-z]'`
  platform_version=`sed 's/^.\+ release \([.0-9]\+\).*/\1/' /etc/system-release | tr '[A-Z]' '[a-z]'`
  # amazon is built off of fedora, so act like RHEL
  if test "$platform" = "amazon linux ami"; then
    platform="el"
    platform_version="6.0"
  fi
elif test -f "/etc/release"; then
  platform="solaris2"
  machine=`/usr/bin/uname -p`
  platform_version=`/usr/bin/uname -r`
elif test -f "/etc/SuSE-release"; then
  if grep -q 'Enterprise' /etc/SuSE-release;
  then
      platform="sles"
      platform_version=`awk '/^VERSION/ {V = $3}; /^PATCHLEVEL/ {P = $3}; END {print V "." P}' /etc/SuSE-release`
  else
      platform="suse"
      platform_version=`awk '/^VERSION =/ { print $3 }' /etc/SuSE-release`
  fi
elif test "x$os" = "xFreeBSD"; then
  platform="freebsd"
  platform_version=`uname -r | sed 's/-.*//'`
elif test "x$os" = "xAIX"; then
  platform="aix"
  platform_version=`uname -v`
  machine="ppc"
fi

# Mangle $platform_version to pull the correct build
# for various platforms
major_version=`echo $platform_version | cut -d. -f1`
case $platform in
  "el")
    platform_version=$major_version
    ;;
  "debian")
    case $major_version in
      "5") platform_version="6";;
      "6") platform_version="6";;
      "7") platform_version="6";;
    esac
    ;;
  "freebsd")
    platform_version=$major_version
    ;;
  "sles")
    platform_version=$major_version
    ;;
  "suse")
    platform_version=$major_version
    ;;
esac

if test "x$platform_version" = "x"; then
  critical "Unable to determine platform version!"
  report_bug
  exit 1
fi

if test "x$platform" = "xsolaris2"; then
  # hack up the path on Solaris to find wget
  PATH=/usr/sfw/bin:$PATH
  export PATH
fi

if test "x$platform" = "x"; then
  critical "Unable to determine platform version!"
  report_bug
  exit 1
fi

if test "x$TMPDIR" = "x"; then
  tmp="/tmp"
else
  tmp=$TMPDIR
fi

# Random function since not all shells have $RANDOM
random () {
    hexdump -n 2 -e '/2 "%u"' /dev/urandom
}

# do_wget URL FILENAME
do_wget() {
  info "Trying wget..."
  wget -O "$2" "$1" 2>$tmp_stderr
  rc=$?

  # check for 404
  grep "ERROR 404" $tmp_stderr 2>&1 >/dev/null
  if test $? -eq 0; then
    critical "ERROR 404"
    unable_to_retrieve_package
  fi

  # check for bad return status or empty output
  if test $rc -ne 0 || test ! -s "$2"; then
    capture_tmp_stderr "wget"
    return 1
  fi

  return 0
}

# do_curl URL FILENAME
do_curl() {
  info "Trying curl..."
  curl -1 -sL -D $tmp_stderr "$1" > "$2"
  rc=$?
  # check for 404
  grep "404 Not Found" $tmp_stderr 2>&1 >/dev/null
  if test $? -eq 0; then
    critical "ERROR 404"
    unable_to_retrieve_package
  fi

  # check for bad return status or empty output
  if test $rc -ne 0 || test ! -s "$2"; then
    capture_tmp_stderr "curl"
    return 1
  fi

  return 0
}

# do_fetch URL FILENAME
do_fetch() {
  info "Trying fetch..."
  fetch -o "$2" "$1" 2>$tmp_stderr
  # check for bad return status
  test $? -ne 0 && return 1
  return 0
}

# do_perl URL FILENAME
do_perl() {
  info "Trying perl..."
  perl -e 'use LWP::Simple; getprint($ARGV[0]);' "$1" > "$2" 2>$tmp_stderr
  rc=$?
  # check for 404
  grep "404 Not Found" $tmp_stderr 2>&1 >/dev/null
  if test $? -eq 0; then
    critical "ERROR 404"
    unable_to_retrieve_package
  fi

  # check for bad return status or empty output
  if test $rc -ne 0 || test ! -s "$2"; then
    capture_tmp_stderr "perl"
    return 1
  fi

  return 0
}

# do_download URL FILENAME
do_download() {
  info "Downloading $1"
  info "  to file $2"

  # we try all of these until we get success.
  # perl, in particular may be present but LWP::Simple may not be installed

  if exists wget; then
    do_wget $1 $2 && return 0
  fi

  if exists curl; then
    do_curl $1 $2 && return 0
  fi

  if exists fetch; then
    do_fetch $1 $2 && return 0
  fi

  if exists perl; then
    do_perl $1 $2 && return 0
  fi

  critical "Could not download file. No download methods available."
}

# Helper bug-reporting text
report_bug() {
  critical "Please file a bug report at https://github.com/ozone-io/bootstrap-salt"
  critical ""
  critical "Version: $version"
  critical "Platform: $platform"
  critical "Platform Version: $platform_version"
  critical "Machine: $machine"
  critical "OS: $os"
  critical ""
  critical "Please detail your operating system type, version and any other relevant details"
}


#set temp stuff
tmp_dir="$tmp/install.sh.$$.`random`"
(umask 077 && mkdir $tmp_dir) || exit 1

tmp_stderr="$tmp/stderr.$$.`random`"

capture_tmp_stderr() {
  # spool up tmp_stderr from all the commands we called
  if test -f $tmp_stderr; then
    output=`cat ${tmp_stderr}`
    stderr_results="${stderr_results}\nSTDERR from $1:\n\n$output\n"
  fi
}


###########################################################################################
# Start of main logic
###########################################################################################

#############
# Install Stage: Installs Salt
# * Is a bootstrapping stage: Only installs essentials, does not configure.
#############
install_stage() {
  info "-- installing salt"
  if [ "x$SALT_ALWAYS_INSTALL_SALT" = "xtrue" ] || ! salt-call --version >/dev/null 2>&1; then
    info "-- salt not detected or installation is forced"
    info "-- download salt install script to $tmp_dir/salt-install.sh"
    do_download "$SALT_INSTALL_SCRIPT" "$tmp_dir/salt-install.sh"
    info "-- run salt install script: sh $tmp_dir/salt-install.sh $SALT_INSTALL_SCRIPT_ARGS"
    if [ "x$SALT_INSTALL_SCRIPT_ARGS" = "x" ]; then
      sh "$tmp_dir/salt-install.sh"
    else 
      sh "$tmp_dir/salt-install.sh" "$SALT_INSTALL_SCRIPT_ARGS"
    fi
    info "-- finished salt install script"
  else
    info "-- salt found. skipping salt installation."
  fi
}

#############
# Configure Stage: Downloads SLS from url and extracts them.
#############



############
# Pick your stages: If you supply an argument with install, configure or run, you can run each stage individually. 
############

case "$1" in
    "install")
      install_stage
    ;;
    *)
      install_stage
    ;;
esac
