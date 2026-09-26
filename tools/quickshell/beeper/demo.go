package main

import (
	"fmt"
	"strings"
	"time"
)

func (b *backend) initDemo() {
	b.demoMessages = map[string][]object{}
	rows := []struct {
		id, title, network, initial, reply string
		unread                             int
	}{
		{"demo-camille", "Camille", "Signal", "On se retrouve près du canal demain ?", "Oui, vers 18 h. Je prends l’appareil photo 📷", 2},
		{"demo-atelier", "L’atelier", "WhatsApp", "J’ai posé les nouvelles couleurs sur la maquette.", "Le bleu avec cette lumière, ça fonctionne vraiment bien.", 3},
		{"demo-lea", "Léa", "Telegram", "Un café cette semaine ? ☕", "Jeudi me va très bien !", 0},
		{"demo-musique", "Musique & découvertes", "Discord", "Une petite sélection pour la soirée.", "Je garde ça pour la prochaine balade.", 0},
	}
	for i, row := range rows {
		when := time.Now().Add(-time.Duration(i*17+2) * time.Minute)
		makeMessage := func(id, text string, own bool, at time.Time) object {
			sender := row.title
			if own {
				sender = "Moi"
			}
			return object{"id": id, "chatID": row.id, "accountID": "demo-" + strings.ToLower(row.network), "senderID": sender, "senderName": sender, "text": text, "isSender": own, "timestamp": at.Format(time.RFC3339Nano), "sortKey": fmt.Sprint(at.UnixMilli()), "type": "TEXT", "reactions": []object{}, "attachments": []object{}, "sendStatus": object{"status": "SUCCESS"}}
		}
		messages := []object{makeMessage(row.id+"-1", "Salut ! Comment se passe ta journée ?", false, when.Add(-time.Hour)), makeMessage(row.id+"-2", "Bien, je prends un peu le temps aujourd’hui.", true, when.Add(-55*time.Minute)), makeMessage(row.id+"-3", row.initial, false, when.Add(-10*time.Minute)), makeMessage(row.id+"-4", row.reply, true, when.Add(-8*time.Minute)), makeMessage(row.id+"-5", "Parfait ✨", false, when)}
		messages[3]["reactions"] = []object{{"id": "demo-reaction", "participantID": "camille", "reactionKey": "💙", "emoji": true}}
		b.demoMessages[row.id] = messages
		b.demoChats = append(b.demoChats, object{"id": row.id, "title": row.title, "network": row.network, "accountID": "demo-" + strings.ToLower(row.network), "type": "single", "unreadCount": row.unread, "lastActivity": when.Format(time.RFC3339Nano), "preview": messages[len(messages)-1], "isMuted": false, "isPinned": i == 0, "isArchived": false, "participants": object{"items": []object{{"id": row.id + "-user", "fullName": row.title}}, "total": 1, "hasMore": false}, "capabilities": object{"archive": true, "delete": 2, "edit": 2, "reaction": 2, "reply": 2, "attachments": object{}}})
	}
}
func demoPage(items any) object {
	return object{"items": items, "hasMore": false, "oldestCursor": "", "newestCursor": ""}
}
func (b *backend) handleDemo(method string, p parameters) (any, error) {
	b.mu.Lock()
	defer b.mu.Unlock()
	switch method {
	case "connect":
		return object{"state": "demo"}, nil
	case "refresh":
		b.emit("chatsChanged", object{})
		return object{}, nil
	case "accounts":
		return []object{{"accountID": "demo-signal", "network": "Signal", "user": object{"id": "demo-self", "fullName": "Moi"}}, {"accountID": "demo-whatsapp", "network": "WhatsApp", "user": object{"id": "demo-self", "fullName": "Moi"}}}, nil
	case "chats":
		return demoPage(b.demoChats), nil
	case "unreadCounts":
		counts := map[string]int{}
		allCounts := map[string]int{}
		archivedCounts := map[string]int{}
		for _, chat := range b.demoChats {
			count, _ := chat["unreadCount"].(int)
			if count > 0 || boolField(chat, "isMarkedUnread") {
				allCounts[textField(chat, "network")]++
				if boolField(chat, "isArchived") {
					archivedCounts[textField(chat, "network")]++
				}
			}
			if countsAsUnread(boolField(chat, "isArchived"), boolField(chat, "isMarkedUnread"), count) {
				counts[textField(chat, "network")]++
			}
		}
		return object{"counts": counts, "allCounts": allCounts, "archivedCounts": archivedCounts}, nil
	case "messages":
		return demoPage(b.demoMessages[p.ChatID]), nil
	case "contacts":
		return object{"items": []object{{"id": "demo-contact", "fullName": "Alex (fictif)", "username": "alex"}}}, nil
	case "search":
		items := []object{}
		for chat, messages := range b.demoMessages {
			if p.ChatID != "" && chat != p.ChatID {
				continue
			}
			for _, m := range messages {
				if strings.Contains(strings.ToLower(textField(m, "text")), strings.ToLower(p.Query)) {
					items = append(items, m)
				}
			}
		}
		return demoPage(items), nil
	case "send":
		if strings.TrimSpace(p.Text) == "" && p.Attachment == nil {
			return nil, fail("empty_message", "The message is empty.")
		}
		id := fmt.Sprintf("demo-send-%d", time.Now().UnixNano())
		now := time.Now().Format(time.RFC3339Nano)
		m := object{"id": id, "chatID": p.ChatID, "text": p.Text, "senderName": "Moi", "isSender": true, "timestamp": now, "sortKey": fmt.Sprint(time.Now().UnixMilli()), "type": "TEXT", "linkedMessageID": p.ReplyToMessageID, "attachments": []object{}, "reactions": []object{}, "sendStatus": object{"status": "SUCCESS"}}
		b.demoMessages[p.ChatID] = append(b.demoMessages[p.ChatID], m)
		for _, chat := range b.demoChats {
			if textField(chat, "id") == p.ChatID {
				chat["preview"] = m
				chat["lastActivity"] = now
			}
		}
		b.emit("messagesChanged", object{"chatID": p.ChatID})
		b.emit("chatsChanged", object{})
		return object{"chatID": p.ChatID, "pendingMessageID": id}, nil
	case "edit", "delete", "react":
		for _, m := range b.demoMessages[p.ChatID] {
			if textField(m, "id") != p.MessageID {
				continue
			}
			switch method {
			case "edit":
				m["text"] = p.Text
				m["editedTimestamp"] = time.Now().Format(time.RFC3339Nano)
			case "delete":
				m["isDeleted"] = true
				m["text"] = ""
			case "react":
				if p.Remove {
					m["reactions"] = []object{}
				} else {
					m["reactions"] = []object{{"id": "demo-own", "participantID": "demo-self", "reactionKey": p.ReactionKey, "emoji": true}}
				}
			}
		}
		b.emit("messagesChanged", object{"chatID": p.ChatID})
		return object{}, nil
	case "read", "unread", "archive", "updateChat":
		if method == "archive" && (p.ChatID == "" || p.Archived == nil) {
			return nil, fail("invalid_params", "Specify the conversation and archive state.")
		}
		var result object
		for _, chat := range b.demoChats {
			if textField(chat, "id") == p.ChatID {
				if method == "read" {
					rows := b.demoMessages[p.ChatID]
					boundary := len(rows) - 1
					if p.MessageID != "" {
						boundary = -1
						for i, message := range rows {
							if textField(message, "id") == p.MessageID {
								boundary = i
								break
							}
						}
						if boundary < 0 {
							return nil, fail("not_found", "The read boundary is unavailable.")
						}
					}
					unread := 0
					for i, message := range rows {
						if i <= boundary {
							message["isUnread"] = false
						} else if !boolField(message, "isSender") && message["isUnread"] != false {
							unread++
						}
					}
					chat["unreadCount"] = unread
					chat["isMarkedUnread"] = false
				} else if method == "unread" {
					chat["isMarkedUnread"] = true
				} else if method == "archive" {
					chat["isArchived"] = *p.Archived
				} else {
					for key, value := range p.Changes {
						chat[key] = value
					}
				}
				result = chat
			}
		}
		b.emit("chatsChanged", object{})
		return result, nil
	case "startChat":
		id := fmt.Sprintf("demo-chat-%d", time.Now().UnixNano())
		chat := object{"id": id, "chatID": id, "title": "Alex (fictif)", "network": "Signal", "accountID": p.AccountID, "unreadCount": 0, "type": "single"}
		b.demoChats = append([]object{chat}, b.demoChats...)
		b.demoMessages[id] = []object{}
		b.emit("chatsChanged", object{})
		return chat, nil
	case "download", "upload":
		return nil, fail("demo", "Real files are disabled in the demo.")
	case "message":
		for _, m := range b.demoMessages[p.ChatID] {
			if textField(m, "id") == p.MessageID {
				return m, nil
			}
		}
		return nil, fail("not_found", "Message not found.")
	}
	return nil, fail("unknown_method", "Unknown command.")
}
