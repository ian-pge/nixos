package main

import (
	"encoding/json"
	"errors"
	"io"
	"strings"
)

// Decode only complete JSON values. In particular an escaped quote, a split
// Unicode escape or a nested "text" field must never publish a partial draft.
func partialCorrection(source, raw string) (result correctionResult, ready bool, err error) {
	raw = strings.TrimSpace(raw)
	if strings.HasPrefix("```json", raw) {
		return result, false, nil
	}
	if strings.HasPrefix(raw, "```") {
		raw = strings.TrimSpace(strings.TrimPrefix(raw, "```json"))
	}
	decoder := json.NewDecoder(strings.NewReader(raw))
	var text string
	explanations := []correctionExplanation{}
	defer func() {
		var syntax *json.SyntaxError
		if err == io.EOF || err == io.ErrUnexpectedEOF || (errors.As(err, &syntax) && syntax.Error() == "unexpected end of JSON input") {
			err = nil
		}
		if ready && err == nil {
			result = explainedCorrection(source, text, explanations, false)
		}
	}()
	token, err := decoder.Token()
	if err != nil {
		return result, false, err
	}
	if token != json.Delim('{') {
		return result, false, errors.New("invalid correction object")
	}
	seen := map[string]bool{}
	for decoder.More() {
		key, e := decoder.Token()
		if e != nil {
			return result, ready, e
		}
		name, ok := key.(string)
		if !ok || seen[name] {
			return result, ready, errors.New("duplicate correction field")
		}
		seen[name] = true
		switch name {
		case "text":
			if e = decoder.Decode(&text); e != nil {
				return result, ready, e
			}
			if len(text) > 16000 {
				return result, false, errors.New("correction too long")
			}
			ready = true
		case "explanations":
			start, e := decoder.Token()
			if e != nil {
				return result, ready, e
			}
			if start != json.Delim('[') {
				return result, ready, errors.New("invalid explanations")
			}
			for decoder.More() {
				var explanation correctionExplanation
				if e = decoder.Decode(&explanation); e != nil {
					return result, ready, e
				}
				explanations = append(explanations, explanation)
			}
			if _, e = decoder.Token(); e != nil {
				return result, ready, e
			}
		default:
			var ignored json.RawMessage
			if e = decoder.Decode(&ignored); e != nil {
				return result, ready, e
			}
		}
	}
	_, err = decoder.Token()
	return result, ready, err
}
