package install

import (
	"log"
	"runtime"

	parent_cmd "github.com/lukaspastva/source-code/cli/cmd/kubernetes"
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
			exec_utils.ExecOut("choco", "feature", "enable", "-n", "allowGlobalConfirmation")
			exec_utils.ExecOut("choco", "install", "kubernetes-cli")
			exec_utils.ExecOut("choco", "install", "kubernetes-helm")
			exec_utils.ExecOut("choco", "install", "minikube")
			exec_utils.ExecOut("choco", "install", "vscode")
			return
		} else if runtime.GOOS == "darwin" {
			exec_utils.ExecOut("brew", "install", "kubernetes-cli")
			exec_utils.ExecOut("brew", "install", "kubernetes-helm")
			exec_utils.ExecOut("brew", "install", "minikube")
			exec_utils.ExecOut("brew", "install", "visual-studio-code")
			return
		} else if runtime.GOOS == "linux" {
			exec_utils.ExecOut("slu", "install-bin-tool", "kubectl")
			exec_utils.ExecOut("slu", "install-bin-tool", "helm")
			exec_utils.ExecOut("slu", "install-bin-tool", "minikube")
			return
		}
		log.Fatalln("`training-cli kubernetes install` is not implemented for " + runtime.GOOS + " yet")
	},
}

func init() {
	parent_cmd.Cmd.AddCommand(Cmd)
}
