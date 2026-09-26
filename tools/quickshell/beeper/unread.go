package main

import (
	"context"
	"time"
)

// Match the UI inbox: an explicit unread reminder takes precedence over Beeper's
// archive flag. Ordinary archived chats remain out of the inbox/count.
func countsAsUnread(archived, marked bool, messages int) bool {
	return marked || (!archived && messages > 0)
}

// Count conversations, not messages. Scan the public catalog rather than just
// the UI's loaded pages, including manual unread flags with a zero message count.
func (b *backend) unreadCounts(ctx context.Context) (object, error) {
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
		IsArchived     bool   `json:"isArchived"`
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
	counts := map[string]int{}
	allCounts := map[string]int{}
	archivedCounts := map[string]int{}
	for _, row := range byID {
		if row.UnreadCount > 0 || row.IsMarkedUnread {
			allCounts[row.Network]++
			if row.IsArchived {
				archivedCounts[row.Network]++
			}
		}
		if countsAsUnread(row.IsArchived, row.IsMarkedUnread, row.UnreadCount) {
			counts[row.Network]++
		}
	}
	return object{"counts": counts, "allCounts": allCounts, "archivedCounts": archivedCounts}, nil
}
