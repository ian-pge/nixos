package main

import (
	"context"
	"encoding/json"
	"math"
	"time"
)

// A complete, lightweight catalog of confirmed states. QML merges these into
// the same records as visible chat pages; there is no separate counter cache.
func (b *backend) chatStates(ctx context.Context) (object, error) {
	client, err := b.api()
	if err != nil {
		return nil, err
	}
	ctx, cancel := context.WithTimeout(ctx, 30*time.Second)
	defer cancel()
	type chat struct {
		ID             string `json:"id"`
		Network        string `json:"network"`
		UnreadCount    int    `json:"unreadCount"`
		IsMarkedUnread bool   `json:"isMarkedUnread"`
		IsLowPriority  bool   `json:"isLowPriority"`
	}
	byID := map[string]chat{}
	seenCursors := map[string]bool{}
	cursor := ""
	for {
		var page struct {
			Items        []chat `json:"items"`
			HasMore      bool   `json:"hasMore"`
			OldestCursor string `json:"oldestCursor"`
		}
		if err := client.Get(ctx, "v1/chats"+pageQuery(parameters{Cursor: cursor, Direction: "before"}), nil, &page); err != nil {
			return nil, err
		}
		for _, row := range page.Items {
			if row.ID != "" {
				byID[row.ID] = row
			}
		}
		if !page.HasMore {
			break
		}
		cursor = page.OldestCursor
		if cursor == "" || seenCursors[cursor] {
			return nil, fail("pagination", "Could not finish counting unread conversations.")
		}
		seenCursors[cursor] = true
	}
	items := make([]chat, 0, len(byID))
	for _, row := range byID {
		items = append(items, row)
	}
	return object{"items": items}, nil
}

// The public API returns a Chat. unreadCount is required; isMarkedUnread is
// optional and defaults to false. Never manufacture success from an empty ACK.
func confirmedReadState(chatID string, raw json.RawMessage) (json.RawMessage, error) {
	var chat object
	if err := json.Unmarshal(raw, &chat); err != nil || textField(chat, "id") != chatID {
		return nil, fail("invalid_response", "Beeper did not return the conversation's read state.")
	}
	count, ok := chat["unreadCount"].(float64)
	if !ok || count < 0 || math.Trunc(count) != count {
		return nil, fail("invalid_response", "Beeper did not return a valid unread count.")
	}
	marked, present := chat["isMarkedUnread"]
	if !present {
		chat["isMarkedUnread"] = false
	} else if _, ok := marked.(bool); !ok {
		return nil, fail("invalid_response", "Beeper did not return a valid unread flag.")
	}
	return json.Marshal(chat)
}
