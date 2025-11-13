# Cirrus - Application Météo Professionnelle pour Pilotes d'Aviation Légère

## 🛩️ Vue d'ensemble

Cirrus a été transformé en une application météo professionnelle et ultra-précise destinée aux pilotes d'aviation légère. L'application fournit des données météorologiques complètes et fiables, essentielles pour la planification et l'exécution de vols en toute sécurité.

## ✨ Nouvelles Fonctionnalités

### 1. Données Météo Aéronautiques (METAR/TAF)

L'application intègre maintenant des données météorologiques spécifiquement conçues pour l'aviation :

#### METAR (Observations Météorologiques)
- **Observations en temps réel** depuis les aéroports
- Texte brut METAR et décodage automatique
- Informations détaillées :
  - Direction et vitesse du vent
  - Visibilité
  - Couverture nuageuse et plafond
  - Température et point de rosée
  - Pression atmosphérique (QNH)
  - Phénomènes météorologiques (pluie, brouillard, orages, etc.)
- Classification automatique des **règles de vol** (VFR/MVFR/IFR/LIFR)

#### TAF (Prévisions Aéronautiques)
- **Prévisions météo aéronautiques** jusqu'à 24-30 heures
- Périodes de prévision détaillées
- Changements prévus (TEMPO, BECMG, PROB)
- Tendances pour la planification de vol

### 2. Système de Recommandation de Vol Intelligent

Le système analyse automatiquement les conditions météorologiques et génère des recommandations personnalisées :

#### Niveau de Sécurité
- ✅ **Sûr** : Conditions excellentes pour le vol
- ⚠️ **Prudence** : Conditions acceptables avec vigilance requise
- 🚫 **Non recommandé** : Conditions défavorables, vol déconseillé
- ⛔ **Dangereux** : Conditions dangereuses, vol à éviter

#### Recommandations d'Altitude
- **Altitude minimale** : Plancher de sécurité
- **Altitude optimale** : Meilleure altitude pour les conditions actuelles
- **Altitude maximale** : Plafond recommandé

Le système prend en compte :
- Couverture nuageuse et plafond
- Vent en altitude
- Visibilité
- Phénomènes météorologiques

#### Type de Vol Recommandé
- Vol local VFR (conditions excellentes)
- Navigation VFR (conditions favorables)
- Vol IFR (conditions IFR)
- Vol d'entraînement (conditions optimales pour l'apprentissage)
- Reporter le vol (conditions marginales)
- Annuler le vol (conditions dangereuses)

### 3. Avertissements et Conseils

#### Avertissements de Sécurité
Le système génère automatiquement des avertissements selon la gravité :
- 🔴 **Critique** : Danger immédiat (orages, cumulonimbus, vent très fort)
- 🟠 **Élevé** : Risque significatif (vent fort, précipitations intenses)
- 🟡 **Moyen** : Attention requise (plafond bas, visibilité réduite)
- 🟢 **Faible** : Informations importantes

Exemples d'avertissements :
- Cumulonimbus présents (CB)
- Vent fort ou rafales importantes
- Plafond bas
- Visibilité réduite
- Givrage possible
- Turbulences

#### Conseils de Vol
Conseils pratiques par catégorie :
- 🌬️ Vent
- 👁️ Visibilité
- ☁️ Nuages
- 🌀 Turbulence
- ❄️ Givrage
- 🌧️ Précipitations
- 🌡️ Température

### 4. Recherche d'Aéroports

- **Recherche automatique** des aéroports à proximité (rayon de 50 km)
- Base de données des principaux aéroports français :
  - Paris CDG (LFPG)
  - Paris Orly (LFPO)
  - Paris Le Bourget (LFPB)
  - Marseille Provence (LFML)
  - Lyon Saint-Exupéry (LFLL)
  - Nice Côte d'Azur (LFMN)
  - Et plus...

- **Informations aéroportuaires** :
  - Code ICAO et IATA
  - Élévation
  - Présence de tour de contrôle
  - Horaires d'opération

### 5. Intégration WeatherKit + APIs Aéronautiques

L'application combine plusieurs sources de données pour une précision maximale :

#### WeatherKit d'Apple
- Données météo générales haute qualité
- Prévisions horaires et quotidiennes
- Indice UV, qualité de l'air
- Précipitations

