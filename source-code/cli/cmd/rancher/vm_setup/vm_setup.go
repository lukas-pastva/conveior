package vm_setup

import (
	"log"
	"runtime"

	parent_cmd "github.com/lukaspastva/source-code/cli/cmd/rancher"
	"github.com/lukaspastva/source-code/cli/utils/general_utils"
	"github.com/lukaspastva/source-code/cli/utils/kubernetes_utils"
	"github.com/lukaspastva/source-code/cli/utils/rancher_utils"
	"github.com/lukaspastva/source-code/cli/utils/terraform_utils"
	"github.com/spf13/cobra"
)

var Cmd = &cobra.Command{
	Use:   "vm-setup",
	Short: "Setup VM (DO, AWS, ...) for Rancher Training",
	Args:  cobra.NoArgs,
	Run: func(c *cobra.Command, args []string) {
		if runtime.GOOS == "windows" {
			log.Fatalln("vm-setup is not supported on windows. You can try WSL.")
		}
		general_utils.VMSetup()
		kubernetes_utils.VMSetup()
		terraform_utils.VMSetup()
		rancher_utils.VMSetup()
	},
}

func init() {
	parent_cmd.Cmd.AddCommand(Cmd)
}
