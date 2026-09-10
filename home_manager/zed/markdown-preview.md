# Catppuccin Macchiato — Markdown

Un aperçu de lecture en **Ubuntu Nerd Font**, avec le code en
**JetBrainsMono Nerd Font**. Ouvre ce fichier dans l’aperçu Markdown de Zed
pour voir le thème « Catppuccin Macchiato Markdown ».

## Texte, liens et citations

Le texte principal reste clair sur un fond sombre. Les [liens vers Zed](https://zed.dev)
sont bleus, et les séparateurs reprennent les accents mauves de Catppuccin.
Le **gras**, l’*italique* et le code court comme `nh switch` structurent la lecture.

> Une citation en lavande met une idée en évidence sans diminuer son contraste.

---

## Code et palette

```nix
{
  # Les commentaires restent lisibles.
  markdown_preview_font_size = 16;
  markdown_preview_font_family = "Ubuntu Nerd Font";
  markdown_preview = {
    limit_content_width = false;
  };
}
```

```javascript
const colors = ["mauve", "green", "peach"];
function describePalette(count = 3) {
  return colors.slice(0, count).join(", ");
}
```

| Élément | Couleur |
| --- | --- |
| Liens | Bleu |
| Citations | Lavande |
| Séparateurs | Mauve |
| Chaînes de code | Vert |
| Nombres de code | Pêche |

## Encadrés

> [!NOTE]
> Les encadrés utilisent les couleurs sémantiques du thème principal de Zed.

> [!TIP]
> Le thème de lecture s’applique aux aperçus des fichiers Markdown.

> [!WARNING]
> Zed 1.19 ne permet pas de colorer séparément chaque niveau de titre via un thème.

### À vérifier

- [x] Contraste du texte et des citations
- [x] Coloration du code
- [ ] Choisir une largeur de lecture selon ses préférences

Le thème principal et celui de l’Agent Panel restent indépendants de cet aperçu.
