@echo off

set gm_data="{\"data\":{\"name\":\"gm_hive_quit\",\"reason\":1}}"

curl --request POST --url http://localhost:9401/message --header 'content-type: application/json'  --data %gm_data%

exit