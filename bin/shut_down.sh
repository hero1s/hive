#!/bin/sh

curl --request POST --url http://localhost:9401/message --header 'content-type: application/json'  --data "{\"data\":{\"name\":\"gm_hive_quit\",\"reason\":1}}"