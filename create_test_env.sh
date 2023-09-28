#!/bin/bash

# create the cluster
kind create cluster --name=external-secret-demo

(
    cd ../mpas-project-controller || return
    flux install
    tilt ci
)

# apply external-secrets manifest
kubectl apply -f ./external-secrets-manifest/external-secrets.yaml


# update the default service account with secret priviledges
kubectl apply -f cluster_role.yaml
kubectl apply -f cluster_role_binding.yaml

# create some test data
# create some secrets in mpas-system we want to replicate with labels.
kubectl apply -f certificates.yaml
kubectl apply -f git_secret.yaml

# Apply the external secrets objects.
kubectl apply -f cluster_secret_store.yaml
kubectl apply -f cluster_external_secret_git.yaml
kubectl apply -f cluster_external_secret_cert.yaml

# Testing applying test-secret.yaml
kubectl apply -f test-secret.yaml

# Check if the secret has been applied to the service account.
kubectl describe serviceaccount mpas-sample-project -n mpas-sample-project