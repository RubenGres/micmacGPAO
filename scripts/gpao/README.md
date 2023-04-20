Pour ajouter la commande makeGPAO à son système linux, se rendre dans le dossier /scripts/gpao et taper la commande:
```bash
source makeGPAO.sh
```
Un fois que c'est fait, il sera alors possible d'appeller makeGPAO depuis n'importe quel dossier.

L'URL de l'api du monitor GPAO doit être spécifiée dans la variable d'environnement URL_API:
Les parametres API_PORT et API_PROTOCOL doivent aussi être spécifiés.
```bash
export API_URL=localhost
export API_PORT=8001
export API_PROTOCOL=http
```

