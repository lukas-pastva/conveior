## Conveior operator

- I have built Kubernetes operator so that manipulation and configuration is a lot simpler
- CRDs:
  - Conveior
  - ConveiorBackupJob
  - ConveiorRestoreJob


#### More info on how to build k8s operator:
- `go mod init conveior.io/ConveiorOperator`
- `operator-sdk init`
- `https://developers.redhat.com/articles/2021/09/07/build-kubernetes-operator-six-steps#`