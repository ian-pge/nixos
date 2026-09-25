package main

import (
	"encoding/json"
	"io"
	"strings"

	"golang.org/x/net/html"
)

// Notifications never execute markup. Keep the original API text and provide an
// additional plainText field for native labels and previews.
func plainText(raw string) string {
	z := html.NewTokenizer(strings.NewReader(raw))
	var out strings.Builder
	hidden := 0
	for {
		t := z.Next()
		switch t {
		case html.ErrorToken:
			if z.Err() == io.EOF {
				return strings.TrimSpace(out.String())
			}
			return raw
		case html.TextToken:
			if hidden == 0 {
				out.Write(z.Text())
			}
		case html.StartTagToken, html.SelfClosingTagToken:
			name, _ := z.TagName()
			switch string(name) {
			case "script", "style":
				hidden++
			case "br", "p", "div", "li":
				if hidden == 0 && out.Len() > 0 {
					out.WriteByte('\n')
				}
			}
		case html.EndTagToken:
			name, _ := z.TagName()
			switch string(name) {
			case "script", "style":
				if hidden > 0 {
					hidden--
				}
			case "p", "div", "li":
				if hidden == 0 && out.Len() > 0 {
					out.WriteByte('\n')
				}
			}
		}
	}
}
func withPlainText(raw json.RawMessage) json.RawMessage {
	var data any
	if json.Unmarshal(raw, &data) != nil {
		return raw
	}
	var visit func(any)
	visit = func(v any) {
		switch value := v.(type) {
		case map[string]any:
			if text, ok := value["text"].(string); ok {
				value["plainText"] = plainText(text)
			}
			for key, child := range value {
				if key != "plainText" {
					visit(child)
				}
			}
		case []any:
			for _, child := range value {
				visit(child)
			}
		}
	}
	visit(data)
	result, err := json.Marshal(data)
	if err != nil {
		return raw
	}
	return result
}
