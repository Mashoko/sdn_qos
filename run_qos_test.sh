#!/bin/bash
# run_qos_test.sh
# Automates the QoS test requested for ZAN Hybrid Topology
HOST1=${1:-h_f1_1} # Flow sender (HQ)
HOST2=${2:-h_sat_1} # Flow receiver (Rural Satellite)

# Find PIDs of HOST1 and HOST2
PID_H1=$(ps aux | grep "mininet:$HOST1$" | grep -v grep | awk '{print $2}')
PID_H2=$(ps aux | grep "mininet:$HOST2$" | grep -v grep | awk '{print $2}')

if [ -z "$PID_H1" ] || [ -z "$PID_H2" ]; then
    echo "Could not find Mininet processes for $HOST1 or $HOST2. Is the topology running?"
    exit 1
fi

echo "$HOST1 PID: $PID_H1"
echo "$HOST2 PID: $PID_H2"

# Get HOST2 IP
H2_IP=$(sudo mnexec -a $PID_H2 ip addr show ${HOST2}-eth0 | awk '/inet / {print $2}' | cut -d/ -f1)

if [ -z "$H2_IP" ]; then
    echo "Could not find IP for $HOST2 on ${HOST2}-eth0. Trying default..."
    H2_IP=$(sudo mnexec -a $PID_H2 ip -4 -o addr show | awk '!/127\.0\.0\.1/ {print $4}' | cut -d/ -f1 | head -n 1)
fi

echo "$HOST2 IP: $H2_IP"

echo "Step 2: Starting UDP servers on $HOST2..."
sudo mnexec -a $PID_H2 iperf -s -u -p 5001 > /tmp/${HOST2}_udp_congestion_server.log 2>&1 &
sudo mnexec -a $PID_H2 iperf -s -u -p 5060 > /tmp/${HOST2}_udp_realtime_server.log 2>&1 &

echo "Step 3: Starting 60s aggressive UDP congestion load (30Mbps) from $HOST1..."
sudo mnexec -a $PID_H1 iperf -c $H2_IP -u -b 30M -p 5001 -t 60 > /tmp/${HOST1}_udp_congestion_client.log 2>&1 &

# Wait for a few seconds to let UDP traffic fill the queues
echo "Waiting 5s for heavy UDP traffic to ramp up and cause congestion..."
sleep 5

echo "Step 4: Starting 30s real-time VoIP UDP test (port 5060) from $HOST1..."
sudo mnexec -a $PID_H1 iperf -c $H2_IP -u -b 2M -p 5060 -t 30 > /tmp/${HOST1}_udp_client.log 2>&1

echo "Step 5: Test complete. Results of the prioritized VoIP (5060) UDP test:"
echo "------------------------------------------------"
cat /tmp/${HOST1}_udp_client.log
echo "------------------------------------------------"

# Clean up iperf processes
echo "Cleaning up background iperf processes..."
sudo pkill -f "iperf.*5001"
sudo pkill -f "iperf.*5060"
echo "Done!"
