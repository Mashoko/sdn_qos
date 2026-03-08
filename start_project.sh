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

ZAN_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$ZAN_DIR" || exit 1

echo ""
echo "[1/4] Cleaning up previous Mininet and Ryu instances..."
# Clean mininet
mn -c > /dev/null 2>&1
# Kill any lingering ryu-manager processes
pkill -f ryu-manager > /dev/null 2>&1


echo ""
echo "[2/4] Starting Ryu controller..."

RYU_PYTHON="$ZAN_DIR/venv/bin/python"
if [ ! -x "$RYU_PYTHON" ]; then
  echo "Python venv not found at $RYU_PYTHON. Please (re)create the venv and install dependencies."
  exit 1
fi

# Prefer the local Ryu source tree under $ZAN_DIR/ryu.
if [ -d "$ZAN_DIR/ryu/ryu" ]; then
  export PYTHONPATH="$ZAN_DIR/ryu${PYTHONPATH:+:$PYTHONPATH}"
  RYU_CMD=( "$RYU_PYTHON" -m ryu.cmd.manager )
else
  # Fallback to any ryu-manager on PATH if available.
  if command -v ryu-manager >/dev/null 2>&1; then
    RYU_CMD=( ryu-manager )
  else
    echo "No local Ryu source at '$ZAN_DIR/ryu' and no 'ryu-manager' found on PATH."
    echo "Please clone https://github.com/faucetsdn/ryu into '$ZAN_DIR/ryu' and install its Python dependencies."
    exit 1
  fi
fi

# Start the controller in the background
"${RYU_CMD[@]}" ryu_qos_apps/qos_simple_switch_13.py \
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
    sudo "$ZAN_DIR/venv/bin/python" "$ZAN_DIR/zan_telemetry_collector.py" > "$ZAN_DIR/collector.log" 2>&1 &
    COLLECTOR_PID=$!
    
    echo "  [✓] All configurations applied successfully!"
    echo "  >>> Press Enter in the mininet CLI to continue..."
) &


echo ""
echo "[4/4] Starting Mininet topology..."
echo "  Topology: zan_hybrid_topology.py (zan_hybrid_scaled)"
echo "-----------------------------------------------------"
echo ""

# Start Mininet. This command will block and give the user the mininet> prompt.
# We set the controller to remote since Ryu is running in the background.
mn --custom topology/zan_hybrid_topology.py \
   --topo zan_hybrid_scaled \
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

echo "ZAN SDN Project Testbed stopped cleanly."
echo "====================================================="
