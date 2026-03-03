#!/bin/bash
# run_simultaneous_test.sh
# Automates a simultaneous test of QoS prioritized traffic vs non-prioritized traffic.

# Find PIDs of h1r1 and h1r4
PID_H1R1=$(ps aux | grep "mininet:h1r1" | grep -v grep | awk '{print $2}')
PID_H1R3=$(ps aux | grep "mininet:h1r3" | grep -v grep | awk '{print $2}')
PID_H1R4=$(ps aux | grep "mininet:h1r4" | grep -v grep | awk '{print $2}')

if [ -z "$PID_H1R1" ] || [ -z "$PID_H1R3" ] || [ -z "$PID_H1R4" ]; then
    echo "Could not find Mininet processes for h1r1, h1r3, or h1r4."
    exit 1
fi

H1R1_IP="172.16.20.10"

echo "=========================================================="
echo "    ZAN SDN Simultaneous QoS Presentation Test"
echo "=========================================================="
echo "This test converges traffic at the bottlenecked core switch (s1)"
echo "where the DiffServ priority queues evaluate and route:"
echo " 1. Congestion Flood: h1r3 -> h1r1 (Port 5001)"
echo " 2. Prioritized UDP:  h1r4 -> h1r1 (Port 5002 - QoS Active)"
echo " 3. Unprioritized UDP:h1r4 -> h1r1 (Port 5004 - Best Effort)"
echo "=========================================================="
echo ""

# Ensure ARP works by doing a quick ping
sudo mnexec -a $PID_H1R3 ping -c 1 $H1R1_IP > /dev/null 2>&1
sudo mnexec -a $PID_H1R4 ping -c 1 $H1R1_IP > /dev/null 2>&1

echo "[1/3] Starting Servers on h1r1..."
sudo mnexec -a $PID_H1R1 iperf -s -u -p 5001 > /dev/null 2>&1 &
sudo mnexec -a $PID_H1R1 iperf -s -u -p 5002 > /tmp/h1r1_prioritized_server.log 2>&1 &
sudo mnexec -a $PID_H1R1 iperf -s -u -p 5004 > /tmp/h1r1_unprioritized_server.log 2>&1 &

echo "[2/3] Starting aggressive 5Mbps background congestion from h1r3..."
sudo mnexec -a $PID_H1R3 iperf -c $H1R1_IP -u -b 5M -p 5001 -t 40 > /tmp/h1r3_congestion.log 2>&1 &
sleep 3

echo "[3/3] Launching simultaneous prioritized/unprioritized traffic from h1r4..."
# Prioritized (Port 5002) - 200Kbps (Safe to pass source-edge limits, dropping at core)
sudo mnexec -a $PID_H1R4 iperf -c $H1R1_IP -u -b 200k -p 5002 -t 30 > /tmp/h1r4_prioritized_client.log 2>&1 &
PID_PRIO=$!

# Unprioritized (Port 5004) - 200Kbps
sudo mnexec -a $PID_H1R4 iperf -c $H1R1_IP -u -b 200k -p 5004 -t 30 > /tmp/h1r4_unprioritized_client.log 2>&1 &
PID_UNPRIO=$!

echo "  -> Tests are running! Please wait 35 seconds..."
wait $PID_PRIO
wait $PID_UNPRIO
sleep 15 # Wait for servers to timeout dropped ACKs and print their final logs

echo ""
echo "=========================================================="
echo "               RESULTS (SERVER RECEIVE LOGS)              "
echo "                 (Traffic reaching h1r1)                  "
echo "=========================================================="
echo ""
echo ">>> UNPRIORITIZED STREAM (Control - Port 5004) <<<"
cat /tmp/h1r1_unprioritized_server.log | grep -A 5 "Server Report:" | head -n 6 || cat /tmp/h1r1_unprioritized_server.log | tail -n 6

echo ""
echo ">>> PRIORITIZED STREAM (QoS Active - Port 5002) <<<"
cat /tmp/h1r1_prioritized_server.log | grep -A 5 "Server Report:" | head -n 6 || cat /tmp/h1r1_prioritized_server.log | tail -n 6


echo ""
echo "Cleaning up..."
sudo pkill -f iperf
echo "Done!"
