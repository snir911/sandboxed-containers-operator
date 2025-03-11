#!/bin/bash -x

# gpu attestation
if [[ " $@ " =~ " prestart " ]]; then
  python3 -m verifier.cc_admin  > /var/log/gpu-attestation-status 2>&1
  tail -3 /var/log/gpu-attestation-status > /var/log/gpu-attestation-status-short
  nohup /usr/local/bin/log-inject.sh & # this passes file to containers
fi
