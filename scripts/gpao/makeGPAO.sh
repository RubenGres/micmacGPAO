#!/bin/bash

NAME=MMGPAO_`(date +'%y%m%d%H%M%S%N' | cut -c 1-14)`
PID=$$
mkdir ./MMGPAO
python3 /home/osgeo/GPAO/micmac/scripts/gpao/MM_GPAO.py "$@" --JSON ./MMGPAO --project_name $NAME --PPID $PID #--API $URL_API
