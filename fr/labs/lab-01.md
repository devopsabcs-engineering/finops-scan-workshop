---
nav_exclude: true
permalink: /fr/labs/lab-01
title: "Lab 01 - Explorer les applications de démonstration et les violations FinOps"
description: "Comprendre les 5 applications de démonstration et leurs violations intentionnelles de gouvernance des coûts."
---

## Aperçu

| | |
|---|---|
| **Durée** | 25 minutes |
| **Niveau** | Débutant |
| **Prérequis** | [Lab 00](lab-00-setup.md) |

## Objectifs d'apprentissage

À la fin de ce lab, vous serez capable de :

* Décrire les 5 applications de démonstration et leurs violations FinOps intentionnelles
* Lire des templates Bicep et identifier visuellement les problèmes de gouvernance des coûts
* Expliquer les 7 étiquettes de gouvernance requises et leurs règles de format
* Naviguer dans le portail Azure pour visualiser les ressources déployées et inspecter leurs étiquettes

## Exercices

### Exercice 1.1 : Examiner la matrice des applications de démonstration

Chaque application de démonstration est conçue pour déclencher une catégorie spécifique de violation de gouvernance des coûts FinOps. Vous allez examiner la matrice complète pour comprendre ce que les outils d'analyse détecteront.

1. Ouvrez le tableau ci-dessous et étudiez le type de violation, les ressources clés et le gaspillage mensuel estimé de chaque application :

   | Application | Violation | Ressources clés | Gaspillage mensuel est. |
   |-------------|-----------|-----------------|-------------------------|
   | 001 | 7 étiquettes requises manquantes | Storage Account + App Service Plan + Web App | Risque de conformité |
   | 002 | Ressources surdimensionnées pour charge de travail dev | App Service Plan P3v3 + Storage Premium | ~800 $/mois |
   | 003 | Ressources orphelines (non attachées) | Public IP + NIC + Managed Disk + NSG | ~25 $/mois |
   | 004 | Pas d'arrêt automatique sur la VM | Machine virtuelle D4s_v5 fonctionnant 24h/24 | ~100 $/mois |
   | 005 | Configuration redondante/coûteuse | 2× App Service Plans S3 dans des régions non approuvées + Storage GRS | ~450 $/mois |

2. Notez comment les violations se répartissent en catégories distinctes : **étiquetage**, **dimensionnement**, **ressources orphelines**, **planification** et **redondance**.

3. Réfléchissez à quel outil d'analyse est le mieux adapté pour chaque type de violation. Vous validerez vos prédictions dans les Labs 02-05.

![Matrice des violations des applications de démonstration](../../images/lab-01/lab-01-demo-app-matrix.png)

### Exercice 1.2 : Lire les templates Bicep

Vous allez ouvrir les templates Bicep pour identifier les problèmes de gouvernance des coûts directement dans le code d'infrastructure.

**Application 001 — Étiquettes manquantes**

1. Ouvrez `finops-demo-app-001/infra/main.bicep` dans VS Code.
2. Parcourez les trois définitions de ressources : `storageAccount`, `appServicePlan` et `webApp`.
3. Notez qu'**aucune** des ressources n'a de propriété `tags`. Les commentaires dans le code confirment que c'est intentionnel :

   ```bicep
   // tags: {} — deliberately omitted to trigger FinOps scanner findings
   ```

4. Comptez le nombre de ressources affectées — vous devriez trouver **3 ressources** sans aucune étiquette.

![Application 001 Bicep — étiquettes manquantes](../../images/lab-01/lab-01-bicep-001.png)

**Application 002 — Ressources surdimensionnées**

5. Ouvrez `finops-demo-app-002/infra/main.bicep`.
6. Trouvez la ressource App Service Plan et notez le SKU :

   ```bicep
   sku: {
     name: 'P3v3'
     tier: 'PremiumV3'
     capacity: 1
   }
   ```

7. Comparez avec la politique de gouvernance : **les environnements dev autorisent un maximum de B1** (voir le tableau de gouvernance des SKU ci-dessous).

   | Environnement | Max App Service Plan | Max taille VM | Max niveau Storage |
   |---------------|----------------------|---------------|--------------------|
   | dev | B1 | Standard_B2s | Standard_LRS |
   | staging | S1 | Standard_D2s_v5 | Standard_LRS |
   | prod | P1v3 | Standard_D4s_v5 | Standard_GRS |

