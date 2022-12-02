package repo_setup

import (
	"log"
	"os"
	"os/exec"

	parent_cmd "github.com/lukaspastva/source-code/cli/cmd/kubernetes"
	"github.com/spf13/cobra"
)

var Cmd = &cobra.Command{
	Use:   "repo-setup",
	Short: "Setup repo ondrejsika/kubernetes-training",
	Args:  cobra.NoArgs,
	Run: func(c *cobra.Command, args []string) {
		home, err := os.UserHomeDir()
		if err != nil {
			log.Fatal(err)
		}
		execOutDir(home, "git", "clone", "https://github.com/ondrejsika/kubernetes-training.git")
		execOutDir(home, "code", "./kubernetes-training")
	},
}

func init() {
	parent_cmd.Cmd.AddCommand(Cmd)
}

// Utils

func execOutDir(dir string, command string, args ...string) error {
	cmd := exec.Command(command, args...)
	cmd.Dir = dir
	cmd.Stdout = os.Stdout
	cmd.Stderr = os.Stderr
	err := cmd.Run()
	return err
}
