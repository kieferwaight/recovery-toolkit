#!/usr/bin/env bash
# TODO: script that can be called with curl github.com/kieferwaight/recovery-toolkit ... bootstrap.sh | sh 
# TODO: Ask for sudo access
export INSTALL_DIR="/opt/recovery-toolkit"

# Update mirrors and grab core dev tools
sudo apt-get update && sudo apt-get upgrade -y
sudo apt-get install -y --no-install-recommends \
  git curl make tree jq shellcheck glow
# TODO: Package configuration triggers UI that wants layout of keyboards. Should prevent
# that from happning

# Setup dir
sudo mkdir -p ${INSTALL_DIR}
sudo groupadd -r toolkit
sudo usermod -aG toolkit ${USER}
sudo chown -R root:toolkit ${INSTALL_DIR}
sudo chmod -R u=rwX,g=rwX,o=rX ${INSTALL_DIR}
sudo find ${INSTALL_DIR} -type d -exec chmod g+s {} +

# Configure Git
git config --global user.name "Kiefer Waight"
git config --global user.email "kwaight@users.noreply.github.com"
git config --global init.defaultBranch main
git config --global --add safe.directory /opt/rescue-toolkit
git clone kieferwaight/recovery-usb ${INSTALL_DIR}

# Generate .env , source, and then run Makefile for everything else.
# Might need to run chmod +x on chmod +x packages/setup-packages.sh and bin stuff
