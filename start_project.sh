#!/bin/bash

# start_project.sh
# 
# Script to automate the startup of the ZAN Software Defined Network.
# It starts the Ryu Controller, Mininet with the default topology,
# and applies the default QoS and Routing configuration scripts.

echo "====================================================="
echo "        Starting ZAN SDN Project Testbed             "
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
"$ZAN_DIR/venv/bin/ryu-manager" ryu_qos_apps/qos_rest_router.py \
            ryu_qos_apps/qos_simple_switch_13.py \
            ryu_qos_apps/rest_conf_switch.py \
            ryu_qos_apps/rest_qos.py \
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
    
    echo "  [.] Applying IP settings to routers..."
    bash scripts/router_set_ip.sh > /dev/null 2>&1

    echo "  [.] Applying routing settings..."
    bash scripts/route_setting.sh > /dev/null 2>&1

    echo "  [.] Applying DiffServ QoS settings..."
    # bash scripts/diffserv_qos_script.sh > /dev/null 2>&1
    
    echo "  [✓] All configurations applied successfully!"
    echo "  >>> Press Enter in the mininet CLI to continue..."
) &


echo ""
echo "[4/4] Starting Mininet topology..."
echo "  Topology: datacenterDiffServ.py (dcbasic)"
echo "-----------------------------------------------------"
echo ""

# Start Mininet. This command will block and give the user the mininet> prompt.
# We set the controller to remote since Ryu is running in the background.
mn --custom topology/datacenterDiffServ.py \
   --topo dcbasic \
   --mac \
   --controller remote,ip=127.0.0.1,port=6633 \
   --switch ovsk,protocols=OpenFlow13 \
   --link tc,bw=5

echo ""
echo "====================================================="
echo "Mininet exited. Cleaning up remaining processes..."

# When the user types 'quit' in mininet, cleanup is performed
pkill -P $$ -f ryu-manager
kill "$RYU_PID" 2>/dev/null

echo "ZAN SDN Project Testbed stopped cleanly."
echo "====================================================="
