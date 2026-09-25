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
