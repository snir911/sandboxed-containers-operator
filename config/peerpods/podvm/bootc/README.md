# Image Mode (bootc) PodVM Builds

Image Mode podVM builds enable OSC users to create PodVM images based
on a RHEL bootc container image. The resulting artifact can be either
a podVM bootc container image or a podVM disk generated from that image.
OSC includes updates to the Image Creation mechanism, supporting the
conversion and upload of podVM images derived from pre-created bootc
(image mode) container images.
The following instructions outline both local and in-cluster options
for image creation.

## Create PodVM Bootc Container Image

### **Local** PodVM Bootc Container Image Build

Use Podman to build a podVM bootc image locally (push it to
a container registry of your choice if needed).
```
IMG=quay.io/example/podvm-bootc
AUTHFILE=/path/to/pull-secret
podman build --authfile ${AUTHFILE} -f Containerfile.rhel -t ${IMG}
#podman push ${IMG}
```

### **In-Cluster**  PodVM Bootc Container Image Build

Use an existing OpenShift cluster to execute the container build
in-cluster and push the container image to the cluster's internal
registry:
```
oc apply -f podvm-git-buildconfig.yaml
IMG=bootc::image-registry.openshift-image-registry.svc:5000/openshift-sandboxed-containers-operator/podvm-bootc
```

## Convert Bootc Container Image to a PodVM Disk

### **Local** PodVM Disk Creation

Use [Bootc Image Builder](https://github.com/osbuild/bootc-image-builder)
to convert the created podVM bootc container image to a podVM disk file
```
# podman pull ${IMG} # optional
mkdir output
podman run \
       -it --rm \
       --privileged \
       --security-opt label=type:unconfined_t \
       --authfile ${AUTHFILE} \
       -v $(pwd)/config.toml:/config.toml:ro \
       -v $(pwd)/output:/output \
       -v /var/lib/containers/storage:/var/lib/containers/storage \
       registry.redhat.io/rhel9/bootc-image-builder:latest \
       --type qcow2 \
       --rootfs xfs \
       --local \
       "${IMG}"
```
Artifact will be located at  output/qcow2/disk.qcow2
Upload it to your cloud-provider.


### **In-Cluster** Podvm Disk & Image Creation

Provide the podVM bootc Container image and allow the operator
to handle the conversion, upload, creation, and configuration
of the podVM image within the cluster where your OSC is installed.

Once you have OSC operator installed and before applying KataConfig,
ensure your `<cloud-provider>-podvm-image-cm` values are configured
correctly:
```
IMAGE_TYPE: pre-built
PODVM_IMAGE_URI: ${IMG}
BOOTC_BUILD_CONFIG: |  # Custom bootc build configuration: https://osbuild.org/docs/bootc/#-build-config
  [[customizations.user]]
  name = "peerpod"
  password = "peerpod"
  #key = "ssh-rsa AAAA..."
  groups = ["wheel", "root"]

  [[customizations.filesystem]]
  mountpoint = "/"
  minsize = "5 GiB"

  [[customizations.filesystem]]
  mountpoint = "/var/kata-containers"
  minsize = "15 GiB"
```

