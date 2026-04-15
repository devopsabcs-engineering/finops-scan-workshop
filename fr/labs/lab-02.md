---
nav_exclude: true
lang: fr
permalink: /fr/labs/lab-02
title: "Lab 02 - PSRule : Analyse d'infrastructure en tant que code"
description: "Analyser les templates Bicep pour détecter les violations de gouvernance des coûts à l'aide de PSRule for Azure."
---

## Aperçu

| | |
|---|---|
| **Durée** | 35 minutes |
| **Niveau** | Intermédiaire |
| **Prérequis** | [Lab 01](lab-01.md) |

## Objectifs d'apprentissage

À la fin de ce lab, vous serez capable de :

* Configurer PSRule avec `ps-rule.yaml` pour l'analyse de Bicep Azure
* Exécuter PSRule localement en utilisant `Invoke-PSRule` avec la baseline Azure.GA
* Interpréter la sortie SARIF de PSRule pour identifier les violations d'étiquettes et de SKU
* Comprendre les catégories de règles PSRule pour la gouvernance des coûts

## Exercices

### Exercice 2.1 : Examiner la configuration PSRule

Vous allez examiner le fichier de configuration PSRule qui contrôle la façon dont les templates Bicep sont analysés.

1. Ouvrez `src/config/ps-rule.yaml` dans VS Code.
2. Examinez la configuration :

   ```yaml
   configuration:
     AZURE_RESOURCE_ALLOWED_LOCATIONS:
       - canadacentral
       - eastus
       - eastus2
     # Expand Bicep files for analysis
     AZURE_BICEP_FILE_EXPANSION: true
     AZURE_BICEP_FILE_EXPANSION_TIMEOUT: 30

   # Use the GA baseline which includes cost-related rules
   rule:
     includeLocal: true

   binding:
     targetType:
       - type
       - resourceType

   input:
     pathIgnore:
       - '*.md'
       - '.github/**'

   output:
     format: Sarif
     path: reports/psrule-results.sarif
   ```

3. Notez les paramètres clés :
   - **`AZURE_BICEP_FILE_EXPANSION: true`** — PSRule décompile les fichiers Bicep en JSON ARM avant l'analyse, permettant une analyse plus approfondie.
   - **`AZURE_RESOURCE_ALLOWED_LOCATIONS`** — restreint les ressources à `canadacentral`, `eastus` et `eastus2`. Les ressources dans d'autres régions sont signalées.
   - **`output.format: Sarif`** — les résultats sont écrits au format SARIF pour l'intégration avec l'onglet Sécurité GitHub.

![Fichier de configuration PSRule](../../images/lab-02/lab-02-psrule-config.png)

> [!TIP]
> La baseline `Azure.GA_2024_12` inclut des règles pour l'étiquetage des ressources, le nommage, le dimensionnement des SKU et la sécurité. Vous pouvez afficher la liste complète des règles avec `Get-PSRule -Module PSRule.Rules.Azure -Baseline Azure.GA_2024_12`.

### Exercice 2.2 : Analyser l'application 001

Vous allez exécuter PSRule sur l'application sans étiquettes pour générer votre premier ensemble de résultats.

1. Créez un répertoire de rapports :

   ```powershell
   New-Item -ItemType Directory -Path reports -Force
   ```

2. Exécutez PSRule sur l'application 001 :

   ```powershell
   Invoke-PSRule `
     -InputPath finops-demo-app-001/infra/ `
     -Module PSRule.Rules.Azure `
     -Baseline Azure.GA_2024_12 `
     -Option src/config/ps-rule.yaml `
     -OutputFormat Sarif `
     -OutputPath reports/psrule-001.sarif
   ```

3. Examinez la sortie console. Vous devriez voir plusieurs résultats **Fail** liés aux étiquettes manquantes.

![Sortie de l'analyse PSRule pour l'application 001](../../images/lab-02/lab-02-psrule-scan-001.png)

> [!TIP]
> Pour voir les résultats sous forme de tableau dans la console sans écrire dans un fichier, omettez les paramètres `-OutputFormat` et `-OutputPath`.

### Exercice 2.3 : Analyser les résultats

Vous allez ouvrir le fichier SARIF et comprendre la structure des résultats PSRule.

