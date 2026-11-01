package services

import (
	"slices"
	"testing"
)

func TestUniqueIdsKeepsTheFirstOccurrenceInOrder(t *testing.T) {
	got := uniqueIds([]string{"c", "a", "c", "b", "a"})
	want := []string{"c", "a", "b"}

	if !slices.Equal(got, want) {
		t.Fatalf("got %v, want %v", got, want)
	}
}

func TestUniqueIdsOnNothing(t *testing.T) {
	if got := uniqueIds(nil); len(got) != 0 {
		t.Fatalf("got %v, want nothing", got)
	}
}
