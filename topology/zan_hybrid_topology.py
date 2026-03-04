"""
Zimbabwe Adaptive Network (ZAN) Hybrid Topology script for Mininet.
Simulates: Fiber (Low latency/jitter), Starlink/Satellite (High latency/jitter), LTE (Medium latency/jitter)
"""

from mininet.topo import Topo
from mininet.link import TCLink

class ZANHybridScaledTopo(Topo):
    "ZAN Massive Hybrid ISP Topology"

    def build(self):
        self.dpid_counter = 1
        def get_dpid():
            dpid = f"{self.dpid_counter:x}"
            self.dpid_counter += 1
            return dpid

        # Core Network
        core_sw = self.addSwitch('s1_core', dpid=get_dpid())

        # Edge Routers/Switches
        fiber_edge = self.addSwitch('s2_fiber', dpid=get_dpid())
        sat_gw = self.addSwitch('s3_sat', dpid=get_dpid())
        lte_edge = self.addSwitch('s4_lte', dpid=get_dpid())

        # Connect Edge to Core with realistic WAN metrics
        # Fiber: High BW, minimal delay
        self.addLink(core_sw, fiber_edge )
        
        # Satellite: Lower BW, high latency, high jitter
        self.addLink(core_sw, sat_gw )
        
        # LTE: Medium BW, medium latency, moderate jitter
        self.addLink(core_sw, lte_edge )

        # --- 1. Fiber Enterprise Customers (HQ) ---
        ent_switch1 = self.addSwitch('sw_ent1', dpid=get_dpid())
        ent_switch2 = self.addSwitch('sw_ent2', dpid=get_dpid())
        self.addLink(fiber_edge, ent_switch1 )
        self.addLink(fiber_edge, ent_switch2 )

        for i in range(1, 16):  # 30 total fiber hosts
            h1 = self.addHost(f'h_f1_{i}')
            h2 = self.addHost(f'h_f2_{i}')
            self.addLink(ent_switch1, h1 )
            self.addLink(ent_switch2, h2 )

        # --- 2. Satellite / Remote Customers (Rural Clinic/Farm) ---
        rural_switch = self.addSwitch('sw_rural1', dpid=get_dpid())
        self.addLink(sat_gw, rural_switch )

        for i in range(1, 11):  # 10 remote hosts sharing poor connection
            h = self.addHost(f'h_sat_{i}')
            self.addLink(rural_switch, h )

        # --- 3. LTE / Mobile Customers ---
        for i in range(1, 21):  # 20 direct LTE users
            h = self.addHost(f'h_lte_{i}')
            self.addLink(lte_edge, h )

# Allows the file to be imported using `mn --custom <filename> --topo zan_hybrid_scaled`
topos = {
    'zan_hybrid_scaled': (lambda: ZANHybridScaledTopo())
}
