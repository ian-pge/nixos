package main

import (
	"encoding/json"
	"strings"
	"testing"
)

func TestPlainTextNormalizesHTMLWithoutActiveContent(t *testing.T) {
	for _, tc := range []struct{ raw, want string }{
		{"Salut <strong>Camille</strong> &amp; Léa", "Salut Camille & Léa"},
		{"<p>Bonjour</p><p>à demain</p>", "Bonjour\n\nà demain"},
		{"<script>unsafe()</script><style>hidden</style>visible", "visible"},
		{"<a href='file:///etc/passwd'>un lien</a>", "un lien"},
		{"1 < 2 et 3 > 2 💙", "1 < 2 et 3 > 2 💙"},
		{"&lt;div&gt; reste du texte", "<div> reste du texte"},
	} {
		if got := plainText(tc.raw); got != tc.want {
			t.Errorf("%q => %q; want %q", tc.raw, got, tc.want)
		}
	}
	var page object
	raw := withPlainText(json.RawMessage(`{"items":[{"id":"c","preview":{"text":"<b>bonjour</b>"}}]}`))
	if json.Unmarshal(raw, &page) != nil {
		t.Fatal("invalid result")
	}
	if !strings.Contains(string(raw), `"plainText":"bonjour"`) || !strings.Contains(string(raw), `"text":"\u003cb\u003ebonjour\u003c/b\u003e"`) {
		t.Fatal("missing plain text or changed original body")
	}
}

func TestPlainTextPreservesLists(t *testing.T) {
	for _, tc := range []struct{ name, raw, want string }{
		{"bullets", "<ul><li>Lait</li><li>Pain &amp; café</li></ul>", "• Lait\n• Pain & café"},
		{"numbers", "<ol><li>Premier</li><li>Deuxième</li></ol>", "1. Premier\n2. Deuxième"},
		{"nested", "<ul><li>Courses<ol><li>Fruits<ul><li>Pommes</li></ul></li><li>Pain</li></ol></li><li>Maison</li></ul>", "• Courses\n  1. Fruits\n    • Pommes\n  2. Pain\n• Maison"},
		{"paragraphs", "<p>Courses :</p><ul><li><p>Lait</p></li><li><p>Pain</p><p>Complet</p></li></ul><p>Merci !</p>", "Courses :\n• Lait\n• Pain\nComplet\nMerci !"},
		{"formatted html", "<ul>\n  <li>Lait</li>\n  <li>Pain</li>\n</ul>", "• Lait\n• Pain"},
		{"inline markup", "<ul><li>Du <b>bon</b> pain<br>et du café</li></ul>", "• Du bon pain\net du café"},
		{"start and value", "<ol start='3'><li>Trois</li><li value='7'>Sept</li><li>Huit</li></ol>", "3. Trois\n7. Sept\n8. Huit"},
		{"invalid numbers", "<ol start='oops'><li value='oops'>Un</li><li>Deux</li></ol>", "1. Un\n2. Deux"},
		{"zero and negative numbers", "<ol start='0'><li>Zéro</li><li value='-2'>Moins deux</li><li>Moins un</li></ol>", "0. Zéro\n-2. Moins deux\n-1. Moins un"},
		{"separate lists", "<ol><li>Un</li></ol><ol><li>Un aussi</li></ol>", "1. Un\n1. Un aussi"},
		{"hidden content", "<ul><li><script>unsafe()</script><style>li {color:red}</style>Visible <img src='https://not-loaded.invalid/pixel'></li></ul>", "• Visible"},
		{"literal bullets", "Courses :\n• Lait\n  - Pain\n1. Café", "Courses :\n• Lait\n  - Pain\n1. Café"},
	} {
		t.Run(tc.name, func(t *testing.T) {
			if got := plainText(tc.raw); got != tc.want {
				t.Errorf("%q => %q; want %q", tc.raw, got, tc.want)
			}
		})
	}
}

func TestWithPlainTextPreservesListsAndOriginalHTML(t *testing.T) {
	body := "<ul><li>Lait</li><li>Pain</li></ul>"
	raw, err := json.Marshal(object{"items": []object{{"text": body, "preview": object{"text": body}}}})
	if err != nil {
		t.Fatal(err)
	}
	var page struct {
		Items []struct {
			Text, PlainText string
			Preview         struct{ Text, PlainText string }
		}
	}
	if err := json.Unmarshal(withPlainText(raw), &page); err != nil {
		t.Fatal(err)
	}
	if len(page.Items) != 1 {
		t.Fatalf("unexpected items: %+v", page.Items)
	}
	message := page.Items[0]
	if message.Text != body || message.Preview.Text != body {
		t.Fatal("original message or preview HTML changed")
	}
	if message.PlainText != "• Lait\n• Pain" || message.Preview.PlainText != message.PlainText {
		t.Fatalf("list markers missing from message or preview: %+v", message)
	}
}
