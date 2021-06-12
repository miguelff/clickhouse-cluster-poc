#!/bin/bash

SCRIPT_DIR=`dirname $0`
cd $SCRIPT_DIR

rm -rf ../clickhouse-s0-r0/volumes/* ../clickhouse-s1-r0/volumes/* ../clickhouse-s0-r1/volumes/* ../clickhouse-s1-r1/volumes/* ../zookeeper/volumes/data/* ../zookeeper/volumes/datalog/*

