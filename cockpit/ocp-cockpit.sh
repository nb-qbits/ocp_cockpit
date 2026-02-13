#!/bin/bash
# ============================================================================
# OpenShift Mixed-Architecture Command Cockpit
# ============================================================================
# Source this file:  source ocp-cockpit.sh
# Then run any function by name, e.g.:  ocp-health
#
# Built during: Mixed Arch (x86_64 + aarch64) OpenShift on AWS setup
# Last updated: 2026-02-13
# ============================================================================

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color
BOLD='\033[1m'

# ============================================================================
# SECTION 1: CLUSTER HEALTH & DIAGNOSTICS
# ============================================================================

# Quick cluster health check - the first thing to run when something seems off
ocp-health() {
    echo -e "${BOLD}${CYAN}=== Cluster Version ===${NC}"
    oc get clusterversion
    echo ""

    echo -e "${BOLD}${CYAN}=== Unhealthy Cluster Operators ===${NC}"
    echo -e "${YELLOW}(Healthy = Available:True, Progressing:False, Degraded:False)${NC}"
    local unhealthy=$(oc get co | grep -v "True.*False.*False" | grep -v "^NAME")
    if [ -z "$unhealthy" ]; then
        echo -e "${GREEN}All operators healthy!${NC}"
    else
        echo -e "${RED}${unhealthy}${NC}"
    fi
    echo ""

    echo -e "${BOLD}${CYAN}=== Node Status ===${NC}"
    oc get nodes -o wide
    echo ""

    echo -e "${BOLD}${CYAN}=== Node Resource Pressure ===${NC}"
    oc describe nodes | grep -E "^Name:|MemoryPressure|DiskPressure|PIDPressure|Ready" | \
        sed 's/^Name:/\n&/'
}

# Show all cluster operators and their status
ocp-operators() {
    echo -e "${BOLD}${CYAN}=== All Cluster Operators ===${NC}"
    oc get co
}

