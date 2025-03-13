#!/bin/bash -x

# gpu attestation
if [[ " $@ " =~ " prestart " ]]; then
  # remote attestation
  for i in {1..3}; do /bin/bash -c 'cd /var/remoteatt/nvtrust/guest_tools/attestation_sdk/tests/end_to_end/hardware && source /var/remoteatt/venv/bin/activate && python3.12 RemoteGPUTest.py' > /var/log/gpu-remote-attestation-status && [[ -e /var/log/gpu-remote-attestation-status ]] && break || sleep 1; done
fi
