#!/bin/bash
set -e;

# Install required Docker images
docker pull postgres:18-trixie;
docker pull quay.io/jupyter/scipy-notebook:latest;
docker pull quay.io/jupyter/pytorch-notebook:latest;
