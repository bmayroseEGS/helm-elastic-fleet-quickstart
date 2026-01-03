#!/bin/bash
################################################################################
# Script: setup-machine.sh
# Purpose: Initial setup for Ubuntu machine (Docker, Git, prerequisites)
# Usage: ./setup-machine.sh
################################################################################

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Print functions
print_header() {
    echo ""
    echo "========================================"
    echo "$1"
    echo "========================================"
}

print_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

################################################################################
# Check if running on Ubuntu/Debian
################################################################################
check_os() {
    print_header "Checking Operating System"

    if [ -f /etc/os-release ]; then
        . /etc/os-release
        print_info "OS: $NAME $VERSION"

        if [[ "$ID" != "ubuntu" ]] && [[ "$ID" != "debian" ]]; then
            print_warning "This script is designed for Ubuntu/Debian"
            read -p "Continue anyway? (y/n): " continue_install
            if [[ ! "$continue_install" =~ ^[Yy]$ ]]; then
                exit 0
            fi
        fi
    else
        print_warning "Cannot determine OS type"
    fi
}

################################################################################
# Update system packages
################################################################################
update_packages() {
    print_header "Updating System Packages"

    print_info "Running apt update..."
    sudo apt update

    print_info "Upgrading installed packages..."
    read -p "Do you want to upgrade existing packages? (y/n): " upgrade
    if [[ "$upgrade" =~ ^[Yy]$ ]]; then
        sudo apt upgrade -y
        print_info "✓ Packages upgraded"
    else
        print_info "Skipping package upgrade"
    fi

    print_info "✓ Package lists updated"
}

