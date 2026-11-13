package main

import (
	"bytes"
	"encoding/base64"
	"html"
	"strings"

	"github.com/yuin/goldmark/ast"
	"github.com/yuin/goldmark/parser"
	"github.com/yuin/goldmark/text"
	"github.com/yuin/goldmark/util"
)

var kindMarkdownMath = ast.NewNodeKind("LocalMath")

type markdownMath struct {
	ast.BaseInline
	tex, original string
	display       bool
}

func (*markdownMath) Kind() ast.NodeKind { return kindMarkdownMath }
func (n *markdownMath) Dump(source []byte, level int) {
	ast.DumpHelper(n, source, level, map[string]string{"TeX": n.tex}, nil)
}

type markdownMathParser struct{}

func (markdownMathParser) Trigger() []byte { return []byte{'$', '\\'} }
func (markdownMathParser) Parse(_ ast.Node, reader text.Reader, _ parser.Context) ast.Node {
	line, _ := reader.PeekLine()
	open, close, display := "", "", false
	switch {
	case bytes.HasPrefix(line, []byte("$$")):
		open, close, display = "$$", "$$", true
	case bytes.HasPrefix(line, []byte(`\[`)):
		open, close, display = `\[`, `\]`, true
	case bytes.HasPrefix(line, []byte(`\(`)):
		open, close = `\(`, `\)`
	case len(line) > 1 && line[0] == '$' && !util.IsSpace(line[1]):
		open, close = "$", "$"
	default:
		return nil
	}
	savedLine, savedPosition := reader.Position()
	reader.Advance(len(open))
	var body strings.Builder
	for body.Len() <= 4096 {
		line, _ = reader.PeekLine()
		if line == nil {
			break
		}
		for i := 0; i < len(line); i++ {
			if bytes.HasPrefix(line[i:], []byte(close)) {
				candidate := body.String() + string(line[:i])
				after := i + len(close)
				// Avoid treating ordinary prices such as "$5 and $10" as mathematics.
				if strings.TrimSpace(candidate) == "" || open == "$" && (util.IsSpace(candidate[len(candidate)-1]) || after < len(line) && line[after] >= '0' && line[after] <= '9') {
					break
				}
				reader.Advance(after)
				return &markdownMath{tex: candidate, original: open + candidate + close, display: display}
			}
			if line[i] == '\\' {
				i++
			}
		}
		body.Write(line)
		if !display {
			break
		}
		reader.AdvanceLine()
	}
	reader.SetPosition(savedLine, savedPosition)
	return nil
}

func renderMarkdownMath(w util.BufWriter, _ []byte, node ast.Node, entering bool) (ast.WalkStatus, error) {
	if entering {
		math := node.(*markdownMath)
		display := "0"
		if math.display {
			display = "1"
		}
		_, _ = w.WriteString(`<span data-math="` + base64.StdEncoding.EncodeToString([]byte(math.tex)) + `" data-display="` + display + `">` + html.EscapeString(math.original) + `</span>`)
	}
	return ast.WalkSkipChildren, nil
}
