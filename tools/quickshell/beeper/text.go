package main

import (
	"encoding/json"
	"io"
	"strconv"
	"strings"

	"golang.org/x/net/html"
)

// Notifications never execute markup. Keep the original API text and provide an
// additional plainText field for native labels and previews.
func plainText(raw string) string {
	z := html.NewTokenizer(strings.NewReader(raw))
	var out strings.Builder
	// Native labels need explicit markers: removing <li> alone loses the list.
	type list struct {
		tag  string
		next int
	}
	var lists []list
	itemStart, afterList := false, false
	lineBreak := func() {
		if out.Len() > 0 && !strings.HasSuffix(out.String(), "\n") {
			out.WriteByte('\n')
		}
	}
	blockBreak := func() {
		if len(lists) > 0 || afterList {
			if !itemStart {
				lineBreak()
			}
		} else if out.Len() > 0 {
			out.WriteByte('\n')
		}
	}
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
				text := string(z.Text())
				// Ignore HTML indentation between list items and their blocks.
				if (len(lists) > 0 || afterList) && strings.TrimSpace(text) == "" &&
					(itemStart || strings.HasSuffix(out.String(), "\n")) {
					continue
				}
				if itemStart {
					text = strings.TrimLeft(text, " \t\r\n")
				}
				if text != "" {
					out.WriteString(text)
					itemStart, afterList = false, false
				}
			}
		case html.StartTagToken, html.SelfClosingTagToken:
			token := z.Token()
			if token.Data == "script" || token.Data == "style" {
				hidden++
				continue
			}
			if hidden > 0 {
				continue
			}
			switch token.Data {
			case "ul", "ol":
				lineBreak()
				lists = append(lists, list{tag: token.Data, next: listNumber(token, "start", 1)})
				itemStart = false
			case "li":
				lineBreak()
				marker := "• "
				if len(lists) > 0 {
					out.WriteString(strings.Repeat("  ", len(lists)-1))
					current := &lists[len(lists)-1]
					if current.tag == "ol" {
						current.next = listNumber(token, "value", current.next)
						marker = strconv.Itoa(current.next) + ". "
						current.next++
					}
				}
				out.WriteString(marker)
				itemStart = true
			case "br":
				if out.Len() > 0 {
					out.WriteByte('\n')
				}
				itemStart = false
			case "p", "div":
				blockBreak()
			}
		case html.EndTagToken:
			name, _ := z.TagName()
			switch string(name) {
			case "script", "style":
				if hidden > 0 {
					hidden--
				}
				continue
			}
			if hidden > 0 {
				continue
			}
			switch string(name) {
			case "ul", "ol":
				for i := len(lists) - 1; i >= 0; i-- {
					if lists[i].tag == string(name) {
						lists = lists[:i]
						break
					}
				}
				lineBreak()
				itemStart, afterList = false, true
			case "li":
				lineBreak()
				itemStart = false
			case "p", "div":
				blockBreak()
			}
		}
	}
}

func listNumber(token html.Token, attribute string, fallback int) int {
	for _, attr := range token.Attr {
		if attr.Key == attribute {
			if number, err := strconv.Atoi(strings.TrimSpace(attr.Val)); err == nil {
				return number
			}
			break
		}
	}
	return fallback
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