################################################################################
# Install Docker
################################################################################
install_docker() {
    print_header "Installing Docker"

    # Check if Docker is already installed
    if command -v docker &> /dev/null; then
        print_info "Docker is already installed: $(docker --version)"
        read -p "Reinstall Docker? (y/n): " reinstall
        if [[ ! "$reinstall" =~ ^[Yy]$ ]]; then
            print_info "Skipping Docker installation"
            return 0
        fi
    fi

    print_info "Downloading Docker installation script..."
    curl -fsSL https://get.docker.com -o get-docker.sh

    print_info "Installing Docker..."

    # Try installing Docker with error handling
    if sudo sh get-docker.sh; then
        print_info "Cleaning up installation script..."
        rm get-docker.sh
        print_info "✓ Docker installed: $(docker --version)"
        return 0
    fi

    # Docker installation failed - offer workarounds
    print_error "Docker installation failed!"
    echo ""
    print_warning "This is often caused by temporary issues with Docker's package repository"
    echo ""

    while true; do
        echo "Choose a workaround:"
        echo ""
        echo "  1) Retry installation (wait 30s and try again)"
        echo "     Use if: Temporary repository sync issue"
        echo ""
        echo "  2) Install docker.io from Ubuntu repositories"
        echo "     Use if: You want stable Ubuntu-packaged Docker"
        echo "     Note: May be an older version"
        echo ""
        echo "  3) Manual containerd version selection"
        echo "     Use if: Specific containerd package is missing"
        echo "     Note: Advanced option"
        echo ""
        echo "  4) Skip Docker installation"
        echo ""
        read -p "Select option (1-4): " choice

        case $choice in
            1)
                print_info "Waiting 30 seconds before retry..."
                sleep 30
                print_info "Retrying Docker installation..."
                if sudo sh get-docker.sh; then
                    print_info "Cleaning up installation script..."
                    rm get-docker.sh
                    print_info "✓ Docker installed: $(docker --version)"
                    return 0
                else
                    print_error "Retry failed. Try another option."
                    echo ""
                fi
                ;;
            2)
                print_info "Installing docker.io from Ubuntu repositories..."
                rm get-docker.sh
                sudo apt update
                sudo apt install -y docker.io docker-compose

                if command -v docker &> /dev/null; then
                    print_info "✓ Docker installed: $(docker --version)"
                    return 0
                else
                    print_error "Installation failed. Try another option."
                    echo ""
                fi
                ;;
            3)
                print_info "Checking available containerd.io versions..."
                rm get-docker.sh

                # Update package cache
                sudo apt update

                # Get latest containerd.io version automatically
                echo ""
                print_info "Detecting latest available containerd.io version..."

                # Get top 3 versions as fallback options
                latest_containerd=$(apt-cache madison containerd.io | head -1 | awk '{print $3}')
                second_latest=$(apt-cache madison containerd.io | sed -n '2p' | awk '{print $3}')

                if [ -n "$latest_containerd" ]; then
                    print_info "Latest version detected: $latest_containerd"

                    # Note: apt-cache may show versions that don't actually exist yet
                    if [ -n "$second_latest" ]; then
                        echo "         Second latest: $second_latest"
                    fi
                    echo ""
                    read -p "Install latest version ($latest_containerd)? (y/n): " use_latest

                    if [[ "$use_latest" =~ ^[Yy]$ ]]; then
                        containerd_version="$latest_containerd"
                    else
                        # Show available versions for manual selection
                        echo ""
                        print_info "Available containerd.io versions:"
                        apt-cache madison containerd.io | head -10
                        echo ""

                        read -p "Enter specific version or 'cancel': " containerd_version

                        if [[ "$containerd_version" == "cancel" ]] || [[ -z "$containerd_version" ]]; then
                            print_info "Cancelled. Choose another option."
                            echo ""
                            continue
                        fi
                    fi
                else
                    print_error "Could not detect containerd.io versions"
                    echo ""
                    continue
                fi

                print_info "Installing Docker with containerd.io=$containerd_version..."

                # Install Docker components with specific containerd version
                sudo apt install -y \
                    apt-transport-https \
                    ca-certificates \
                    curl \
                    gnupg \
                    lsb-release

                # Add Docker's GPG key
                sudo mkdir -p /etc/apt/keyrings
                curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg

                # Add Docker repository
                echo \
                  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
                  $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

                sudo apt update

                # Install with specific containerd version
                if sudo apt install -y containerd.io=$containerd_version docker-ce docker-ce-cli docker-buildx-plugin docker-compose-plugin; then
                    print_info "✓ Docker installed: $(docker --version)"
                    return 0
                else
                    # If installation failed and we have a second-latest version, offer to try it
                    if [ -n "$second_latest" ] && [ "$containerd_version" = "$latest_containerd" ]; then
                        echo ""
                        print_warning "Installation of $containerd_version failed (package may not exist yet)"
                        print_info "Second latest version available: $second_latest"
                        echo ""
                        read -p "Try installing $second_latest instead? (y/n): " try_second

                        if [[ "$try_second" =~ ^[Yy]$ ]]; then
                            print_info "Installing Docker with containerd.io=$second_latest..."
                            if sudo apt install -y containerd.io=$second_latest docker-ce docker-ce-cli docker-buildx-plugin docker-compose-plugin; then
                                print_info "✓ Docker installed: $(docker --version)"
                                return 0
                            fi
                        fi
                    fi

                    print_error "Installation failed. Try another option."
                    echo ""
                fi
                ;;
            4)
                print_warning "Skipping Docker installation"
                rm get-docker.sh 2>/dev/null || true
                return 1
                ;;
            *)
                print_error "Invalid option. Please choose 1-4."
                echo ""
                ;;
        esac
    done
}

################################################################################
# Configure Docker permissions
################################################################################
configure_docker_permissions() {
    print_header "Configuring Docker Permissions"

    local current_user=$(whoami)
    print_info "Adding user '$current_user' to docker group..."

    sudo usermod -aG docker "$current_user"

    print_info "✓ User added to docker group"
    print_warning "You need to log out and back in for group changes to take effect"
    print_info "Or run: newgrp docker"
}

################################################################################
# Verify Docker installation
################################################################################
verify_docker() {
    print_header "Verifying Docker Installation"

    print_info "Docker version:"
    docker --version || true

    echo ""
    print_info "Testing Docker with newgrp (temporary group activation)..."

    # Use newgrp to test Docker without logout
    if newgrp docker << 'EOFTEST'
docker info > /dev/null 2>&1
EOFTEST
    then
        print_info "✓ Docker is working correctly"
    else
        print_warning "⚠ Docker requires logout/login or run: newgrp docker"
    fi
}

