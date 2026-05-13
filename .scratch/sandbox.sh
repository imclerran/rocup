#!/bin/bash
export ROCUP_HOME="/tmp/rocup-sandbox/home"
export ROCUP_PREFIX="/tmp/rocup-sandbox/bin"
export ROCUP_ASSUME_YES=1
rm -rf /tmp/rocup-sandbox
mkdir -p "$ROCUP_HOME" "$ROCUP_PREFIX"
echo "sandbox: ROCUP_HOME=$ROCUP_HOME ROCUP_PREFIX=$ROCUP_PREFIX"
