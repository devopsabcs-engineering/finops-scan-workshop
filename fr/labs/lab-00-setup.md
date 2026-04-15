---
nav_exclude: true
permalink: /fr/labs/lab-00-setup
title: "Lab 00 - Prérequis et configuration de l'environnement"
description: "Configurez votre environnement avec tous les outils requis pour l'analyse de gouvernance des coûts FinOps."
---

## Aperçu

> [!NOTE]
> Cet atelier fait partie de l'[Agentic Accelerator Framework](https://github.com/devopsabcs-engineering/agentic-accelerator-framework).

| | |
|---|---|
| **Durée** | 30 minutes |
| **Niveau** | Débutant |
| **Prérequis** | Aucun |

> [!IMPORTANT]
> Ce lab nécessite un abonnement Azure avec un accès **Contributeur** et un compte GitHub. Vous déploierez des ressources qui génèrent des coûts. N'oubliez pas de supprimer les ressources de démonstration après l'atelier.

## Objectifs d'apprentissage

À la fin de ce lab, vous serez capable de :

* Dupliquer (fork) et cloner le dépôt `finops-scan-demo-app`
* Installer les 4 outils d'analyse requis (PSRule, Checkov, Cloud Custodian, Infracost)
* Vous authentifier auprès d'Azure à l'aide d'Azure CLI
* Vérifier toutes les installations d'outils avec des contrôles de version
* Déployer les 5 applications de démonstration dans votre abonnement Azure

## Exercices

### Exercice 0.1 : Dupliquer le dépôt

Vous allez dupliquer (fork) le dépôt source de l'atelier afin d'avoir votre propre copie à analyser et modifier.

1. Ouvrez un terminal (PowerShell ou bash).
2. Dupliquez et clonez le dépôt en utilisant GitHub CLI :

   ```bash
   gh repo fork devopsabcs-engineering/finops-scan-demo-app --clone
   ```

3. Accédez au répertoire cloné :

   ```bash
   cd finops-scan-demo-app
   ```

4. Vérifiez que le remote pointe vers votre fork :

   ```bash
   git remote -v
   ```

   Vous devriez voir votre nom d'utilisateur GitHub dans l'URL `origin`.

> [!TIP]
> Si GitHub CLI n'est pas installé, exécutez `winget install GitHub.cli` sous Windows ou `brew install gh` sous macOS au préalable.

![Confirmation du fork sur GitHub](../../images/lab-00/lab-00-fork-repo.png)

### Exercice 0.2 : Installer les outils d'analyse

Vous allez installer les 4 outils d'analyse utilisés tout au long de l'atelier.

1. **PSRule for Azure** — Installez le module PowerShell :

   ```powershell
   Install-Module PSRule.Rules.Azure -Scope CurrentUser -Force
   ```

2. **Checkov** — Installez via pip :

   ```bash
   pip install checkov
   ```

3. **Cloud Custodian** — Installez le package principal et le fournisseur Azure :

   ```bash
   pip install c7n c7n-azure
   ```

4. **Infracost** — Installez le CLI :

   ```powershell
   # Windows
   choco install infracost
   # ou téléchargez depuis https://www.infracost.io/docs/#quick-start
   ```

   ```bash
   # macOS / Linux
   brew install infracost
   ```

5. **Azure CLI** — Si non déjà installé :

   ```powershell
   winget install Microsoft.AzureCLI
   ```

> [!TIP]
> Utilisez un environnement virtuel Python pour isoler les dépendances de Checkov et Cloud Custodian : `python -m venv .venv && .venv/Scripts/Activate.ps1` (PowerShell) ou `source .venv/bin/activate` (bash).

### Exercice 0.3 : Authentification Azure

Vous allez vous authentifier auprès d'Azure pour que les outils d'analyse puissent accéder à votre abonnement.

1. Connectez-vous à Azure :

   ```bash
   az login
   ```

2. Si vous avez plusieurs abonnements, définissez l'abonnement cible :

   ```bash
   az account set --subscription "<votre-nom-ou-id-abonnement>"
   ```

3. Vérifiez que vous êtes authentifié avec le bon abonnement :

   ```bash
   az account show --output table
   ```

   Confirmez que le `Name` et le `SubscriptionId` correspondent à votre cible prévue.

![Sortie Azure CLI account](../../images/lab-00/lab-00-az-login.png)

### Exercice 0.4 : Vérification des outils

Vous allez exécuter des contrôles de version pour confirmer que chaque outil est correctement installé.

1. **GitHub CLI :**

   ```bash
   gh --version
   ```

   ![Version GitHub CLI](../../images/lab-00/lab-00-gh-version.png)

2. **PSRule :**

   ```powershell
   Get-Module PSRule.Rules.Azure -ListAvailable | Select-Object Name, Version
   ```

   ![Version PSRule](../../images/lab-00/lab-00-psrule-version.png)

3. **Checkov :**

   ```bash
   checkov --version
   ```

   ![Version Checkov](../../images/lab-00/lab-00-checkov-version.png)

4. **Cloud Custodian :**

   ```bash
   custodian version
   ```

   ![Version Cloud Custodian](../../images/lab-00/lab-00-custodian-version.png)

5. **Infracost :**

   ```bash
   infracost --version
   ```

   ![Version Infracost](../../images/lab-00/lab-00-infracost-version.png)

> [!CAUTION]
> Si un outil échoue au contrôle de version, résolvez le problème d'installation avant de continuer. Les labs suivants dépendent de la disponibilité des 4 outils d'analyse.

### Exercice 0.5 : Déployer les applications de démonstration

Vous allez déployer les 5 applications de démonstration sur Azure pour que les outils d'analyse aient de vraies ressources à analyser.

**Option A — Déploiement automatisé (recommandé)**

1. Exécutez le script d'initialisation depuis la racine du dépôt :

   ```powershell
   ./scripts/bootstrap-demo-apps.ps1
   ```

   Le script crée 5 groupes de ressources (`rg-finops-demo-001` à `rg-finops-demo-005`) et déploie le template Bicep de chaque application.

   ![Sortie du script d'initialisation](../../images/lab-00/lab-00-deploy-output.png)

**Option B — Déploiement manuel d'une seule application**

1. Créez le groupe de ressources pour l'application 001 :

   ```bash
   az group create --name rg-finops-demo-001 --location canadacentral
   ```

2. Déployez le template Bicep :

   ```bash
   az deployment group create \
     --resource-group rg-finops-demo-001 \
     --template-file finops-demo-app-001/infra/main.bicep
   ```

3. Répétez pour les applications supplémentaires selon les besoins des labs suivants.

> [!IMPORTANT]
> Les applications de démonstration déploient intentionnellement des ressources avec des violations FinOps. Ces ressources génèrent de vrais coûts Azure. Exécutez le script de suppression après avoir terminé l'atelier : `./scripts/teardown-all.ps1`.

## Point de vérification

Avant de continuer, vérifiez :

* [ ] Dépôt dupliqué (fork) et cloné localement
* [ ] Les 4 outils d'analyse installés et retournant leur version
* [ ] Azure CLI authentifié avec le bon abonnement
* [ ] Au moins `finops-demo-app-001` déployé sur Azure

## Étapes suivantes

Passez au [Lab 01 — Explorer les applications de démonstration et les violations FinOps](lab-01.md).
