#!/bin/bash
# -*- coding: utf-8, tab-width: 2 -*-


function bot_init_before_config () {
  local NMBIN="$PWD"/node_modules/.bin
  # ^-- Using $PWD rather than $BOT_PATH to make it work in adapters
  #     independent of their variable names.
  if [[ ":$PATH:" != *":$NMBIN:"* ]]; then
    PATH="$NMBIN:$PATH:"
    export PATH
  fi
}


function load_host_config () {
  local CFG_TOPIC="$1"
  tty --silent && \
    echo P: "Reading config file(s) for host ${HOSTNAME:-<?none?>}." >&2
  local ITEM=
  for ITEM in {config,cfg.@"$HOSTNAME"}{/*,.*,}.rc; do
    [ ! -f "$ITEM" ] || source_in_func "$ITEM" cfg:"$CFG_TOPIC" || return $?
  done
}


function source_in_func () {
  source -- "$@" || return $?$(
    echo W: "$FUNCNAME failed (rv=$?) for '$1'" >&2)
}


function source_these_libs () {
  local LIB=
  for LIB in "$@"; do
    source_in_func "$LIB" --lib || return $?
  done
}






return 0
