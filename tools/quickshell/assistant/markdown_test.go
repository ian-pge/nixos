package main

import (
	"encoding/base64"
	"strings"
	"testing"
)

func TestLocalMarkdownMathPreservesTeXAndCode(t *testing.T) {
	for _, source := range []string{`$$ (A-B)^2=A^2-2AB+B^2 $$`, `$x_i^2$`, `\(\frac{a}{b}\)`, "\\[\n\\sqrt{x^2+1}\n\\]", "$$\n\\begin{pmatrix} a & b \\\\ c & d \\end{pmatrix}\n$$"} {
		rendered := renderMarkdown(source)
		if !strings.Contains(rendered, `data-math="`) || strings.Contains(rendered, "<em>") {
			t.Fatalf("math not preserved: %s", rendered)
		}
	}
	got := renderMarkdown(`Avant $x_i$ puis **gras**.`)
	if !strings.Contains(got, base64.StdEncoding.EncodeToString([]byte("x_i"))) || !strings.Contains(got, "<strong>gras</strong>") {
		t.Fatal(got)
	}
	for _, source := range []string{"`$x_i$`", "```tex\n$$x_i$$\n```", `Prix : $5 et $10`, `Prix : \$5`, `Formule incomplète $$x_i`} {
		if got := renderMarkdown(source); strings.Contains(got, `data-math="`) {
			t.Fatalf("unexpected math: %s", got)
		}
	}
	got = renderMarkdown(`$$\text{<img src="https://example.test">}$$`)
	if strings.Contains(got, "<img") {
		t.Fatal("raw HTML in math escaped its placeholder")
	}
}

func TestLocalMarkdownStructureAndSourcePreservation(t *testing.T) {
	source := "# Titre\n\nDu **gras**, de l'*italique* et du `code`.\n\n- premier\n  - enfant\n\n1. un\n2. deux\n\n> citation\n\n```go\nif x < 2 { println(\"OK\") }\n```\n\n| A | B |\n| --- | --- |\n| un | deux |\n\n- [x] fini\n- [ ] ensuite"
	m := chatMessage{Role: "assistant", Content: source, State: "complete"}.display()
	if m["text"] != source {
		t.Fatal("copyable Markdown source changed")
	}
	html := m["html"].(string)
	for _, token := range []string{"<h1>", "<strong>gras</strong>", "<em>italique</em>", "<code>code</code>", "<ul>", "<ol>", "<blockquote>", "<pre><code", "x &lt; 2", "<table>", "☑", "☐"} {
		if !strings.Contains(html, token) {
			t.Fatalf("missing %q in %s", token, html)
		}
	}
	if user := (chatMessage{Role: "user", Content: source}).display()["html"].(string); strings.Contains(user, "<h1>") || !strings.Contains(user, "# Titre") {
		t.Fatal("user message was rendered as Markdown")
	}
}

func TestLocalMarkdownDoesNotEmbedResourcesOrUnsafeLinks(t *testing.T) {
	source := "![image](https://example.test/tracking.png)\n\n<img src=\"file:///etc/passwd\">\n\n[web](https://example.test/a?q=1&b=2) [mail](mailto:test@example.test) [bad](javascript:alert%281%29) [file](file:///etc/passwd) [relative](/etc/passwd)\n\n[encoded](javascript&#58;alert%281%29)\n\n<script>alert(1)</script>"
	rendered := renderMarkdown(source)
	for _, token := range []string{"<img", "<script", "href=\"javascript", "href=\"file", "href=\"/", "src=\""} {
		if strings.Contains(rendered, token) {
			t.Fatalf("resource/unsafe markup %q in %s", token, rendered)
		}
	}
	for _, token := range []string{"image", "&lt;img", "href=\"https://example.test/", "href=\"mailto:test@example.test\"", "&lt;script&gt;"} {
		if !strings.Contains(rendered, token) {
			t.Fatalf("missing safe representation %q in %s", token, rendered)
		}
	}
}

func TestLocalMarkdownStreamingFenceAndEscapedCode(t *testing.T) {
	for _, source := range []string{"```html\n<img src=\"https://example.test/x\">", "```html\n<img src=\"https://example.test/x\">\n```"} {
		rendered := renderMarkdown(source)
		if !strings.Contains(rendered, "<pre><code") || !strings.Contains(rendered, "&lt;img") || strings.Contains(rendered, "<img") {
			t.Fatalf("bad partial code block: %s", rendered)
		}
	}
	if got := renderMarkdown("A &copy; &amp; B"); !strings.Contains(got, "© &amp; B") {
		t.Fatalf("unexpected entities: %s", got)
	}
}

func TestLocalMarkdownDoesNotDecodeLinkEntitiesTwice(t *testing.T) {
	got := renderMarkdown("[lien](https://example.test/?q=&amp;copy;)")
	if !strings.Contains(got, `href="https://example.test/?q=&amp;copy;"`) {
		t.Fatalf("URL changed: %s", got)
	}
}
