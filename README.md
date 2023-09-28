# external-secret-demo

We begin by setting up the environment. Normally, this is the point where we bootstrap the MPAS system.

For now, let's just load in the project controller to test the ability to change the service account for new secrets.

Clone this pull request if you would like to play along: https://github.com/open-component-model/mpas-project-controller/pull/36

When ready, run the script in this repository. `./create_test_env.sh`. Make sure to change the `project.yaml` and add
a git secret that actually has correct username/password combination.

Once that is ready, we continue by applying the following objects.

## external-secrets-operator

Install the external-secret-operator by applying the latest manifest:

```
kubectl apply -f ./external-secrets-manifest/external-secrets.yaml
```

## CRDs

Once the controller is up and running, it's time to apply the key ingredients.

### ClusterSecretStore

This CRD defines from where the secrets will be pulled from. In this scenario we will provide secrets coming from the
same Kubernetes cluster that we are currently using.

```yaml
apiVersion: external-secrets.io/v1beta1
kind: ClusterSecretStore
metadata:
  name: secret-store-name
spec:
  provider:
    kubernetes:
      # This is the namespace in which it will look for the secrets to be distributed.
      # Meaning, all secrets are applied in here. This might be some secret-namespace for distribution purposes.
      remoteNamespace: mpas-system
      auth:
        serviceAccount:
          namespace: "default"
          # This would be the project service account which has the right permissions to create secrets.
          name: "default"
      server:
        caProvider: # we are connecting to our own cluster.
          namespace: "default"
          type: ConfigMap
          name: kube-root-ca.crt
          key: ca.crt
  # Conditions about namespaces in which the ClusterSecretStore is usable for ExternalSecrets
  conditions:
    - namespaces:
        - "ocm-system"
        - "mpas-system"
        - "mpas-sample-project"
```

The provider could be anything that external secrets provides. Now, we just need some `ClusterExternalSecrets` that will
tie in the Cluster's secrets into the running cluster. ( Never mind that they exist now, they could come from any number
of sources. ).

### ClusterExternalSecret

Now, we need to describe HOW to use the secret that the store provides. The MPAS System needs a couple secrets to start
like the certificates and some git secrets to access the Flux Repository. Other secrets are usually related to the
component versions and their pull access, we'll talk about that in a bit.

Let's see how to replicate the certificate secret. The pull the certificate secrets from the secret store, apply this
external secret:

```yaml
# DON'T TOUCH IT, THIS WORKS!
apiVersion: external-secrets.io/v1beta1
kind: ClusterExternalSecret
metadata:
  name: replicator-cert
spec:
  # The name to be used on the ExternalSecrets
  externalSecretName: "replicator-cert-es"

  # This is a basic label selector to select the namespaces to deploy ExternalSecrets to.
  # you can read more about them here https://kubernetes.io/docs/concepts/overview/working-with-objects/labels/#resources-that-support-set-based-requirements
  namespaceSelector:
    matchExpressions:
      - key: "kubernetes.io/metadata.name"
        operator: "In"
        values: ["ocm-system", "mpas-system", "mpas-sample-project"]

  # How often the ClusterExternalSecret should reconcile itself
  # This will decide how often to check and make sure that the ExternalSecrets exist in the matching namespaces
  refreshTime: "1m"

  # This is the spec of the ExternalSecrets to be created
  # The content of this was taken from our ExternalSecret example
  externalSecretSpec:
    secretStoreRef:
      name: secret-store-name
      kind: ClusterSecretStore

    refreshInterval: "1h"
    target:
      name: ocm-registry-tls-certs
    data:
    - secretKey: ca.crt # name of the property in the remote secret
      remoteRef:
        key: ocm-registry-tls-certs # name of the secret
        property: ca.crt
    - secretKey: tls.crt
      remoteRef:
        key: ocm-registry-tls-certs
        property: tls.crt
    - secretKey: tls.key
      remoteRef:
        key: ocm-registry-tls-certs
        property: tls.key
```

The namespaceSelector defines where this secret needs to appear. The data section describes how to create the secret's
`data` part. This might looks a bit all over the place:

```yaml
    - secretKey: tls.crt
      remoteRef:
        key: ocm-registry-tls-certs
        property: tls.crt
```

Don't think about this coming from a secret, but a completely different medium.
- `secretKey` will be the name of the key in the created secret.
- `remoteRef` defines the remote secret options. For us, using Kubernetes provider:
    - `key` is the name of the secret this data is contained in
    - `property` is the property in the remote secret we want to copy

There is also an optional `version` field.

## Updating

Now let's come to the interesting part. To aliviate some of the trouble of going through and updating the service account
with access secrets that is used by the project's many objects like `ComponentVersion` and `ComponentSubscription` etc,
we provide the ability to automatically add any pull secrets that the service account has to provide.

To do this, simply mark a created secret with the annotation `mpas.ocm.system/secret.dockerconfig`. The
`mpas-project-controller` will detect these secrets and add them to the service account. It will leave any existing
items in the service account so updating by hand is also an option.

```yaml
apiVersion: external-secrets.io/v1beta1
kind: ClusterExternalSecret
metadata:
  name: replicator-docker-pull-access
spec:
  # The name to be used on the ExternalSecrets
  externalSecretName: "replicator-docker-pull-access-cert-es"

  # This is a basic label selector to select the namespaces to deploy ExternalSecrets to.
  # you can read more about them here https://kubernetes.io/docs/concepts/overview/working-with-objects/labels/#resources-that-support-set-based-requirements
  namespaceSelector:
    matchExpressions:
      - key: "kubernetes.io/metadata.name"
        operator: "In"
        values: ["mpas-sample-project", "ocm-system", "mpas-system"]

  # How often the ClusterExternalSecret should reconcile itself
  # This will decide how often to check and make sure that the ExternalSecrets exist in the matching namespaces
  refreshTime: "1m"

  # This is the spec of the ExternalSecrets to be created
  # The content of this was taken from our ExternalSecret example
  externalSecretSpec:
    secretStoreRef:
      name: secret-store-name
      kind: ClusterSecretStore
    target:
      template:
        type: kubernetes.io/dockerconfigjson
        metadata:
          annotations:
            # this will make sure that this pull access is also put into the service account created by the project.
            mpas.ocm.system/secret.dockerconfig: managed
        data:
          .dockerconfigjson: "{{ .dockerconfigjson | toString }}"
      name: regcreds
      creationPolicy: Owner
    data:
    - secretKey: .dockerconfigjson
      remoteRef:
        key: regcred
        property: .dockerconfigjson
```
