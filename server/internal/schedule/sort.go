package schedule

import (
	"cmp"
	"slices"
)

func sortGroups(groups []Group) {
	slices.SortFunc(groups, func(a, b Group) int {
		return cmp.Or(cmp.Compare(a.Course, b.Course), cmp.Compare(a.Name, b.Name))
	})
}
