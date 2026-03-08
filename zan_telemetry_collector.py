import subprocess
import json
import time
from datetime import datetime, timezone
from concurrent.futures import ThreadPoolExecutor
from influxdb import InfluxDBClient

# Connect to local InfluxDB
client = InfluxDBClient(host='localhost', port=8086)
client.create_database('zan_qos_metrics')
client.switch_database('zan_qos_metrics')

# Shorter iperf test = more points per minute = smoother Grafana
IPERF_DURATION_SEC = 1
# How often to run the full cycle (both streams)
POLL_INTERVAL_SEC = 2

def ensure_qos_rule_applied(port):
    try:
        # Get the s3_sat datapath ID
        result = subprocess.run(["ovs-vsctl", "get", "bridge", "s3_sat", "datapath_id"], capture_output=True, text=True)
        dpid = result.stdout.strip().strip('"')
        if not dpid: return
        
        # Apply rule to prioritize the given port
        rule = {
            "match": {"nw_proto": "UDP", "udp_dst": str(port)},
            "actions": {"queue": "1"}
        }
        cmd = f"curl -s -X POST -d '{json.dumps(rule)}' http://localhost:8080/qos/rules/{dpid}"
        subprocess.run(cmd, shell=True, capture_output=True)
        print(f"Applied QoS priority rule for telemetry port {port}")
    except Exception as e:
        print(f"Failed to apply QoS rule for telemetry: {e}")

def get_mininet_pid(node_name):
    try:
        # Find the PID of the mininet node (e.g., mininet:h_f1_2)
        result = subprocess.run(["ps", "aux"], capture_output=True, text=True)
        for line in result.stdout.splitlines():
            if f"mininet:{node_name}" in line and "grep" not in line:
                return line.split()[1]
    except Exception as e:
        print(f"Error finding PID for {node_name}: {e}")
    return None

def get_mininet_ip(pid, node_name):
    try:
        # Try getting IP for eth0
        result = subprocess.run(f"sudo mnexec -a {pid} ip addr show {node_name}-eth0".split(), capture_output=True, text=True)
        for line in result.stdout.splitlines():
            if 'inet ' in line:
                return line.split()[1].split('/')[0]
                
        # Fallback to any active non-local IP
        result = subprocess.run(f"sudo mnexec -a {pid} ip -4 -o addr show".split(), capture_output=True, text=True)
        for line in result.stdout.splitlines():
            if '127.0.0.1' not in line:
                return line.split()[3].split('/')[0]
    except Exception as e:
        print(f"Error finding IP for {node_name}: {e}")
    return None

def start_iperf_server(pid, port):
    # Ensure iperf3 server is running in the background on the target
    cmd = f"sudo mnexec -a {pid} iperf3 -s -p {port} -D"
    result = subprocess.run(cmd.split(), capture_output=True, text=True)
    if result.returncode != 0:
        print(f"Error starting iperf3 server on port {port}: {result.stderr}")

def run_iperf_and_log(client_pid, target_ip, port, stream_type):
    # Shorter test = more frequent points = smoother Grafana
    cmd = f"sudo mnexec -a {client_pid} iperf3 -c {target_ip} -u -p {port} -b 200K -t {IPERF_DURATION_SEC} -J"
    
    try:
        result = subprocess.run(cmd.split(), capture_output=True, text=True, timeout=IPERF_DURATION_SEC + 5)
        data = json.loads(result.stdout)
        
        jitter_ms = data['end']['sum_received']['jitter_ms']
        bandwidth_bps = data['end']['sum_received']['bits_per_second']
        packet_loss = data['end']['sum_received']['lost_percent']
        
        # Explicit timestamp for aligned, smooth time series in Grafana
        now_ns = int(datetime.now(timezone.utc).timestamp() * 1e9)
        
        json_body = [
            {
                "measurement": "network_jitter",
                "tags": {"stream_type": stream_type, "port": str(port)},
                "time": now_ns,
                "fields": {"value": float(jitter_ms)}
            },
            {
                "measurement": "network_metrics",
                "tags": {"stream_type": stream_type, "port": str(port)},
                "time": now_ns,
                "fields": {
                    "bandwidth_bps": float(bandwidth_bps),
                    "packet_loss_percent": float(packet_loss)
                }
            }
        ]
        client.write_points(json_body, time_precision='n')
        print(f"Logged {stream_type} - Jitter: {jitter_ms}ms, BW: {bandwidth_bps}bps, Loss: {packet_loss}%")
        
    except json.JSONDecodeError:
        print(f"Error: Could not parse iperf3 JSON output for port {port}. Server busy or not running?")
    except KeyError:
        print(f"Error: Metric data not found in iperf3 output for port {port}.")
    except subprocess.TimeoutExpired:
        print(f"Error: iperf3 timed out for port {port}.")
    except Exception as e:
        print(f"Error collecting data for port {port}: {e}")

# Run continuous loops during your presentation
if __name__ == '__main__':
    print("Starting ZAN Telemetry Collector (Waiting for Mininet)...")
    
    CLIENT_NODE = "h_f1_2" # Test sender
    SERVER_NODE = "h_sat_1" # Test receiver
    
    client_pid = None
    server_pid = None
    server_ip = None
    
    # Wait until Mininet is running and nodes are found
    while not client_pid or not server_pid or not server_ip:
        client_pid = get_mininet_pid(CLIENT_NODE)
        server_pid = get_mininet_pid(SERVER_NODE)
        if server_pid:
            server_ip = get_mininet_ip(server_pid, SERVER_NODE)
            
        if not client_pid or not server_pid or not server_ip:
            print(f"Waiting for nodes {CLIENT_NODE} and {SERVER_NODE} to be ready...")
            time.sleep(5)
            
    print(f"Found {CLIENT_NODE} PID: {client_pid}")
    print(f"Found {SERVER_NODE} PID: {server_pid}, IP: {server_ip}")
    
    # Start the robust iperf3 servers on the receiver
    print("Starting telemetry iperf3 servers on receiver...")
    
    # We use 5061 (Prioritized) and 5015 (Best Effort) 
    # to avoid conflicting with 5060 which is used by run_simultaneous_test.sh
    start_iperf_server(server_pid, 5015)
    start_iperf_server(server_pid, 5061)
    
    # Ensure port 5061 gets QoS priority
    ensure_qos_rule_applied(5061)
    
    # Run both streams in parallel so Grafana gets aligned points every POLL_INTERVAL_SEC
    while True:
        with ThreadPoolExecutor(max_workers=2) as ex:
            ex.submit(run_iperf_and_log, client_pid, server_ip, 5061, "Prioritized")
            ex.submit(run_iperf_and_log, client_pid, server_ip, 5015, "Unprioritized")
        time.sleep(POLL_INTERVAL_SEC)

