package main

import (
	"bytes"
	"context"
	"encoding/binary"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"
)

func nativeFrame(value any) []byte {
	encoded, _ := json.Marshal(value)
	var frame bytes.Buffer
	binary.Write(&frame, binary.NativeEndian, uint32(len(encoded)))
	frame.Write(encoded)
	return frame.Bytes()
}
func TestNativeCorrectionFramesAndPreservesUnicode(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		jsonResponse(w, object{"done": true, "message": object{"content": `{"text":"😂 Les filles sont là."}`}})
	}))
	defer server.Close()
	input := append(nativeFrame(object{"action": "correct", "text": "😂 Les fille sont là."}), nativeFrame(object{"action": "delete-file"})...)
	var output bytes.Buffer
	if err := serveNativeCorrection(context.Background(), bytes.NewReader(input), &output, server.URL); err != nil {
		t.Fatal(err)
	}
	var size uint32
	if err := binary.Read(&output, binary.NativeEndian, &size); err != nil {
		t.Fatal(err)
	}
	var reply struct {
		OK     bool             `json:"ok"`
		Result correctionResult `json:"result"`
	}
	if err := json.Unmarshal(output.Next(int(size)), &reply); err != nil {
		t.Fatal(err)
	}
	if !reply.OK || reply.Result.Text != "😂 Les filles sont là." || len(reply.Result.Edits) != 1 {
		t.Fatalf("wrong native response: %+v", reply)
	}
	if err := binary.Read(&output, binary.NativeEndian, &size); err != nil {
		t.Fatal(err)
	}
	var rejected object
	json.Unmarshal(output.Next(int(size)), &rejected)
	if rejected["ok"] != false {
		t.Fatal("accepted an unsupported native action")
	}
}
func TestNativeCorrectionRejectsInvalidFrames(t *testing.T) {
	var oversized bytes.Buffer
	binary.Write(&oversized, binary.NativeEndian, uint32(1<<30))
	for _, input := range [][]byte{{0, 0, 0, 0}, {1, 2}, {8, 0, 0, 0, '{'}, oversized.Bytes()} {
		if err := serveNativeCorrection(context.Background(), bytes.NewReader(input), &bytes.Buffer{}, "http://127.0.0.1:1"); err == nil {
			t.Fatal("accepted invalid frame")
		}
	}
}
