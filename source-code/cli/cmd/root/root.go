package root

import (
	"github.com/lukaspastva/source-code/cli/version"
	"github.com/spf13/cobra"
)

var Cmd = &cobra.Command{
	Use:   "training-cli",
	Short: "training-cli, " + version.Version,
}
