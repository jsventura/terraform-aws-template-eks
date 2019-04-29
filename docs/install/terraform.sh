#!/bin/bash

cd /opt && wget https://releases.hashicorp.com/terraform/0.11.13/terraform_0.11.13_linux_amd64.zip
unzip terraform_0.11.13_linux_amd64.zip
chmod +x terraform
sudo mv terraform /usr/sbin/
