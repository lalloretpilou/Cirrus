# Cirrus - Fonctionnalités Aviation

## Vue d'ensemble

Cirrus est maintenant une application météo professionnelle dédiée aux pilotes d'aviation légère. Elle combine les données météorologiques classiques de WeatherKit avec des données aéronautiques spécialisées (METAR, TAF) pour fournir aux pilotes toutes les informations nécessaires à la planification de vols en toute sécurité.

## Nouvelles Fonctionnalités Aviation

### 1. Onglet Aviation Dédié 🛩️

Un nouvel onglet "Aviation" a été ajouté à la navigation principale, offrant:

- **Affichage METAR** : Observations météo aéronautiques en temps réel
- **Prévisions TAF** : Prévisions terminales d'aérodrome jusqu'à 30 heures
- **Vents en altitude** : Profils de vent à différentes altitudes (3000, 6000, 9000, 12000, 18000 ft)
- **Aérodromes à proximité** : Liste des aérodromes dans un rayon de 50 km

### 2. Système de Recommandations Intelligent 🎯

Le système analyse les conditions météo et fournit:

- **Type de vol recommandé** :
  - ✈️ Vol VFR recommandé
  - ⚠️ Vol VFR avec prudence
  - 🛩️ Vol IFR uniquement
  - ⛔ Vol non recommandé

- **Altitude optimale** : Calcul de l'altitude de croisière recommandée basée sur :
  - Dégagement des nuages (1000 ft minimum)
  - Vents en altitude (recherche du niveau avec les vents les plus favorables)
  - Altitudes VFR réglementaires (impaires + 500 ft pour l'est, paires + 500 ft pour l'ouest)

- **Fenêtre de départ optimale** : Identification des meilleures périodes pour décoller basées sur les prévisions TAF

### 3. Indicateurs de Conditions de Vol 🎨

- **VFR** (✅) : Plafond > 3000 ft, Visibilité > 5 SM
- **MVFR** (⚠️) : Plafond 1000-3000 ft ou Visibilité 3-5 SM
- **IFR** (⛔) : Plafond 500-1000 ft ou Visibilité 1-3 SM
- **LIFR** (🚫) : Plafond < 500 ft ou Visibilité < 1 SM

### 4. Calculs Aéronautiques Avancés 📊

#### Altitude Densité
- Calcul automatique de l'altitude densité basé sur :
  - Altitude pression (corrigée du calage altimétrique)
  - Température et point de rosée
  - Humidité relative
- Évaluation de l'impact sur les performances de l'aéronef

#### Composantes de Vent
- Calcul automatique pour chaque piste :
  - Vent de face / vent arrière
  - Vent de travers (gauche / droite)
  - Intensité effective

#### Autres Calculs
- True Airspeed (TAS) à partir de l'IAS
- Ground Speed avec correction du vent
- Estimation de l'altitude de base des nuages
- Calculs de carburant et temps de vol

### 5. Système d'Alertes Aviation 🚨

Alertes automatiques pour conditions dangereuses :

- **Vent** : Alertes si vent > 25 kt ou rafales > 20 kt
- **Visibilité** : Alertes si visibilité < 3 SM
- **Plafond** : Alertes si plafond < 1000 ft
- **Givrage** : Détection des conditions de givrage (0°C à -20°C avec humidité)
- **Orages** : Alertes pour activité orageuse
- **Vent de travers** : Alertes si vent de travers > 15 kt
- **Altitude densité** : Alertes si DA > 5000 ft (performances dégradées)

Chaque alerte indique :
- Type et sévérité (légère, modérée, sévère)
- Message descriptif
- Localisation
- Durée de validité

### 6. Sources de Données 🌐

#### API Utilisées (toutes gratuites)

1. **WeatherKit (Apple)** : Données météo générales
   - Conditions actuelles
   - Prévisions horaires et quotidiennes
   - Température, humidité, pression

2. **Aviation Weather Center (NOAA)** :
   - METAR en temps réel
   - TAF jusqu'à 30 heures
   - Entièrement gratuit, pas de clé API requise
   - Endpoint : `https://aviationweather.gov/api/data/`

3. **CheckWX API** :
   - Backup pour METAR/TAF
   - Données décodées en JSON
   - Format facilement parsable

4. **OurAirports Database** :
   - Base de données complète des aérodromes mondiaux
   - Codes OACI/IATA
   - Coordonnées géographiques
   - Informations sur les pistes

### 7. Interface Utilisateur 🎨

#### Écran Principal Aviation
- En-tête avec sélection d'aérodrome (recherche par code OACI ou nom)
- Carte des conditions de vol avec code couleur
- Recommandations en temps réel
- Onglets pour naviguer entre METAR, TAF, Vents et Aérodromes

#### Affichage METAR
- METAR brut (format texte officiel)
- Décodage lisible avec icônes :
  - 🌬️ Vent avec direction et intensité
  - 👁️ Visibilité
  - 🌡️ Température / Point de rosée
  - 📊 Altimètre (inHg et hPa)
  - ☁️ Couches nuageuses détaillées
- Calcul d'altitude densité avec évaluation des performances

#### Affichage TAF
- TAF brut (format texte officiel)
- Périodes de prévision décodées
- Types de changement (TEMPO, BECMG, FM, PROB)
- Conditions prévues pour chaque période

#### Vents en Altitude
- Tableau avec 5 niveaux standards (3000, 6000, 9000, 12000, 18000 ft)
- Direction et vitesse du vent
- Température à chaque niveau
- Code couleur pour les températures

