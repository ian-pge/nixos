package main

import (
	"bytes"
	"html"
	"net/url"
	"strings"

	"github.com/yuin/goldmark"
	"github.com/yuin/goldmark/ast"
	"github.com/yuin/goldmark/extension"
	extast "github.com/yuin/goldmark/extension/ast"
	"github.com/yuin/goldmark/renderer"
	"github.com/yuin/goldmark/util"
)

// The HTML renderer is used only for local assistant replies. It emits no
// image/resources or raw HTML, and only explicit web/mail links are clickable.
var localMarkdown = goldmark.New(
	goldmark.WithExtensions(extension.GFM),
	goldmark.WithRendererOptions(renderer.WithNodeRenderers(util.Prioritized(markdownRenderer{}, 100))),
)

func renderMarkdown(source string) string {
	var result bytes.Buffer
	if err := localMarkdown.Convert([]byte(source), &result); err != nil {
		return "<p>" + html.EscapeString(source) + "</p>"
	}
	return result.String()
}

type markdownRenderer struct{}

func (markdownRenderer) RegisterFuncs(r renderer.NodeRendererFuncRegisterer) {
	r.Register(ast.KindImage, renderMarkdownLiteral)
	r.Register(ast.KindHTMLBlock, renderMarkdownLiteral)
	r.Register(ast.KindRawHTML, renderMarkdownLiteral)
	r.Register(ast.KindLink, renderMarkdownLink)
	r.Register(ast.KindAutoLink, renderMarkdownAutoLink)
	r.Register(extast.KindTaskCheckBox, renderMarkdownCheckbox)
}

func renderMarkdownLiteral(w util.BufWriter, source []byte, node ast.Node, entering bool) (ast.WalkStatus, error) {
	if entering {
		block := node.Kind() == ast.KindHTMLBlock
		if block {
			_, _ = w.WriteString("<pre>")
		}
		_, _ = w.Write(util.EscapeHTML(node.Text(source)))
		if block {
			_, _ = w.WriteString("</pre>\n")
		}
	}
	return ast.WalkSkipChildren, nil
}

func markdownHref(raw []byte) string {
	// Goldmark's URLEscape already resolves references for Markdown links.
	value := string(raw)
	u, err := url.Parse(value)
	if err != nil {
		return ""
	}
	switch strings.ToLower(u.Scheme) {
	case "http", "https":
		if u.Host == "" {
			return ""
		}
	case "mailto":
		if u.Opaque == "" && u.Path == "" {
			return ""
		}
	default:
		return ""
	}
	return html.EscapeString(u.String())
}

func renderMarkdownLink(w util.BufWriter, _ []byte, node ast.Node, entering bool) (ast.WalkStatus, error) {
	link := node.(*ast.Link)
	href := markdownHref(util.URLEscape(link.Destination, true))
	if href != "" {
		if entering {
			_, _ = w.WriteString("<a href=\"" + href + "\">")
		} else {
			_, _ = w.WriteString("</a>")
		}
	}
	return ast.WalkContinue, nil
}

func renderMarkdownAutoLink(w util.BufWriter, source []byte, node ast.Node, entering bool) (ast.WalkStatus, error) {
	if entering {
		link := node.(*ast.AutoLink)
		destination := link.URL(source)
		if link.AutoLinkType == ast.AutoLinkEmail && !bytes.HasPrefix(bytes.ToLower(destination), []byte("mailto:")) {
			destination = append([]byte("mailto:"), destination...)
		}
		href := markdownHref(util.URLEscape(destination, false))
		if href != "" {
			_, _ = w.WriteString("<a href=\"" + href + "\">")
		}
		_, _ = w.Write(util.EscapeHTML(link.Label(source)))
		if href != "" {
			_, _ = w.WriteString("</a>")
		}
	}
	return ast.WalkSkipChildren, nil
}

func renderMarkdownCheckbox(w util.BufWriter, _ []byte, node ast.Node, entering bool) (ast.WalkStatus, error) {
	if entering {
		if node.(*extast.TaskCheckBox).IsChecked {
			_, _ = w.WriteString("☑ ")
		} else {
			_, _ = w.WriteString("☐ ")
		}
	}
	return ast.WalkSkipChildren, nil
}
