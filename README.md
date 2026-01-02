# Elastic Stack Helm Quickstart

Quick deployment of Elasticsearch, Kibana, Logstash, and Fleet Server to Kubernetes using public Docker images.

## Quick Start

```bash
cd helm_charts
./deploy.sh
```

## Features

- 🚀 Simple one-script deployment
- 🔄 Choose latest or specific versions
- 🔐 Automatic password setup
- ☁️ Uses official Elastic Docker images

## Prerequisites

- Kubernetes cluster
- kubectl configured
- helm 3.0+
- Internet access

## Access

**Kibana**: http://localhost:5601 (elastic/elastic)
```bash
kubectl port-forward -n elastic svc/kibana 5601:5601
```

**Elasticsearch**: http://localhost:9200
```bash
kubectl port-forward -n elastic svc/elasticsearch-master 9200:9200
```

## Components

- Elasticsearch 9.2.2
- Kibana 9.2.2
- Logstash 9.2.2
- Fleet Server 9.2.3

See full documentation in docs/
