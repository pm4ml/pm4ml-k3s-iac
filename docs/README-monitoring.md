## Monitoring stack options

### EFK (Elasticsearch, Fluentd, Kibana) + Grafana + Prometheus
EFK is a commonly used and popular logging and monitoring stack used across the open source community. 
Elasticsearch can become difficult to manage and upgrade, particularly in small footprint environments where k3s is intended to be deployed.

However, Mojaloop currently has a dependency on elasticsearch, so if deploying mojaloop on this cluster, it may make sense to utilise elasticsearch for all logging data. 

This option was the only available prior to Feb 2021 and is therefore the default for backwards compatibility with existing environments. 

With the EFK stack, Kibana is used for viewing logs, and Grafana is used for viewing metrics. 

See [this digital ocean article](https://www.digitalocean.com/community/tutorials/how-to-set-up-an-elasticsearch-fluentd-and-kibana-efk-logging-stack-on-kubernetes) for a good description of EFK stack and how it is deployed. 


### Loki (Loki, Promtail, Grafana, Prometheus)
"Like prometheus, but for logs" is a good description from Grafana labs of what Loki provides. It is a lightweight alternative to elastic search optimised for storing and querying log data. Additionally, since it is built by grafana labs, it integrates well with grafana as a datasource.

With Loki, Grafana is used for viewing both logs and metrics.

See [grafana docs](https://grafana.com/docs/loki/latest/overview/comparisons/) for a good comparison and overview of Loki.

This option is recommended for any environment which does not require elasticsearch as it is much easier to support and operate. 