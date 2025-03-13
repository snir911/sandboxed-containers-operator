#!/bin/bash -x

# gpu attestation
if [[ " $@ " =~ " prestart " ]]; then
  # local # TODO: remove or swtich to nvtrust local attestation
  for i in {1..3}; do python3 -m verifier.cc_admin > /var/log/gpu-attestation-status 2>&1 && break || sleep 1; done
  python3 -m verifier.cc_admin  > /var/log/gpu-attestation-status 2>&1
  tail -3 /var/log/gpu-attestation-status > /var/log/gpu-attestation-status-short
fi
