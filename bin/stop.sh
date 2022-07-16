#!/bin/sh

params=( )
if [ $# -gt 0 ]; then
  for file in ` ls pid `
  do
    echo "pid file:"$file
    cat pid/$file | xargs kill -10
  done
  sleep 3
  echo "hive exist:" `ps -lef | grep "hive" | grep -v "grep" | wc -l`
  exit 1
else
  echo "you have kill all hive server !!!!!!!!!!!!!!!!!"
  pidcount=$(ps aux | grep hive | grep -v grep | wc -l)
  if [ $pidcount -gt 0 ]; then
    ps aux | grep hive | grep -v grep | awk '{print $2}' | xargs kill -9
  fi
  sleep 3
fi

echo "hive exist:" `ps -lef | grep "hive" | grep -v "grep" | wc -l`
