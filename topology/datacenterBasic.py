"""
Scaled Enterprise Datacenter Topology for Mininet.
Structure: Core -> Aggregation -> Top of Rack (ToR) -> Hosts
"""

from mininet.topo import Topo
from mininet.link import TCLink

class DatacenterScaledTopo(Topo):
    "Massive Enterprise Datacenter Topology"
    
    def build(self, num_agg=2, racks_per_agg=5, hosts_per_rack=10):
        self.dpid_counter = 1
        def get_dpid():
            dpid = f"{self.dpid_counter:x}"
            self.dpid_counter += 1
            return dpid

        # Add Core Switch
        core = self.addSwitch('core1', dpid=get_dpid())

        # Add Aggregation Switches
        for a in range(1, num_agg + 1):
            agg = self.addSwitch(f'agg{a}', dpid=get_dpid())
            # 100 Mbps link between Core and Aggregation
            self.addLink(core, agg, cls=TCLink, bw=100)

            # Add Top of Rack (ToR) Switches for each Aggregation Switch
            for r in range(1, racks_per_agg + 1):
                tor = self.addSwitch(f'tor{a}_{r}', dpid=get_dpid())
                # 50 Mbps link between Aggregation and ToR (Congestion point)
                self.addLink(agg, tor, cls=TCLink, bw=50)

                # Add Hosts for each ToR Switch
                for h in range(1, hosts_per_rack + 1):
                    # Host naming: h_<agg>_<rack>_<host>
                    host = self.addHost(f'h_{a}_{r}_{h}')
                    # 10 Mbps link between ToR and Host
                    self.addLink(tor, host, cls=TCLink, bw=10)

# Allows the file to be imported using `mn --custom <filename> --topo datacenter_scaled`
topos = {
    'datacenter_scaled': (lambda: DatacenterScaledTopo())
}
