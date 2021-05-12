#!/bin/bash
sudo podman rm -f influxdb
sudo podman volume prune -f
rm ./export.tar.gz