################################################################################
# Configure Git
################################################################################
configure_git() {
    print_header "Configuring Git"

    # Check if git is installed
    if ! command -v git &> /dev/null; then
        print_info "Git not found. Installing git..."
        sudo apt install -y git
        print_info "✓ Git installed: $(git --version)"
    else
        print_info "Git is already installed: $(git --version)"
    fi

    echo ""
    print_info "Git requires your name and email for commits"
    echo ""

    # Check current git config
    local current_name=$(git config --global user.name 2>/dev/null || echo "")
    local current_email=$(git config --global user.email 2>/dev/null || echo "")

    if [ -n "$current_name" ] && [ -n "$current_email" ]; then
        print_info "Current Git configuration:"
        echo "  Name:  $current_name"
        echo "  Email: $current_email"
        echo ""
        read -p "Keep current configuration? (y/n): " keep_config
        if [[ "$keep_config" =~ ^[Yy]$ ]]; then
            print_info "Keeping existing Git configuration"
            return 0
        fi
    fi

    # Interactive Git configuration
    echo ""
    read -p "Enter your Git username: " git_name
    while [ -z "$git_name" ]; do
        print_warning "Username cannot be empty"
        read -p "Enter your Git username: " git_name
    done

    read -p "Enter your Git email: " git_email
    while [ -z "$git_email" ]; do
        print_warning "Email cannot be empty"
        read -p "Enter your Git email: " git_email
    done

    # Set Git configuration
    git config --global user.name "$git_name"
    git config --global user.email "$git_email"

    print_info "✓ Git configured:"
    echo "  Name:  $(git config --global user.name)"
    echo "  Email: $(git config --global user.email)"

    # Optional: Set default branch name
    echo ""
    read -p "Set default branch name to 'main'? (y/n): " set_main
    if [[ "$set_main" =~ ^[Yy]$ ]]; then
        git config --global init.defaultBranch main
        print_info "✓ Default branch set to 'main'"
    fi
}

################################################################################
# Install additional useful tools
################################################################################
install_additional_tools() {
    print_header "Installing Additional Tools"

    echo ""
    print_info "Recommended tools for air-gapped deployment:"
    echo "  - curl: Download files"
    echo "  - wget: Download files"
    echo "  - jq: JSON processor (used by scripts)"
    echo "  - vim: Text editor"
    echo ""

    read -p "Install recommended tools? (y/n): " install_tools
    if [[ "$install_tools" =~ ^[Yy]$ ]]; then
        print_info "Installing tools..."
        sudo apt install -y curl wget jq vim

        print_info "✓ Additional tools installed"
    else
        print_info "Skipping additional tools"
    fi
}

################################################################################
# Clone additional repository (optional)
################################################################################
clone_repository() {
    print_header "Clone Additional Repository"

    echo ""
    print_info "This script is part of helm-fleet-deployment (already cloned)"
    echo ""
    read -p "Do you want to clone an additional repository? (y/n): " clone_repo
    if [[ ! "$clone_repo" =~ ^[Yy]$ ]]; then
        print_info "Skipping repository clone"
        return 0
    fi

    read -p "Enter repository URL: " repo_url
    if [ -z "$repo_url" ]; then
        print_info "No URL provided, skipping"
        return 0
    fi

    # Extract repo name from URL (last part without .git)
    local default_dir=$(basename "$repo_url" .git)

    read -p "Enter directory name (default: $default_dir): " dir_name
    dir_name=${dir_name:-$default_dir}

    # Clone one level up from current directory
    local clone_path="../$dir_name"

    if [ -d "$clone_path" ]; then
        print_warning "Directory '$clone_path' already exists"
        return 0
    fi

    print_info "Cloning repository to: $clone_path"
    git clone "$repo_url" "$clone_path"

    print_info "✓ Repository cloned to: $clone_path"
}

