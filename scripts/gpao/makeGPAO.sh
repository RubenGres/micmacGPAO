#!/bin/bash

NAME=MMGPAO_`(date +'%y%m%d%H%M%S%N' | cut -c 1-14)`
PID=$$

python3 /home/osgeo/GPAO/micmac/scripts/gpao/MM_GPAO.py "$@" --project_name $NAME --PPID 2 --API_URL $URL_API --API_PORT $API_PORT --API_PROTOCOL $API_PROTOCOL --API --await #--JSON ./MMGPAO