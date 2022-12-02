package kubernetes

import (
	"github.com/lukaspastva/source-code/cli/cmd/root"
	"github.com/spf13/cobra"
)

var Cmd = &cobra.Command{
	Use:     "kubernetes",
	Short:   "Kubernetes Training Utils",
	Aliases: []string{"k", "k8s", "kube"},
}

func init() {
	root.Cmd.AddCommand(Cmd)
}