1. Ouvrez `reports/psrule-001.sarif` dans VS Code (installez l'extension **SARIF Viewer** pour une expérience plus riche).

2. Localisez le tableau `results`. Chaque résultat contient :
   - **`ruleId`** — la règle PSRule violée (par exemple, `Azure.Resource.UseTags`)
   - **`level`** — sévérité : `error`, `warning` ou `note`
   - **`message.text`** — description lisible de la violation
   - **`locations`** — le nom et le type de la ressource ayant échoué à la règle

3. Identifiez les résultats. Les identifiants de règles courants pour la gouvernance des coûts incluent :

   | Identifiant de règle | Catégorie | Description |
   |---------------------|-----------|-------------|
   | `Azure.Resource.UseTags` | Étiquetage | Les ressources doivent avoir des étiquettes |
   | `Azure.Resource.AllowedRegions` | Localisation | Ressources dans une région non approuvée |

4. Comptez le nombre total de résultats. L'application 001 a 3 ressources sans étiquettes, vous devriez donc voir au moins 3 résultats liés à l'étiquetage.

![Sortie SARIF montrant les résultats](../../images/lab-02/lab-02-psrule-sarif.png)

### Exercice 2.4 : Analyser l'application 002

Vous allez analyser l'application avec des ressources surdimensionnées et comparer les résultats avec l'application 001.

1. Exécutez PSRule sur l'application 002 :

   ```powershell
   Invoke-PSRule `
     -InputPath finops-demo-app-002/infra/ `
     -Module PSRule.Rules.Azure `
     -Baseline Azure.GA_2024_12 `
     -Option src/config/ps-rule.yaml `
     -OutputFormat Sarif `
     -OutputPath reports/psrule-002.sarif
   ```

2. Examinez la sortie console. L'application 002 **possède** les 7 étiquettes requises, donc les règles d'étiquetage devraient passer.

3. Recherchez les résultats liés au **dimensionnement des SKU** ou à la **gouvernance des niveaux**. L'App Service Plan P3v3 et le stockage Premium peuvent déclencher des règles selon la baseline.

4. Comparez le nombre de résultats entre les applications 001 et 002 :

   | Application | Résultats étiquettes | Résultats SKU | Total |
   |-------------|---------------------|---------------|-------|
   | 001 | Multiples | 0 | Élevé |
   | 002 | 0 | Variable | Plus bas |

![Sortie de l'analyse PSRule pour l'application 002](../../images/lab-02/lab-02-psrule-scan-002.png)

> [!TIP]
> PSRule se concentre principalement sur les bonnes pratiques IaC. Pour l'analyse des coûts en temps réel (dépenses réelles, recommandations de dimensionnement), vous utiliserez Cloud Custodian dans le Lab 04 et Infracost dans le Lab 05.

### Exercice 2.5 : Corriger et ré-analyser

Vous allez corriger la violation d'étiquetage dans l'application 001 et observer la réduction des résultats.

1. Ouvrez `finops-demo-app-001/infra/main.bicep`.

2. Ajoutez une variable `commonTags` après les déclarations de paramètres :

   ```bicep
   var commonTags = {
     CostCenter: 'CC-1234'
     Owner: 'team@contoso.com'
     Environment: 'dev'
     Application: 'finops-demo-001'
     Department: 'Engineering'
     Project: 'FinOps-Scanner'
     ManagedBy: 'Bicep'
   }
   ```

3. Ajoutez `tags: commonTags` à chaque ressource. Par exemple, le Storage Account devient :

   ```bicep
   resource storageAccount 'Microsoft.Storage/storageAccounts@2023-05-01' = {
     name: storageAccountName
     location: location
     kind: 'StorageV2'
     sku: {
       name: 'Standard_LRS'
     }
     tags: commonTags
   }
   ```

4. Répétez pour les ressources `appServicePlan` et `webApp`.

5. Relancez l'analyse PSRule :

   ```powershell
   Invoke-PSRule `
     -InputPath finops-demo-app-001/infra/ `
     -Module PSRule.Rules.Azure `
     -Baseline Azure.GA_2024_12 `
     -Option src/config/ps-rule.yaml `
     -OutputFormat Sarif `
     -OutputPath reports/psrule-001-fixed.sarif
   ```

6. Comparez les nouveaux résultats avec l'analyse initiale. Les résultats d'étiquetage devraient être éliminés.

![Résultats de la ré-analyse après correction des étiquettes](../../images/lab-02/lab-02-psrule-fixed.png)

> [!CAUTION]
> Ne **validez pas** (commit) le fichier Bicep corrigé si vous souhaitez que la violation reste présente pour les labs suivants. Utilisez `git checkout -- finops-demo-app-001/infra/main.bicep` pour annuler vos modifications.

## Point de vérification

Avant de continuer, vérifiez :

* [ ] L'analyse PSRule s'est terminée avec succès sur au moins 2 applications de démonstration
* [ ] Les fichiers de sortie SARIF ont été générés dans le répertoire `reports/`
* [ ] Pouvez expliquer ce que `Azure.Resource.UseTags` détecte
* [ ] Avez corrigé avec succès au moins 1 résultat en ajoutant des étiquettes au Bicep

## Étapes suivantes

Passez au [Lab 03 — Checkov : Analyse statique de politiques](lab-03.md).
