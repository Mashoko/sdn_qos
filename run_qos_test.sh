#!/bin/bash
# run_qos_test.sh
# Automates the QoS test requested for h1r1 and h1r4

# Find PIDs of h1r1 and h1r4
PID_H1R1=$(ps aux | grep "mininet:h1r1" | grep -v grep | awk '{print $2}')
PID_H1R4=$(ps aux | grep "mininet:h1r4" | grep -v grep | awk '{print $2}')

if [ -z "$PID_H1R1" ] || [ -z "$PID_H1R4" ]; then
    echo "Could not find Mininet processes for h1r1 or h1r4. Is the topology running?"
    exit 1
fi

echo "h1r1 PID: $PID_H1R1"
echo "h1r4 PID: $PID_H1R4"

# Get h1r4 IP
H1R4_IP=$(sudo mnexec -a $PID_H1R4 ip addr show h1r4-eth0 | awk '/inet / {print $2}' | cut -d/ -f1)

if [ -z "$H1R4_IP" ]; then
    echo "Could not find IP for h1r4 on h1r4-eth0. Trying default..."
    H1R4_IP=$(sudo mnexec -a $PID_H1R4 ip -4 -o addr show | awk '!/127\.0\.0\.1/ {print $4}' | cut -d/ -f1 | head -n 1)
fi

echo "h1r4 IP: $H1R4_IP"

echo "Step 2: Starting UDP servers on h1r4..."
sudo mnexec -a $PID_H1R4 iperf -s -u -p 5001 > /tmp/h1r4_udp_congestion_server.log 2>&1 &
sudo mnexec -a $PID_H1R4 iperf -s -u -p 5002 > /tmp/h1r4_udp_realtime_server.log 2>&1 &

echo "Step 3: Starting 60s aggressive UDP congestion load (10Mbps) from h1r1..."
sudo mnexec -a $PID_H1R1 iperf -c $H1R4_IP -u -b 10M -p 5001 -t 60 > /tmp/h1r1_udp_congestion_client.log 2>&1 &

# Wait for a few seconds to let UDP traffic fill the queues
echo "Waiting 5s for heavy UDP traffic to ramp up and cause congestion..."
sleep 5

echo "Step 4: Starting 30s real-time UDP test from h1r1..."
sudo mnexec -a $PID_H1R1 iperf -c $H1R4_IP -u -b 2M -p 5002 -t 30 > /tmp/h1r1_udp_client.log 2>&1

echo "Step 5: Test complete. Results of the UDP test:"
echo "------------------------------------------------"
cat /tmp/h1r1_udp_client.log
echo "------------------------------------------------"

# Clean up iperf processes
echo "Cleaning up background iperf processes..."
sudo pkill -f iperf
echo "Done!"
