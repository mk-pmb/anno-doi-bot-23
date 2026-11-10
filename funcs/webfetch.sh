#!/bin/bash
# -*- coding: utf-8, tab-width: 2 -*-


function webfetch () {
  local ABU="${CFG[doibot_auth_baseurl]}"
  [ -n "$ABU" ] || ABU="${CFG[anno_public_baseurl]}"
  [ -n "$ABU" ] || return 4$(echo E: 'Empty doibot_auth_baseurl' >&2)
  local CURL_OPT=(
    --silent
    --show-error
    --user-agent "${CFG[doibot_useragent]}"
    )
  local LATE_ARGS=()
  while [ "$#" -ge 1 ]; do case "$1" in
    bot-auth:* )
      LATE_ARGS+=( "$ABU${1#*:}" )
      webfetch__set_custom_headers "${CFG[doibot_auth_headers]}"
      shift;;
    data:* ) webfetch__decode_data_url "$1"; return $?;;
    --header=* ) webfetch__set_custom_headers "${1#*=}"; shift;;
    --- ) shift; break;; # start of verbatim curl options
    -- ) break;;
    -* ) echo "E: $FUNCNAME: Unsupported option: $1" >&2; return 6;;
    * ) break;;
  esac; done
  CURL_OPT+=( "$@" "${LATE_ARGS[@]}" )
  # echo D: >&2 curl "${CURL_OPT[@]}" || return $?
  curl "${CURL_OPT[@]}" || return $?
}


function webfetch__set_custom_headers () {
  local ADD=()
  readarray -t ADD < <(<<<"$1" sed -nrf <(echo '
    s~^\s+~~
    /^#/b
    /^;/b
    s~\s+$~~
    s!^([^: ]+)\s*:\s*!--header\n\1: !p
    '))
  CURL_OPT+=( "${ADD[@]}" )
}


function webfetch__decode_data_url () {
  local DU=
  for DU in "$@"; do
    DU="${DU%%\#*}"
    case "$DU" in
      'data:text/plain',* )
        DU="${DU#*,}"
        DU="${DU//\\/\\x5C}"
        echo -e "${DU//%/\\x}"
        ;;
      'data:text/plain;base64',* )
        DU="${DU#*,}"
        base64 --decode --ignore-garbage <<<"$DU"
        ;;
    esac
  done
}









return 0
