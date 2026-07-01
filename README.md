# legend-of-dragoon-3D

Projet Godot 4 qui reconstruit, en 3D, la boucle de combat tour par tour de **Legend of Dragoon** (PS1) : ordre des tours à l'initiative, mini-jeu de timing des **Additions**, jauge de **SP** et **transformation Dragoon**.

> ⚠️ Il s'agit d'une réimplémentation des **mécaniques de gameplay** (non protégeables), pas d'une copie du jeu. Aucun asset, personnage, sprite, musique ou modèle original n'est réutilisé — tout le contenu (modèles 3D, textures, etc.) est propre au projet ou généré (par ex. via Meshy).

## Aperçu

- **Moteur** : Godot 4.7 (rendu Forward+, moteur physique Jolt)
- **Genre** : RPG au tour par tour en 3D
- **Scène principale** : `scenes/Battle.tscn`

## Mécaniques de combat

1. **Tour par tour à l'initiative** — chaque combattant agit selon une jauge d'initiative (ATB simplifié) pilotée par sa vitesse.
2. **Additions** — lors d'une attaque, un mini-jeu de timing (appui au bon moment) permet d'enchaîner les coups : plus l'enchaînement est réussi, plus les dégâts et le gain de **SP** sont importants. Un coup raté interrompt l'enchaînement.
3. **SP (Spirit Points)** — se remplissent en réussissant des Additions, par paliers (jusqu'à 500).
4. **Transformation Dragoon** — dépenser un ou plusieurs paliers de SP permet de se transformer temporairement en Dragoon : magie élémentaire puissante et attaques Dragoon (mini-jeu de timing dédié).
5. **Commandes classiques** — Attaque (Addition), Magie/Objet Dragoon, Objet, Défense, Fuite.

## Structure du projet

```
scenes/
├── Battle.tscn      # scène de combat (arène, positions, caméra, UI)
└── Battler.tscn      # combattant (data + représentation 3D)

scripts/
├── battle_manager.gd     # boucle de combat, initiative, résolution des tours
├── battler.gd            # stats et état d'un combattant (HP, SP, Dragoon...)
├── battle_camera.gd      # caméra de la scène de combat
├── battle_ui.gd          # orchestration de l'UI de combat
├── command_menu.gd       # menu de commandes (Attaque, Magie, Objet, Défense, Fuite)
├── party_status.gd       # affichage des barres HP/SP de l'équipe
├── addition_data.gd      # données d'une Addition (enchaînement d'attaques)
└── addition_minigame.gd  # mini-jeu de timing des Additions
```

## Documentation

Le fichier [`tuto_combat_dragoon_godot.md`](tuto_combat_dragoon_godot.md) détaille pas à pas la conception et l'implémentation du système de combat (machine à états, Additions, SP, transformation Dragoon).

## Lancer le projet

Ouvrir le dossier avec **Godot 4.7+**, puis lancer la scène principale `scenes/Battle.tscn` (ou F5).

### Contrôles

| Action         | Touche(s)                |
|----------------|---------------------------|
| `addition_hit` | Espace, Entrée, manette A |
| `menu_up`      | Flèche haut               |
| `menu_down`    | Flèche bas                |
| `menu_confirm` | Entrée / manette A        |
| `menu_cancel`  | Échap / manette B         |
