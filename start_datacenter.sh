#!/bin/bash

# start_datacenter.sh
# 
# Script to automate the startup of the ZAN Software Defined Network.
# Specifically launches the massive Datacenter scaled environment.

echo "====================================================="
echo "        Starting ZAN SDN Datacenter Testbed          "
echo "====================================================="

# Must run as root for Mininet
if [ "$EUID" -ne 0 ]; then
  echo "Please run as root (using sudo)."
  exit
fi

ZAN_DIR="/home/user/Documents/ZAN"
cd "$ZAN_DIR" || exit

echo ""
echo "[1/4] Cleaning up previous Mininet and Ryu instances..."
# Clean mininet
mn -c > /dev/null 2>&1
# Kill any lingering ryu-manager processes
pkill -f ryu-manager > /dev/null 2>&1


echo ""
echo "[2/4] Starting Ryu controller..."
# Start the controller in the background
"$ZAN_DIR/venv/bin/ryu-manager" ryu_qos_apps/qos_simple_switch_13.py \
            ryu_qos_apps/rest_conf_switch.py \
            ryu_qos_apps/rest_qos.py \
            flowmanager/flowmanager.py \
            > ryu.log 2>&1 &
RYU_PID=$!
echo "Ryu controller started with PID: $RYU_PID. Logging to ryu.log"


echo ""
echo "[3/4] Preparing background configuration script..."
# We need to wait for Mininet to start and for the switches to connect to the controller 
# before applying configurations. We do this in a subshell in the background.
(
    # Wait for the controller and mininet to be ready (approx 10-15 seconds)
    echo "  [.] Waiting 15 seconds for Mininet and Ryu to initialize before applying configs..."
    sleep 15
    
    echo "  [.] Ignoring old hardcoded 4-host IP & Routing settings for massive topology..."
    # bash scripts/router_set_ip.sh > /dev/null 2>&1
    # bash scripts/route_setting.sh > /dev/null 2>&1
    # bash scripts/diffserv_qos_script.sh > /dev/null 2>&1

    echo "  [.] Applying Automated QoS limits for massive scales..."
    ./zan_massive_qos.sh > /dev/null 2>&1
    
    echo "  [.] Starting Python Telemetry Collector..."
    # Run the collector in the background, logging to collector.log
    "$ZAN_DIR/venv/bin/python" "$ZAN_DIR/zan_telemetry_collector.py" > "$ZAN_DIR/collector.log" 2>&1 &
    COLLECTOR_PID=$!
    
    echo "  [✓] All configurations applied successfully!"
    echo "  >>> Press Enter in the mininet CLI to continue..."
) &


echo ""
echo "[4/4] Starting Mininet topology..."
echo "  Topology: datacenterBasic.py (datacenter_scaled)"
echo "-----------------------------------------------------"
echo ""

# Start Mininet. This command will block and give the user the mininet> prompt.
# We set the controller to remote since Ryu is running in the background.
mn --custom topology/datacenterBasic.py \
   --topo datacenter_scaled \
   --mac \
   --controller remote,ip=127.0.0.1,port=6633 \
   --switch ovsk,protocols=OpenFlow13 \
   --link tc,bw=5

echo ""
echo "====================================================="
echo "Mininet exited. Cleaning up remaining processes..."

# When the user types 'quit' in mininet, cleanup is performed
pkill -P $$ -f ryu-manager
pkill -f "python.*zan_telemetry_collector.py"
kill "$RYU_PID" 2>/dev/null

echo "ZAN SDN Datacenter Testbed stopped cleanly."
echo "====================================================="
