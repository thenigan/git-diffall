#!/bin/sh
cp git-diffall* "$(git --exec-path)" || (
	echo "Failed to copy files to $(git --exec-path)!"
	exit 1
)