################################################################################
# Install K3s (Lightweight Kubernetes)
################################################################################
install_k3s() {
    print_header "Installing K3s (Kubernetes)"

    # Check if k3s is already installed
    if command -v k3s &> /dev/null; then
        print_info "K3s is already installed: $(k3s --version | head -1)"
        read -p "Reinstall K3s? (y/n): " reinstall
        if [[ ! "$reinstall" =~ ^[Yy]$ ]]; then
            print_info "Skipping K3s installation"
            return 0
        fi
        print_info "Uninstalling existing K3s..."
        sudo /usr/local/bin/k3s-uninstall.sh || true
        sleep 2
    fi

    print_info "Installing K3s..."
    echo ""
    print_info "K3s will be installed with:"
    echo "  - Built-in kubectl"
    echo "  - Built-in containerd"
    echo "  - Registry mirrors configuration for localhost:5000"
    echo ""

    # Install K3s with registry mirror configuration
    print_info "Downloading and installing K3s..."
    curl -sfL https://get.k3s.io | sh -s - \
        --write-kubeconfig-mode 644 \
        --disable traefik

    # Wait for k3s to be ready
    print_info "Waiting for K3s to start..."
    sleep 5

    # Check if k3s is running
    if systemctl is-active --quiet k3s; then
        print_info "✓ K3s installed and running: $(k3s --version | head -1)"

        # Create kubectl symlink if it doesn't exist
        if [ ! -f /usr/local/bin/kubectl ]; then
            print_info "Creating kubectl symlink..."
            sudo ln -s /usr/local/bin/k3s /usr/local/bin/kubectl
        fi

        print_info "✓ kubectl available: $(kubectl version --client --short 2>/dev/null || kubectl version --client)"
    else
        print_error "K3s installation failed"
        print_info "Check logs with: sudo journalctl -u k3s -n 50"
        return 1
    fi

    # Configure registry mirror for localhost:5000
    print_info "Configuring registry mirror for localhost:5000..."
    sudo mkdir -p /etc/rancher/k3s

    cat <<EOF | sudo tee /etc/rancher/k3s/registries.yaml > /dev/null
mirrors:
  "localhost:5000":
    endpoint:
      - "http://localhost:5000"
  "docker.io":
    endpoint:
      - "https://registry-1.docker.io"
configs:
  "localhost:5000":
    tls:
      insecure_skip_verify: true
EOF

    print_info "✓ Registry mirror configured for localhost:5000"

    # Restart k3s to apply registry configuration
    print_info "Restarting K3s to apply registry configuration..."
    sudo systemctl restart k3s
    sleep 5

    print_info "✓ K3s installation complete"
}

################################################################################
# Install Helm
################################################################################
install_helm() {
    print_header "Installing Helm"

    # Check if helm is already installed
    if command -v helm &> /dev/null; then
        print_info "Helm is already installed: $(helm version --short)"
        read -p "Reinstall Helm? (y/n): " reinstall
        if [[ ! "$reinstall" =~ ^[Yy]$ ]]; then
            print_info "Skipping Helm installation"
            return 0
        fi
    fi

    print_info "Downloading Helm installation script..."
    curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 -o get_helm.sh

    print_info "Installing Helm..."
    chmod 700 get_helm.sh
    ./get_helm.sh

    rm get_helm.sh

    if command -v helm &> /dev/null; then
        print_info "✓ Helm installed: $(helm version --short)"
    else
        print_error "Helm installation failed"
        return 1
    fi
}

################################################################################
# Setup local Docker registry
################################################################################
setup_local_registry() {
    print_header "Setting Up Local Docker Registry"

    # Check if registry is already running
    if docker ps --format '{{.Names}}' | grep -q "^registry$"; then
        print_info "Docker registry is already running"
        read -p "Restart registry? (y/n): " restart
        if [[ "$restart" =~ ^[Yy]$ ]]; then
            print_info "Stopping existing registry..."
            docker stop registry
            docker rm registry
        else
            print_info "Keeping existing registry"
            return 0
        fi
    fi

    print_info "Starting local Docker registry on port 5000..."
    docker run -d \
        --name registry \
        --restart=always \
        -p 5000:5000 \
        -v registry-data:/var/lib/registry \
        registry:2

    # Wait for registry to be ready
    sleep 3

    if docker ps --format '{{.Names}}' | grep -q "^registry$"; then
        print_info "✓ Docker registry running on localhost:5000"

        # Test registry
        if curl -s http://localhost:5000/v2/_catalog > /dev/null; then
            print_info "✓ Registry is accessible"
        else
            print_warning "Registry started but may not be ready yet"
        fi
    else
        print_error "Failed to start Docker registry"
        return 1
    fi
}

