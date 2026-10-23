package parser

import (
	"testing"

	"github.com/relya/sked/server/internal/pdfx"
	"github.com/relya/sked/server/internal/schedule"
)

func runs(texts ...string) []pdfx.Run {
	out := make([]pdfx.Run, len(texts))
	for i, t := range texts {
		out[i] = pdfx.Run{X: 10, Y: float64(10 + 12*i), Text: t}
	}
	return out
}

func TestInterpretCell(t *testing.T) {
	tests := []struct {
		name  string
		in    []pdfx.Run
		want  cellContent
		notes []schedule.Note
	}{
		{name: "lesson", in: runs("ОСиС", "Петров С.И."), want: cellContent{subject: "ОСиС", teacher: "Петров С.И."}},
		{name: "remote", in: runs("ООИ", "Д", "Волкова В.В."), want: cellContent{subject: "ООИ", teacher: "Волкова В.В.", remote: true}},
		{name: "room prefix", in: runs("ЭиС", "ауд.114/1", "Андрианов Н.В."), want: cellContent{subject: "ЭиС", room: "114/1", teacher: "Андрианов Н.В."}},
		{name: "workshop", in: runs("Инд. проект", "11 цех", "Волкова В.В."), want: cellContent{subject: "Инд. проект", room: "11 цех", teacher: "Волкова В.В."}},
		{name: "teacher typo", in: runs("Элем. выс. матем.", "Мурина Е.В,"), want: cellContent{subject: "Элем. выс. матем.", teacher: "Мурина Е.В"}},
		{name: "two teachers", in: runs("Информатика", "Семчук М.Н.", "Максименкова В.О."), want: cellContent{subject: "Информатика", teacher: "Семчук М.Н., Максименкова В.О."}},
		{
			name: "lunch with до", in: runs("Обед с 11:25", "до 11:50"),
			notes: []schedule.Note{{Kind: schedule.NoteLunch, Text: "Обед с 11:25 до 11:50", Time: "11:25", EndTime: "11:50"}},
		},
		{
			name: "starts at", in: runs("Занятия начинаются с", "11:10"),
			notes: []schedule.Note{{Kind: schedule.NoteStartsAt, Text: "Занятия начинаются с 11:10", Time: "11:10"}},
		},
		{name: "meeting", in: runs("Собрание по", "практике"), want: cellContent{subject: "Собрание по практике"}},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got := interpretCell(tt.in)
			if len(got.warnings) > 0 {
				t.Errorf("warnings: %v", got.warnings)
			}
			if got.subject != tt.want.subject || got.teacher != tt.want.teacher || got.room != tt.want.room || got.remote != tt.want.remote {
				t.Errorf("got %+v, want %+v", got, tt.want)
			}
			if len(got.notes) != len(tt.notes) {
				t.Fatalf("notes = %+v, want %+v", got.notes, tt.notes)
			}
			for i := range got.notes {
				if got.notes[i] != tt.notes[i] {
					t.Errorf("note = %+v, want %+v", got.notes[i], tt.notes[i])
				}
			}
		})
	}
}

func TestInterpretCellWarnsWithoutSubject(t *testing.T) {
	if got := interpretCell(runs("Петров С.И.", "17/1")); len(got.warnings) == 0 {
		t.Error("cell with teacher and room but no subject must be reported")
	}
}
