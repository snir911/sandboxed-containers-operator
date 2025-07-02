# GitHub Actions Workflows

This directory contains GitHub Actions workflows for the sandboxed-containers-operator project.

## Bootc PodVM Build Workflow

The `bootc-podvm-build.yml` workflow builds bootc-based PodVM container images and converts them to disk images for deployment.

### Features

- **Multi-target builds**: Builds both standard and NVIDIA-enabled PodVM images
- **Disk image conversion**: Converts bootc container images to qcow2 disk images using bootc-image-builder
- **Artifact-based workflow**: Uses container artifacts for efficient container-to-disk conversion
- **Artifact management**: Uploads both container images and disk images as artifacts
- **Cloud provider support**: Configurable for Azure, AWS, and libvirt

### Triggers

The workflow runs on:
- **Push events** to `main` or `devel` branches when bootc files change
- **Pull requests** to `main` or `devel` branches (container build only, no push)
- **Manual dispatch** with configurable options

### Manual Execution

You can manually trigger the workflow from the GitHub Actions tab with these options:

- **Cloud Provider**: Choose between `azure`, `aws`, or `libvirt`
- **Build Disk**: Whether to build the disk image from the container
- **Container Variant**: Choose between `standard` or `nvidia` variant for disk conversion



### Workflow Jobs

#### 1. build-container
- Builds the standard bootc PodVM container image
- Saves container as workflow artifact
- Uses Docker layer caching for efficiency

#### 2. build-nvidia-container
- Builds NVIDIA GPU-enabled PodVM container image
- Only runs for Azure cloud provider
- Saves container as workflow artifact

#### 3. build-disk-image
- Downloads container image artifacts from previous jobs (no registry required)
- Supports both standard and nvidia container variants
- Converts the container image to a qcow2 disk image using bootc-image-builder
- Compresses the disk image with xz
- Uploads as workflow artifacts
- Generates metadata including checksums

### Artifacts

The workflow generates these artifacts:

- **Container Images**: Saved as workflow artifacts (`podvm-bootc-container-{sha}`, `podvm-bootc-nvidia-container-{sha}`)
- **Disk Images**: Available as workflow artifacts (`podvm-disk-{variant}-{provider}-{sha}`)
- **Metadata**: JSON file with build information and checksums (`podvm-disk-metadata-{variant}-{provider}-{sha}`)

### Usage Examples

#### Building for Azure with NVIDIA support:
```bash
# Trigger manually from GitHub Actions UI
# Select: cloud_provider=azure, container_variant=nvidia, build_disk=true
```

#### Building for AWS:
```bash
# Trigger manually from GitHub Actions UI  
# Select: cloud_provider=aws, build_disk=true
```

#### Development workflow:
```bash
# Create a pull request with changes to bootc files
# Workflow will build containers and generate artifacts
```

### Artifact-Based Workflow Benefits

This workflow uses GitHub Actions artifacts to pass container images between jobs:

- **No registry required**: Complete workflow runs without external registry dependencies
- **Faster builds**: Eliminates registry push/pull overhead
- **Cost efficient**: No registry bandwidth usage
- **Secure**: Container images stay within the GitHub Actions environment
- **Reliable**: No dependency on external registry availability
- **Simplified setup**: No secrets or registry configuration needed

The workflow saves container images as tar files in the first job, uploads them as artifacts, then downloads and loads them in the disk conversion job.

### Disk Image Usage

The generated disk images can be used:

1. **Direct deployment**: Download the compressed qcow2 from artifacts
2. **Cloud upload**: Use the disk image for VM creation in your cloud provider
3. **OSC integration**: Reference the container image URI in OSC ConfigMaps

### Configuration

The workflow uses the `config.toml` file in the bootc directory for bootc-image-builder configuration. Modify this file to customize:

- Root filesystem size
- User accounts
- Additional packages
- Kernel parameters

### Troubleshooting

#### Common Issues:

1. **Disk space**: The workflow includes cleanup steps to free space on runners
2. **Build failures**: Check the bootc-image-builder logs in the workflow output
3. **Missing artifacts**: If disk conversion fails, check that the container build job completed successfully
4. **Container loading**: Verify that the tar file was properly created and downloaded

#### Debugging:

- Enable debug logging by setting `ACTIONS_STEP_DEBUG=true` in repository secrets
- Check individual job logs for detailed error messages
- Verify the Containerfile syntax and build context
- Check artifact upload/download logs for container image transfer issues

### Contributing

When modifying the workflow:

1. Test changes in a fork first
2. Ensure all paths in triggers are correct
3. Consider impact on artifact storage limits
4. Verify container image naming consistency across jobs
