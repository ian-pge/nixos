package main

import (
	"context"
	"encoding/json"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"
)

func TestPartialCorrectionPublishesOnlyWholeJSONValues(t *testing.T) {
	source := "Les fille \"texte\" 😂\n"
	candidate := "Les filles \"texte\" 😂\n"
	encoded, _ := json.Marshal(candidate)
	prefix := `{"text":` + string(encoded)
	raw := prefix + `,"explanations":[{"from":"fille","to":"filles","reason":"Le nom s’accorde avec « les »."}]}`
	for n := 0; n <= len(raw); n++ {
		r, ready, err := partialCorrection(source, raw[:n])
		if err != nil {
			t.Fatalf("prefix %d: %v", n, err)
		}
		if ready != (n >= len(prefix)) {
			t.Fatalf("prefix %d: premature or missing preview", n)
		}
		if ready && r.Text != candidate {
			t.Fatalf("partial text escaped: %q", r.Text)
		}
	}
	r, ready, err := partialCorrection(source, prefix+`,"explanations":[{"from":"fille","to":"filles","reason":"unfinished`)
	if err != nil || !ready || len(r.Explanations) != 0 {
		t.Fatalf("incomplete explanation displayed: %+v %v", r, err)
	}
	r, ready, err = partialCorrection(source, raw)
	if err != nil || !ready || len(r.Explanations) != 1 {
		t.Fatalf("complete explanation missing: %+v %v", r, err)
	}
	_, ready, _ = partialCorrection(source, `{"other":{"text":"not the correction"},"text":"unfinished`)
	if ready {
		t.Fatal("nested text used as a proposal")
	}
	if _, _, err = partialCorrection(source, prefix+`,"text":"different"}`); err == nil {
		t.Fatal("duplicate text accepted")
	}
	r, ready, err = partialCorrection("Les fille", `{"text":"Voici une réécriture complète",`)
	if err != nil || !ready || r.Text != "Les fille" || len(r.Edits) != 0 {
		t.Fatal("stream bypassed conservative validation")
	}
}

func correctionSnapshot(b *backend) object {
	b.mu.Lock()
	defer b.mu.Unlock()
	r := object{}
	for k, v := range b.correction {
		r[k] = v
	}
	return r
}
func awaitCorrection(t *testing.T, b *backend, check func(object) bool) {
	t.Helper()
	deadline := time.Now().Add(3 * time.Second)
	for time.Now().Before(deadline) {
		if check(correctionSnapshot(b)) {
			return
		}
		time.Sleep(5 * time.Millisecond)
	}
	t.Fatal("correction update did not arrive")
}
func streamingCorrection(t *testing.T, b *backend) correctionResult {
	t.Helper()
	ctx, cancel := context.WithCancel(b.ctx)
	defer cancel()
	type reply struct {
		r   correctionResult
		err error
	}
	done := make(chan reply, 1)
	go func() {
		r, err := b.runCorrection(ctx, parameters{Conversation: "openai", Text: "Les fille", Review: true})
		done <- reply{r, err}
	}()
	select {
	case v := <-done:
		if v.err != nil {
			t.Fatal(v.err)
		}
		return v.r
	case <-time.After(3 * time.Second):
		t.Fatal("text waited for the explanation gate")
		return correctionResult{}
	}
}
func TestCorrectionStreamsExplanationsAfterInitialRPCEnds(t *testing.T) {
	b, _ := testBackend(t)
	gate := filepath.Join(t.TempDir(), "continue")
	t.Setenv("FAKE_PI_CORRECTION_GATE", gate)
	r := streamingCorrection(t, b) // its request context is now cancelled
	if r.Text != "Les filles" || len(r.Edits) != 1 || len(r.Explanations) != 0 {
		t.Fatalf("bad early proposal: %+v", r)
	}
	if s := correctionSnapshot(b); s["state"] != "ready" || s["explaining"] != true || !strings.Contains(s["html"].(string), "#ed8796") {
		t.Fatal(s)
	}
	os.WriteFile(gate, []byte("go"), 0600)
	awaitCorrection(t, b, func(s object) bool { return len(s["explanations"].([]correctionExplanation)) == 1 })
	if s := correctionSnapshot(b); s["explaining"] != true {
		t.Fatal("explanations stopped when initial RPC ended")
	}
	os.WriteFile(gate+".finish", []byte("go"), 0600)
	awaitCorrection(t, b, func(s object) bool { return s["explaining"] == false })
	if s := correctionSnapshot(b); s["text"] != r.Text || s["state"] != "ready" {
		t.Fatal("proposal changed or applied without Enter")
	}
}
func TestEarlyCorrectionDecisionCancelsRemainingExplanations(t *testing.T) {
	for _, decision := range []string{"accept", "reject"} {
		t.Run(decision, func(t *testing.T) {
			b, _ := testBackend(t)
			t.Setenv("FAKE_PI_CORRECTION_GATE", filepath.Join(t.TempDir(), "never"))
			r := streamingCorrection(t, b)
			b.mu.Lock()
			review := b.correctionReview
			b.mu.Unlock()
			b.decideCorrection(parameters{ReportID: r.ReportID, Status: decision})
			select {
			case <-review.done:
			case <-time.After(time.Second):
				t.Fatal("decision did not stop generation")
			}
			s := correctionSnapshot(b)
			want := "accepted"
			if decision == "reject" {
				want = "dismissed"
			}
			if s["state"] != want {
				t.Fatal("late result replaced the decision")
			}
			reply, _ := b.waitCorrectionDecision(b.ctx, r.ReportID)
			if reply.(object)["decision"] != decision {
				t.Fatal("Chrome cannot resolve early decision")
			}
		})
	}
}
func TestExplanationFailureKeepsValidatedCorrection(t *testing.T) {
	b, _ := testBackend(t)
	gate := filepath.Join(t.TempDir(), "fail")
	t.Setenv("FAKE_PI_CORRECTION_GATE", gate)
	t.Setenv("FAKE_PI_CORRECTION_FAIL", "1")
	r := streamingCorrection(t, b)
	os.WriteFile(gate, []byte("go"), 0600)
	awaitCorrection(t, b, func(s object) bool { return s["explaining"] == false })
	if s := correctionSnapshot(b); s["text"] != r.Text || s["state"] != "ready" || s["message"] == nil {
		t.Fatal("valid proposal lost after explanation failure")
	}
	b.decideCorrection(parameters{ReportID: r.ReportID, Status: "accept"})
	if s := correctionSnapshot(b); s["state"] != "accepted" {
		t.Fatal("valid proposal cannot be accepted")
	}
}
