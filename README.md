# eoepca-plus

[![Smoke Tests](https://github.com/EOEPCA/eoepca-plus/actions/workflows/run-smoke-tests.yaml/badge.svg)](https://github.com/EOEPCA/eoepca-plus/actions/workflows/run-smoke-tests.yaml)
[![Smoke Tests](https://github.com/EOEPCA/eoepca-plus/actions/workflows/run-acceptance-tests.yaml/badge.svg)](https://github.com/EOEPCA/eoepca-plus/actions/workflows/run-acceptance-tests.yaml)
[![GitHub commit activity](https://img.shields.io/github/commit-activity/m/EOEPCA/eoepca-plus.svg)](https://github.com/EOEPCA/eoepca-plus/commits)
[![GitHub issues](https://img.shields.io/github/issues/EOEPCA/eoepca-plus.svg)](https://github.com/EOEPCA/eoepca-plus/issues)
[![License](https://img.shields.io/badge/License-Apache_2.0-blue.svg)](LICENSE)

EOEPCA+ deployments for development team

## Virtual Infrastructure

The `deploy` directory contains the Pulumi infrastructure code for setting up the EOEPCA+ platform on OpenStack.
See the corresponding [README](deploy/README.md) for setup instructions.

## ArgoCD Bootstrap

See [README](argocd/README.md) in `argocd` directory.
