.. _index:

Welcome to conveior.io
=============================================

.. toctree::
   :maxdepth: 2
   :caption: Contents:

About Conveior
==================

Conveior.io is a DevOps Docker+Kubernetes tool

TLDR: Do you need out of box lightweight solution to back up all of your DB and Stateful Pods? Even Docker containers? Well conveior will convey the backups for You!

 - Opensource
 - Backup and restore Docker containers or k8s pods (MySQL, Files)
 - Custom SQL Metrics (YAML defined custom SQL queries exposing Prometheus metrics)
 - https://github.com/lukas-pastva/conveior
 - https://hub.docker.com/repository/docker/lukaspastva/conveior


Installation
==================

Kubernetes Operator
- https://github.com/lukas-pastva/conveior/tree/main/installation-operator
- Install the operator via HELM chart and use CRDs in convinient way

HELM installation
- https://github.com/lukas-pastva/conveior/tree/main/installation-helm
- There is a HELM chart in conveior repo. Just run it as you would normally do.
- The chart will be soon uploaded to global helm registry

Standard Kubernetes installation
- https://github.com/lukas-pastva/conveior/tree/main/installation-kubernetes
- There are static Kubernetes manifests that will deploy conveior into daemon sets.
- Also it will create ServiceMonitor that will be scraped by Prometheus.

Docker installation
- https://github.com/lukas-pastva/conveior/tree/main/installation-docker
- In directory conveior-docker there is docker-compose file and bash file to help you installing conveior on your docker server.

License
==================
- This is fully OpenSource tool. Do whatever You want with it :-)
- Apache License, Version 2.0, January 2004

Contact
==================

 - E-mail: info@lukaspastva.sk