import subprocess
import json
import time
from influxdb import InfluxDBClient

# Connect to local InfluxDB
client = InfluxDBClient(host='localhost', port=8086)
client.create_database('zan_qos_metrics')
client.switch_database('zan_qos_metrics')

def get_mininet_pid(node_name):
    try:
        # Find the PID of the mininet node (e.g., mininet:h1r4)
        result = subprocess.run(["ps", "aux"], capture_output=True, text=True)
        for line in result.stdout.splitlines():
            if f"mininet:{node_name}" in line and "grep" not in line:
                return line.split()[1]
    except Exception as e:
        print(f"Error finding PID for {node_name}: {e}")
    return None

def run_iperf_and_log(pid, port, stream_type):
    # Run iperf3 in client mode via Mininet's mnexec or directly if scripted in Mininet
    # Note: Ensure the iperf3 server is already running on the destination host
    cmd = f"sudo mnexec -a {pid} iperf3 -c 172.16.20.10 -u -p {port} -b 200K -t 2 -J"
    
    try:
        result = subprocess.run(cmd.split(), capture_output=True, text=True)
        data = json.loads(result.stdout)
        
        # Extract Jitter from the JSON output
        jitter_ms = data['end']['sum']['jitter_ms']
        
        # Format for InfluxDB
        json_body = [
            {
                "measurement": "network_jitter",
                "tags": {
                    "stream_type": stream_type,
                    "port": str(port)
                },
                "fields": {
                    "value": float(jitter_ms)
                }
            }
        ]
        client.write_points(json_body)
        print(f"Logged {stream_type} Jitter: {jitter_ms} ms")
        
    except Exception as e:
        print(f"Error collecting data for port {port}: {e}")

# Run continuous loops during your presentation
if __name__ == '__main__':
    print("Starting ZAN Telemetry Collector...")
    
    # Try to find the PID for h1r4 (the client in the QoS test)
    h1r4_pid = get_mininet_pid("h1r4")
    
    if not h1r4_pid:
        print("Could not find Mininet process for h1r4. Is Mininet running?")
        print("Make sure run_simultaneous_test.sh or the topology is active.")
        exit(1)
        
    print(f"Found h1r4 PID: {h1r4_pid}")
    
    while True:
        # Port 5012 serves as the Prioritized telemetry testing port
        run_iperf_and_log(h1r4_pid, 5012, "Prioritized")
        # Port 5014 serves as the Unprioritized telemetry testing port
        run_iperf_and_log(h1r4_pid, 5014, "Unprioritized")
        time.sleep(1) # Poll every 1 second
