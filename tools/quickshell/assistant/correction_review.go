package main

import (
	"context"
	"time"
)

// A proposal is not permission to edit. Both clients keep the source intact
// until this review records an explicit acceptance of the ready result.
type correctionReview struct {
	id       string
	decision string
	wake     chan struct{}
	cancel   context.CancelFunc
}

func (b *backend) decideCorrection(p parameters) (any, error) {
	if p.Status != "accept" && p.Status != "reject" {
		return nil, fail("invalid_params", "Invalid correction decision")
	}
	b.mu.Lock()
	r := b.correctionReview
	if r == nil || r.id != p.ReportID {
		b.mu.Unlock()
		return object{"decision": "reject"}, nil
	}
	if r.decision != "" || (p.Status == "accept" && b.correction["state"] != "ready") {
		decision := r.decision
		b.mu.Unlock()
		return object{"decision": decision}, nil
	}
	r.decision = p.Status
	close(r.wake)
	if p.Status == "reject" {
		r.cancel()
	}
	report := object{}
	for key, value := range b.correction {
		report[key] = value
	}
	if p.Status == "accept" {
		report["state"] = "accepted"
	} else {
		report["state"] = "dismissed"
	}
	b.correction = report
	b.emit("correctionChanged", report)
	b.mu.Unlock()
	return object{"decision": p.Status}, nil
}

// Short long-polls keep Chrome's background worker alive without retaining
// an unbounded native-message request while the user reads the preview.
func (b *backend) waitCorrectionDecision(ctx context.Context, id string) (any, error) {
	b.mu.Lock()
	r := b.correctionReview
	if r == nil || r.id != id {
		b.mu.Unlock()
		return object{"decision": "reject"}, nil
	}
	wake := r.wake
	b.mu.Unlock()
	timer := time.NewTimer(20 * time.Second)
	defer timer.Stop()
	select {
	case <-wake:
	case <-timer.C:
	case <-ctx.Done():
		return nil, ctx.Err()
	}
	b.mu.Lock()
	decision := r.decision
	if b.correctionReview != r {
		decision = "reject"
	}
	b.mu.Unlock()
	return object{"decision": decision}, nil
}
