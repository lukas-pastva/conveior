package vm_setup

import (
	"fmt"
	"io/ioutil"
	"log"
	"os"
	"os/exec"
	"path"
	"runtime"

	parent_cmd "github.com/lukaspastva/source-code/cli/cmd/terraform"
	"github.com/lukaspastva/source-code/cli/utils/terraform_utils"
	"github.com/spf13/cobra"
)

var Cmd = &cobra.Command{
	Use:   "vm-setup",
	Short: "Setup VM (DO, AWS, ...) for Terraform Training",
	Args:  cobra.NoArgs,
	Run: func(c *cobra.Command, args []string) {
		if runtime.GOOS == "windows" {
			log.Fatalln("vm-setup is not supported on windows. You can try WSL.")
		}
		terraform_utils.VMSetup()
	},
}

func init() {
	parent_cmd.Cmd.AddCommand(Cmd)
}

// Utils

func handleError(err error) {
	log.Fatalln(err)
}

func execOutDir(dir string, command string, args ...string) error {
	cmd := exec.Command(command, args...)
	cmd.Dir = dir
	cmd.Stdout = os.Stdout
	cmd.Stderr = os.Stderr
	err := cmd.Run()
	return err
}

func execShOutDir(dir string, script string) error {
	return execOutDir(dir, "/bin/sh", "-c", script)
}

func execShOutHome(script string) error {
	home, err := os.UserHomeDir()
	if err != nil {
		return err
	}
	return execShOutDir(home, script)
}

func sh(script string) {
	fmt.Println(script)
	err := execShOutHome(script)
	if err != nil {
		handleError(err)
	}
}

func file(file_path, content string) {
	home, err := os.UserHomeDir()
	if err != nil {
		handleError(err)
	}
	err = ioutil.WriteFile(path.Join(home, file_path), []byte(content), 0644)
	if err != nil {
		handleError(err)
	}
}
