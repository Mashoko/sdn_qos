#!/bin/bash
# run_simultaneous_test.sh
# Automates a simultaneous test of QoS prioritized traffic vs non-prioritized traffic for ZAN Hybrid Topology.

HOST_RX=${1:-h_sat_1}
HOST_CONG=${2:-h_f1_1}
HOST_TEST=${3:-h_f1_2}

# Find PIDs
PID_RX=$(ps aux | grep "mininet:$HOST_RX$" | grep -v grep | awk '{print $2}')
PID_CONG=$(ps aux | grep "mininet:$HOST_CONG$" | grep -v grep | awk '{print $2}')
PID_TEST=$(ps aux | grep "mininet:$HOST_TEST$" | grep -v grep | awk '{print $2}')

if [ -z "$PID_RX" ] || [ -z "$PID_CONG" ] || [ -z "$PID_TEST" ]; then
    echo "Could not find Mininet processes for $HOST_RX, $HOST_CONG, or $HOST_TEST."
    exit 1
fi

RX_IP=$(sudo mnexec -a $PID_RX ip addr show ${HOST_RX}-eth0 | awk '/inet / {print $2}' | cut -d/ -f1)
if [ -z "$RX_IP" ]; then
    RX_IP=$(sudo mnexec -a $PID_RX ip -4 -o addr show | awk '!/127\.0\.0\.1/ {print $4}' | cut -d/ -f1 | head -n 1)
fi

echo "=========================================================="
echo "    ZAN SDN Simultaneous QoS Presentation Test"
echo "=========================================================="
echo "This test converges traffic at the bottlenecked switch (s3_sat)"
echo "where the DiffServ priority queues evaluate and route:"
echo " 1. Congestion Flood: $HOST_CONG -> $HOST_RX (Port 5001)"
echo " 2. Prioritized UDP:  $HOST_TEST -> $HOST_RX (Port 5060 - QoS Active)"
echo " 3. Unprioritized UDP:$HOST_TEST -> $HOST_RX (Port 5004 - Best Effort)"
echo "=========================================================="
echo ""

# Ensure ARP works by doing a quick ping
sudo mnexec -a $PID_CONG ping -c 1 $RX_IP > /dev/null 2>&1
sudo mnexec -a $PID_TEST ping -c 1 $RX_IP > /dev/null 2>&1

echo "[1/3] Starting Servers on $HOST_RX..."
sudo mnexec -a $PID_RX iperf3 -s -p 5001 -1 > /dev/null 2>&1 &
# Main presentation servers
sudo mnexec -a $PID_RX iperf3 -s -p 5060 -1 > /tmp/${HOST_RX}_prioritized_server.log 2>&1 &
sudo mnexec -a $PID_RX iperf3 -s -p 5004 -1 > /tmp/${HOST_RX}_unprioritized_server.log 2>&1 &

echo "[2/3] Starting aggressive 30Mbps background congestion from $HOST_CONG..."
sudo mnexec -a $PID_CONG iperf3 -c $RX_IP -u -b 30M -p 5001 -t 310 > /tmp/${HOST_CONG}_congestion.log 2>&1 &
sleep 3

echo "[3/3] Launching simultaneous prioritized/unprioritized traffic from $HOST_TEST..."
# Prioritized (Port 5060) - 200Kbps
sudo mnexec -a $PID_TEST iperf3 -c $RX_IP -u -b 200k -p 5060 -t 300 > /tmp/${HOST_TEST}_prioritized_client.log 2>&1 &
PID_PRIO=$!

# Unprioritized (Port 5004) - 200Kbps
sudo mnexec -a $PID_TEST iperf3 -c $RX_IP -u -b 200k -p 5004 -t 300 > /tmp/${HOST_TEST}_unprioritized_client.log 2>&1 &
PID_UNPRIO=$!

echo "  -> Tests are running for 5 minutes! Streaming live logs below..."
echo "  (Press Ctrl+C to stop early, but keep in mind Mininet will need manual cleanup)"
echo ""

# Tail the logs in the background so the user can watch the stream
tail -f /tmp/${HOST_TEST}_prioritized_client.log /tmp/${HOST_TEST}_unprioritized_client.log &
TAIL_PID=$!

wait $PID_PRIO
wait $PID_UNPRIO

# Stop tailing when the tests finish
kill $TAIL_PID 2>/dev/null

sleep 15 # Wait for servers to timeout dropped ACKs and print their final logs

echo ""
echo "=========================================================="
echo "               RESULTS (SERVER RECEIVE LOGS)              "
echo "                 (Traffic reaching $HOST_RX)                  "
echo "=========================================================="
echo ""
echo ">>> UNPRIORITIZED STREAM (Control - Port 5004) <<<"
cat /tmp/${HOST_TEST}_unprioritized_client.log | grep -A 5 "Server Report:" | head -n 6 || tail -n 6 /tmp/${HOST_RX}_unprioritized_server.log

echo ""
echo ">>> PRIORITIZED STREAM (QoS Active - Port 5060) <<<"
cat /tmp/${HOST_TEST}_prioritized_client.log | grep -A 5 "Server Report:" | head -n 6 || tail -n 6 /tmp/${HOST_RX}_prioritized_server.log


echo ""
echo "Cleaning up..."
sudo pkill -f iperf
echo "Done!"
