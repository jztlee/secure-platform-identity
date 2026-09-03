package entitlement

type Role string

const (
	RoleAdmin     Role = "admin"
	RoleDeveloper Role = "developer"
	RoleReadOnly  Role = "read-only"
)

type Subject struct {
	ID    string
	Type  string // "user", "workload", "agent", "pipeline"
	Roles []Role
}

type Graph struct {
	subjects map[string]Subject
}

func NewGraph() *Graph {
	return &Graph{subjects: make(map[string]Subject)}
}

func (g *Graph) AddSubject(s Subject) { g.subjects[s.ID] = s }

func (g *Graph) Lookup(id string) (Subject, bool) {
	s, ok := g.subjects[id]
	return s, ok
}
