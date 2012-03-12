#!/bin/sh
# Copyright 2012, Tim Henigan <tim.henigan@gmail.com>
LOCAL="$1"
REMOTE="$2"
TOOL_MODE=diff
. "$(git --exec-path)/git-mergetool--lib"
merge_tool="$(get_merge_tool)"
run_merge_tool "$merge_tool" false
