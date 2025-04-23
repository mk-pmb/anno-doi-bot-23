#!/bin/bash
# -*- coding: utf-8, tab-width: 2 -*-

function log_dump () {
  local DUMP_DEST="${CFG[doibot_log_dest_dir]}/$1"
  mkdir --parents -- "$(dirname -- "$DUMP_DEST")"
  cat >"$DUMP_DEST" || return $?$(
    echo E: "Failed to dump debug file: $DUMP_DEST" >&2)
  local PRV='s![ \t]+! !g; s!\s*\n\s*!\n!g'
  PRV="$(head --bytes=1k -- "$DUMP_DEST" | tr '\0' ' ' | sed -zre "$PRV")"
  PRV="${PRV:0:128}"
  PRV="${PRV//$'\n'/¶ }"
  echo D: "Dump file saved: $(du --bytes -- "$DUMP_DEST") | Preview: «$PRV»"
}


function logts () {
  printf '%s [%(%F %T %Z)T] ' "$1" -1; shift
  echo "$*"
}



return 0
