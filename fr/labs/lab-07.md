---
nav_exclude: true
lang: fr
permalink: /fr/labs/lab-07
title: "Lab 07 - Pipelines GitHub Actions et contrôles de coûts"
description: "Construire des pipelines d'analyse automatisés et des contrôles de coûts dans les PR avec GitHub Actions."
---

## Aperçu

| | |
|---|---|
| **Durée** | 45 minutes |
| **Niveau** | Avancé |
| **Prérequis** | [Lab 02](lab-02.md), [Lab 03](lab-03.md), [Lab 04](lab-04.md), [Lab 05](lab-05.md), [Lab 06](lab-06.md) |

> [!TIP]
> **Vous utilisez Azure DevOps ?** Consultez le [Lab 07-ADO — Pipelines YAML ADO et contrôles de coûts](lab-07-ado.md) pour la variante ADO de ce lab.

## Objectifs d'apprentissage

À la fin de ce lab, vous serez capable de :

* Construire un workflow GitHub Actions avec une stratégie de matrice pour l'analyse multi-applications
* Configurer l'authentification OIDC pour Azure avec la fédération d'identité de charge de travail
* Implémenter un workflow de contrôle de coûts dans les PR avec Infracost
* Mettre en place le téléversement SARIF inter-dépôts via l'API GitHub Code Scanning
* Déclencher, surveiller et déboguer les exécutions de workflow

## Exercices

### Exercice 7.1 : Examiner le workflow d'analyse

Vous allez parcourir le workflow d'analyse centralisé qui exécute les 4 outils sur les 5 applications de démonstration.

1. Ouvrez `.github/workflows/finops-scan.yml` et examinez l'architecture globale :

   ```text
   finops-scan.yml
   ├── psrule-scan (matrix: 5 apps)     → SARIF artifacts
   ├── checkov-scan (matrix: 5 apps)    → SARIF artifacts
   ├── custodian-scan (matrix: 5 apps)  → SARIF artifacts
   └── cross-repo-upload (matrix: 5 apps)
       └── Downloads all SARIF → uploads to each demo app's Security tab
   ```

2. Examinez les déclencheurs du workflow :

   ```yaml
   on:
     schedule:
       - cron: '0 6 * * 1'  # Weekly Monday 06:00 UTC
     workflow_dispatch:
   ```

   Le workflow s'exécute selon un calendrier hebdomadaire et peut être déclenché manuellement.

3. Examinez le bloc de permissions :

   ```yaml
   permissions:
     contents: read
     security-events: write
     id-token: write
   ```

   - `contents: read` — récupère le code du dépôt
   - `security-events: write` — téléverse les SARIF vers Code Scanning
   - `id-token: write` — demande des jetons OIDC pour l'authentification Azure

4. Examinez la stratégie de matrice utilisée par chaque job d'analyse :

   ```yaml
   strategy:
     matrix:
       app: ['001', '002', '003', '004', '005']
   ```

   Cela crée 5 jobs parallèles — un pour chaque application de démonstration. Chaque job récupère le dépôt de l'application correspondante et exécute l'outil d'analyse.

5. Examinez les étapes du job `psrule-scan` :
   - **Checkout scanner repo** — récupère la configuration PSRule et les convertisseurs SARIF
   - **Checkout target app** — clone le dépôt de l'application de démonstration dans `target-app/`
   - **Run PSRule** — utilise l'action `microsoft/ps-rule@v2.9.0` avec la baseline `Azure.GA_2024_12`
   - **Upload artifact** — enregistre le fichier SARIF comme artefact de build pour le job de téléversement inter-dépôts

6. Examinez le job `custodian-scan`. Contrairement à PSRule et Checkov, Cloud Custodian :
   - S'authentifie auprès d'Azure via OIDC (`azure/login@v2`)
   - S'exécute sur des **ressources actives** au lieu de fichiers IaC
   - Utilise `continue-on-error: true` pour empêcher les échecs d'analyse de bloquer le pipeline
   - Convertit la sortie JSON en SARIF avec `custodian-to-sarif.py`

