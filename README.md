# Elastic Stack Helm Quickstart

Quick deployment of Elasticsearch, Kibana, Logstash, and Fleet Server to Kubernetes using public Docker images.

## Quick Start (3 Steps)

### 1. Setup Machine
```bash
cd deployment_infrastructure
./setup-machine.sh
```
Installs Docker, Kubernetes (K3s), Helm, and sets up a local container registry.

### 2. Deploy Elastic Stack
```bash
cd ../helm_charts
./deploy.sh
```
Deploys Elasticsearch, Kibana, Logstash, and optionally Fleet Server.

### 3. Configure Fleet (Optional)
```bash
cd ../deployment_infrastructure
./setup-fleet.sh
```
Configures Fleet Server in Kibana via API.

## Features

- 🚀 Simple three-script deployment workflow
- 🔧 Automated machine setup (Docker, K3s, Helm)
- 🔄 Interactive component selection
- 🔐 Automatic password setup
- ☁️ Uses official Elastic Docker images
- 🏗️ Production-ready Kubernetes deployment

## Prerequisites

- Ubuntu/Debian Linux machine (or compatible)
- Internet access (for initial setup)
- Sudo privileges

## Deployment Workflow

```
┌─────────────────────────────────────────┐
│  1. setup-machine.sh                    │
│     • Installs Docker                   │
│     • Installs K3s (Kubernetes)         │
│     • Installs Helm                     │
│     • Sets up local registry            │
└─────────────────┬───────────────────────┘
                  │
                  ▼
┌─────────────────────────────────────────┐
│  2. deploy.sh                           │
│     • Deploys Elasticsearch             │
│     • Deploys Kibana                    │
│     • Deploys Logstash                  │
│     • Deploys Fleet Server (optional)   │
└─────────────────┬───────────────────────┘
                  │
                  ▼
┌─────────────────────────────────────────┐
│  3. setup-fleet.sh (optional)           │
│     • Configures Fleet in Kibana        │
│     • Creates Fleet Server policy       │
│     • Sets up agent enrollment          │
└─────────────────────────────────────────┘
```

## Access Services

**Kibana**: http://localhost:5601 (elastic/elastic)
```bash
kubectl port-forward -n elastic svc/kibana 5601:5601
```

**Elasticsearch**: http://localhost:9200
```bash
kubectl port-forward -n elastic svc/elasticsearch-master 9200:9200
```

**Fleet Server**: http://localhost:8220
```bash
kubectl port-forward -n elastic svc/fleet-server 8220:8220
```

## Components

- Elasticsearch 9.2.2
- Kibana 9.2.2
- Logstash 9.2.2
- Fleet Server 9.2.3

## Project Structure

```
.
├── deployment_infrastructure/   # Setup scripts
│   ├── setup-machine.sh        # 1. Install Docker, K3s, Helm
│   └── setup-fleet.sh          # 3. Configure Fleet in Kibana
├── helm_charts/                 # Helm charts
│   ├── deploy.sh               # 2. Deploy Elastic Stack
│   ├── elasticsearch/
│   ├── kibana/
│   ├── logstash/
│   └── fleet-server/
├── README.md                    # This file
├── DEPLOYMENT-WORKFLOW.md       # Detailed deployment guide
└── TROUBLESHOOTING.md          # Common issues and solutions
```

## Documentation

- **[DEPLOYMENT-WORKFLOW.md](DEPLOYMENT-WORKFLOW.md)** - Detailed deployment workflow and architecture
- **[TROUBLESHOOTING.md](TROUBLESHOOTING.md)** - Common issues and solutions
- **[helm_charts/README.md](helm_charts/README.md)** - Comprehensive Helm charts documentation
- **[helm_charts/QUICKSTART.md](helm_charts/QUICKSTART.md)** - Quick reference guide

## Uninstall

```bash
# Uninstall all components
helm uninstall elasticsearch kibana logstash fleet-server -n elastic

# Delete persistent data
kubectl delete pvc -n elastic --all

# Delete namespace
kubectl delete namespace elastic
```

## Support

For issues or questions:
1. Check [TROUBLESHOOTING.md](TROUBLESHOOTING.md)
2. Review logs: `kubectl logs -n elastic -l app=<component>`
3. Check events: `kubectl get events -n elastic`
