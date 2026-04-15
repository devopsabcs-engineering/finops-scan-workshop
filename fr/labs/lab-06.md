---
nav_exclude: true
permalink: /fr/labs/lab-06
title: "Lab 06 - Sortie SARIF et onglet Sécurité GitHub"
description: "Comprendre le format SARIF et téléverser les résultats d'analyse vers l'onglet Sécurité GitHub."
---

## Aperçu

| | |
|---|---|
| **Durée** | 30 minutes |
| **Niveau** | Intermédiaire |
| **Prérequis** | [Lab 02](lab-02.md), [Lab 03](lab-03.md), [Lab 04](lab-04.md) ou [Lab 05](lab-05.md) (au moins un) |

> [!TIP]
> **Vous utilisez Azure DevOps ?** Consultez le [Lab 06-ADO — Sortie SARIF et ADO Advanced Security](lab-06-ado.md) pour la variante ADO de ce lab.

## Objectifs d'apprentissage

À la fin de ce lab, vous serez capable de :

* Expliquer le schéma SARIF v2.1.0 incluant les sections runs, tool, rules, results et locations
* Téléverser des résultats SARIF vers GitHub Code Scanning via l'API REST
* Naviguer dans l'onglet Sécurité GitHub pour visualiser les alertes FinOps
* Filtrer, trier et rejeter les alertes dans l'onglet Sécurité

## Exercices

### Exercice 6.1 : Exploration approfondie du schéma SARIF

Vous allez examiner le format SARIF v2.1.0 que les quatre outils d'analyse produisent.

1. Ouvrez n'importe quel fichier SARIF que vous avez généré dans un lab précédent (par exemple, `reports/psrule-001.sarif` ou `reports/custodian.sarif`).

2. Examinez la structure de haut niveau. Chaque fichier SARIF suit ce schéma :

   ```json
   {
     "version": "2.1.0",
     "$schema": "https://raw.githubusercontent.com/oasis-tcs/sarif-spec/main/sarif-2.1/schema/sarif-schema-2.1.0.json",
     "runs": [
       {
         "tool": {
           "driver": {
             "name": "CloudCustodian",
             "version": "1.0.0",
             "informationUri": "https://cloudcustodian.io",
             "rules": [
               {
                 "id": "check-required-tags",
                 "name": "check-required-tags",
                 "shortDescription": {
                   "text": "Cloud Custodian policy violation"
                 },
                 "defaultConfiguration": {
                   "level": "warning"
                 }
               }
             ]
           }
         },
         "results": [
           {
             "ruleId": "check-required-tags",
             "level": "warning",
             "message": {
               "text": "Resource rg-finops-demo-001 violates policy check-required-tags"
             },
             "locations": [
               {
                 "physicalLocation": {
                   "artifactLocation": {
                     "uri": "infra/main.bicep"
                   },
                   "region": {
                     "startLine": 1
                   }
                 }
               }
             ]
           }
         ]
       }
     ]
   }
   ```

3. Comprenez les quatre sections principales :

   | Section | Objectif |
   |---------|----------|
   | `version` / `$schema` | Déclare la conformité SARIF v2.1.0 |
   | `runs[].tool.driver` | Identifie l'outil d'analyse, la version et les définitions de règles |
   | `runs[].tool.driver.rules[]` | Définit les identifiants de règles, les descriptions, la sévérité et les URL d'aide |
   | `runs[].results[]` | Contient les résultats individuels avec l'identifiant de règle, la sévérité, le message et l'emplacement |

4. Notez comment `physicalLocation` lie un résultat à un fichier et un numéro de ligne spécifiques. GitHub Code Scanning utilise cela pour annoter les fichiers source dans les pull requests.

![Structure JSON SARIF avec annotations](../../images/lab-06/lab-06-sarif-structure.png)

> [!TIP]
> SARIF (Static Analysis Results Interchange Format) est un standard OASIS. GitHub, Azure DevOps et de nombreuses extensions d'IDE peuvent consommer des fichiers SARIF. En produisant du SARIF à partir des 4 outils, vous obtenez une vue unifiée des violations FinOps sur l'ensemble de votre plateforme d'analyse.

### Exercice 6.2 : Téléverser manuellement un SARIF

