package install

import (
	"log"
	"runtime"

	parent_cmd "github.com/lukaspastva/source-code/cli/cmd/terraform"
	"github.com/sikalabs/slu/utils/exec_utils"
	"github.com/spf13/cobra"
)

var Cmd = &cobra.Command{
	Use:     "install",
	Short:   "Install course dependencies (kubectl, helm, vscode, ...)",
	Aliases: []string{"i"},
	Args:    cobra.NoArgs,
	Run: func(c *cobra.Command, args []string) {
		if runtime.GOOS == "windows" {
			exec_utils.ExecOut("choco", "install", "terraform")
			return
		} else if runtime.GOOS == "darwin" {
			exec_utils.ExecOut("brew", "install", "terraform")
			return
		} else if runtime.GOOS == "linux" {
			exec_utils.ExecOut("slu", "install-bin-tool", "terraform")
			return
		}
		log.Fatalln("`training-cli terraform install` is not implemented for " + runtime.GOOS + " yet")
	},
}

func init() {
	parent_cmd.Cmd.AddCommand(Cmd)
}
