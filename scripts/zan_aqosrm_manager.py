import requests
import json
import time

# Ryu Controller REST API Base URL
RYU_URL = "http://127.0.0.1:8080"

# Switch DPIDs (Datapath IDs assigned by Mininet)
# Assuming core1=1, edge_fiber=2, edge_sat=3, edge_lte=4
CORE_SWITCH = "0000000000000001"
EDGE_SAT = "0000000000000003"

# IP Addresses for our ZAN Hybrid Nodes (we will set these in Mininet later)
CLINIC_IP = "10.0.0.30"
FARM_IP = "10.0.0.31"
FIBER_IP = "10.0.0.10"
MOBILE_IP = "10.0.0.40"

def register_ovsdb(dpid, addr):
    url = f"http://localhost:8080/v1.0/conf/switches/{dpid}/ovsdb_addr"
    try:
        # Ryu expects the address as a JSON string
        response = requests.put(url, json=addr)
        print(f"[*] Registering OVSDB for {dpid}: {response.status_code}")
    except Exception as e:
        print(f"[!] Failed to register OVSDB: {e}")

def configure_ovs_queues(dpid):
    """
    Creates HTB (Hierarchical Token Bucket) queues on the switch.
    Queue 0: Default
    Queue 1: Critical Starlink Traffic (Guaranteed min_rate, high max_rate)
    Queue 2: Bulk Traffic (Throttled max_rate)
    """
    print(f"[*] Configuring AQoSRM Queues on Switch {dpid}...")
    
    # Register OVSDB address first (Assuming Mininet runs OVSDB on 6632)
    register_ovsdb(dpid, "tcp:127.0.0.1:6632")
    
    url = f"{RYU_URL}/qos/queue/{dpid}"
    
    # Configuration based on rest_qos.py expected payload
    payload = {
        "type": "linux-htb",
        "max_rate": "10000000", # 10 Mbps total link
        "queues": [
            {"max_rate": "10000000"}, # Queue 0: Default
            {"min_rate": "5000000", "max_rate": "10000000"}, # Queue 1: Critical (Guarantee 5Mbps)
            {"max_rate": "2000000"}  # Queue 2: Bulk (Throttle to 2Mbps max)
        ]
    }
    
    response = requests.post(url, json=payload)
    print(f"    Response: {response.status_code} - {response.text}")

def apply_zan_prioritization(switch_id):
    """
    Matches specific traffic and maps it to the queues created above.
    """
    print(f"[*] Applying ZAN Flow Rules to Switch {switch_id}...")
    url = f"{RYU_URL}/qos/rules/{switch_id}"
    
    # 1. Prioritize Clinic Traffic (Starlink) -> Queue 1
    clinic_payload = {
        "priority": "100",
        "match": {
            "nw_dst": CLINIC_IP,
            "nw_proto": "UDP" # Example: Prioritizing UDP telemetry/VoIP
        },
        "actions": {
            "queue": "1"
        }
    }
    requests.post(url, json=clinic_payload)

    # 2. Prioritize Farm IoT Traffic (Starlink) -> Queue 1
    farm_payload = {
        "priority": "100",
        "match": {
            "nw_dst": FARM_IP
        },
        "actions": {
            "queue": "1"
        }
    }
    requests.post(url, json=farm_payload)

    # 3. Throttle Fiber/Mobile bulk downloads -> Queue 2
    throttle_payload = {
        "priority": "50",
        "match": {
            "nw_dst": FIBER_IP,
            "nw_proto": "TCP" # Throttle heavy TCP downloads
        },
        "actions": {
            "queue": "2"
        }
    }
    requests.post(url, json=throttle_payload)
    print("    [+] AQoSRM Prioritization Active.")

if __name__ == "__main__":
    print("--- ZAN Framework: AQoSRM Manager Started ---")
    # Wait for Ryu controller to boot and recognize switches
    time.sleep(2) 
    
    # Apply to the Core switch routing the traffic
    configure_ovs_queues(CORE_SWITCH)
    apply_zan_prioritization(CORE_SWITCH)
    
    print("--- ZAN Framework: Initialization Complete ---")
