package main

import "strings"

// Keep identifiers typed: a phone number or handle is not a Beeper user ID.
type chatContact struct {
	ID          string `json:"id,omitempty"`
	PhoneNumber string `json:"phoneNumber,omitempty"`
	Username    string `json:"username,omitempty"`
	Email       string `json:"email,omitempty"`
	FullName    string `json:"fullName,omitempty"`
}

func startChatContact(p parameters) (chatContact, error) {
	user := chatContact{ID: p.UserID}
	if p.User != nil {
		user = *p.User
	}
	user.ID = strings.TrimSpace(user.ID)
	user.PhoneNumber = strings.TrimSpace(user.PhoneNumber)
	user.Username = strings.TrimSpace(user.Username)
	user.Email = strings.TrimSpace(user.Email)
	user.FullName = strings.TrimSpace(user.FullName)
	if strings.TrimSpace(p.AccountID) == "" || (user.ID == "" && user.PhoneNumber == "" && user.Username == "" && user.Email == "") {
		return chatContact{}, fail("invalid_params", "An account and a contact identifier are required.")
	}
	return user, nil
}
