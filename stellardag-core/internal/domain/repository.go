package domain

import "context"

// EventRepository contract persistence for data cli.
type EventRepository interface {
	ListAll(ctx context.Context, namespace string) ([]EventStellar, error)

	// Watch stream
	Subscribe() chan EventStellar

	// Watch stream
	UnSubscribe(chan EventStellar)
}
