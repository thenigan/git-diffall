#!/bin/sh
GIT_XPATH="$(git --exec-path)"
cp git-diffall.perl "$GIT_XPATH/git-diffall" || exit 1
cp git-diffall--helper.sh "$GIT_XPATH/git-diffall--helper" || exit 1
echo Installed 2 files
