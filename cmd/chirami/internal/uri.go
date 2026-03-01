package internal

import (
	"net/url"
	"strings"
)

// BuildURI constructs a chirami:// URI for the given subcommand and parameters.
func BuildURI(subcommand string, params map[string]string) string {
	u := url.URL{
		Scheme: "chirami",
		Host:   subcommand,
	}
	q := url.Values{}
	for k, v := range params {
		q.Set(k, v)
	}
	// url.Values.Encode() encodes spaces as "+", but Swift's URLComponents
	// treats "+" as a literal plus sign. Use "%20" instead.
	u.RawQuery = strings.ReplaceAll(q.Encode(), "+", "%20")
	return u.String()
}