Vous allez téléverser un fichier SARIF vers l'API GitHub Code Scanning en utilisant GitHub CLI.

1. Choisissez un fichier SARIF d'un lab précédent. Cet exemple utilise la sortie PSRule pour l'application 001 :

   ```bash
   SARIF_FILE="reports/psrule-001.sarif"
   ```

2. Compressez et encodez en base64 le fichier SARIF (requis par l'API) :

   ```bash
   cat $SARIF_FILE | gzip | base64 > /tmp/sarif-base64.txt
   ```

   Sous Windows PowerShell :

   ```powershell
   $bytes = [System.IO.File]::ReadAllBytes("reports/psrule-001.sarif")
   $ms = New-Object System.IO.MemoryStream
   $gz = New-Object System.IO.Compression.GZipStream($ms, [System.IO.Compression.CompressionMode]::Compress)
   $gz.Write($bytes, 0, $bytes.Length)
   $gz.Close()
   $encoded = [Convert]::ToBase64String($ms.ToArray())
   $encoded | Out-File /tmp/sarif-base64.txt -NoNewline
   ```

3. Téléversez vers le point de terminaison Code Scanning :

   ```bash
   gh api -X POST /repos/{owner}/{repo}/code-scanning/sarifs \
     -f "commit_sha=$(git rev-parse HEAD)" \
     -f "ref=refs/heads/main" \
     -f "sarif=$(cat /tmp/sarif-base64.txt)" \
     -f "tool_name=PSRule"
   ```

   Remplacez `{owner}` et `{repo}` par le propriétaire et le nom de votre fork.

4. L'API retourne une réponse avec un champ `url`. Vous pouvez interroger cette URL pour vérifier le statut du traitement :

   ```bash
   gh api /repos/{owner}/{repo}/code-scanning/sarifs/{sarif_id}
   ```

5. Le traitement prend quelques secondes. Une fois terminé, les résultats apparaissent dans l'onglet Sécurité.

![Commande gh api pour téléverser un SARIF](../../images/lab-06/lab-06-gh-api-upload.png)

> [!IMPORTANT]
> L'API Code Scanning nécessite que le dépôt ait GitHub Advanced Security activé. Si vous recevez une erreur 403, vérifiez que GHAS est activé dans les paramètres de votre dépôt sous **Settings → Code security and analysis**.

### Exercice 6.3 : Visualiser l'onglet Sécurité

Vous allez naviguer vers l'onglet Sécurité GitHub pour visualiser les alertes FinOps téléversées.

1. Ouvrez votre dépôt sur GitHub.

2. Cliquez sur l'onglet **Security** dans la barre de navigation supérieure.

3. Cliquez sur **Code scanning** dans la barre latérale gauche.

4. Vous devriez voir les alertes du fichier SARIF que vous avez téléversé. Chaque alerte affiche :
   - **Rule ID** — l'identifiant de règle spécifique à l'outil d'analyse
   - **Severity** — error, warning ou note
   - **File** — le fichier source où la violation a été détectée
   - **Tool** — l'outil d'analyse qui a produit le résultat (PSRule, Checkov, Cloud Custodian ou Infracost)

5. Cliquez sur une alerte individuelle pour voir la vue détaillée :
   - La description du résultat et les conseils de remédiation
   - L'emplacement dans le code source mis en surbrillance
   - Les métadonnées de la règle SARIF

![Onglet Sécurité GitHub montrant les alertes FinOps](../../images/lab-06/lab-06-security-tab.png)

> [!NOTE]
> Si vous avez téléversé des SARIF provenant de plusieurs outils, utilisez le filtre **Tool** pour voir les résultats d'un outil spécifique. Cela facilite le tri lorsque vous souhaitez vous concentrer sur une catégorie de violations à la fois.

### Exercice 6.4 : Trier les alertes

Vous allez pratiquer le workflow de tri pour les alertes FinOps.

1. Dans la liste des alertes Code Scanning, cliquez sur n'importe quelle alerte.

2. Utilisez le menu déroulant **Dismiss alert** pour explorer les options de tri :
   - **False positive** — l'alerte ne s'applique pas à cette ressource
   - **Won't fix** — reconnu mais ne vaut pas la peine d'être corrigé
   - **Used in tests** — la violation est intentionnelle à des fins de test

3. Rejetez une alerte comme **Used in tests** (puisque ces applications de démonstration sont intentionnellement mal configurées).

4. Utilisez les contrôles de filtre pour affiner la liste des alertes :
   - Filtrer par **Tool** — afficher uniquement les résultats PSRule, Checkov ou Cloud Custodian
   - Filtrer par **Severity** — afficher uniquement les erreurs, avertissements ou notes
   - Filtrer par **State** — afficher les alertes ouvertes, rejetées ou corrigées

5. Marquez une alerte comme **Closed** pour simuler un workflow de remédiation. En pratique, vous corrigeriez le template Bicep et relanceriez l'analyse pour confirmer la résolution de l'alerte.

![Menu déroulant de tri des alertes](../../images/lab-06/lab-06-alert-triage.png)

> [!TIP]
> Dans un programme FinOps en production, assignez le tri des alertes à des membres d'équipe spécifiques. Utilisez les webhooks de l'API GitHub Code Scanning pour créer des notifications automatiques lorsque de nouvelles alertes FinOps de haute sévérité apparaissent.

### Exercice 6.5 : Téléversement inter-dépôts

Vous allez comprendre comment le pipeline automatisé téléverse les SARIF vers le dépôt de chaque application de démonstration.

1. Ouvrez `.github/workflows/finops-scan.yml` et trouvez le job `cross-repo-upload`.

2. Examinez la configuration du job :

   ```yaml
   cross-repo-upload:
     needs: [psrule-scan, checkov-scan, custodian-scan]
     if: always() && (needs.psrule-scan.result == 'success' || needs.checkov-scan.result == 'success')
     runs-on: ubuntu-latest
     strategy:
       matrix:
         app: ['001', '002', '003', '004', '005']
   ```

   Le job s'exécute après que les trois jobs d'analyse sont terminés et utilise une matrice pour traiter chaque application de démonstration.

3. Comprenez les étapes de téléversement :
   - **Download artifacts** — récupère tous les fichiers SARIF pour l'application courante en utilisant `actions/download-artifact@v4` avec une correspondance par motif
   - **Upload SARIF** — itère sur chaque fichier SARIF et le POSTe vers le point de terminaison Code Scanning du dépôt cible

4. Le script de téléversement compresse chaque fichier SARIF, recherche le dernier SHA de commit sur la branche `main` du dépôt cible, et appelle l'API Code Scanning — les mêmes étapes que vous avez effectuées manuellement dans l'Exercice 6.2 :

   ```bash
   SARIF_CONTENT=$(gzip -c "$sarif_file" | base64 -w0)
   COMMIT_SHA=$(gh api repos/{org}/finops-demo-app-{app}/commits/main --jq '.sha')
   gh api --method POST \
     repos/{org}/finops-demo-app-{app}/code-scanning/sarifs \
     -f "commit_sha=$COMMIT_SHA" \
     -f "ref=refs/heads/main" \
     -f "sarif=$SARIF_CONTENT"
   ```

5. Ce modèle pousse les résultats d'analyse depuis un dépôt d'analyse centralisé **vers** chaque dépôt d'application individuel, pour que les équipes voient les alertes FinOps directement dans leur propre onglet Sécurité.

![Page de détail d'une alerte individuelle](../../images/lab-06/lab-06-alert-detail.png)

> [!NOTE]
> Le téléversement inter-dépôts nécessite un secret `ORG_ADMIN_TOKEN` avec la permission `security_events: write` sur tous les dépôts cibles. Le script `setup-oidc.ps1` du Lab 07 ne couvre pas ce jeton — il doit être créé comme un jeton d'accès personnel GitHub ou un jeton à granularité fine.

## Point de vérification

Avant de continuer, vérifiez :

* [ ] Pouvez décrire les 4 sections principales du SARIF (schema, runs, tool/rules, results)
* [ ] Avez téléversé avec succès un fichier SARIF via `gh api`
* [ ] Avez visualisé les alertes FinOps dans l'onglet Sécurité GitHub
* [ ] Avez trié au moins 1 alerte (rejetée ou marquée comme corrigée)

## Étapes suivantes

Passez au [Lab 07 — Pipelines GitHub Actions et contrôles de coûts](lab-07.md).