#### APIs Aéronautiques Gratuites
1. **AVWX API** (https://avwx.rest/)
   - Jusqu'à 4000 requêtes/jour
   - METAR et TAF décodés
   - Format JSON structuré

2. **CheckWX API** (https://www.checkwx.com/)
   - Jusqu'à 100 requêtes/jour
   - Backup en cas d'indisponibilité d'AVWX
   - Données météo aéronautiques mondiales

#### Fallback Intelligent
En cas d'indisponibilité des APIs, l'application :
- Génère des données simulées pour démonstration
- Continue de fonctionner avec WeatherKit
- Informe l'utilisateur du mode dégradé

## 🔧 Configuration

### Étape 1 : Obtenir les Clés API

#### AVWX API (Recommandé)
1. Créez un compte sur https://avwx.rest/
2. Générez une clé API (gratuit jusqu'à 4000 requêtes/jour)
3. Copiez votre token API

#### CheckWX API (Backup)
1. Créez un compte sur https://www.checkwx.com/
2. Générez une clé API (gratuit jusqu'à 100 requêtes/jour)
3. Copiez votre clé API

### Étape 2 : Configurer l'Application

Ouvrez le fichier `AviationWeatherService.swift` et remplacez les placeholders :

```swift
// Ligne 16-17
private let avwxToken = "VOTRE_TOKEN_AVWX" // Remplacez par votre token
private let checkwxAPIKey = "VOTRE_CLE_CHECKWX" // Remplacez par votre clé
```

### Étape 3 : WeatherKit

WeatherKit d'Apple est déjà configuré dans le projet. Assurez-vous que :
1. Votre Apple Developer account a accès à WeatherKit
2. Les capabilities WeatherKit sont activées dans Xcode
3. Votre Bundle ID est correctement configuré

## 📱 Utilisation

### Accéder aux Données Aviation

1. Lancez l'application Cirrus
2. Appuyez sur l'onglet **"Aviation"** 🛩️ dans la barre inférieure
3. L'application détectera automatiquement votre position et trouvera les aéroports à proximité

### Consulter les Données METAR/TAF

1. Sélectionnez un aéroport dans la liste
2. Consultez les données en temps réel :
   - **METAR** : Observations actuelles
   - **TAF** : Prévisions aéronautiques
3. Le texte brut est affiché avec son décodage automatique

### Interpréter les Recommandations

#### Indicateurs de Règles de Vol
- **VFR** (Vert) : Conditions visuelles - Vol à vue autorisé
- **MVFR** (Bleu) : Conditions VFR marginales - Vol possible avec prudence
- **IFR** (Rouge) : Conditions aux instruments - Vol IFR requis
- **LIFR** (Magenta) : Conditions IFR basses - Conditions difficiles

#### Niveau de Sécurité
L'indicateur de sécurité principal vous indique rapidement :
- ✅ **Vert** : Conditions sûres pour voler
- ⚠️ **Orange** : Prudence nécessaire
- 🚫 **Rouge** : Vol non recommandé
- ⛔ **Magenta** : Conditions dangereuses

#### Altitude Recommandée
- Consultez les **altitudes min/optimal/max**
- Le système explique pourquoi ces altitudes sont recommandées
- Basé sur le plafond nuageux, le vent et la visibilité

### Planifier Votre Vol

1. **Vérifiez les avertissements** : Lisez tous les avertissements de sécurité
2. **Consultez les conseils** : Prenez note des conseils spécifiques
3. **Choisissez votre altitude** : Utilisez l'altitude optimale recommandée
4. **Vérifiez la fenêtre de départ** : Si disponible, optimisez votre heure de départ
5. **Suivez le type de vol recommandé** : VFR local, navigation, IFR, etc.

### Fonctionnalités Avancées

#### Aéroports à Proximité
- Liste automatique des aéroports dans un rayon de 50 km
- Changez rapidement d'aéroport d'un simple tap
- Comparez les conditions entre différents aéroports

#### Rafraîchissement des Données
- Appuyez sur le bouton ↻ en haut à droite
- Les données sont automatiquement mises en cache (15 minutes)
- METAR : mis à jour toutes les heures
- TAF : mis à jour toutes les 6 heures

## 🔐 Sécurité et Fiabilité

### Sources Multiples
L'application combine plusieurs sources pour une **fiabilité maximale** :
- WeatherKit d'Apple (données générales)
- AVWX (données aéronautiques primaires)
- CheckWX (backup automatique)
- Données simulées (mode démo/fallback)

### Cache Intelligent
- Cache de 15 minutes pour les données aviation (fraîcheur garantie)
- Cache de 10 minutes pour les données météo générales
- Gestion automatique de la mémoire

### Validation des Données
- Toutes les données sont validées avant affichage
- Les erreurs sont gérées avec des messages clairs
- Mode dégradé en cas de problème réseau

## ⚠️ Avertissements Importants

### Usage Professionnel

**IMPORTANT** : Cette application est un **outil d'aide à la décision**. Elle ne remplace PAS :
- Le briefing météo officiel pré-vol
- La consultation d'un instructeur ou d'un pilote expérimenté
- Votre jugement personnel de pilote
- Les procédures et réglementations aériennes officielles

### Limitations

1. **Données TAF/METAR** :
   - Disponibles uniquement pour les aéroports équipés de stations météo
   - Mises à jour selon les cycles officiels (horaire pour METAR, 6h pour TAF)
   - Peuvent ne pas refléter les conditions micro-locales

2. **Recommandations** :
   - Basées sur des règles générales
   - À adapter selon votre expérience et qualification
   - Ne prennent pas en compte votre type d'aéronef

3. **Connectivité** :
   - Requiert une connexion internet active
   - Les APIs gratuites ont des limites de requêtes
   - Mode hors-ligne non disponible

### Responsabilité du Pilote

En tant que pilote, vous êtes le **seul responsable** de :
- La décision de voler ou non
- La planification complète de votre vol
- Le respect des minimums météo de votre licence
- La vérification des NOTAM et restrictions d'espace aérien
- La conformité avec toutes les réglementations aériennes

## 🚀 Fonctionnalités Futures

### Prochaines Améliorations

1. **NOTAM**
   - Intégration des Notice to Airmen
   - Alertes sur restrictions d'espace aérien
   - Informations sur fermetures de pistes

2. **Cartes Météo**
   - Radar de précipitations en temps réel
   - Cartes de vents en altitude
   - Visualisation des fronts météorologiques

3. **Calculs Aéronautiques**
   - Composantes de vent pour pistes spécifiques
   - Calcul de vent traversier (crosswind)
   - Performance avion selon température et altitude

4. **Planification de Route**
   - Météo le long de la route prévue
   - Alertes météo sur le trajet
   - Aérodromes de dégagement recommandés

5. **Historique et Tendances**
   - Évolution des conditions sur 24h
   - Tendances prévues
   - Graphiques de vent, température, pression

6. **Base de Données Étendue**
   - Plus d'aéroports français
   - Aérodromes européens
   - Terrains ULM

## 🛠️ Architecture Technique

### Fichiers Principaux

```
Cirrus/
├── AviationModels.swift          # Modèles de données aviation
├── AviationWeatherService.swift  # Service API METAR/TAF
├── AviationView.swift            # Interface utilisateur aviation
├── WeatherService.swift          # Service WeatherKit
├── WeatherViewModel.swift        # ViewModel météo général
├── Models.swift                  # Modèles généraux
└── CirrusApp.swift              # Point d'entrée
```

### Architecture des Services

```
┌─────────────────┐
│  AviationView   │ ← Interface utilisateur
└────────┬────────┘
         │
┌────────▼───────────┐
│  AviationViewModel │ ← Logique métier
└────────┬───────────┘
         │
┌────────▼──────────────────┐
│ AviationWeatherService    │ ← Services API
└───┬────────┬──────────────┘
    │        │
    │        └──────┐
    │               │
┌───▼───┐     ┌────▼────┐     ┌──────────┐
│ AVWX  │     │CheckWX  │     │WeatherKit│
│  API  │     │  API    │     │   API    │
└───────┘     └─────────┘     └──────────┘
```

### Système de Recommandation

```
METAR/TAF → Analyse Multi-Critères → Recommandation
             │
             ├─ Vent (vitesse, rafales, direction)
             ├─ Visibilité (distance, obstacles)
             ├─ Nuages (plafond, couverture, CB)
             ├─ Précipitations (type, intensité)
             ├─ Phénomènes (orages, givrage, turbulence)
             └─ Règles de vol (VFR/IFR)
                    │
                    ▼
             Niveau de Sécurité
             Altitude Recommandée
             Type de Vol
             Avertissements
             Conseils
```

## 📖 Références

### Standards Aéronautiques
- ICAO Annex 3 : Meteorological Service for International Air Navigation
- FAA Aviation Weather Services (AC 00-45H)
- EASA Easy Access Rules for Standardised European Rules of the Air

### APIs Utilisées
- [AVWX REST API Documentation](https://avwx.docs.apiary.io/)
- [CheckWX API Documentation](https://api.checkwx.com/)
- [Apple WeatherKit Documentation](https://developer.apple.com/weatherkit/)

### Ressources Météo Aviation
- [Aviation Weather Center (AWC)](https://aviationweather.gov/)
- [Météo France Aviation](https://aviation.meteo.fr/)
- [SIA (Service de l'Information Aéronautique)](https://www.sia.aviation-civile.gouv.fr/)

## 💬 Support

Pour toute question ou suggestion concernant les fonctionnalités aviation :
1. Consultez cette documentation
2. Vérifiez que vos clés API sont correctement configurées
3. Assurez-vous d'avoir une connexion internet active

## 📄 Licence

Ce projet est destiné à des fins éducatives et d'assistance à la navigation aérienne légère. L'utilisation est à vos propres risques et responsabilités.

---

**Bon vol et ciel dégagé ! ✈️**
