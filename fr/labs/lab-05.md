---
nav_exclude: true
lang: fr
permalink: /fr/labs/lab-05
title: "Lab 05 - Infracost : Estimation des coûts et budgétisation"
description: "Estimer les coûts d'infrastructure à partir de templates Bicep et mettre en place des contrôles de coûts dans les PR."
---

## Aperçu

| | |
|---|---|
| **Durée** | 35 minutes |
| **Niveau** | Intermédiaire |
| **Prérequis** | [Lab 01](lab-01.md) |

## Objectifs d'apprentissage

À la fin de ce lab, vous serez capable de :

* Configurer Infracost avec une clé API et les paramètres du projet
* Exécuter `infracost breakdown` pour estimer les coûts mensuels d'infrastructure à partir de templates Bicep
* Utiliser `infracost diff` pour comparer les changements de coûts entre les révisions Bicep
* Convertir la sortie JSON d'Infracost en SARIF à l'aide du convertisseur `infracost-to-sarif.py`
* Comprendre comment le workflow de contrôle de coûts dans les PR bloque les changements coûteux

## Exercices

### Exercice 5.1 : Configurer Infracost

Vous allez configurer Infracost avec une clé API et examiner la configuration du projet.

1. Inscrivez-vous pour obtenir une clé API Infracost gratuite sur [infracost.io](https://www.infracost.io/) si ce n'est pas déjà fait.

2. Configurez la clé API :

   ```bash
   infracost configure set api_key YOUR_API_KEY
   ```

3. Vérifiez la configuration :

   ```bash
   infracost configure get api_key
   ```

4. Ouvrez `src/config/infracost.yml` et examinez la configuration du projet :

   ```yaml
   version: 0.1
   projects:
     - path: infra/
       name: finops-demo-app
   ```

   Cela indique à Infracost d'analyser le répertoire `infra/` de chaque application de démonstration pour les templates Bicep ou Terraform.

![Configuration Infracost](../../images/lab-05/lab-05-infracost-config.png)

> [!TIP]
> Infracost utilise les API de tarification cloud pour estimer les coûts. Il ne nécessite pas de ressources déployées — il analyse les templates IaC et associe les types de ressources aux données de tarification actuelles. Cela le rend idéal pour les vérifications de coûts **avant déploiement** dans les pipelines CI/CD.

### Exercice 5.2 : Détail des coûts — Application 002

Vous allez générer un détail des coûts pour l'application de démonstration avec des ressources surdimensionnées.

1. Créez le répertoire de rapports :

   ```bash
   mkdir -p reports
   ```

2. Exécutez le détail des coûts Infracost pour l'application 002 :

   ```bash
   infracost breakdown --path finops-demo-app-002/infra/ --format json --out-file reports/infracost.json
   ```

3. Affichez le résumé lisible :

   ```bash
   infracost breakdown --path finops-demo-app-002/infra/
   ```

   La sortie sous forme de tableau montre chaque ressource, son SKU ou niveau, et le coût mensuel estimé.

4. Ouvrez `reports/infracost.json` et examinez la structure :
   - **`projects`** — tableau des chemins IaC analysés
   - **`totalMonthlyCost`** — coût mensuel total estimé pour toutes les ressources
   - **`resources`** — détails des coûts par ressource avec tarification détaillée

5. Notez le coût de l'App Service Plan P3v3. C'est la ressource surdimensionnée que l'application 002 déploie intentionnellement — un plan de niveau premium pour une charge de travail de développement.

![Sortie du détail des coûts Infracost](../../images/lab-05/lab-05-infracost-breakdown.png)

> [!NOTE]
> L'application 002 utilise un App Service Plan **P3v3** et un stockage **Premium**. Ce sont des niveaux coûteux destinés aux charges de travail de niveau production. Infracost rend le coût mensuel immédiatement visible pour que vous puissiez prendre des décisions éclairées avant le déploiement.

### Exercice 5.3 : Comparaison des coûts

Vous allez modifier un SKU dans le template Bicep de l'application 002 et utiliser `infracost diff` pour voir l'impact sur les coûts.

1. Ouvrez `finops-demo-app-002/infra/main.bicep` dans votre éditeur.

2. Trouvez le SKU de l'App Service Plan et changez-le de `P3v3` à `B1` (niveau Basic) :

   ```bicep
   // Before:
   // sku: { name: 'P3v3', tier: 'PremiumV3' }

   // After:
   sku: { name: 'B1', tier: 'Basic' }
   ```

3. Exécutez `infracost diff` pour comparer le coût du template modifié par rapport à la référence :

   ```bash
   infracost diff --path finops-demo-app-002/infra/ --compare-to reports/infracost.json
   ```

4. Examinez la sortie de la comparaison. Elle montre :
   - Les ressources avec un coût **augmenté** (▲)
   - Les ressources avec un coût **diminué** (▼)
   - Le **changement mensuel net** résultant de la modification

5. La comparaison devrait montrer une réduction significative des coûts en passant de P3v3 à B1 — cela démontre l'importance du dimensionnement correct pour la gouvernance FinOps.

6. **Annulez** la modification de `main.bicep` pour ne pas affecter les labs suivants :

   ```bash
   git checkout finops-demo-app-002/infra/main.bicep
   ```

![Sortie de la comparaison Infracost](../../images/lab-05/lab-05-infracost-diff.png)

> [!IMPORTANT]
> Annulez toujours les modifications intentionnelles de Bicep après avoir terminé cet exercice. Les applications de démonstration sont conçues avec des violations spécifiques, et les modifier de façon permanente peut affecter les Labs 06 et 07.

### Exercice 5.4 : Convertir en SARIF

Vous allez convertir la sortie JSON d'Infracost au format SARIF.

1. Exécutez le convertisseur SARIF :

   ```bash
   python src/converters/infracost-to-sarif.py reports/infracost.json reports/infracost.sarif
   ```

2. Ouvrez le fichier SARIF généré :

   ```bash
   cat reports/infracost.sarif
   ```

3. Examinez la structure SARIF :
   - Le `tool.driver.name` est défini à `infracost-to-sarif`
   - Chaque ressource avec un coût mensuel supérieur à un seuil est rapportée comme un résultat
   - Le `message.text` inclut le coût mensuel estimé pour la ressource
   - Le `physicalLocation` pointe vers le fichier Bicep qui définit la ressource

4. Ce fichier SARIF peut être téléversé vers l'onglet Sécurité GitHub aux côtés des résultats PSRule, Checkov et Cloud Custodian pour fournir une vue unifiée des résultats de gouvernance des coûts.

![SARIF converti depuis Infracost](../../images/lab-05/lab-05-infracost-sarif.png)

### Exercice 5.5 : Examiner le workflow de contrôle de coûts

Vous allez parcourir le workflow GitHub Actions qui bloque les changements d'infrastructure coûteux dans les pull requests.

1. Ouvrez `.github/workflows/finops-cost-gate.yml` et examinez la structure du workflow :

   ```yaml
   name: FinOps Cost Gate

   on:
     pull_request:
       branches: [main]
       paths: ['infra/**']
   ```

   Le workflow se déclenche sur les pull requests vers `main` qui modifient des fichiers sous `infra/`.

2. Examinez les étapes du workflow :
   - **Setup Infracost** — installe le CLI Infracost avec la clé API depuis les secrets du dépôt
   - **Generate Infracost baseline** — exécute `infracost breakdown` pour capturer le coût actuel
   - **Run Infracost diff** — compare les changements de la PR par rapport à la référence
   - **Post PR comment** — utilise `infracost comment github` pour ajouter un commentaire de résumé des coûts sur la PR
   - **Convert to SARIF** — génère un fichier SARIF à partir de la sortie de la comparaison Infracost
   - **Upload SARIF** — téléverse le fichier SARIF vers l'onglet Sécurité GitHub

3. Notez la commande `infracost comment github` :

   ```yaml
   infracost comment github \
     --path infracost-output.json \
     --repo ${{ github.repository }} \
     --pull-request ${{ github.event.pull_request.number }} \
     --github-token ${{ secrets.GITHUB_TOKEN }} \
     --behavior update
   ```

   Le drapeau `--behavior update` met à jour le commentaire existant au lieu de créer des doublons à chaque push.

4. Ce workflow crée un **contrôle de coûts** — les réviseurs peuvent voir l'impact financier des changements d'infrastructure directement dans la PR avant d'approuver.

![YAML du workflow de contrôle de coûts](../../images/lab-05/lab-05-cost-gate-workflow.png)

> [!TIP]
> En production, vous pouvez étendre le contrôle de coûts pour **faire échouer la vérification de la PR** si les coûts dépassent un seuil. Ajoutez une étape qui lit le `totalMonthlyCost` depuis le JSON Infracost et le compare à une limite budgétaire.

## Point de vérification

Avant de continuer, vérifiez :

* [ ] Infracost authentifié et retournant des estimations de coûts
* [ ] Détail des coûts généré pour au moins 1 application de démonstration
* [ ] Avez observé la différence de coûts avec `infracost diff` après modification d'un SKU
* [ ] Fichier SARIF généré à partir de la sortie Infracost

## Étapes suivantes

Passez au [Lab 06 — Sortie SARIF et onglet Sécurité GitHub](lab-06.md).
