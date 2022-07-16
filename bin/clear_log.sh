#!/bin/sh

find ./logs/* -mtime +$1 -type f | xargs rm -rf

