#!/bin/bash

MMGPAO_path=/Volumes/ESPACE_TRAVAIL_Puma/DANI/RUBEN/MM3D/micmac/scripts/gpao

export PATH=$PATH:$MMGPAO_path/bin

if [ -z "$http_proxy" ]; then
  export http_proxy=http://proxy.ign.fr:3128
fi

if [ -z "$https_proxy" ]; then
  export https_proxy=http://proxy.ign.fr:3128
fi

if [ -z "$URL_API" ]; then
  export URL_API=172.24.1.44
fi

if [ -z "$API_PORT" ]; then
  export API_PORT=8080
fi

if [ -z "$API_PROTOCOL" ]; then
  export API_PROTOCOL=http
fi

if [ -z "$MM_GPAO_PY" ]; then
  export MM_GPAO_PY=$MMGPAO_path/MM_GPAO.py
fi