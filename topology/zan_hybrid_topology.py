"""
Zimbabwe Adaptive Network (ZAN) Hybrid Topology script for Mininet.

    [ core1 (ISP Backbone) ]====================================.
           |                           |                        |
    [ edge_fiber ]             [ edge_sat (Starlink) ]    [ edge_lte ]
      |        |                   |             |              |
   [h_ent]  [h_fiber]          [h_farm]      [h_clinic]      [h_mob]
"""

from mininet.topo import Topo
from mininet.link import TCLink

class ZanHybridTopo( Topo ):
    "ZAN Hybrid Topology combining Fiber, Satellite, and Mobile Edge"

    def build( self ):
        # 1. Core ISP Backbone Switch
        core_sw = self.addSwitch( 'core1', dpid='1' )

        # 2. Edge Gateways / Distribution Switches
        fiber_edge = self.addSwitch( 'edge_fiber', dpid='2' )
        starlink_gw = self.addSwitch( 'edge_sat', dpid='3' )
        lte_edge = self.addSwitch( 'edge_lte', dpid='4' )

        # Connect Edge gateways to the Core
        # In Phase 3, we will use TCLink parameters here to simulate 
        # actual satellite latency/jitter for the starlink_gw link.
        self.addLink( core_sw, fiber_edge )
        self.addLink( core_sw, starlink_gw )
        self.addLink( core_sw, lte_edge )

        # 3. Add End-User Hosts and link them to their respective gateways
        
        # High-Speed Urban Fiber Users
        h_enterprise = self.addHost( 'h_ent' )      # E.g., Tech Company HQ
        h_home_fiber = self.addHost( 'h_fiber' )    # E.g., Standard Home User
        self.addLink( fiber_edge, h_enterprise )
        self.addLink( fiber_edge, h_home_fiber )

        # Remote/Satellite Users 
        h_smart_farm = self.addHost( 'h_farm' )     # E.g., IoT Agriculture sensors
        h_clinic = self.addHost( 'h_clinic' )       # E.g., Remote medical facility
        self.addLink( starlink_gw, h_smart_farm )
        self.addLink( starlink_gw, h_clinic )

        # Mobile LTE Users
        h_mobile = self.addHost( 'h_mob' )          # E.g., Smartphone user
        self.addLink( lte_edge, h_mobile )

# Allows the file to be imported using `mn --custom <filename> --topo zantopo`
topos = {
    'zantopo': ZanHybridTopo
}
