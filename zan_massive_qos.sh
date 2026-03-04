#!/bin/bash
# zan_massive_qos.sh
# Automates the application of Ryu QoS rules for the ZAN Massive Topologies

CONTROLLER="http://localhost:8080"
OVSDB_ADDR='"tcp:127.0.0.1:6632"'

echo "Starting ZAN Massive QoS Automation..."

# Function to get DPID from bridge name
get_dpid() {
    local bridge=$1
    ovs-vsctl get bridge $bridge datapath_id 2>/dev/null | tr -d '"'
}

# --- 1. ZAN Hybrid Topology: s3_sat ---
SAT_DPID=$(get_dpid s3_sat)
if [ -n "$SAT_DPID" ]; then
    echo "Found s3_sat with DPID $SAT_DPID. Applying QoS..."
    
    # Step 1: Link OVSDB
    curl -s -X PUT -d "$OVSDB_ADDR" $CONTROLLER/v1.0/conf/switches/$SAT_DPID/ovsdb_addr
    
    # Step 2: Create Queues on s3_sat-eth2
    curl -s -X POST -d '{
        "port_name": "s3_sat-eth2", 
        "type": "linux-htb", 
        "max_rate": "20000000", 
        "queues": [
            {"max_rate": "10000000"}, 
            {"min_rate": "10000000", "max_rate": "20000000"}
        ]
    }' $CONTROLLER/qos/queue/$SAT_DPID
    
    # Step 3: Apply Rule - Proritize UDP 5060 (VoIP)
    curl -s -X POST -d '{
        "match": {
            "nw_proto": "UDP", 
            "udp_dst": "5060"
        }, 
        "actions": {
            "queue": "1"
        }
    }' $CONTROLLER/qos/rules/$SAT_DPID
    echo "QoS successfully applied to s3_sat."
fi

# --- 2. Enterprise Datacenter Topology: ToR Switches ---
# Loop to dynamically find and configure ToR switches
for agg in {1..10}; do
    for tor in {1..20}; do
        TOR_NAME="tor${agg}_${tor}"
        TOR_DPID=$(get_dpid $TOR_NAME)
        
        if [ -n "$TOR_DPID" ]; then
            echo "Found $TOR_NAME with DPID $TOR_DPID. Applying QoS..."
            
            # Link OVSDB
            curl -s -X PUT -d "$OVSDB_ADDR" $CONTROLLER/v1.0/conf/switches/$TOR_DPID/ovsdb_addr
            
            # Create Queues on the uplink port torX_Y-eth1 (max rate 50M)
            curl -s -X POST -d '{
                "port_name": "'$TOR_NAME'-eth1", 
                "type": "linux-htb", 
                "max_rate": "50000000", 
                "queues": [
                    {"max_rate": "10000000"}, 
                    {"min_rate": "40000000"}
                ]
            }' $CONTROLLER/qos/queue/$TOR_DPID
            
            # Apply Rules: Prioritize TCP 80 & 443 (Dashboard/Web)
            curl -s -X POST -d '{"match": {"nw_proto": "TCP", "tcp_dst": "80"}, "actions": {"queue": "1"}}' $CONTROLLER/qos/rules/$TOR_DPID
            curl -s -X POST -d '{"match": {"nw_proto": "TCP", "tcp_dst": "443"}, "actions": {"queue": "1"}}' $CONTROLLER/qos/rules/$TOR_DPID
        fi
    done
done

echo "QoS Automation Complete!"
