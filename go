#!/usr/bin/env bash
# Run Bricks.

# The bricks binary is named after the version and platform.
# This script figures out which binary to run.

# Specify the path to BRICKS_TS.
BricksPath='./BRICKS_TS'

# What is the system?
System="$(uname -s | tr 'A-Z' 'a-z')"

# What is the architecture?
Architecture="$(uname -m)"
if [[ $Architecture == "x86_64" ]]; then
    Architecture="amd64"
fi

${BricksPath}/bin/bricks-*-${System}-${Architecture}
