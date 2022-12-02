package kubernetes

import (
	"github.com/lukaspastva/source-code/cli/cmd/root"
	"github.com/spf13/cobra"
)

var Cmd = &cobra.Command{
	Use:   "rancher",
	Short: "Rancher Training Utils",
}

func init() {
	root.Cmd.AddCommand(Cmd)
}
