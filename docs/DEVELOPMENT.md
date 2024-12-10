# Hacking on the sandboxed-containers-operator

## Prerequisites
- Golang - 1.22.x
- Operator SDK version - 1.36.1
```
export ARCH=$(case $(uname -m) in x86_64) echo -n amd64 ;; aarch64) echo -n arm64 ;; *) echo -n $(uname -m) ;; esac)
export OS=$(uname | awk '{print tolower($0)}')
export OPERATOR_SDK_DL_URL=https://github.com/operator-framework/operator-sdk/releases/download/v1.36.1
curl -LO ${OPERATOR_SDK_DL_URL}/operator-sdk_${OS}_${ARCH}
install -m 755 operator-sdk_linux_amd64 ${SOME_DIR_IN_YOUR_PATH}/operator-sdk
```
- podman, podman-docker or docker
- Access to OpenShift cluster (4.12+)
- Container registry to storage images

### Get a token on registry.ci.openshift.org
Our builder and base images are curated images from OpenShift.
They are pulled from registry.ci.openshift.org, which require an authentication.
To get access to these images, you have to login and retrieve a token, following [these steps](https://docs.ci.openshift.org/docs/how-tos/use-registries-in-build-farm/#how-do-i-log-in-to-pull-images-that-require-authentication)

In summary:
- login to one of the clusters' console
- use the console's shortcut to get the commandline login command
- log in from the command line with the provided command
- use "oc registry login" to save the token locally

### Using public images

If you cannot login to registry.ci.openshift.org, a temporary solution is to use
public images during build and test. At the time of writing, the following public images
does the trick.

```shell
export BUILDER_IMAGE=registry.ci.openshift.org/openshift/release:golang-1.22
export TARGET_IMAGE=registry.ci.openshift.org/origin/4.17:base
make docker-build
```

## Set Environment Variables

Set your quay.io userid
```
export QUAY_USERID=<user>
```

```
export IMAGE_TAG_BASE=quay.io/${QUAY_USERID}/openshift-sandboxed-containers-operator
export IMG=quay.io/${QUAY_USERID}/openshift-sandboxed-containers-operator
```

## Viewing available Make targets
```
make help
```

## Building Operator image
```
make docker-build
make docker-push
```

## Building Operator bundle image

If you are deploying in an OpenShift cluster then modify the
value of the env variable `SANDBOXED_CONTAINERS_EXTENSION` to `sandboxed-containers`
in the file `config/manager/manager.yaml` before running the below mentioned
commands.

```
make bundle CHANNELS=candidate
make bundle-build
make bundle-push
```


## Building Catalog image
```
make catalog-build
make catalog-push
```

## Installing the Operator using OpenShift Web console

### Create Custom Operator Catalog

Create a new `CatalogSource` yaml. Replace `user` with your quay.io user and
`version` with the operator version.

```
cat > my_catalog.yaml <<EOF
apiVersion: operators.coreos.com/v1alpha1
kind: CatalogSource
metadata:
 name:  my-operator-catalog
 namespace: openshift-marketplace
spec:
 displayName: My Operator Catalog
 sourceType: grpc
 image:  quay.io/${QUAY_USERID}/openshift-sandboxed-containers-operator-catalog:version
 updateStrategy:
   registryPoll:
      interval: 5m

EOF
```
Deploy the catalog
```
oc create -f my_catalog.yaml
```

The new operator should be now available for installation from the OpenShift web console


## Installing the Operator using CLI

When deploying the Operator using CLI, cert-manager needs to be installed otherwise
webhook will not start. `cert-manager` is not required when deploying via the web console as OLM
takes care of webhook certificate management. You can read more on this [here]( https://olm.operatorframework.io/docs/advanced-tasks/adding-admission-and-conversion-webhooks/#deploying-an-operator-with-webhooks-using-olm)

### Install cert-manager
```
 oc apply -f https://github.com/jetstack/cert-manager/releases/download/v1.5.3/cert-manager.yaml
```

### Modify YAMLs
Uncomment all entries marked with `[CERTMANAGER]` in manifest files under `config/*`

### Deploy Operator
```
make install && make deploy
```

### Updating versions

When starting a new version, the locations tagged with `OSC_VERSION` should be updated with the new version number. A few places are also tagged with `OSC_VERSION_BEFORE`, referring to the version being replaced.

On the  `main` branch `1.5.2`, the following locations were identified, but looking for the version pattern would give too many false positives on `devel` with `1.7.0`, and even more false positives were found with `1.8.0`. Most hits were in `go.mod` or `go.sum` and should be ignored, since they refer to dependencies with unrelated version numbering.

```
Makefile:6:VERSION ?= 1.5.2
config/manager/kustomization.yaml:16:  newTag: 1.5.2
config/manifests/bases/sandboxed-containers-operator.clusterserviceversion.yaml:16:    olm.skipRange: '>=1.1.0 <1.5.2'
config/manifests/bases/sandboxed-containers-operator.clusterserviceversion.yaml:28:  name: sandboxed-containers-operator.v1.5.2
config/manifests/bases/sandboxed-containers-operator.clusterserviceversion.yaml:368:  version: 1.5.2
config/samples/deploy.yaml:9: image:  quay.io/openshift_sandboxed_containers/openshift-sandboxed-containers-operator-catalog:v1.5.2
config/samples/deploy.yaml:39:  startingCSV: sandboxed-containers-operator.v1.5.2
hack/aws-image-job.yaml:24:        image: registry.redhat.io/openshift-sandboxed-containers/osc-podvm-payload-rhel9:1.5.2
hack/azure-image-job.yaml:23:        image: registry.redhat.io/openshift-sandboxed-containers/osc-podvm-payload-rhel9:1.5.2
```
