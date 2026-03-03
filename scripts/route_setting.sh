#!/bin/bash

s1_router_URL="http://localhost:8080/router/0000000000000001"

s1r1_router_URL="http://localhost:8080/router/0000000000000011"
echo "setting the default route for router s1r1..." $'\n'
curl -X POST -d '{"gateway": "172.16.30.1"}' "$s1r1_router_URL"
echo $'\n' $?

s1r2_router_URL="http://localhost:8080/router/0000000000000021"
echo "setting the default route for router s1r2..." $'\n'
curl -X POST -d '{"gateway": "172.16.40.1"}' "$s1r2_router_URL"
echo $'\n' $?

s1r3_router_URL="http://localhost:8080/router/0000000000000031"
echo "setting the default route for router s1r3..." $'\n'
curl -X POST -d '{"gateway": "172.16.50.1"}' "$s1r3_router_URL"
echo $'\n' $?

s1r4_router_URL="http://localhost:8080/router/0000000000000041"
echo "setting the default route for router s1r4..." $'\n'
curl -X POST -d '{"gateway": "192.168.10.1"}' "$s1r4_router_URL"
echo $'\n' $?

echo "setting static route for s1 to s1r1 subnet..." $'\n'
curl -X POST -d '{"destination": "172.16.20.0/24", "gateway": "172.16.30.30"}' "$s1_router_URL"
echo $'\n' $?

echo "setting static route for s1 to s1r2 subnet..." $'\n'
curl -X POST -d '{"destination": "172.16.100.0/24", "gateway": "172.16.40.40"}' "$s1_router_URL"
echo $'\n' $?

echo "setting static route for s1 to s1r3 subnet..." $'\n'
curl -X POST -d '{"destination": "172.16.200.0/24", "gateway": "172.16.50.50"}' "$s1_router_URL"
echo $'\n' $?

echo "setting static route for s1 to s1r4 subnet..." $'\n'
curl -X POST -d '{"destination": "192.168.30.0/24", "gateway": "192.168.10.20"}' "$s1_router_URL"
echo $'\n' $?