################################################################################
# Configure kubectl/k3s access
################################################################################
configure_kubectl() {
    print_header "Configuring kubectl/k3s Access"

    # Check if k3s is installed
    if [ ! -f /etc/rancher/k3s/k3s.yaml ]; then
        print_info "k3s config not found at /etc/rancher/k3s/k3s.yaml"
        print_info "Skipping kubectl configuration (install k3s first)"
        return 0
    fi

    print_info "Found k3s configuration"
    echo ""
    read -p "Configure kubectl to access k3s cluster? (y/n): " setup_kubectl
    if [[ ! "$setup_kubectl" =~ ^[Yy]$ ]]; then
        print_info "Skipping kubectl configuration"
        return 0
    fi

    # Create .kube directory
    mkdir -p ~/.kube

    # Copy k3s config to default kubectl location
    print_info "Copying k3s config to ~/.kube/config..."
    sudo cp /etc/rancher/k3s/k3s.yaml ~/.kube/config
    sudo chown $(id -u):$(id -g) ~/.kube/config

    # Add KUBECONFIG export to .bashrc if not already present
    if ! grep -q "KUBECONFIG" ~/.bashrc 2>/dev/null; then
        print_info "Adding KUBECONFIG to ~/.bashrc..."
        echo "" >> ~/.bashrc
        echo "# k3s kubectl configuration" >> ~/.bashrc
        echo "export KUBECONFIG=~/.kube/config" >> ~/.bashrc
    fi

    # Export for current session
    export KUBECONFIG=~/.kube/config

    print_info "✓ kubectl configured"
    echo ""

    # Test kubectl access
    if command -v kubectl &> /dev/null; then
        print_info "Testing kubectl access..."
        if kubectl get nodes &> /dev/null; then
            echo "  ✓ kubectl can access k3s cluster:"
            kubectl get nodes
        else
            print_warning "  kubectl installed but cannot access cluster yet"
            print_info "  You may need to start k3s first"
        fi
    else
        print_info "kubectl not installed. Install with:"
        print_info "  curl -LO https://dl.k8s.io/release/\$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
        print_info "  sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl"
    fi
}