# Show only unhealthy operators with details
ocp-operators-sick() {
    echo -e "${BOLD}${CYAN}=== Unhealthy Cluster Operators (with messages) ===${NC}"
    oc get co -o json | jq -r '
        .items[] |
        select(
            (.status.conditions[] | select(.type=="Available") | .status) != "True" or
            (.status.conditions[] | select(.type=="Progressing") | .status) != "False" or
            (.status.conditions[] | select(.type=="Degraded") | .status) != "False"
        ) |
        "\n\(.metadata.name):" +
        "\n  Available:   " + (.status.conditions[] | select(.type=="Available") | .status) +
        "\n  Progressing: " + (.status.conditions[] | select(.type=="Progressing") | .status) +
        "\n  Degraded:    " + (.status.conditions[] | select(.type=="Degraded") | .status) +
        "\n  Message:     " + (.status.conditions[] | select(.type=="Degraded") | .message // "none")
    '
}

# Cluster version detailed conditions (useful during upgrades/migrations)
ocp-version-detail() {
    echo -e "${BOLD}${CYAN}=== ClusterVersion Conditions ===${NC}"
    oc get clusterversion version -o json | jq '.status.conditions[]'
}

# ============================================================================
# SECTION 2: NODE & MACHINE MANAGEMENT
# ============================================================================

# Show nodes with architecture labels - essential for multi-arch
ocp-nodes-arch() {
    echo -e "${BOLD}${CYAN}=== Nodes by Architecture ===${NC}"
    oc get nodes --label-columns='kubernetes.io/arch' -o wide
}

# Show all machines and their instance types
ocp-machines() {
    echo -e "${BOLD}${CYAN}=== Machines ===${NC}"
    oc get machines -n openshift-machine-api -o wide
}

# Show all machinesets - the templates that define node groups
ocp-machinesets() {
    echo -e "${BOLD}${CYAN}=== MachineSets ===${NC}"
    oc get machinesets -n openshift-machine-api -o wide
}

# Show node resource usage (requires metrics-server)
ocp-node-resources() {
    echo -e "${BOLD}${CYAN}=== Node Resource Usage ===${NC}"
    echo -e "${YELLOW}(Requires metrics-server to be running)${NC}"
    oc adm top nodes 2>/dev/null || echo -e "${RED}Metrics not available. Try: oc describe node | grep -A5 'Allocated resources'${NC}"
    echo ""
    echo -e "${BOLD}${CYAN}=== Allocated Resources (from describe) ===${NC}"
    oc describe nodes | grep -A 12 "Allocated resources:"
}

# ============================================================================
# SECTION 3: MULTI-ARCHITECTURE SPECIFIC
# ============================================================================

# Check if cluster is using multi-arch payload
ocp-multiarch-check() {
    echo -e "${BOLD}${CYAN}=== Multi-Architecture Payload Check ===${NC}"
    local metadata=$(oc adm release info -o jsonpath="{ .metadata.metadata }")
    echo "Raw metadata: $metadata"
    echo ""
    if echo "$metadata" | grep -q '"multi"'; then
        echo -e "${GREEN}✓ Cluster IS using multi-architecture payload${NC}"
    else
        echo -e "${RED}✗ Cluster is NOT using multi-architecture payload${NC}"
        echo -e "${YELLOW}  Run: oc adm upgrade --to-multi-arch${NC}"
    fi
}

# Show pods scheduled by architecture
ocp-pods-by-arch() {
    echo -e "${BOLD}${CYAN}=== Pod Distribution by Node Architecture ===${NC}"
    for node in $(oc get nodes -o jsonpath='{.items[*].metadata.name}'); do
        arch=$(oc get node $node -o jsonpath='{.metadata.labels.kubernetes\.io/arch}')
        count=$(oc get pods --all-namespaces --field-selector spec.nodeName=$node --no-headers 2>/dev/null | wc -l)
        echo -e "  ${BOLD}$node${NC} (${CYAN}$arch${NC}): $count pods"
    done
}

# List all supported architectures in the cluster
ocp-ami-architectures() {
    echo -e "${BOLD}${CYAN}=== Supported Architectures ===${NC}"
    oc get configmap/coreos-bootimages -n openshift-machine-config-operator \
        -o jsonpath='{.data.stream}' | jq '.architectures | keys'
}

# Show AMIs for your region across all architectures
ocp-ami-region() {
    local region=${1:-"us-east-2"}
    echo -e "${BOLD}${CYAN}=== RHCOS AMIs for region: $region ===${NC}"
    oc get configmap/coreos-bootimages -n openshift-machine-config-operator \
        -o jsonpath='{.data.stream}' | jq --arg r "$region" '
        .architectures | to_entries[] |
        select(.value.images.aws.regions[$r] != null) |
        {architecture: .key, region: $r, ami: .value.images.aws.regions[$r].image}
    '
}

# Show all AWS regions available for a specific architecture
ocp-ami-all-regions() {
    local arch=${1:-"aarch64"}
    echo -e "${BOLD}${CYAN}=== All AWS regions for architecture: $arch ===${NC}"
    oc get configmap/coreos-bootimages -n openshift-machine-config-operator \
        -o jsonpath='{.data.stream}' | jq --arg a "$arch" '
        .architectures[$a].images.aws.regions | to_entries[] |
        {region: .key, ami: .value.image}
    '
}

# Quick AMI lookup: get the AMI for a specific arch + region
ocp-ami-lookup() {
    local arch=${1:?"Usage: ocp-ami-lookup <arch> [region]  (arch: x86_64, aarch64, ppc64le, s390x)"}
    local region=${2:-"us-east-2"}
    echo -e "${BOLD}${CYAN}=== AMI Lookup ===${NC}"
    local ami=$(oc get configmap/coreos-bootimages -n openshift-machine-config-operator \
        -o jsonpath='{.data.stream}' | jq -r --arg a "$arch" --arg r "$region" \
        '.architectures[$a].images.aws.regions[$r].image')
    if [ "$ami" = "null" ] || [ -z "$ami" ]; then
        echo -e "${RED}No AMI found for arch=$arch region=$region${NC}"
    else
        echo -e "  Architecture: ${CYAN}$arch${NC}"
        echo -e "  Region:       ${CYAN}$region${NC}"
        echo -e "  AMI:          ${GREEN}$ami${NC}"
    fi
}

# Check Multiarch Tuning Operator status
ocp-multiarch-operator() {
    echo -e "${BOLD}${CYAN}=== Multiarch Tuning Operator ===${NC}"
    oc get csv -n openshift-multiarch-tuning-operator 2>/dev/null || \
        echo -e "${YELLOW}Multiarch Tuning Operator not installed${NC}"
    echo ""
    echo -e "${BOLD}${CYAN}=== ClusterPodPlacementConfig ===${NC}"
    oc get clusterpodplacementconfig 2>/dev/null || \
        echo -e "${YELLOW}No ClusterPodPlacementConfig found${NC}"
}

# ============================================================================
# SECTION 4: POD & WORKLOAD TROUBLESHOOTING
# ============================================================================

# Show all non-running pods (the "what's broken" view)
ocp-pods-sick() {
    echo -e "${BOLD}${CYAN}=== Non-Running Pods (across all namespaces) ===${NC}"
    local sick=$(oc get pods -A | grep -vE "Running|Completed" | grep -v "^NAMESPACE")
    if [ -z "$sick" ]; then
        echo -e "${GREEN}All pods are healthy!${NC}"
    else
        echo -e "${RED}${sick}${NC}"
    fi
}

# Show pods in a specific namespace with status
ocp-pods-ns() {
    local ns=${1:-"default"}
    echo -e "${BOLD}${CYAN}=== Pods in namespace: $ns ===${NC}"
    oc get pods -n "$ns" -o wide
}

# Get events for troubleshooting (sorted by time, last 20)
ocp-events() {
    local ns=${1:-"--all-namespaces"}
    echo -e "${BOLD}${CYAN}=== Recent Events ===${NC}"
    if [ "$ns" = "--all-namespaces" ]; then
        oc get events -A --sort-by='.lastTimestamp' | tail -20
    else
        oc get events -n "$ns" --sort-by='.lastTimestamp' | tail -20
    fi
}

# ============================================================================
# SECTION 5: IMAGE & BUILD INSPECTION
# ============================================================================

# Check if an image is multi-arch (manifest list)
ocp-image-arch() {
    local image=${1:?"Usage: ocp-image-arch <image:tag>"}
    echo -e "${BOLD}${CYAN}=== Architecture check for: $image ===${NC}"
    oc image info "$image" 2>/dev/null || \
        echo -e "${YELLOW}Try: podman manifest inspect $image${NC}"
}

# ============================================================================
# SECTION 6: OPENSHIFT AI
# ============================================================================

# Check OpenShift AI operator status
ocp-ai-status() {
    echo -e "${BOLD}${CYAN}=== OpenShift AI Operator ===${NC}"
    oc get csv -n redhat-ods-operator 2>/dev/null || \
    oc get csv -n openshift-operators 2>/dev/null | grep -i "rhods\|openshift-ai" || \
        echo -e "${YELLOW}OpenShift AI operator not found${NC}"
    echo ""
    echo -e "${BOLD}${CYAN}=== DataScienceClusters ===${NC}"
    oc get datascienceclusters 2>/dev/null || \
        echo -e "${YELLOW}No DataScienceCluster resources found${NC}"
    echo ""
    echo -e "${BOLD}${CYAN}=== InferenceServices ===${NC}"
    oc get inferenceservices -A 2>/dev/null || \
        echo -e "${YELLOW}No InferenceServices found${NC}"
}

# ============================================================================
# SECTION 7: QUICK REFERENCES
# ============================================================================

# List all available cockpit commands
ocp-help() {
    echo -e "${BOLD}${CYAN}============================================${NC}"
    echo -e "${BOLD}${CYAN}  OpenShift Mixed-Arch Command Cockpit${NC}"
    echo -e "${BOLD}${CYAN}============================================${NC}"
    echo ""
    echo -e "${BOLD}CLUSTER HEALTH:${NC}"
    echo -e "  ${GREEN}ocp-health${NC}              Full cluster health check (start here)"
    echo -e "  ${GREEN}ocp-operators${NC}           List all cluster operators"
    echo -e "  ${GREEN}ocp-operators-sick${NC}      Show unhealthy operators with details"
    echo -e "  ${GREEN}ocp-version-detail${NC}      ClusterVersion conditions (upgrade status)"
    echo ""
    echo -e "${BOLD}NODES & MACHINES:${NC}"
    echo -e "  ${GREEN}ocp-nodes-arch${NC}          Nodes with architecture labels"
    echo -e "  ${GREEN}ocp-machines${NC}            All machines and instance types"
    echo -e "  ${GREEN}ocp-machinesets${NC}         All machinesets (node group templates)"
    echo -e "  ${GREEN}ocp-node-resources${NC}      Node CPU/memory usage"
    echo ""
    echo -e "${BOLD}MULTI-ARCHITECTURE:${NC}"
    echo -e "  ${GREEN}ocp-multiarch-check${NC}     Is cluster using multi-arch payload?"
    echo -e "  ${GREEN}ocp-pods-by-arch${NC}        Pod count per node architecture"
    echo -e "  ${GREEN}ocp-multiarch-operator${NC}  Multiarch Tuning Operator status"
    echo -e "  ${GREEN}ocp-ami-architectures${NC}   List all supported CPU architectures"
    echo -e "  ${GREEN}ocp-ami-region [region]${NC} AMIs for a region (default: us-east-2)"
    echo -e "  ${GREEN}ocp-ami-all-regions [arch]${NC} All AWS regions for an architecture"
    echo -e "  ${GREEN}ocp-ami-lookup <arch> [region]${NC} Quick AMI lookup"
    echo ""
    echo -e "${BOLD}TROUBLESHOOTING:${NC}"
    echo -e "  ${GREEN}ocp-pods-sick${NC}           Show all non-running pods"
    echo -e "  ${GREEN}ocp-pods-ns <ns>${NC}        Pods in a specific namespace"
    echo -e "  ${GREEN}ocp-events [ns]${NC}         Recent events (all or by namespace)"
    echo ""
    echo -e "${BOLD}IMAGES & BUILDS:${NC}"
    echo -e "  ${GREEN}ocp-image-arch <img>${NC}    Check if image is multi-arch"
    echo ""
    echo -e "${BOLD}OPENSHIFT AI:${NC}"
    echo -e "  ${GREEN}ocp-ai-status${NC}           OpenShift AI components status"
    echo ""
    echo -e "${YELLOW}Tip: Source this file first:  source ocp-cockpit.sh${NC}"
}

# Auto-show help when sourced
echo -e "${GREEN}OpenShift Cockpit loaded. Type 'ocp-help' for available commands.${NC}"