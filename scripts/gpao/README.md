#  MicMac 3D GPAO

> Cette version de MicMac 3D s'appuie sur la [GPAO](https://github.com/ign-gpao) pour faciliter le suivi, la parallélisation et l'ordonnancement des tâches réalisées par cet outil. Tous les traitements parallélisables seront donc automatiquement envoyés sur la GPAO.


## Mise en place

exécuter le script `MM3D_GPAO_install.sh` pour installer toutes les dépendances.

```bash
source /Volumes/ESPACE_TRAVAIL_Puma/DANI/RUBEN/MM3D/micmac/scripts/gpao/MM3D_GPAO_install.sh
```

Actuellement la version mm3d linux compilée pour la GPAO se situe temporairement à l'adresse:
`/Volumes/ESPACE_TRAVAIL_Puma/DANI/RUBEN/MM3D/micmac/bin/mm3d`

## Paramètres

Les différents paramètres de configuration pour la GPAO sont initialisés par des valeurs par défaut avec le script d'installation. Cependant si l'adresse de l'a GPAO venait à changer, voici les variables d'environnement à modifier:

Par exemple pour GPAO s'exécutant en local:
```bash
export URL_API=localhost
export API_PORT=8080
export API_PROTOCOL=http
```

D'autres variables d'environnement optionnelles permettent d'avoir plus de controle sur l'environnement d'exécution:  
`MMGPAO_PROJECT_NAME`, `MMGPAO_CONDA_ENV`, `MMGPAO_WORKING_DIR`

exemple de configuration:
```bash
export MMGPAO_PROJECT_NAME=my_project
export MMGPAO_CONDA_ENV=base
export MMGPAO_WORKING_DIR=$PWD
```