7. Examinez le job `cross-repo-upload` (couvert dans le Lab 06, Exercice 6.5). Notez comment il dépend des trois jobs d'analyse et s'exécute même si l'analyse custodian échoue.

![YAML du workflow d'analyse](../../images/lab-07/lab-07-scan-workflow.png)

> [!TIP]
> La stratégie de matrice multiplie le nombre de jobs : 3 outils × 5 applications = 15 jobs d'analyse + 5 jobs de téléversement = 20 jobs au total. GitHub Actions exécute les jobs de la matrice en parallèle, donc l'ensemble de l'analyse se termine dans le temps du job individuel le plus lent.

### Exercice 7.2 : Configuration OIDC

Vous allez configurer la fédération OIDC Azure pour que GitHub Actions puisse s'authentifier sans stocker de secrets.

1. Exécutez le script de configuration OIDC :

   ```powershell
   ./scripts/setup-oidc.ps1
   ```

2. Le script effectue 5 étapes :
   - **Enregistrement d'application** — crée ou récupère une application Azure AD nommée `finops-scanner-github-actions`
   - **Informations d'identification fédérées** — crée des informations d'identification OIDC pour chaque combinaison dépôt et branche
   - **Principal de service** — crée ou récupère le principal de service pour l'application
   - **Attribution de rôle** — accorde le rôle `Reader` sur l'abonnement
   - **Résumé** — affiche le Client ID, le Tenant ID et le Subscription ID à configurer comme secrets GitHub

3. Examinez le format du sujet des informations d'identification fédérées :

   ```text
   repo:devopsabcs-engineering/finops-scan-demo-app:ref:refs/heads/main
   repo:devopsabcs-engineering/finops-demo-app-001:environment:production
   ```

   Chaque information d'identification associe un dépôt GitHub spécifique + une branche (ou un environnement) à l'application Azure AD. C'est la **revendication de sujet** OIDC qu'Azure valide lors de l'émission des jetons.

4. Une fois le script terminé, ajoutez les secrets suivants dans les paramètres de votre dépôt GitHub :
   - `AZURE_CLIENT_ID` — le client ID de l'enregistrement d'application
   - `AZURE_TENANT_ID` — votre tenant ID Azure AD
   - `AZURE_SUBSCRIPTION_ID` — l'ID de l'abonnement cible

![Sortie du script de configuration OIDC](../../images/lab-07/lab-07-oidc-setup.png)

> [!IMPORTANT]
> La fédération OIDC élimine le besoin de secrets client ou de certificats. Le runner GitHub Actions demande un jeton à durée de vie courte au fournisseur OIDC de GitHub, et Azure le valide par rapport à la configuration des informations d'identification fédérées. Aucune information d'identification à longue durée de vie n'est stockée dans les secrets GitHub.

### Exercice 7.3 : Déclencher le workflow d'analyse

Vous allez déclencher le workflow d'analyse manuellement et surveiller son exécution.

1. Déclenchez le workflow avec GitHub CLI :

   ```bash
   gh workflow run finops-scan.yml
   ```

2. Surveillez l'exécution du workflow :

   ```bash
   gh run watch
   ```

   Cela ouvre une vue interactive montrant tous les jobs de la matrice et leur progression.

3. Sinon, ouvrez le dépôt sur GitHub, cliquez sur **Actions**, et sélectionnez le workflow **FinOps Scan** pour suivre l'exécution dans le navigateur.

4. Le workflow crée 20 jobs au total :
   - 5 jobs d'analyse PSRule (un par application)
   - 5 jobs d'analyse Checkov (un par application)
   - 5 jobs d'analyse Cloud Custodian (un par application)
   - 5 jobs de téléversement inter-dépôts (un par application)

5. Attendez la fin de l'exécution. Les jobs PSRule et Checkov se terminent généralement en 1 à 2 minutes. Les jobs Cloud Custodian peuvent prendre plus de temps car ils interrogent les ressources Azure actives.

![Exécution du workflow GitHub Actions](../../images/lab-07/lab-07-workflow-run.png)

> [!NOTE]
> Si les jobs Cloud Custodian échouent avec des erreurs d'authentification, vérifiez que vos informations d'identification OIDC sont correctement configurées (Exercice 7.2) et que les secrets `AZURE_CLIENT_ID`, `AZURE_TENANT_ID` et `AZURE_SUBSCRIPTION_ID` sont définis dans les paramètres du dépôt.

### Exercice 7.4 : Examiner les résultats du workflow

Vous allez inspecter les artefacts, les téléversements SARIF et l'onglet Sécurité après la fin du workflow.

1. Listez les artefacts du workflow :

   ```bash
   gh run view --log
   ```

2. Téléchargez les artefacts SARIF pour une application spécifique :

   ```bash
   gh run download -n sarif-psrule-001
   gh run download -n sarif-checkov-001
   gh run download -n sarif-custodian-001
   ```

3. Ouvrez les fichiers SARIF téléchargés et vérifiez qu'ils contiennent des résultats.

4. Naviguez vers le dépôt de chaque application de démonstration sur GitHub et consultez l'onglet **Security**. Le job de téléversement inter-dépôts devrait avoir rempli les alertes Code Scanning des trois outils.

5. Comparez les résultats entre les outils :
   - **PSRule** — violations d'étiquettes, nommage, régions et bonnes pratiques Azure
   - **Checkov** — violations de sécurité, chiffrement et benchmarks CIS
   - **Cloud Custodian** — état des ressources en temps réel (orphelins, surdimensionnées, inactives)

![Jobs de la matrice montrant 5 jobs par application](../../images/lab-07/lab-07-matrix-jobs.png)

![Liste des artefacts SARIF](../../images/lab-07/lab-07-sarif-artifacts.png)

### Exercice 7.5 : PR avec contrôle de coûts

Vous allez créer une pull request qui modifie les coûts d'infrastructure et observer le contrôle de coûts Infracost en action.

1. Créez une nouvelle branche :

   ```bash
   git checkout -b test/cost-gate-demo
   ```

2. Ouvrez le `infra/main.bicep` de n'importe quelle application de démonstration et changez un SKU pour quelque chose de plus coûteux. Par exemple, augmentez l'App Service Plan de l'application 001 :

   ```bicep
   sku: { name: 'P3v3', tier: 'PremiumV3' }
   ```

3. Validez et poussez la modification :

   ```bash
   git add .
   git commit -m "test: upgrade SKU to trigger cost gate"
   git push -u origin test/cost-gate-demo
   ```

4. Créez une pull request :

   ```bash
   gh pr create --title "test: upgrade SKU to trigger cost gate" --body "Testing Infracost cost gate workflow"
   ```

5. Attendez l'exécution du workflow `FinOps Cost Gate`. Il :
   - Génère une référence de coûts depuis la branche `main`
   - Exécute `infracost diff` sur les changements de votre PR
   - Publie un commentaire résumant les coûts sur la PR montrant l'impact mensuel
   - Téléverse un fichier SARIF avec les résultats de coûts

6. Examinez le commentaire Infracost sur la PR. Il montre un tableau avec les changements de coûts par ressource et l'impact mensuel total.

7. Fermez la PR sans fusionner (c'était un test) :

   ```bash
   gh pr close --delete-branch
   ```

![PR avec commentaire de coûts Infracost](../../images/lab-07/lab-07-cost-gate-pr.png)

> [!TIP]
> Le workflow de contrôle de coûts utilise le drapeau `--behavior update` pour le commentaire Infracost. Cela signifie que chaque push vers la branche de la PR met à jour le commentaire existant plutôt que d'en créer un nouveau, gardant la conversation de la PR propre.

### Exercice 7.6 : Déploiement et suppression

Vous allez déclencher les workflows deploy-all et teardown-all pour comprendre le cycle de vie complet.

1. Déclenchez le workflow deploy-all :

   ```bash
   gh workflow run deploy-all.yml
   ```

2. Surveillez le déploiement :

   ```bash
   gh run watch
   ```

   Le workflow deploy-all déploie les 5 applications de démonstration séquentiellement. Chaque application déploie son template Bicep dans un groupe de ressources dédié (`rg-finops-demo-001` à `rg-finops-demo-005`).

3. Une fois le déploiement terminé, vérifiez les ressources dans le portail Azure ou via le CLI :

   ```bash
   az group list --query "[?starts_with(name, 'rg-finops-demo')].[name, location]" -o table
   ```

4. Déclenchez le workflow teardown-all :

   ```bash
   gh workflow run teardown-all.yml
   ```

5. Le workflow de suppression nécessite une **approbation d'environnement**. Naviguez vers la page GitHub Actions et approuvez le déploiement de l'environnement `production` lorsque demandé.

6. Après approbation, le workflow supprime les 5 groupes de ressources et leur contenu.

![Résumé du workflow deploy-all](../../images/lab-07/lab-07-deploy-teardown.png)

> [!IMPORTANT]
> Le workflow de suppression utilise un environnement `production` avec des réviseurs requis comme barrière de sécurité. Cela empêche la suppression accidentelle. Dans les workflows FinOps en production, utilisez toujours des règles de protection d'environnement pour les opérations destructrices.

## Point de vérification

Avant de terminer l'atelier, vérifiez :

* [ ] Le workflow `finops-scan.yml` s'est exécuté avec succès avec les jobs de la matrice
* [ ] Les artefacts SARIF ont été téléversés vers les onglets Sécurité des 5 dépôts d'applications
* [ ] Le workflow de contrôle de coûts a publié un commentaire Infracost sur une pull request
* [ ] Pouvez expliquer le format de la revendication de sujet des informations d'identification fédérées OIDC

## Félicitations

Vous avez terminé les 8 labs de l'Atelier de gouvernance des coûts FinOps. Voici un résumé de ce que vous avez appris :

| Lab | Ce que vous avez appris |
|-----|------------------------|
| **Lab 00** | Mise en place de l'environnement de développement avec les 4 outils d'analyse |
| **Lab 01** | Identification des 5 violations FinOps des applications de démonstration et des 7 étiquettes de gouvernance requises |
| **Lab 02** | Exécution de PSRule sur des templates Bicep pour l'analyse des bonnes pratiques Azure |
| **Lab 03** | Exécution de Checkov pour l'analyse de sécurité et des benchmarks CIS |
| **Lab 04** | Exécution de Cloud Custodian sur les ressources Azure actives pour la détection de violations en temps réel |
| **Lab 05** | Utilisation d'Infracost pour estimer les coûts et comparer les changements d'infrastructure |
| **Lab 06** | Compréhension du format SARIF et téléversement des résultats vers l'onglet Sécurité GitHub |
| **Lab 07** | Construction de pipelines automatisés avec stratégie de matrice, authentification OIDC et contrôles de coûts dans les PR |

Vous avez maintenant les compétences pour implémenter une plateforme d'analyse FinOps complète qui :

* **Analyse les templates IaC** avant le déploiement (PSRule, Checkov, Infracost)
* **Analyse les ressources actives** après le déploiement (Cloud Custodian)
* **Produit une sortie SARIF unifiée** pour tous les outils
* **S'intègre à l'onglet Sécurité GitHub** pour la gestion centralisée des alertes
* **Bloque les changements coûteux** avec des contrôles de coûts dans les PR
* **S'exécute automatiquement** selon un calendrier et à la demande via GitHub Actions
