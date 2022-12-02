package cmd

import (
	_ "github.com/lukaspastva/source-code/cli/cmd/kubernetes"
	_ "github.com/lukaspastva/source-code/cli/cmd/kubernetes/connect"
	_ "github.com/lukaspastva/source-code/cli/cmd/kubernetes/install"
	_ "github.com/lukaspastva/source-code/cli/cmd/kubernetes/repo_setup"
	_ "github.com/lukaspastva/source-code/cli/cmd/kubernetes/vm_setup"
	_ "github.com/lukaspastva/source-code/cli/cmd/prometheus"
	_ "github.com/lukaspastva/source-code/cli/cmd/prometheus/vm_setup"
	_ "github.com/lukaspastva/source-code/cli/cmd/rancher"
	_ "github.com/lukaspastva/source-code/cli/cmd/rancher/vm_setup"
	"github.com/lukaspastva/source-code/cli/cmd/root"
	_ "github.com/lukaspastva/source-code/cli/cmd/terraform"
	_ "github.com/lukaspastva/source-code/cli/cmd/terraform/install"
	_ "github.com/lukaspastva/source-code/cli/cmd/terraform/vm_setup"
	_ "github.com/lukaspastva/source-code/cli/cmd/version"
	"github.com/spf13/cobra"
)

func Execute() {
	cobra.CheckErr(root.Cmd.Execute())
}
