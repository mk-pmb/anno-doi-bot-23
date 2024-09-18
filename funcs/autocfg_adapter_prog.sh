#!/bin/bash
# -*- coding: utf-8, tab-width: 2 -*-


function doibot_autocfg_adapter_prog () {
  [ -z "${CFG[doibot_adapter_prog]}" ] || return 0 # No need to guess.
  local AN="${CFG[doibot_adapter_name]}"
  [ -n "$AN" ] || return 4$(echo E: $FUNCNAME: >&2 \
    "Cannot guess option doibot_adapter_prog:" \
    "Option doibot_adapter_name is empty!")
  local PROG=
  local LIST=(
    "$BOT_PATH-adapter-$AN/"
    "$BOT_PATH/adapters/$AN/"
    "$BOT_PATH/adapter.$AN/"
    )
  for PROG in "${LIST[@]}"; do
    for PROG in "$PROG"adapter.{sh,pl,py,elf}; do
      [ -f "$PROG" -a -x "$PROG" ] || continue
      CFG[doibot_adapter_prog]="$PROG"
      PROG="${PROG/#$BOT_PATH/'${BOT_PATH}'}"
      echo D: "Found doibot_adapter_prog: $PROG"
      return 0
    done
  done
}









return 0
