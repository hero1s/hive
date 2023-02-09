#!/bin/bash
set -xe

#Linux之CentOS 7通过yum安装gcc
yum install centos-release-scl -y
yum install devtoolset-10-toolchain -y
scl enable devtoolset-10 bash
echo "source /opt/rh/devtoolset-10/enable" >> ~/.bash_profile
source ~/.bash_profile
source /opt/rh/devtoolset-10/enable


yum install libcurl-devel -y
yum install zlib-devel -y

