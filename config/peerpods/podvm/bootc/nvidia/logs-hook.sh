#!/bin/bash -x

# gpu attestation
if [[ " $@ " =~ " prestart " ]]; then
  nohup /usr/local/bin/log-inject.sh & # this passes file to containers
fi