################################################################################
# Display summary
################################################################################
display_summary() {
    print_header "Setup Complete"

    echo ""
    print_info "Installation Summary:"
    echo ""

    # Docker
    if command -v docker &> /dev/null; then
        echo "  ✓ Docker: $(docker --version)"
    else
        echo "  ✗ Docker: Not installed"
    fi

    # Git
    if command -v git &> /dev/null; then
        echo "  ✓ Git: $(git --version)"
        local git_name=$(git config --global user.name 2>/dev/null || echo "Not configured")
        local git_email=$(git config --global user.email 2>/dev/null || echo "Not configured")
        echo "    Name:  $git_name"
        echo "    Email: $git_email"
    else
        echo "  ✗ Git: Not installed"
    fi

    # K3s/Kubernetes
    if command -v k3s &> /dev/null; then
        echo "  ✓ K3s: $(k3s --version | head -1)"
        if systemctl is-active --quiet k3s; then
            echo "    Status: Running"
        else
            echo "    Status: Not running"
        fi
    else
        echo "  ✗ K3s: Not installed"
    fi

    # kubectl
    if command -v kubectl &> /dev/null; then
        echo "  ✓ kubectl: $(kubectl version --client --short 2>/dev/null || echo "Available")"
    else
        echo "  ✗ kubectl: Not installed"
    fi

    # Helm
    if command -v helm &> /dev/null; then
        echo "  ✓ Helm: $(helm version --short)"
    else
        echo "  ✗ Helm: Not installed"
    fi

    # Docker Registry
    if docker ps --format '{{.Names}}' 2>/dev/null | grep -q "^registry$"; then
        echo "  ✓ Docker Registry: Running on localhost:5000"
    else
        echo "  ✗ Docker Registry: Not running"
    fi

    # Additional tools
    local tools_status=""
    command -v curl &> /dev/null && tools_status+="curl "
    command -v wget &> /dev/null && tools_status+="wget "
    command -v jq &> /dev/null && tools_status+="jq "
    if [ -n "$tools_status" ]; then
        echo "  ✓ Tools: $tools_status"
    fi

    echo ""
    print_warning "IMPORTANT: Docker group membership requires a new login session!"
    echo ""
    print_info "You have two options:"
    echo ""
    echo "  Option 1 (Quick): Activate in current session"
    echo "    Run: newgrp docker"
    echo "    This creates a new shell with docker group active"
    echo ""
    echo "  Option 2 (Permanent): Logout and login"
    echo "    Run: exit"
    echo "    Then SSH/login again"
    echo ""

    echo ""
    print_warning "IMPORTANT: Docker registry setup requires Docker group membership!"
    echo ""

    read -p "Do you want to activate Docker permissions now and setup the registry? (y/n): " activate_now
    if [[ "$activate_now" =~ ^[Yy]$ ]]; then
        echo ""
        print_info "Activating Docker group and continuing setup..."
        echo ""

        # Continue setup in a new shell with docker group active
        newgrp docker <<'CONTINUE_SETUP'
#!/bin/bash
# Re-source the script functions for registry setup
source "$(dirname "$0")/$(basename "$0")" functions_only 2>/dev/null || true

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_header() {
    echo ""
    echo "========================================"
    echo "$1"
    echo "========================================"
}

print_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_header "Setting Up Local Docker Registry"

# Check if registry is already running
if docker ps --format '{{.Names}}' 2>/dev/null | grep -q "^registry$"; then
    print_info "Docker registry is already running"
else
    print_info "Starting local Docker registry on port 5000..."
    docker run -d \
        --name registry \
        --restart=always \
        -p 5000:5000 \
        -v registry-data:/var/lib/registry \
        registry:2 2>&1

    # Wait for registry to be ready
    sleep 3

    if docker ps --format '{{.Names}}' 2>/dev/null | grep -q "^registry$"; then
        print_info "✓ Docker registry running on localhost:5000"
        if curl -s http://localhost:5000/v2/_catalog > /dev/null; then
            print_info "✓ Registry is accessible"
        fi
    else
        print_error "Failed to start Docker registry"
    fi
fi

echo ""
print_header "Setup Complete!"
echo ""
echo "Next steps:"
echo ""
echo "  1. Deploy Elastic Stack:"
echo "     cd helm_charts"
echo "     ./deploy.sh"
echo ""
echo "  2. Configure Fleet (optional):"
echo "     cd deployment_infrastructure"
echo "     ./setup-fleet.sh"
echo ""
echo "  3. Access services (after deployment):"
echo "     kubectl port-forward -n elastic svc/kibana 5601:5601"
echo "     kubectl port-forward -n elastic svc/elasticsearch-master 9200:9200"
echo ""
CONTINUE_SETUP
    else
        echo ""
        print_warning "Skipping registry setup"
        echo ""
        print_info "To complete setup later:"
        echo "  1. Activate Docker group:"
        echo "     newgrp docker"
        echo ""
        echo "  2. Start registry:"
        echo "     docker run -d --name registry --restart=always -p 5000:5000 registry:2"
        echo ""
        echo "  3. Continue with deployment:"
        echo "     cd helm_charts"
        echo "     ./deploy.sh"
        echo ""
    fi
}

################################################################################
# Main execution
################################################################################
main() {
    echo "=========================================="
    echo "Elastic Stack Quickstart Setup Script"
    echo "=========================================="
    echo "This script will install and configure:"
    echo "  • Docker"
    echo "  • K3s (Kubernetes)"
    echo "  • kubectl"
    echo "  • Helm"
    echo "  • Local Docker Registry (localhost:5000)"
    echo ""

    check_os
    update_packages
    install_docker
    configure_docker_permissions
    verify_docker
    configure_git
    install_additional_tools
    install_k3s
    install_helm
    configure_kubectl
    clone_repository
    display_summary
    # Note: setup_local_registry is now called within display_summary after docker group activation
}

# Run main
main