#### Aérodromes Proches
- Liste triée par distance
- Indication si METAR/TAF disponible
- Élévation du terrain
- Localisation (ville, pays)

## Architecture du Code

### Nouveaux Fichiers Créés

1. **AviationModels.swift** (500+ lignes)
   - Modèles de données : METAR, TAF, Aerodrome, WindsAloft
   - Enums : FlightRules, WeatherPhenomenon, CloudCoverage
   - Structures : WindComponents, DensityAltitude, FlightRecommendation

2. **AviationWeatherService.swift** (800+ lignes)
   - Service principal pour récupérer les données aviation
   - Intégration multi-API avec fallback automatique
   - Cache NSCache avec expiration 10 minutes
   - Recherche d'aérodromes par géolocalisation ou nom

3. **AviationCalculations.swift** (600+ lignes)
   - Calculs d'altitude densité
   - Composantes de vent (headwind/crosswind)
   - True Airspeed et Ground Speed
   - Conversions d'unités
   - Calculs de performance (décollage/atterrissage)

4. **FlightRecommendationService.swift** (700+ lignes)
   - Moteur de recommandations intelligent
   - Analyse des conditions météo
   - Détermination du type de vol recommandé
   - Calcul d'altitude optimale
   - Identification des fenêtres de départ
   - Génération d'avertissements

5. **AviationView.swift** (1000+ lignes)
   - Vue SwiftUI principale pour l'onglet Aviation
   - Sous-vues : METAR, TAF, Winds, Aerodromes
   - Interface de recherche d'aérodromes
   - Cartes de recommandations
   - Design professionnel avec gradient et glassmorphism

6. **AviationAlertsService.swift** (400+ lignes)
   - Génération automatique d'alertes
   - Notifications push pour conditions sévères
   - Gestion du cycle de vie des alertes
   - Intégration avec UserNotifications

7. **LocationManager.swift** (100+ lignes)
   - Gestionnaire de géolocalisation
   - Demande de permissions
   - Mise à jour en temps réel de la position

### Modifications de Fichiers Existants

**CirrusApp.swift**
- Ajout de l'onglet "Aviation" dans le TabView
- Icône : avion (`airplane`)
- Positionné entre "Météo" et "Comparer"

## Utilisation

### Pour les Pilotes VFR

1. **Planification Pré-Vol** :
   - Ouvrir l'onglet Aviation
   - Rechercher l'aérodrome de départ
   - Vérifier les conditions METAR actuelles
   - Consulter le TAF pour les prévisions
   - Noter l'altitude densité et les performances

2. **Check des Recommandations** :
   - Lire le type de vol recommandé
   - Noter l'altitude optimale suggérée
   - Vérifier les avertissements et alertes
   - Identifier les fenêtres de départ favorables

3. **Analyse des Vents** :
   - Consulter les vents en altitude
   - Choisir l'altitude avec vents favorables
   - Calculer le cap et temps de vol estimé

4. **Check des Aérodromes Alternatifs** :
   - Consulter les aérodromes proches
   - Vérifier leurs conditions METAR
   - Planifier des alternatives en cas de besoin

### Pour les Pilotes IFR

1. **Briefing Météo Complet** :
   - METAR et TAF pour tous les aérodromes du plan de vol
   - Vérification des minima IFR
   - Analyse des vents en altitude pour le plan de vol

2. **Conditions Alternates** :
   - Vérifier les conditions aux terrains de dégagement
   - S'assurer que les minima sont respectés

3. **Fenêtres de Vol** :
   - Identifier les périodes de meilleures conditions
   - Éviter les périodes de conditions LIFR

## Sécurité et Responsabilité ⚠️

**IMPORTANT** : Cirrus est un outil d'aide à la décision. Les pilotes doivent :

- ✅ Toujours vérifier les informations avec des sources officielles (Météo France, SIA, etc.)
- ✅ Respecter les réglementations aériennes en vigueur
- ✅ Tenir compte de leur expérience et qualifications
- ✅ Considérer les performances réelles de leur aéronef
- ✅ Faire preuve de jugement et ne pas voler en conditions douteuses
- ❌ Ne pas utiliser Cirrus comme unique source d'information météo
- ❌ Ne pas voler si les conditions ne correspondent pas à vos qualifications

## Améliorations Futures Possibles 🚀

1. **Intégration NOTAM** : Affichage des NOTAM pour les aérodromes
2. **Cartes météo** : Overlay des conditions METAR sur une carte
3. **Planificateur de route** : Calcul de route avec profil de vent
4. **Historique météo** : Tendances et statistiques
5. **Briefing météo PDF** : Génération de briefing complet exportable
6. **Intégration avec plan de vol** : Import/export de plans de vol
7. **Mode hors-ligne** : Cache des données pour utilisation sans connexion
8. **Apple Watch** : Conditions météo sur la montre en vol

## Compatibilité

- **iOS 15.0+** minimum
- **WeatherKit** requis (intégré à iOS)
- **CoreLocation** pour la géolocalisation
- **Connexion Internet** nécessaire pour les données en temps réel

## Crédits

- **Données météo générales** : WeatherKit (Apple)
- **METAR/TAF** : Aviation Weather Center (NOAA) & CheckWX
- **Base de données aérodromes** : OurAirports
- **Développement** : Pierre-Louis L'ALLORET
- **Version** : 2.0 (Aviation Edition)

---

**Bon vol et ciel bleu ! ✈️☀️**
