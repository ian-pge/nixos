package main

import (
	"context"
	"encoding/binary"
	"encoding/json"
	"errors"
	"io"
	"time"
)

// Chrome's documented native-messaging protocol: a native-endian uint32
// length followed by UTF-8 JSON. No keyboard, clipboard or chat state access.
func serveNativeCorrection(ctx context.Context, input io.Reader, output io.Writer, endpoint string) error {
	for {
		var size uint32
		if err := binary.Read(input, binary.NativeEndian, &size); err != nil {
			if errors.Is(err, io.EOF) {
				return nil
			}
			return err
		}
		if size == 0 || size > 64*1024 {
			return errors.New("invalid native message size")
		}
		data := make([]byte, size)
		if _, err := io.ReadFull(input, data); err != nil {
			return err
		}
		var request struct {
			Action   string `json:"action"`
			Text     string `json:"text"`
			Provider string `json:"provider"`
			ReportID string `json:"reportId"`
			Status   string `json:"status"`
			Review   bool   `json:"review"`
		}
		response := object{"ok": false, "error": "Invalid correction request."}
		if json.Unmarshal(data, &request) == nil && (request.Action == "correct" || request.Action == "status" || request.Action == "decide" || request.Action == "wait") {
			if endpoint == "" {
				call, cancel := context.WithTimeout(ctx, correctionBridgeTimeout)
				result, err := requestCorrectionPanel(call, parameters{Action: request.Action, Conversation: request.Provider, Text: request.Text, ReportID: request.ReportID, Status: request.Status, Review: request.Review})
				cancel()
				if err != nil {
					response = object{"ok": false, "error": safeError(err).Message}
				} else {
					response = result
				}
			} else {
				call, cancel := context.WithTimeout(ctx, 45*time.Second)
				result, err := correctSpelling(call, endpoint, request.Text)
				cancel()
				if err != nil {
					response = object{"ok": false, "error": safeError(err).Message}
				} else {
					response = object{"ok": true, "result": result}
				}
			}
		}
		encoded, err := json.Marshal(response)
		if err != nil {
			return err
		}
		if err := binary.Write(output, binary.NativeEndian, uint32(len(encoded))); err != nil {
			return err
		}
		if _, err := output.Write(encoded); err != nil {
			return err
		}
	}
}
