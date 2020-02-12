package vnc

import (
	"context"
	"encoding/json"
	"fmt"
	"net"
	"sync"
	"time"

	"github.com/kward/go-vnc"
	"github.com/s-newman/scorestack/dynamicbeat/checks/schema"
)

type Definition struct {
	ID       string // a unique identifier for this check
	Name     string // a human-readable title for the check
	Group    string // the group this check is part of
	Host     string // (required) The IP or hostname of the vnc server
	Port     string // (required) The port for the vnc server
	Password string // (required) The password for the vnc server
}

// Run a single instance of the check
func (d *Definition) Run(wg *sync.WaitGroup, out chan<- schema.CheckResult) {
	defer wg.Done()

	// Set up result
	result := schema.CheckResult{
		Timestamp: time.Now(),
		ID:        d.ID,
		Name:      d.Name,
		Group:     d.Group,
		CheckType: "vnc",
	}

	// Dial the vnc server
	conn, err := net.Dial("tcp", fmt.Sprintf("%s:%s", d.Host, d.Port))
	if err != nil {
		result.Message = fmt.Sprintf("Connection to vnc server %s failed : %s", d.Host, err)
		out <- result
		return
	}

	// Negotiate connection with the server.
	client := vnc.NewClientConfig(d.Password)
	vncSession, err := vnc.Connect(context.Background(), conn, client)
	if err != nil {
		result.Message = fmt.Sprintf("Login on server %s failed : %s", d.Host, err)
		out <- result
		return
	}
	defer vncSession.Close()

	// If we made it here the check passes
	result.Passed = true
	out <- result
}

// Init the check using a known ID and name. The rest of the check fields will
// be filled in by parsing a JSON string representing the check definition.
func (d *Definition) Init(id string, name string, group string, def []byte) error {

	// Unpack JSON definition
	err := json.Unmarshal(def, &d)
	if err != nil {
		return err
	}

	// Set generic values
	d.ID = id
	d.Name = name
	d.Group = group

	// Check for missing fields
	missingFields := make([]string, 0)
	if d.Host == "" {
		missingFields = append(missingFields, "Host")
	}

	if d.Port == "" {
		missingFields = append(missingFields, "Port")
	}

	if d.Password == "" {
		missingFields = append(missingFields, "Password")
	}

	// Error only the first missing field, if there are any
	if len(missingFields) > 0 {
		return schema.ValidationError{
			ID:    d.ID,
			Type:  "vnc",
			Field: missingFields[0],
		}
	}
	return nil
}