8. La variable `commonTags` montre `Environment: 'Development'`, confirmant qu'il s'agit d'une charge de travail dev utilisant un plan de niveau production.

![Application 002 Bicep — SKU P3v3](../../images/lab-01/lab-01-bicep-002.png)

### Exercice 1.3 : Liste de vérification des étiquettes de gouvernance

Chaque ressource Azure doit inclure les 7 étiquettes suivantes. Vous utiliserez cette liste tout au long de l'atelier pour évaluer les résultats des analyses.

1. Examinez le tableau des étiquettes requises :

   | # | Nom de l'étiquette | Objectif | Valeurs d'exemple |
   |---|-------------------|----------|-------------------|
   | 1 | `CostCenter` | Centre de coûts pour la refacturation | `CC-1234`, `CC-5678` |
   | 2 | `Owner` | Contact du propriétaire de la ressource | `team@contoso.com` |
   | 3 | `Environment` | Environnement de déploiement | `dev`, `staging`, `prod` |
   | 4 | `Application` | Identifiant de l'application | `finops-demo-001` |
   | 5 | `Department` | Département organisationnel | `Engineering`, `Finance` |
   | 6 | `Project` | Nom ou code du projet | `FinOps-Scanner` |
   | 7 | `ManagedBy` | Mécanisme de gestion | `Bicep`, `Terraform`, `Manual` |

2. Notez les règles de format :
   - Les noms d'étiquettes utilisent le **PascalCase**
   - Les valeurs des étiquettes ne doivent pas être des chaînes vides
   - `Environment` doit être l'un de : `dev`, `staging`, `prod`, `shared`
   - `Owner` doit être une adresse e-mail valide
   - `CostCenter` doit correspondre au motif `CC-\d{4,6}`

3. Ouvrez à nouveau `finops-demo-app-001/infra/main.bicep` et confirmez qu'**aucune** des 7 étiquettes n'est présente sur les ressources.

4. Ouvrez `finops-demo-app-002/infra/main.bicep` et vérifiez que les 7 étiquettes **sont** présentes dans la variable `commonTags`.

![Liste de vérification des étiquettes de gouvernance](../../images/lab-01/lab-01-governance-tags.png)

> [!TIP]
> L'application 001 est la pire en termes de conformité d'étiquetage. Les applications 002-005 incluent toutes des étiquettes mais violent d'autres politiques de gouvernance (dimensionnement, orphelins, planification, redondance).

### Exercice 1.4 : Exploration du portail Azure

Vous allez visualiser les ressources déployées dans le portail Azure pour voir comment les violations apparaissent en temps réel.

1. Ouvrez le [portail Azure](https://portal.azure.com) et naviguez vers **Groupes de ressources**.
2. Recherchez `rg-finops-demo-001` et ouvrez-le.
3. Sélectionnez n'importe quelle ressource (par exemple, le Storage Account) et cliquez sur **Étiquettes** dans le menu de gauche.
4. Confirmez que le panneau des étiquettes est vide — aucune étiquette appliquée.

   ![Portail Azure — aperçu du groupe de ressources](../../images/lab-01/lab-01-azure-portal-rg.png)

5. Naviguez vers `rg-finops-demo-002` et ouvrez l'App Service Plan.
6. Vérifiez le **Niveau tarifaire** — il devrait afficher **P3v3**.
7. Cliquez sur **Étiquettes** et confirmez que les 7 étiquettes de gouvernance sont présentes, mais que le niveau est surdimensionné pour un environnement `Development`.

   ![Portail Azure — vue des étiquettes](../../images/lab-01/lab-01-azure-portal-tags.png)

> [!IMPORTANT]
> Si des groupes de ressources sont manquants, retournez au Lab 00, Exercice 0.5 et déployez les applications de démonstration avant de continuer.

## Point de vérification

Avant de continuer, vérifiez :

* [ ] Pouvez nommer les 5 catégories de violations (étiquettes manquantes, surdimensionnement, orphelins, pas d'arrêt automatique, redondance)
* [ ] Pouvez identifier au moins 3 violations en lisant les fichiers Bicep `main.bicep`
* [ ] Pouvez lister les 7 étiquettes de gouvernance requises de mémoire
* [ ] Avez visualisé au moins un groupe de ressources dans le portail Azure

## Étapes suivantes

Passez au [Lab 02 — PSRule : Analyse d'infrastructure en tant que code](lab-02.md).
