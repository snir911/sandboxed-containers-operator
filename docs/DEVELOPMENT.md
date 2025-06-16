# Hacking on the sandboxed-containers-operator

## Prerequisites
- Golang - 1.22.x
- Operator SDK version - 1.39.1
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

### Adding new containers to OSC

When adding a new container definition in some pod yaml, make sure to tag the `image`
field with `  ## OSC_VERSION`, e.g.

```
image: registry.redhat.io/openshift-sandboxed-containers/osc-monitor-rhel9:1.10.0  ## OSC_VERSION
```

Do the same when adding new `RELATED_IMAGE` entries in the environment of the controller
in `config/manager/manager.yaml`, e.g.

```
            - name: RELATED_IMAGE_KATA_MONITOR
              value: registry.redhat.io/openshift-sandboxed-containers/osc-monitor-rhel9:1.10.0  ## OSC_VERSION
```

This is a best effort to track locations where OSC version bumps should happen.

### Updating versions

When starting a new version, several locations should be updated with the new version number :
- all the locations tagged with `  ## OSC_VERSION`, e.g.
```
sed -Ei 's/[[:digit:]]+\.[[:digit:]]+\.[[:digit:]]+  ## OSC_VERSION/1.10.0  ## OSC_VERSION/g' $(git grep -El '[[:digit:]]+\.[[:digit:]]+\.[[:digit:]]+[[:blank:]]+## OSC_VERSION')
```
- the `spec.version` field in `config/manifests/bases/sandboxed-containers-operator.clusterserviceversion.yaml`
- the `olm.skipRange` annotation in the `spec.metadata` field in `config/manifests/bases/sandboxed-containers-operator.clusterserviceversion.yaml`

The `spec.replaces` field in `config/manifests/bases/sandboxed-containers-operator.clusterserviceversion.yaml` should be updated with the number
of the latest officialy released version.

Finally, run `make bundle` : this should propagate the version bump to the rest of the tree.
