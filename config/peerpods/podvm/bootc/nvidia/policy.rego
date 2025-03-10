# Example kata-agent policy to allow only specific CDH command to retrieve the attestation status

package agent_policy

import future.keywords.in
import future.keywords.if
import future.keywords.every

default AddARPNeighborsRequest := true
default AddSwapRequest := true
default CloseStdinRequest := true
default CopyFileRequest := true
default CreateSandboxRequest := true
default DestroySandboxRequest := true
default GetMetricsRequest := true
default GetOOMEventRequest := true
default GuestDetailsRequest := true
default ListInterfacesRequest := true
default ListRoutesRequest := true
default MemHotplugByProbeRequest := true
default OnlineCPUMemRequest := true
default PauseContainerRequest := true
default PullImageRequest := true
default RemoveContainerRequest := true
default RemoveStaleVirtiofsShareMountsRequest := true
default ReseedRandomDevRequest := true
default ResumeContainerRequest := true
default SetGuestDateTimeRequest := true
default SetPolicyRequest := true
default SignalProcessRequest := true
default StartContainerRequest := true
default StartTracingRequest := true
default StatsContainerRequest := true
default StopTracingRequest := true
default TtyWinResizeRequest := true
default UpdateContainerRequest := true
default UpdateEphemeralMountsRequest := true
default UpdateInterfaceRequest := true
default UpdateRoutesRequest := true
default WaitProcessRequest := true
default WriteStreamRequest := true
default CreateContainerRequest := true
default ReadStreamRequest := true

default ExecProcessRequest := false


ExecProcessRequest if {
    input_command = concat(" ", input.process.Args)
    some allowed_command in policy_data.allowed_commands
    input_command == allowed_command
}

policy_data := {  
  "allowed_commands": [         
        "curl -s http://localhost:8006/cdh/resource/default/trustee-attestation-status/status",
        "cat /var/log/gpu-attestation-status",
        "cat /var/log/gpu-attestation-status-short",
        "nvidia-smi",
        "nvidia-persistenced",
        "nvidia-debugdump",
        "nvidia-cuda-mps-server",
        "nvidia-cuda-mps-control"
  ] 
}
